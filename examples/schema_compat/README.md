# Existing schemas: generics, AnyPointer and constants

This example uses the **unmodified Cap'n Proto 1.5.0** `test.capnp` and
`schema.capnp`. The original files, imports, embedded data, MIT notices and
SHA-256 manifest are in [the upstream fixtures](../../fixtures/upstream/capnproto-1.5.0).
No generic declarations are replaced with handwritten concrete schemas.

`test.capnp` exercises the standard data model; `schema.capnp` is the real
protocol spoken by the official compiler and its language plugins. The
[telemetry example](../telemetry) separately demonstrates an application that
exchanges measurements and computed results.

## Run the two peers

Requirements: MoonBit 0.10.14, Python 3.12, `pycapnp==2.2.1`, and Node.js 24 for
the JS target. Run from the repository root:

```sh
moon update
python -m pip install -r examples/telemetry/requirements.txt
python examples/schema_compat/peer.py prepare work/schema-compat
moon run --target js examples/schema_compat -- work/schema-compat
python examples/schema_compat/peer.py verify work/schema-compat
```

The last command prints:

```text
Verified MoonBit output: bound/nested/unbound generics, AnyPointer kinds, defaults and constants
```

Use `--target native` to run the same MoonBit peer as a native executable.
Generated bindings are committed in `tests/generated/upstream` and
`tests/generated/compiler`, so this exchange does not require a local compiler.

## What is checked

| Existing declaration | Input and independently checked output |
| --- | --- |
| `TestUseGenerics.basic` | `TestGenerics(TestAllTypes, TestAnyPointer)` retains concrete field types; reversed bindings and a list of nested generic structs round-trip |
| `TestUseGenerics.inner2` | Ancestor `Bar` binding, local `Baz=Text`, bound inner scope and unbound inner scope keep their distinct meanings |
| `unspecified`, `bindEnumList` | Unbound parameter carries Text through AnyPointer; a bound enum list preserves its ordinals |
| Generic defaults and aliases | Unwritten fields expose `123`, `"text"`, `321`, `[12,34]` and `[12,34,56]` from the original schema |
| `TestAnyPointer` | Struct, Int32 list, UTF-8 Text, arbitrary Data and null are interpreted and copied without dropping unknown content |
| `TestAnyOthers` | AnyStruct and AnyList use their constrained views; a null capability remains null |
| `genericConstant`, `anyPointerConstants`, `embeddedStruct` | Generated constant functions produce real messages that Python/C++ decodes and checks |
| `CodeGeneratorRequest` | Bindings generated from `schema.capnp` read an actual 1.5.0 compiler request, inspect `Node`, `Brand` and AnyPointer-backed `Value`, and serialize it for Python/C++ verification |

Python deliberately uses a small initial segment, forcing multi-segment input.
MoonBit verifies both the ordinary frame and the packed frame. The reply uses
generated builders for new values and schema-free deep copy for open payloads.
Assertions check decoded values; merely exiting the generator is insufficient.

## Regenerate from the original schema files

Install the official `capnp` **1.5.0** compiler and a C compiler for MoonBit's
native plugin, then run:

```sh
moon build --target native --release cmd/capnpc-moonbit
capnp compile --no-standard-import -Ifixtures/upstream/capnproto-1.5.0 --src-prefix=fixtures/upstream/capnproto-1.5.0 -o./_build/native/release/build/cmd/capnpc-moonbit/capnpc-moonbit.exe:tests/generated/upstream fixtures/upstream/capnproto-1.5.0/capnp/test.capnp
capnp compile --no-standard-import -Ifixtures/upstream/capnproto-1.5.0 --src-prefix=fixtures/upstream/capnproto-1.5.0 -o./_build/native/release/build/cmd/capnpc-moonbit/capnpc-moonbit.exe:tests/generated/compiler fixtures/upstream/capnproto-1.5.0/capnp/schema.capnp
moon fmt
git diff --exit-code -- tests/generated/upstream tests/generated/compiler
```

The include root also contains `stream.capnp`, an implicit dependency of the
upstream streaming-method declaration. Removing that declaration to avoid its
dependency would change the protocol and invalidate this check.

## Scope

The [versioned serialization target](../../docs/SERIALIZATION-STANDARD.md)
defines the completion criterion. These selected cases provide reproducible
evidence, not a proof that every possible schema is covered. Interface
declarations can coexist with data declarations; this example does not invoke
RPC methods or transfer live capability tables. Unbound and recursively growing
generic boundaries use explicit dynamic views rather than an infinite set of
static specializations. The schema and wire data remain unchanged.
