# Unmodified Cap'n Proto 1.5.0 fixtures

These files were copied byte for byte from the official Cap'n Proto C++ 1.5.0
source distribution. No declarations, imports, IDs, defaults, constants,
annotations, interfaces, comments, or embedded data have been removed or
rewritten for this project. The files retain their upstream MIT notices; the
distribution's complete license is in [LICENSE.txt](LICENSE.txt).

- Release source archive: <https://capnproto.org/capnproto-c++-1.5.0.tar.gz>
- Archive SHA-256: `77dbc13ca82d9c87ddb4581dd49559d45b63096433d3dadea08b7f31b360a5ba`
- Tagged upstream tree: <https://github.com/capnproto/capnproto/tree/v1.5.0/c%2B%2B/src/capnp>
- Original prefix inside the source distribution: `src/capnp/`
- Original prefix inside the Git repository: `c++/src/capnp/`

The manifest below was checked against a fresh binary-safe extraction of that
archive. Upstream line endings and final blank lines are preserved. The local
Git attributes disable text conversion and whitespace checks only for those
upstream files; this project-authored README uses the repository's normal rules.

`test.capnp` is the reference implementation's existing test protocol. It
contains generic types, nested scopes and aliases, AnyPointer/AnyStruct/AnyList,
scalar/list/struct constants, embedded values, and RPC interfaces. A
serialization-only generator must not require deleting the unrelated interface
declarations. The three `testdata` files are required by its `embed` constants.
`stream.capnp` supplies the compiler's implicit import for methods whose return
type is `stream`; retaining it lets the complete upstream schema compile even
when generation does not emit RPC clients or servers.

`schema.capnp` is the actual compiler-plugin protocol, not a simplified schema
created for the MoonBit implementation. `test-import.capnp` and
`test-import2.capnp` exercise importing both this protocol and `test.capnp`.

From the repository root, this command checks that the fixture set is complete
using the official compiler (with `capnpc-capnp` installed alongside `capnp`):

```sh
capnp compile -ocapnp \
  -Ifixtures/upstream/capnproto-1.5.0 \
  --src-prefix=fixtures/upstream/capnproto-1.5.0 \
  fixtures/upstream/capnproto-1.5.0/capnp/test-import2.capnp
```

The include root and source prefix deliberately match so the compiler does not
load `c++.capnp` under two different logical paths. No MoonBit generated output
is included in this directory.

## SHA-256 manifest

Hashes cover the exact file bytes, including line endings. Preserve these bytes
when checking out or refreshing fixtures. Paths are relative to this directory.

| Path | SHA-256 |
| --- | --- |
| `LICENSE.txt` | `9564998c8d7f270a61a8b89869a8d17a9d5e3783b64027788b5e339ec8479e10` |
| `capnp/c++.capnp` | `52ead0eaa560b21e692d6f3d9966a52dfc99e19f53ae2d7c7bd2944a240d86de` |
| `capnp/schema.capnp` | `3b81c9e8d02bc3da090c901ccdc113ed125128c75f74199b3f62e2ad315f5554` |
| `capnp/stream.capnp` | `5b0656ca3daca9ef28740c14813d5dd474fd0f9991ce99f652838f4cccf6fb30` |
| `capnp/test-import.capnp` | `dfc8fec000a7bcb24125442d218ca5795799076f4b6b85343e738debe89f7500` |
| `capnp/test-import2.capnp` | `a0c533fc543abbb24caf380226a254fbd734d6810a66f2e38c1eb7188774678d` |
| `capnp/test.capnp` | `5ab426b44cac8ad78f031688ccff70de3d7f9636baffa1133d31d30c017984b7` |
| `capnp/testdata/binary` | `73a8f3f8712655637b86d18653896d3a94ade8b384e7d82300a81890ba130c04` |
| `capnp/testdata/packed` | `f8001fa34f313bdc8a7c015d592f5fbde2cb1f32dd99a3ca54d14899f87938c0` |
| `capnp/testdata/short.txt` | `d009d68ad9f54c563213c9b4dff81cf82d6755df6670bfe3523d0f77a67b5236` |

## Interoperability cases

Use the original schema in both implementations. Generated API names can differ
by language; changing the source schema to make generation succeed is not an
acceptable workaround.

| Upstream declaration | Required assertions |
| --- | --- |
| `TestUseGenerics.basic` | `foo` is `TestAllTypes`; `rev.foo` is `TestAnyPointer`; values survive both encoding directions |
| `TestUseGenerics.inner2` | `bar` uses the ancestor `Bar` binding; `baz` is `Text`; `innerBound` inherits and `innerUnbound` erases outer arguments |
| `TestUseGenerics.unspecified` | Unspecified generic arguments remain usable as AnyPointer, not rejected or silently dropped |
| `TestUseGenerics.aliasInner2Bind` | Bound `List(UInt32)` parameter reads `[12, 34]` from its declared default |
| `TestUseGenerics.bindEnumList` | A generic parameter bound to `List(TestEnum)` preserves known ordinals `0`/`7` and unknown ordinal `40000` in both directions |
| `TestAnyPointer.anyPointerField` | Struct, list, Text, Data, and null payloads can be read, written, and copied with explicit interpretation |
| `TestAnyOthers` | AnyStruct/AnyList enforce their target kinds; non-null capabilities have an explicit unsupported/context policy |
| `TestConstants` | All scalar, blob, list, enum, and nested struct constants are exposed and match `capnp eval` |
| `genericConstant` | `foo.int16Field=123`, `rev.foo="text"`, `rev.rev.foo.int16Field=321` |
| `anyPointerConstants` | Its two struct payloads and two Int32-list payloads can be inspected and copied without a handwritten replacement schema |
| `embeddedData`, `embeddedText`, `embeddedStruct` | Compiler-resolved `embed` values are reproduced; Data and UTF-8 Text output match the original embedded files byte for byte, while Python/C++ checks the struct values |
| `schema.capnp:CodeGeneratorRequest` | Generate bindings and inspect a real request containing `Node`, `Type`, `Brand`, and `Value`; both peers check the generic's scope ID and the concrete bound type IDs |

Passing a selected case does not establish exhaustive compatibility with the
whole upstream test suite. Record the executed cases and implementations in the
project's compatibility report.
