"""Recover the Pyodide Modules.Bundle linked into the pinned Windows workerd release."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_SHA256 = "0383c294bb40c2ec5d153ee90abddce83a9dbcc5805527d598fca932179f1126"
FRAME_SHA256 = "be2a4f48c472990d0f3c5e745e22a593cd62ed26e3709cead00ffb805712e361"
# C++ embeds a single unframed segment in the PE image. These coordinates are
# for the authenticated 1.20261112.1 windows-64 archive only.
SEGMENT_OFFSET = 0x52F6C80
SEGMENT_BYTES = 206384


def release_frame(archive):
    with archive.open("rb") as src:
        if hashlib.file_digest(src, "sha256").hexdigest() != ARCHIVE_SHA256:
            raise ValueError("Expected @cloudflare/workerd-windows-64 1.20261112.1")
    with tarfile.open(archive, "r:gz") as package:
        with package.extractfile("package/bin/workerd.exe") as exe:
            exe.seek(SEGMENT_OFFSET)
            segment = exe.read(SEGMENT_BYTES)
    frame = struct.pack("<II", 0, SEGMENT_BYTES // 8) + segment
    if hashlib.sha256(frame).hexdigest() != FRAME_SHA256:
        raise ValueError("Embedded Pyodide segment differs")
    return frame


def verify(frame, path, cli):
    import capnp
    schema_root = ROOT / "fixtures/upstream"
    peer = capnp.load(str(schema_root / "workerd/modules.capnp"),
                      imports=[str(schema_root / "capnproto-1.5.0")])
    listed = json.loads(subprocess.check_output([*cli, "list", path], timeout=60))
    # The Windows release embeds the Python files with CRLF. Compare their
    # original payload bytes with C++, then just normalize checkout newlines for
    # git's blob IDs at the release source revision.
    source_blobs = {
        "pyodide-internal:workers-api/src/asgi.py": "e2ed6ba3cad7bdffb346983444c443e01cfedc57",
        "pyodide-internal:topLevelEntropy/entropy_patches.py": "d76333909f4593330f74c766df65a75dfbe5b704",
    }
    verified_sources = set()
    with peer.Bundle.from_bytes(frame) as bundle, tempfile.TemporaryDirectory(dir=path.parent) as temp:
        if len(listed) != 28 or len(bundle.modules) != len(listed):
            raise ValueError("Expected 28 modules")
        for index, (module, entry) in enumerate(zip(bundle.modules, listed)):
            tag = module.which()
            payload = getattr(module, tag)
            if tag == "json":
                payload = payload.encode("utf-8")
            expected = dict(name=module.name, kind=tag, type=module.type.raw, bytes=len(payload))
            if entry != expected:
                raise ValueError(f"Module index mismatch at {index}: {entry}")
            output = Path(temp) / str(index)
            subprocess.run([*cli, "extract", path, module.name, output], check=True, timeout=60)
            extracted = output.read_bytes()
            if extracted != payload:
                raise ValueError(f"Payload differs from C++ reader for {module.name}")
            if module.name in source_blobs:
                text = extracted.replace(b"\r\n", b"\n")
                header = f"blob {len(text)}\0".encode()
                if hashlib.sha1(header + text).hexdigest() != source_blobs[module.name]:
                    raise ValueError(f"Payload differs from release source for {module.name}")
                verified_sources.add(module.name)
        if verified_sources != source_blobs.keys():
            raise ValueError("A required upstream Python source is absent")
    print("Verified all 28 linked module payloads against C++ and two Python sources against Git.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--verify-with", nargs="+", metavar="COMMAND")
    args = parser.parse_args()
    data = release_frame(args.archive)
    with args.output.open("xb") as output:
        output.write(data)
    if args.verify_with:
        verify(data, args.output.resolve(), args.verify_with)
