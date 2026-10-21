# Serialization standard and evidence

## Fixed baseline

Version 0.2.0 targets the serialization and data-declaration semantics of
**Cap'n Proto 1.5.0**, using its tagged
[encoding specification](https://github.com/capnproto/capnproto/blob/v1.5.0/doc/encoding.md),
[schema language](https://github.com/capnproto/capnproto/blob/v1.5.0/doc/language.md),
and [compiler schema](https://github.com/capnproto/capnproto/blob/v1.5.0/c%2B%2B/src/capnp/schema.capnp).

The completion criterion is practical: an existing schema's data declarations
can generate usable MoonBit APIs **without rewriting the protocol**, and its
values can be exchanged with the reference implementation. This includes
generic containers, AnyPointer payloads, constants, defaults and compatible
evolution, not only fixed scalar records. The official compiler remains
responsible for parsing, layout, import resolution, aliases, constant
expressions and `embed`; the MoonBit plugin consumes `CodeGeneratorRequest`.

The following is the compatibility surface to maintain, not a claim that
every possible schema has been exhaustively tested.

| Surface | Required behavior |
| --- | --- |
| Values | Void, Bool, every integer/float width, Text/Data, enums including unknown ordinals, structs, nested types and all list encodings |
| Field semantics | Scalar XOR defaults, non-empty pointer defaults, groups, unions, nested unions, missing/extra fields and documented compatible list/struct evolution |
| Generics | Explicit, inherited and ancestor-scope brands, nested generics, aliases, omitted parameters as AnyPointer, recursive references and generic defaults/constants |
| Dynamic payloads | AnyPointer/AnyStruct/AnyList access, construction and schema-free copying, including unknown data and pointer fields; explicit capability policy |
| Constants | Top-level/nested scalar, blob, enum, list, struct, AnyPointer and generic values, including compiler-resolved references and embedded data |
| Wire transport | Standard framing, segmented input, relative/single-far/double-far pointers, packed encoding and concatenated/partial-frame boundaries |
| Safety | Checked bounds and arithmetic, lazy validation, traversal/depth/allocation limits, malformed-pointer errors, and zero-sized-list amplification limits |

A single-segment writer is a valid strategy; it does not weaken segmented-input
support. Newly written struct lists use inline-composite encoding.

## Generic APIs without schema changes

Known bindings generate typed reader/builder wrappers. A brand includes the
target and relevant ancestor scope IDs. `inherit` passes existing bindings
through; absent or unbound parameters become AnyPointer. These cases are
distinct and appear together in the original upstream test protocol.

An indefinitely growing recursive type cannot have infinitely many static
specializations. Such edges retain an unbound wrapper with public `.inner`
views. The caller can continue reading or constructing its actual payload using
runtime pointer/struct/list APIs; the source schema and wire data stay intact.
This is a stated static-typing boundary, not an instruction to replace a generic
protocol with a hand-specialized one. Resource limits and naming behavior are
listed in [compatibility](COMPATIBILITY.md).

## Evidence using existing schemas

The [upstream fixture manifest](../fixtures/upstream/capnproto-1.5.0/README.md)
records unchanged 1.5.0 `test.capnp`, its imports and embedded data, and
`schema.capnp`, with MIT notices and byte-level hashes.

The [schema interoperability example](../examples/schema_compat/README.md)
uses that original `test.capnp` in Python/C++ and MoonBit. It exercises:

- `TestUseGenerics`: concrete, reversed, ancestor-bound and unbound parameters;
  nested container elements, enum-list binding, aliases and declared defaults.
- `TestAnyPointer`: struct, list, Text, Data and null payloads copied without
  knowing their fields; `TestAnyOthers`: AnyStruct/AnyList constraints and null
  Capability.
- `genericConstant`, `anyPointerConstants` and `embeddedStruct`: generated
  constant accessors written by MoonBit and checked by the independent peer.
- `schema.capnp:CodeGeneratorRequest`: generated bindings read an actual
  compiler request, inspect generic `Node`/`Brand`/`Value` content and write
  a request that Python/C++ can decode.

Python/C++ writes segmented and packed input. MoonBit validates it and writes
typed replies, copied opaque values and constants; Python/C++ verifies those
outputs. The interfaces and annotations in the upstream file are retained.
The existing [telemetry example](../examples/telemetry/README.md) separately
demonstrates a batch-processing application. Neither example is presented as
evidence of external production adoption.

The compiler-schema fixture supplies the actual plugin protocol used by the
generator. Its `Brand` structures describe generics; reading that file alone
would not demonstrate generic-container support. `TestUseGenerics` supplies
that evidence, while the project-authored [growing-generic regressions](../tests/generated/growing/growing_test.mbt)
exercise dynamic boundaries for increasing nested lists and duplicated type
arguments. Tests compare values across implementations rather than relying
only on a self-roundtrip, generated-code size or test count.

## Canonical form

Ordinary serialization does not require canonical output: the specification
explicitly permits non-canonical encoders. This release additionally provides
`canonicalize` for struct-root messages. Its output is an unpacked canonical
segment **without a segment table**, suitable as the input to a separate
hashing/signing operation. The function does not perform that operation.

[Reference-generated vectors](../fixtures/upstream/oracle-1.5.0/README.md)
cover null roots, empty structs/lists, dirty bit and byte padding, uniform
struct-list trimming, far pointers and preorder allocation. The implementation
also compares ordinary and segmented official fixtures with the official
converter's output. Null roots normalize to an empty-struct pointer; nested null
pointers remain null. See [compatibility](COMPATIBILITY.md) for input and output
limits.

## Capability and RPC boundary

A capability pointer contains a UInt32 index into an external table. Index zero
is still a non-null capability; it is not the zero pointer. Reserved OTHER
pointer encodings are invalid. Merely preserving this index does not preserve
the remote object's identity across messages or authorize an operation.

Interface declarations and null interface/Capability fields are accepted.
Explicit low-level APIs can inspect/store an opaque index. Deep copy rejects
non-null capabilities because it cannot remap an external table;
canonicalization rejects them too. RPC clients/servers, calls, promise
pipelining and capability lifetime management are separate from this
serialization endpoint.

Release claims should name the baseline, unchanged schema, peer and tested
cases. These checks substantiate interoperability for the exercised paths;
they do not justify “100% compatible” or “every schema works.”
