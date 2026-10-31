# Serialization conformance checks

Baseline: **Cap'n Proto 1.5.0** encoding, schema language and compiler protocol.
The [standard target](SERIALIZATION-STANDARD.md) defines the intended endpoint;
this document records how the implemented behavior is checked. It is not a
percentage-complete estimate or an assertion of exhaustive protocol coverage.

## Feature-to-evidence matrix

| Serialization behavior | Executable evidence | Independent reference |
| --- | --- | --- |
| Every scalar width, Text/Data, enums, nested structs and lists | [generated conformance tests](../tests/generated/conformance_test.mbt), [builder tests](../builder_test.mbt) | Official 1.5.0 encoded [conformance fixtures](../fixtures/README.md) |
| XOR defaults, non-empty pointer defaults, group/union transitions | [conformance](../tests/generated/conformance_test.mbt), [advanced tests](../tests/generated/advanced/advanced_test.mbt) | Official compiler-resolved field layouts and values; generic defaults also checked by the Python/C++ peer |
| Generic parameters, explicit/inherited/ancestor brands, aliases, nested containers | [brands tests](../tests/generated/brands/brands_test.mbt), [upstream tests](../tests/generated/upstream/upstream_test.mbt) | Original `test.capnp:TestUseGenerics`, read and written by [both peers](../examples/schema_compat) |
| Unbound parameters and recursively growing generic types | [growing tests](../tests/generated/growing/growing_test.mbt), [generator tests](../codegen/codegen_test.mbt) | Schemas accepted by official 1.5.0; project regressions access three levels beyond a dynamic boundary; unbound Text also crosses the Python/C++ peer |
| AnyPointer struct/list/Text/Data/null, AnyStruct and AnyList | [opaque-copy tests](../copy_test.mbt), [brands tests](../tests/generated/brands/brands_test.mbt) | Original `TestAnyPointer` and `TestAnyOthers` payloads independently checked in Python/C++ |
| Scalar, blob, enum, list, struct, generic and embedded constants | [upstream constant tests](../tests/generated/upstream/upstream_test.mbt) | Compiler-evaluated values; generic/AnyPointer/embedded struct constants independently decoded by Python/C++; embedded Text/Data compared byte-for-byte with original files |
| Large Unicode Text constants and defaults | [large Text tests](../tests/generated/long_text/long_text_test.mbt) | Official 1.5.0 compiles an embedded Text file with quotes, backslashes, newlines, CJK, Greek and emoji; generated values match the original file, and explicit empty Text overrides its non-empty default |
| Real compiler protocol containing Brand and AnyPointer-backed Value | [compiler tests](../tests/generated/compiler/compiler_test.mbt), [both peers](../examples/schema_compat) | Actual 1.5.0 request is read and rewritten; peers verify parameter names, Brand scope ID, binding type IDs and constant values |
| Multiple segments, near/single-far/double-far pointers | [reader oracle tests](../reader_oracle_test.mbt), [pointer checks](../reader_security_test.mbt), [opaque copy](../copy_test.mbt) | Official segmented fixture; Python/C++ creates small-segment messages; double-far boundary vectors are project-authored |
| Packed encoding and partial/concatenated frames | [packed tests](../packed_test.mbt), [stream tests](../stream_test.mbt) | Official packed fixture is decoded and re-encoded identically; CI uses `capnp decode --packed` on MoonBit output |
| Bounded incremental standard framing and EOF/error state | [decoder tests](../stream_decoder_test.mbt), [stream processor](../examples/streaming) | Independent C++ producer writes segmented messages through irregular pipe chunks; native/JS filters return reports independently decoded and verified in Python/C++ |
| Compatible field/list evolution and unknown enum values | [reader oracle tests](../reader_oracle_test.mbt), [reader checks](../reader_security_test.mbt), [enum tests](../tests/generated/names/names_test.mbt) | Official primitive/pointer-list inputs; project-authored old/new struct cases; generic enum ordinal `40000` round-trips through Python/C++ |
| Existing old/new protocol defaults and unknown-field forwarding | [upstream evolution tests](../tests/generated/upstream/evolution_test.mbt) | Original `TestOldVersion`/`TestNewVersion` and old/new union types exchange values with C++; opaque copying retains new fields even through the older generated view |
| Nested unions, interleaved groups and unknown discriminant guards | [upstream evolution tests](../tests/generated/upstream/evolution_test.mbt) | Original `TestUnionInUnion` and `TestInterleavedGroups` are independently checked; a C++-generated discriminant unknown to a smaller view cannot expose a known member and survives opaque copying |
| Schema-free copying preserves unknown contents and fails within budgets | [copy tests](../copy_test.mbt) | Complete official multi-segment fixture copied; canonical bytes compared, plus 1,024 deterministic malformed-input mutations and destination rollback checks |
| Canonical struct-message encoding | [canonical tests](../canonical_test.mbt) | [Official converter outputs](../fixtures/upstream/oracle-1.5.0/README.md); CI regenerates and byte-compares every canonical vector |
| Stable generation despite irrelevant compiler metadata | [generator regression](../codegen/codegen_test.mbt) | Stored Windows requests and fresh Linux 1.5.0 compilation generate identical formatted source; source-info/annotation/version mutations are also checked |
| Valid schema names colliding with generated Reader/Builder, list or generic names | [collision regression](../tests/generated/collision_compat/collision_test.mbt) | [Official-compiler input](../codegen/fixtures/collision-compat.capnp) retains the original names; generated APIs read/write each distinct declaration and field |

## Reproduce

Use MoonBit `0.10.16+b1a0e846e` with matching core. Node.js 24 and Python 3.12
are configured in CI. The generated bindings are committed; the first commands need no `capnp`
compiler or C++ runtime:

```sh
moon update
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --release
moon run --target js examples/roundtrip
python -m pip install -r examples/telemetry/requirements.txt
python examples/schema_compat/peer.py prepare work/schema-compat
moon run --target js examples/schema_compat -- work/schema-compat
python examples/schema_compat/peer.py verify work/schema-compat
```

Native compilation additionally needs a C compiler; see [development](DEVELOPMENT.md).
[The CI workflow](../.github/workflows/ci.yml) builds the SHA-256-pinned official
1.5.0 compiler, compares vendored files with the distribution, regenerates the
bindings, runs both application peers and compares canonical output. The
[unchanged-schema example](../examples/schema_compat/README.md) gives the exact
compiler commands. Generated source size and self-roundtrips alone are not the
independent compatibility evidence.

Published releases additionally run [the fresh-consumer check](../scripts/verify_release.py).
It installs the declared version from Mooncakes without a local source override,
generates new bindings and runs the consumer on all four backends. The check
verifies required distribution files and upstream hashes, builds the installed
native/Node.js CLIs, compares binary stdin/stdout packing with the official
fixture, and checks that an invalid compiler request cannot replace existing
output. Release tag, checkout manifest and installed package versions must agree.

## Explicit boundaries

Serialization includes generic and dynamic data declarations; they are not
deferred to a future release. The parser/layout engine is the official
compiler, while serialization and generated accessors run in MoonBit.
Unbound and indefinitely growing generic types use explicit dynamic views.
There is no requirement to rewrite the schema or discard their wire data.

RPC transport, capability-table ownership/remapping, reflection-based schema
loading, and editing an incoming message in place are separate SDK features.
Interface declarations and null capabilities can coexist with ordinary data.
Opaque capability indices can be inspected, but copying a non-null capability
without a table mapping is rejected. Resource budgets and malformed-input
errors are specified in [compatibility](COMPATIBILITY.md).
