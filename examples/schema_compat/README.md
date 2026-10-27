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
Verified MoonBit output: generics, AnyPointer, constants, schema evolution and union/group transitions
```

Use `--target native` to run the same MoonBit peer as a native executable.
Generated bindings are committed in `tests/generated/upstream` and
`tests/generated/compiler`, so this exchange does not require a local compiler.

## What is checked

| Existing declaration | Input and independently checked output |
| --- | --- |
| `TestUseGenerics.basic` | `TestGenerics(TestAllTypes, TestAnyPointer)` retains concrete field types; reversed bindings and a list of nested generic structs round-trip |
| `TestUseGenerics.inner2` | Ancestor `Bar` binding, local `Baz=Text`, bound inner scope and unbound inner scope keep their distinct meanings |
| `unspecified`, `bindEnumList` | Unbound parameter carries Text through AnyPointer; a bound enum list preserves known ordinals `0`/`7` and unknown ordinal `40000` in both directions |
| Generic defaults and aliases | Unwritten fields expose `123`, `"text"`, `321`, `[12,34]` and `[12,34,56]` from the original schema |
| `TestAnyPointer` | Struct, Int32 list, UTF-8 Text, arbitrary Data and null are interpreted and copied without dropping unknown content |
| `TestAnyOthers` | AnyStruct and AnyList use their constrained views; a null capability remains null |
| `genericConstant`, `anyPointerConstants`, `embeddedStruct` | Generated constant functions produce real messages that Python/C++ decodes and checks |
| `embeddedData`, `embeddedText` | Generated values match Python/C++ constants and original embedded files byte for byte, including the Text file's final newline |
| `CodeGeneratorRequest` | Both peers check `Node`, `Brand.scopeId`, each bound `Type.typeId`, and AnyPointer-backed `Value` against the original schema declarations |
| `TestOldVersion`, `TestNewVersion` | An old writer is read with new recursive defaults (`987`, `"baz"`) in both languages; MoonBit forwards a new message through the older typed view, and Python verifies the unknown root and child extension fields survive |
| `TestOldUnionVersion`, `TestNewUnionVersion` | Existing `a`/`b` alternatives retain their meanings when `a` becomes a nested union group; Python reads the MoonBit nested alternative through both old and new views |
| `TestUnionInUnion`, `TestInterleavedGroups` | Nested union reinitialization resets its tag and value; switching or clearing one interleaved group preserves the other group's data, pointers and tag |
| `TestUnion` viewed through `TestOldUnionVersion` | A legal C++-built tag `4` is unknown to the smaller view: both implementations reject its known members, MoonBit exposes the raw tag and forwards the complete payload without loss |

Python deliberately uses a small initial segment, forcing multi-segment input.
MoonBit verifies both the ordinary frame and the packed frame. The reply uses
generated builders for new values and schema-free deep copy for open payloads.
Assertions check decoded values; merely exiting the generator is insufficient.
For an unknown enum ordinal, the Python peer uses the original generic's
unbound view to populate a UInt16 list with the C++ builder, then interprets it
through the original bound enum-list schema. It does not patch message bytes or
add an enum declaration to the source schema.

The unknown-union case deliberately uses two existing layout-test declarations
whose discriminants share an offset. It tests the unknown-tag guard and opaque
forwarding, not a protocol-evolution relationship between those two types.
Python checks the original schema offsets and constructs the payload with the
C++ builder; no wire bytes are patched. Actual old/new-version compatibility is
tested separately with upstream's explicitly paired version declarations.

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
