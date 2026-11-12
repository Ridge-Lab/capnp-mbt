"""Build an inspector from workerd's original deployment schema and this checkout."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / "fixtures/upstream/workerd/config"
SAMPLE = UPSTREAM / "unit-tests"
EXAMPLE = Path(__file__).resolve().parent


def inspector(directory, target, node):
    executable = directory / "_build" / target / "release/build/example/workerd/cmd/inspect/inspect"
    return [node, str(executable.with_suffix(".js"))] if target == "js" else [str(executable.with_suffix(".exe"))]


def build(directory, moon, capnp, targets):
    directory.mkdir(parents=True, exist_ok=False)
    types = directory / "schema"
    types.mkdir()
    app = directory / "cmd/inspect"
    app.mkdir(parents=True)
    metadata = (ROOT / "moon.mod").read_text(encoding="utf-8")
    version = re.search(r'^version\s*=\s*"([^"]+)"', metadata, re.MULTILINE)[1]
    fs = re.search(r'"(moonbitlang/x@[^"]+)"', metadata)[1]
    (directory / "moon.work").write_text(
        f'members = [".", {json.dumps(ROOT.as_posix())}]\n', encoding="utf-8")
    (directory / "moon.mod").write_text(
        f'name = "example/workerd"\nversion = "0.0.0"\n'
        f'import {{ "Ridge-Lab/capnp@{version}", "{fs}" }}\n', encoding="utf-8")
    (app / "moon.pkg").write_text(
        'import { "example/workerd/schema", "Ridge-Lab/capnp", "moonbitlang/core/env", '
        '"moonbitlang/core/encoding/utf8", "moonbitlang/x/fs" }\n'
        'pkgtype(kind: "executable")\noptions(link: { "js": { "format": "esm" } })\n',
        encoding="utf-8")
    shutil.copyfile(EXAMPLE / "inspect.mbt", app / "inspect.mbt")
    request = directory / "request.bin"
    with request.open("wb") as protocol:
        subprocess.run([capnp, "compile", "--no-standard-import", "-I" + str(ROOT / "fixtures/upstream/capnproto-1.5.0"),
                        "--src-prefix=" + str(UPSTREAM), "-o-", str(UPSTREAM / "workerd.capnp")],
                       stdout=protocol, check=True)
    subprocess.run([moon, "-C", str(ROOT), "run", "--release", "--target", "js",
                    "--target-dir", str(directory / "generator-build"), "cmd/capnpc-moonbit",
                    "--", "--request", str(request), "--out", str(types)], check=True)
    for target in targets:
        subprocess.run([moon, "-C", str(directory), "build", "--release", "--deny-warn",
                        "--target", target, "cmd/inspect"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="New directory for generated bindings and executable")
    parser.add_argument("--target", choices=("js", "native"), default="js")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--node", default="node")
    parser.add_argument("--capnp", default="capnp")
    args = parser.parse_args()
    out = args.directory.resolve()
    build(out, args.moon, args.capnp, [args.target])
    print(subprocess.list2cmdline([*inspector(out, args.target, args.node), "list", str(SAMPLE / "config.bin")]))
