"""Build and measure the actual Capnp-MBT runtime, without timing process startup.

Requires MoonBit 0.10.14+, Node.js for JS, and MoonBit's native C toolchain.
The benchmark executable uses the SDK monotonic clock (microseconds).
Results describe this workload on this machine; they are not a language ranking.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
OPERATIONS = {"encode", "selected_read", "full_scan", "pack", "unpack", "opaque_copy"}


def bounded_integer(minimum: int, maximum: int):
    def parse(value: str) -> int:
        try:
            number = int(value)
        except ValueError as error:
            raise argparse.ArgumentTypeError("expected an integer") from error
        if not minimum <= number <= maximum:
            raise argparse.ArgumentTypeError(f"expected {minimum}..{maximum}")
        return number
    return parse


def program(name: str) -> str:
    found = shutil.which(name)
    if found is None:
        raise RuntimeError(f"Cannot find {name!r}; add the required tool to PATH")
    return found


def probe(command: list[str], *, required: bool = False) -> str | None:
    try:
        completed = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                                   errors="replace", capture_output=True, timeout=30,
                                   check=True)
        return (completed.stdout + completed.stderr).strip()
    except (OSError, subprocess.SubprocessError):
        if required:
            raise
        return None


def source_snapshot() -> dict:
    # Cover the benchmark and its project-local runtime/binding/host dependencies.
    # Store hashes instead of claiming that an uncommitted tree equals git HEAD.
    paths = [ROOT / "moon.mod", Path(__file__).resolve()]
    paths.extend(ROOT.glob("*.mbt"))
    paths.append(ROOT / "moon.pkg")
    for directory in ("benchmarks", "internal/stdio", "examples/telemetry/generated"):
        paths.extend(path for path in (ROOT / directory).iterdir()
                     if path.suffix in {".mbt", ".pkg", ".c"})
    files = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in sorted(set(paths)) if path.is_file()}
    digest = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    return {"sha256": digest, "files": files}


def executable(build: Path, target: str, node: str | None) -> list[str]:
    base = build / target / "release/build/benchmarks/benchmarks"
    if target == "js":
        assert node is not None
        return [node, str(base.with_suffix(".js"))]
    for candidate in (base.with_suffix(".exe"), base):
        if candidate.is_file():
            return [str(candidate)]
    raise RuntimeError(f"Native benchmark executable is missing under {base.parent}")


def validate_result(record: dict, samples: int, rounds: int, warmup_ms: int) -> None:
    if record["operation"] not in OPERATIONS or record["sample_count"] != samples:
        raise RuntimeError("Unexpected benchmark operation or sample count")
    times = record["round_us"]
    iterations = record["iterations"]
    if len(times) != rounds or iterations < 1:
        raise RuntimeError("Missing rounds or invalid iteration count")
    if not all(isinstance(value, (int, float)) and math.isfinite(value) and value > 0
               for value in times):
        raise RuntimeError("Monotonic clock produced a non-positive/non-finite timing")
    if record["warmup_us"] < warmup_ms * 1000 or record["warmup_batches"] < 1:
        raise RuntimeError("Benchmark did not complete the requested warmup")
    first, second = record["variant_checksums"]
    expected = (first * ((iterations + 1) // 2) + second * (iterations // 2)) % (2**32)
    if record["checksums"] != [expected] * rounds:
        raise RuntimeError("Benchmark checksum changed between measured rounds")
    median_ns = statistics.median(times) * 1000 / iterations
    if not math.isclose(record["median_ns_per_op"], median_ns, rel_tol=1e-10):
        raise RuntimeError("Reported median does not match raw measured rounds")
    if record["wire_bytes"] < 1 or record["packed_bytes"] < 1:
        raise RuntimeError("Missing workload byte sizes")


def run(args: argparse.Namespace) -> dict:
    moon = program(args.moon)
    node = program(args.node) if "js" in args.targets else None
    build = args.target_dir.resolve()
    snapshot = source_snapshot()
    metadata = {
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "system": platform.system(),
        "machine": platform.machine(),
        "processor": platform.processor() or os.environ.get("PROCESSOR_IDENTIFIER", "unknown"),
        "logical_cpu_count": os.cpu_count(),
        "python": platform.python_version(),
        "moon": probe([moon, "version", "--all"], required=True),
        "node": probe([node, "--version"], required=True) if node else None,
        "native_compiler_candidates": {
            compiler: probe([path, "--version"])
            for compiler in ("clang", "gcc")
            if (path := shutil.which(compiler)) is not None
        } if "native" in args.targets else {},
        "native_c_override_options": os.environ.get("CCC_OVERRIDE_OPTIONS"),
        "git_revision": probe(["git", "rev-parse", "HEAD"]),
        "git_dirty": bool(probe(["git", "status", "--porcelain"])),
        "source_snapshot": snapshot,
    }
    results = []
    commands = []
    for target in args.targets:
        command = [moon, "build", "--target", target, "--release", "--target-dir",
                   str(build), "benchmarks", "--deny-warn"]
        print("+ " + " ".join(command), file=sys.stderr, flush=True)
        subprocess.run(command, cwd=ROOT, check=True)
        commands.append(command)
        binary = executable(build, target, node)
        for samples in args.samples:
            command = binary + [str(samples), str(args.round_ms), str(args.warmup_ms),
                                str(args.rounds)]
            print(f"Measuring {target}, {samples} samples ...", file=sys.stderr, flush=True)
            measured = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                                      capture_output=True, check=True,
                                      timeout=args.timeout)
            if measured.stderr:
                print(measured.stderr, file=sys.stderr, end="")
            records = [json.loads(line) for line in measured.stdout.splitlines() if line.strip()]
            if len(records) != len(OPERATIONS) or {r["operation"] for r in records} != OPERATIONS:
                raise RuntimeError("Benchmark did not report each operation exactly once")
            for record in records:
                validate_result(record, samples, args.rounds, args.warmup_ms)
                record["target"] = target
                record["min_ns_per_op"] = min(record["round_us"]) * 1000 / record["iterations"]
                record["max_ns_per_op"] = max(record["round_us"]) * 1000 / record["iterations"]
                record["round_range_percent_of_median"] = (
                    (max(record["round_us"]) - min(record["round_us"]))
                    * 100 / statistics.median(record["round_us"]))
                record["calibration_target_met"] = record["calibration_us"] >= args.round_ms * 1000
                record["serialized_input_equivalent_mib_per_second"] = (
                    record["operations_per_second"] * record["input_bytes"] / 1048576
                    if record["input_bytes"] else None)
                results.append(record)
                print(f"  {record['operation']:14s} {record['median_ns_per_op']:12.1f} ns/op"
                      f"  range {record['round_range_percent_of_median']:.1f}%", file=sys.stderr)
    if snapshot != source_snapshot():
        raise RuntimeError("Benchmark or runtime source changed during the run; rerun on a stable tree")
    return {
        "format_version": 1,
        "workload": "telemetry-batch-v1",
        "metadata": metadata,
        "configuration": {
            "targets": args.targets, "samples": args.samples, "rounds": args.rounds,
            "round_ms": args.round_ms, "warmup_ms": args.warmup_ms,
            "build_mode": "release", "clock": "moonbitlang/core/bench monotonic clock",
            "clock_output_unit": "microseconds", "build_commands": commands,
            "fresh_process_per_target_and_sample_count": True,
        },
        "interpretation": [
            "Local measurements, not a cross-language or cross-machine ranking.",
            "Each round includes operation dispatch, checksum accumulation and normal allocations/GC.",
            "Byte-producing operations include a constant-size output fingerprint; complete validation is outside timing.",
            "Selected read accesses job ID, list length and first/last value; it does not decode the entire message.",
            "Wire MiB/s uses full uncompressed message size even for selected read; it is message-size-equivalent throughput, not memory bandwidth.",
            "Serialized-input-equivalent MiB/s uses packed bytes for unpack; encode has no serialized input and reports null. This is not memory bandwidth.",
            "CPU frequency, background activity, thermal state and JS JIT/GC can affect the recorded spread.",
        ],
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", choices=("native", "js"), default=["native", "js"])
    parser.add_argument("--samples", nargs="+", type=bounded_integer(1, 65536), default=[1, 32, 512])
    parser.add_argument("--round-ms", type=bounded_integer(1, 60000), default=100)
    parser.add_argument("--warmup-ms", type=bounded_integer(1, 60000), default=200)
    parser.add_argument("--rounds", type=bounded_integer(3, 99), default=7)
    parser.add_argument("--timeout", type=bounded_integer(1, 86400), default=600,
                        help="timeout in seconds per target/sample process")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--node", default="node")
    parser.add_argument("--target-dir", type=Path, default=ROOT / "work/benchmark-build")
    parser.add_argument("--output", type=Path, default=ROOT / "work/benchmarks/latest.json")
    args = parser.parse_args()
    if args.rounds % 2 != 1:
        parser.error("--rounds must be odd, so the median is an observed round")
    if len(set(args.targets)) != len(args.targets) or len(set(args.samples)) != len(args.samples):
        parser.error("--targets and --samples must not contain duplicates")
    try:
        result = run(args)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(args.output.name + ".tmp")
        temporary.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
                             encoding="utf-8")
        temporary.replace(args.output)
        print(f"Saved {len(result['results'])} measurements to {args.output.resolve()}", file=sys.stderr)
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            for diagnostic in (error.stdout, error.stderr):
                if diagnostic:
                    print(str(diagnostic)[-8000:], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
