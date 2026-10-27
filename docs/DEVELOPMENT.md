# Development

CI pins MoonBit `0.10.14+7d59c7ec9` with matching core. From the repository root:

```sh
moon update
moon fmt
moon info
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --release
```

Review generated `.mbti` diffs when changing public APIs; do not edit them by hand. All four backends run the same protocol tests. `tests/generated` and `examples/telemetry/generated` contain compiler output with handwritten tests alongside it.

## External oracles

Committed fixtures use official Cap'n Proto 1.5.0; see [regeneration](../fixtures/README.md). CI builds the same 1.5.0 compiler from its SHA-256-pinned source archive, regenerates the unchanged upstream test/compiler schemas, and exchanges messages with `pycapnp==2.2.1` on Python 3.12. The [schema compatibility peer](../examples/schema_compat) checks generic, dynamic and constant values; the telemetry peer performs the application calculation independently.

The portable example requires no filesystem or host FFI:

```sh
moon run --target wasm examples/roundtrip
moon run --target wasm-gc examples/roundtrip
moon run --target js examples/roundtrip
moon run --target native examples/roundtrip
```

## Native and Node.js CLIs

`internal/stdio` is a host adapter. C handles binary stdin/stdout; JS uses Node's `node:fs`. Protocol parsing, generation and packing remain MoonBit code. Standard input/output is supported on native and Node.js. Wasm users can use file-based commands where the host filesystem package is available, or call the library directly.

Linux CI uses the system C compiler. On Windows, configure a C toolchain supported by the installed MoonBit version. Initial local verification used LLVM-MinGW 20261006 and MoonBit 0.10.14. This combination needed `_CRT_RAND_S` defined for the MoonBit runtime; LLVM-MinGW's Clang accepted the temporary environment setting `CCC_OVERRIDE_OPTIONS=+-D_CRT_RAND_S`. This is a toolchain detail, not a library flag. The Node.js request-file path needs no C compiler.

## Layout

- Root `reader_*`, `builder_*`, `pointer_builder.mbt`, `copy.mbt`, `canonical.mbt`, `packed.mbt`, `stream.mbt`: serialization runtime.
- `codegen/`: compiler request decoding and MoonBit source generation.
- `cmd/`: compiler plugin and packing utilities.
- `fixtures/`, `tests/`: independent fixtures, generated API tests and regressions.
- `examples/`: portable roundtrip, cross-language batch processing, and unchanged-schema interoperability.

Changes should include a reproducer or reference fixture where practical. Do not add performance or production-use claims without reproducible evidence.

## Published package verification

After publishing to Mooncakes, run this from the matching release checkout:

```sh
python scripts/verify_release.py --release-tag v0.2.2
```

The script requires Python 3.12, MoonBit 0.10.14, Node.js 24, a native C compiler,
and the official `capnp` 1.5.0 executable. `--moon` and `--capnp` accept explicit
tool paths. `--version` can select an older published package for comparison;
when `--release-tag` is supplied, it must match both the checkout and package.

A temporary module under `work/` installs the registry package, generates an
unchanged schema containing a name collision, generic container, AnyPointer and
constants, and runs the resulting API on all four targets. It also checks the
package's required files, MIT notices and original upstream hashes; compiles
its native/Node.js host adapters; exercises binary stdin/stdout and invalid
request handling. It removes only its own temporary directory when finished.

CI runs this check for published releases and manual workflow runs. Push/PR
checks do not require an unreleased package to exist in the registry. Publish
the Mooncakes package before publishing its GitHub release; the release check
binds the tag, manifest, CLI and installed package to the same version.
