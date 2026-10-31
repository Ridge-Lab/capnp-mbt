"""Install a published package and use its generator/runtime in a fresh module.

Requires MoonBit 0.10.16 or later, Node.js, a native C toolchain and capnp 1.5.0.
No source override or generated bindings from the checkout are used.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r'^version\s*=\s*"([^"]+)"', re.MULTILINE)
SCHEMA = """@0xc6ba5b4329891aef;
struct Record { id @0 :UInt64; name @1 :Text; }
enum RecordReader { unset @0; ready @1; }
struct Parcel(T) { value @0 :T; }
struct Envelope {
  item @0 :Parcel(Record);
  extra @1 :AnyPointer;
  status @2 :RecordReader;
}
const defaultId :UInt64 = 9007199254740993;
const fallback :Record = (id = 42, name = "constant payload");
"""
GENERATOR = """fn main raise {
  let files = @codegen.generate(@fs.read_file_to_bytes("request.bin"))
  assert_eq(files.length(), 1)
  assert_eq(files[0].path, "capnp_generated.mbt")
  @fs.write_string_to_file("generated/capnp_generated.mbt", files[0].content)
  println("Installed generator produced bindings from the original schema")
}
"""
CONSUMER = """fn main raise {
  let message = @capnp.Builder::new()
  let root = @types.EnvelopeBuilder::init_root(message)
  let record = root.init_item().init_value()
  record.set_id(@types.const_default_id())
  record.set_name("fresh Mooncakes consumer")
  root.set_status(@types.RecordReader::Ready)
  root.init_extra().set_struct(@types.const_fallback().inner)
  let bytes = @capnp.unpack(@capnp.pack(message.finish()))
  let received = @types.EnvelopeReader::from_message(@capnp.read_message(bytes))
  assert_eq(received.get_item().get_value().get_id(), 9007199254740993UL)
  assert_eq(received.get_item().get_value().get_name(), "fresh Mooncakes consumer")
  assert_eq(received.get_status().to_raw(), 1U)
  let payload = received.get_extra().as_struct()
  assert_eq(payload.get_uint64(0), 42UL)
  assert_eq(payload.get_text(0), "constant payload")
  let copied = @capnp.Builder::new()
  copied.root_pointer().set(@capnp.read_message(bytes).root_pointer())
  assert_eq(
    @capnp.canonicalize(@capnp.read_message(bytes)),
    @capnp.canonicalize(@capnp.read_message(copied.finish())),
  )
  let decoder = @capnp.FrameDecoder::new(max_message_bytes=bytes.length())
  assert_eq(decoder.feed(bytes[:3].to_owned()), [])
  let frames = decoder.feed(bytes[3:].to_owned() + bytes)
  decoder.finish()
  assert_eq(frames, [bytes, bytes])
  assert_eq(decoder.buffered_bytes(), 0)
  println("Verified installed runtime: generics, AnyPointer, constants, packing, canonical copy and incremental framing")
}
"""


def run(*args: str, cwd: Path) -> None:
    print("+ " + " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def write(directory: Path, name: str, content: str) -> None:
    path = directory / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def verify_distribution(installed: Path) -> None:
    required = (
        "LICENSE", "README.md", "docs/PROVENANCE.md", "docs/COMPATIBILITY.md",
        "docs/SERIALIZATION-STANDARD.md", "docs/CONFORMANCE.md",
        "internal/stdio/stdio.c", "internal/stdio/js.mbt",
        "cmd/capnpc-moonbit/main.mbt", "cmd/packing/main.mbt",
        "examples/roundtrip/main.mbt", "examples/schema_compat/main.mbt",
        "examples/schema_compat/peer.py", "examples/telemetry/worker.py",
        "examples/streaming/main.mbt", "examples/streaming/peer.py",
        "benchmarks/main.mbt", "scripts/run_benchmarks.py",
        "fixtures/conformance.bin", "fixtures/conformance.packed.bin",
    )
    for name in required:
        if not (installed / name).is_file():
            raise RuntimeError(f"Published package is missing {name}")
    if "Permission is hereby granted" not in (installed / "LICENSE").read_text():
        raise RuntimeError("Published package is missing the MIT permission notice")
    upstream = Path("fixtures/upstream/capnproto-1.5.0")
    # Use this checkout's recorded upstream hashes, not a package-supplied checksum
    # paired with a potentially changed file. These values refer to upstream 1.5.0.
    manifest = (ROOT / upstream / "README.md").read_text(encoding="utf-8")
    entries = re.findall(r"\| `([^`]+)` \| `([0-9a-f]{64})` \|", manifest)
    if len(entries) != 10:
        raise RuntimeError("Expected the ten-file upstream source/license manifest")
    for name, expected in entries:
        data = (installed / upstream / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f"Published upstream file differs from 1.5.0: {name}")
    print("Verified published documentation, licenses, host adapters and upstream hashes")


def verify_host_tools(installed: Path, directory: Path, moon: str, version: str) -> None:
    build = directory / "host-build"
    expected_source = (directory / "generated/capnp_generated.mbt").read_bytes()
    request = (directory / "request.bin").read_bytes()
    plain = (installed / "fixtures/conformance.bin").read_bytes()
    packed = (installed / "fixtures/conformance.packed.bin").read_bytes()
    for target in ("native", "js"):
        run(moon, "build", "--target", target, "--release", "--target-dir", str(build),
            "cmd/capnpc-moonbit", "cmd/packing", cwd=installed)
        def command(name: str) -> list[str]:
            base = build / target / "release/build/cmd" / name / name
            return [str(base) + ".exe"] if target == "native" else ["node", str(base) + ".js"]
        output = directory / ("plugin-" + target)
        output.mkdir()
        plugin = command("capnpc-moonbit")
        reported = subprocess.check_output(plugin + ["--version"], text=True).strip()
        if reported != "capnpc-moonbit " + version:
            raise RuntimeError(f"Installed CLI reports unexpected version: {reported}")
        subprocess.run(plugin, input=request, cwd=output, check=True, stdout=subprocess.PIPE)
        generated = output / "capnp_generated.mbt"
        if generated.read_bytes() != expected_source:
            raise RuntimeError(f"Installed {target} stdin plugin differs from library generator")
        invalid = subprocess.run(plugin, input=b"invalid", cwd=output, capture_output=True)
        if (invalid.returncode == 0 or invalid.stdout or not invalid.stderr
                or generated.read_bytes() != expected_source):
            raise RuntimeError(f"Installed {target} plugin mishandled an invalid request or its diagnostics")
        for mode, source, expected in (("pack", plain, packed), ("unpack", packed, plain)):
            actual = subprocess.check_output(command("packing") + [mode, "-", "-"], input=source)
            if actual != expected:
                raise RuntimeError(f"Installed {target} binary stdin/stdout {mode} differs from oracle")
        malformed = subprocess.run(command("packing") + ["unpack", "-", "-"],
                                   input=b"\xff", capture_output=True)
        if malformed.returncode == 0 or malformed.stdout or not malformed.stderr:
            raise RuntimeError(f"Installed {target} unpacker mixed an error into binary stdout")
        print(f"Verified installed {target} plugin, invalid-request preservation, binary packing and stderr-only errors")


def verify(directory: Path, version: str, moon: str, capnp: str) -> None:
    toolchain = subprocess.check_output([moon, "version", "--all"], text=True)
    match = re.search(r"^moonc v(\d+)\.(\d+)\.(\d+)(?:\+|\s|$)", toolchain, re.MULTILINE)
    if match is None or tuple(map(int, match.groups())) < (0, 10, 16):
        raise RuntimeError("Acceptance verification requires moonc >= 0.10.16; run moon version --all")
    print(toolchain.strip(), flush=True)
    compiler_version = subprocess.check_output([capnp, "--version"], text=True).strip()
    if compiler_version != "Cap'n Proto version 1.5.0":
        raise RuntimeError(f"Expected Cap'n Proto 1.5.0; found {compiler_version}")
    write(directory, "moon.mod", f'''name = "consumer/capnp-release"
version = "0.0.0"
import {{
  "Ridge-Lab/capnp@{version}",
  "moonbitlang/x@0.5.5",
}}
''')
    write(directory, "contract.capnp", SCHEMA)
    # subprocess writes the binary compiler protocol without a shell/text pipe.
    with (directory / "request.bin").open("wb") as output:
        subprocess.run(
            [capnp, "compile", "-o-", "contract.capnp"], cwd=directory,
            stdout=output, check=True,
        )
    write(directory, "generator/main.mbt", GENERATOR)
    write(directory, "generator/moon.pkg", '''import {
  "Ridge-Lab/capnp/codegen",
  "moonbitlang/x/fs",
}
pkgtype(kind: "executable")
''')
    write(directory, "generated/moon.pkg", 'import { "Ridge-Lab/capnp" }\n')
    write(directory, "main.mbt", CONSUMER)
    write(directory, "moon.pkg", '''import {
  "Ridge-Lab/capnp",
  "consumer/capnp-release/generated" @types,
}
pkgtype(kind: "executable")
''')
    run(moon, "update", cwd=directory)
    # Generate first: this also resolves and downloads the registry dependencies.
    run(moon, "run", "--target", "js", "generator", cwd=directory)
    installed = directory / ".mooncakes/Ridge-Lab/capnp"
    actual = VERSION.search((installed / "moon.mod").read_text(encoding="utf-8"))
    if actual is None or actual.group(1) != version:
        raise RuntimeError(f"Installed package does not match requested version {version}")
    run(moon, "check", "--target", "all", "--deny-warn", cwd=directory)
    for target in ("wasm", "wasm-gc", "js", "native"):
        run(moon, "run", "--target", target, ".", cwd=directory)
    verify_distribution(installed)
    verify_host_tools(installed, directory, moon, version)
    print(f"Published Ridge-Lab/capnp@{version}: fresh consumer passed on all four backends")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Published version; defaults to checkout's moon.mod")
    parser.add_argument("--moon", default="moon", help="Moon executable")
    parser.add_argument("--capnp", default="capnp", help="Cap'n Proto 1.5.0 executable")
    parser.add_argument("--release-tag", default=os.environ.get("RELEASE_TAG", ""),
                        help="Require this GitHub release tag to match the checkout and package")
    args = parser.parse_args()
    manifest_version = VERSION.search((ROOT / "moon.mod").read_text(encoding="utf-8"))
    version = args.version or (manifest_version.group(1) if manifest_version else "")
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is None:
        parser.error("version must be a stable x.y.z release")
    if args.release_tag and (
        args.release_tag != "v" + version or manifest_version is None
        or manifest_version.group(1) != version
    ):
        parser.error("release tag, checkout version and requested package must match")
    def executable(value: str) -> str:
        found = shutil.which(value)
        if found is None:
            parser.error(f"executable not found: {value}")
        return str(Path(found).resolve())
    moon, capnp = executable(args.moon), executable(args.capnp)
    # TemporaryDirectory owns only its newly created child of this workspace.
    work = ROOT / "work"
    work.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="published-consumer-", dir=work) as temporary:
        directory = Path(temporary).resolve()
        if directory.parent != work.resolve():
            raise RuntimeError("Temporary consumer escaped the workspace")
        verify(directory, version, moon, capnp)


if __name__ == "__main__":
    main()
