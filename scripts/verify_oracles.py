"""Replay official 1.5.0 / pycapnp 2.2.1 checks without modifying source files."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from verify_release import verify_distribution

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capnp", default="capnp")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--node", default="node")
    parser.add_argument("--targets", nargs="+", choices=("js", "native"), default=["js"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    compiler = shutil.which(args.capnp)
    if compiler is None:
        raise RuntimeError(f"Official compiler not found: {args.capnp}")
    moon = shutil.which(args.moon)
    if moon is None:
        raise RuntimeError(f"MoonBit executable not found: {args.moon}")
    formatter = str(Path(moon).with_name("moonfmt.exe" if os.name == "nt" else "moonfmt"))

    def run(command: list[str], *, data: bytes | None = None, binary: bool = False) -> bytes:
        print("+ " + " ".join(map(str, command)), flush=True)
        result = subprocess.run(command, cwd=ROOT, input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=180)
        if result.stderr:
            print(result.stderr.decode("utf-8", errors="replace"), flush=True)
        result.check_returncode()
        if not binary and result.stdout:
            print(result.stdout.decode("utf-8", errors="replace"), flush=True)
        return result.stdout

    version = run([compiler, "--version"]).decode().strip()
    if version != "Cap'n Proto version 1.5.0":
        raise RuntimeError(f"Expected official 1.5.0, found {version}")
    import capnp
    if capnp.__version__ != "2.2.1":
        raise RuntimeError(f"Expected pycapnp 2.2.1, found {capnp.__version__}")
    verify_distribution(ROOT)

    def command(target: str, package: str) -> list[str]:
        path = ROOT / "_build" / target / "release/build" / package / Path(package).name
        return [args.node, str(path.with_suffix(".js"))] if target == "js" else [str(path.with_suffix(".exe"))]

    upstream = "fixtures/upstream/capnproto-1.5.0"
    cases = [("fixtures/conformance.capnp", "tests/generated", []),
             ("examples/telemetry/schema/telemetry.capnp", "examples/telemetry/generated", [])]
    for source, generated in (("advanced", "advanced"), ("names", "names"), ("generic", "generic"),
                              ("brands", "brands"), ("growing", "growing"),
                              ("collision-compat", "collision_compat"), ("long-text", "long_text")):
        cases.append((f"codegen/fixtures/{source}.capnp", f"tests/generated/{generated}", []))
    for schema, generated in (("test", "upstream"), ("schema", "compiler")):
        cases.append((f"{upstream}/capnp/{schema}.capnp", f"tests/generated/{generated}",
                      ["--no-standard-import", f"-I{upstream}", f"--src-prefix={upstream}"]))
    for index, (source, expected, flags) in enumerate(cases):
        request = run([compiler, "compile", *flags, "-o-", source], binary=True)
        (directory / f"request-{index}.bin").write_bytes(request)
        for target in args.targets:
            generated = directory / f"generated-{index}-{target}"
            generated.mkdir()
            if target == "native":
                # Exercise the real plugin invocation, not just request-file mode.
                run([compiler, "compile", *flags,
                     "-o" + command(target, "cmd/capnpc-moonbit")[0] + ":" + str(generated), source])
            else:
                run(command(target, "cmd/capnpc-moonbit") + ["--out", str(generated)], data=request)
            output = generated / "capnp_generated.mbt"
            run([formatter, "-w", str(output)])
            if output.read_text(encoding="utf-8") != (ROOT / expected / output.name).read_text(encoding="utf-8"):
                raise RuntimeError(f"Generated API drift: {source} on {target}")
    canonical_cases = [(ROOT / "fixtures" / source, ROOT / "fixtures/conformance.canonical.bin")
                       for source in ("conformance.bin", "conformance.segmented.bin")]
    for expected in (ROOT / "fixtures/upstream/oracle-1.5.0").glob("*.canonical.bin"):
        canonical_cases.append((expected.with_name(expected.name.replace(".canonical.bin", ".bin")), expected))
    for source, expected in canonical_cases:
        if run([compiler, "convert", "binary:canonical"], data=source.read_bytes(), binary=True) != expected.read_bytes():
            raise RuntimeError(f"Canonical fixture differs from official converter: {source}")

    for target in args.targets:
        batch, report = directory / f"batch-{target}.bin", directory / f"report-{target}.bin"
        run(command(target, "examples/telemetry") + ["produce", str(batch)])
        run([sys.executable, "examples/telemetry/worker.py", str(batch), str(report)])
        run(command(target, "examples/telemetry") + ["verify", str(report)])
        packed = run(command(target, "cmd/packing") + ["pack", "-", "-"], data=batch.read_bytes(), binary=True)
        (directory / f"batch-{target}.packed.bin").write_bytes(packed)
        run([compiler, "decode", "--packed", "examples/telemetry/schema/telemetry.capnp", "Batch"], data=packed)
        compatibility = directory / f"schema-{target}"
        run([sys.executable, "examples/schema_compat/peer.py", "prepare", str(compatibility)])
        run(command(target, "examples/schema_compat") + [str(compatibility)])
        run([sys.executable, "examples/schema_compat/peer.py", "verify", str(compatibility)])
        for packed_mode in (False, True):
            run([sys.executable, "examples/streaming/peer.py", "--jobs", "128",
                 "--output", str(directory / f"stream-{target}-{'packed' if packed_mode else 'plain'}"),
                 *(["--packed"] if packed_mode else []), "--", *command(target, "examples/streaming"),
                 *(["--packed"] if packed_mode else [])])

    artifacts = [{"path": str(path.relative_to(directory)), "bytes": path.stat().st_size,
                  "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                 for path in sorted(directory.rglob("*")) if path.is_file()]
    (directory / "report.json").write_text(json.dumps({"status": "passed", "compiler": version,
        "pycapnp": capnp.__version__, "targets": args.targets, "schema_cases": len(cases),
        "canonical_cases": len(canonical_cases), "artifacts": artifacts}, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(cases)} schemas, {len(canonical_cases)} official canonical fixtures, "
          "bidirectional typed values and plain/packed streams", flush=True)


if __name__ == "__main__":
    main()
