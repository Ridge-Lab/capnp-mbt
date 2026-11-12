"""Check workerd's binary deployment config against its original test Worker."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, SAMPLE, UPSTREAM, build, inspector


def rejected(command):
    result = subprocess.run(command, capture_output=True)
    if result.returncode == 0:
        raise RuntimeError(f"Expected failure: {command}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workerd", help="Pinned workerd executable to rebuild and run the upstream Worker")
    parser.add_argument("--capnp", default="capnp")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--node", default="node")
    parser.add_argument("--targets", nargs="+", choices=("js", "native"), default=["js"])
    args = parser.parse_args()
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    # CI retains the report and exchanged files. Generated code, downloaded
    # dependencies and compiler outputs are only needed while the check runs.
    with tempfile.TemporaryDirectory(dir=directory) as temporary:
        project = Path(temporary) / "project"
        build(project, args.moon, args.capnp, args.targets)
        check_exchange(args, directory, project)


def check_exchange(args, directory, project):
    config = SAMPLE / "config.bin"
    if args.workerd:
        compiled = subprocess.check_output([args.workerd, "compile", "--config-only", "config.capnp"], cwd=SAMPLE)
        if compiled != config.read_bytes():
            raise ValueError("workerd compile --config-only differs from the pinned artifact")
        config = directory / "rebuilt.bin"
        config.write_bytes(compiled)
        result = subprocess.run([args.workerd, "test", "--binary", str(config)], check=True, capture_output=True)
        output = (result.stdout + result.stderr).decode("utf-8")
        for test in ("main:testMath", "main:testStrings"):
            if "[ PASS ] " + test not in output:
                raise ValueError(f"Missing workerd test result: {test}\n{output}")

    # Exercise non-source payloads and reference-only modules that aren't used
    # by the upstream JS sample. pycapnp writes the extra test message.
    import capnp
    schema = capnp.load(str(UPSTREAM / "workerd.capnp"),
                        imports=[str(ROOT / "fixtures/upstream/capnproto-1.5.0")])
    embedded = [("esModule", "export default 'é';"), ("commonJsModule", "module.exports=5"),
                ("text", "音频"), ("data", b"\x00\xff\x80"), ("wasm", b"\x00asm\x01\x00\x00\x00"),
                ("json", '{"ok":true}'), ("pythonModule", "print(42)")]
    modules = [{"name": kind, kind: value} for kind, value in embedded]
    modules.append({"name": "builtin", "bundled": "/workerd/kv.js"})
    services = [{"name": "mixed", "worker": {"modules": modules}}]
    mixed = directory / "mixed.bin"
    mixed.write_bytes(schema.Config.new_message(services=services).to_bytes())
    duplicate = directory / "duplicate.bin"
    duplicate.write_bytes(schema.Config.new_message(services=services + services).to_bytes())
    broken = directory / "truncated.bin"
    broken.write_bytes(config.read_bytes()[:-1])
    source = (SAMPLE / "worker.js").read_bytes()
    for target in args.targets:
        cli = inspector(project, target, args.node)
        observed = json.loads(subprocess.check_output([*cli, "list", config]))
        if observed != [{"service": "main", "module": "worker", "kind": "esModule"}]:
            raise ValueError(f"Unexpected compiled Worker module list: {observed}")
        extracted = directory / f"worker-{target}.js"
        subprocess.run([*cli, "extract", config, "main", "worker", extracted], check=True)
        if extracted.read_bytes() != source:
            raise ValueError("Extracted JS differs from workerd's actual build input")
        rejected([*cli, "extract", config, "main", "worker", extracted])
        rejected([*cli, "list", broken])
        listed = json.loads(subprocess.check_output([*cli, "list", mixed]))
        if [entry["kind"] for entry in listed] != [k for k, _ in embedded] + ["bundled"]:
            raise ValueError(f"Incorrect mixed module list: {listed}")
        for kind, value in embedded:
            dest = directory / f"{target}-{kind}.out"
            subprocess.run([*cli, "extract", mixed, "mixed", kind, dest], check=True)
            if dest.read_bytes() != (value if isinstance(value, bytes) else value.encode("utf-8")):
                raise ValueError(f"{target}: incorrect {kind} payload")
        unused = directory / f"{target}-absent.out"
        for message, name in [(mixed, "builtin"), (mixed, "missing"), (duplicate, "text")]:
            rejected([*cli, "extract", message, "mixed", name, unused])
        if unused.exists():
            raise ValueError("Failed extraction created an output file")
    report = {"workerd_package": "1.20261112.1", "rebuilt_and_tested": bool(args.workerd),
              "config_sha256": hashlib.sha256(config.read_bytes()).hexdigest(),
              "worker_sha256": hashlib.sha256(source).hexdigest(), "targets": args.targets}
    (directory / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
