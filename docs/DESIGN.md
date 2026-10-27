# Design and maintenance notes

## Protocol boundary

The official Cap'n Proto 1.5.0 compiler parses schema syntax, resolves imports,
aliases and constants, and computes field layouts. `codegen/` consumes its
binary `CodeGeneratorRequest` and emits MoonBit readers/builders. Applications
use those bindings and the MoonBit runtime without linking the C++ runtime.
This keeps a single authoritative layout engine and allows existing protocol
files, including unrelated interface declarations, to remain unchanged.

RPC transport, capability-table identity/lifetime and runtime schema reflection
are separate concerns. Reading an opaque capability index does not provide the
remote object or authorize calling it. Cross-message copies without a mapping
therefore reject non-null capabilities.

## Readers, builders and resources

Readers retain the original input bytes and expose views. Framing is checked at
message creation; object bounds and traversal/depth budgets are checked lazily
when pointers are followed. A successfully created message is not evidence that
every pointer was examined. Text decoding validates UTF-8 and materializes a
String, so this API is not described as universally zero-copy.

Builders allocate into an append-only, single-segment arena. This is a valid
Cap'n Proto encoding and keeps ownership simple. Replacing a pointer does not
reclaim its old storage; `finish` returns a snapshot while handles remain valid.
Opaque copy recursively preserves unknown fields, duplicates aliases, and rolls
back destination changes if an error or configured limit occurs. Reader work
budgets stay consumed even when a copy fails.

`FrameDecoder` handles fragmented and concatenated input separately from object
decoding. It progresses through segment count, segment table and payload once,
retains only an incomplete frame, and requires explicit EOF validation. Its
logical byte limit does not claim a process RSS bound. Callers should bound
input chunks and immediately process/release returned frames. The streaming
example demonstrates that pattern using 8 KiB reads and a 1 MiB per-frame limit.

## Generated APIs and evolution

Known generic bindings generate typed wrappers. Unbound parameters and
indefinitely growing recursive specializations keep explicit dynamic views.
This preserves wire data and does not force a hand-expanded replacement schema;
it does not promise infinitely many static types. Name allocation considers
all emitted symbols, including wrappers and constants, and disambiguates legal
schema names deterministically.

Scalar defaults use the standard XOR representation; pointer defaults and
constants preserve compiler-resolved values. Groups and unions can overlap
storage. Resetting one group must clear only its own fields and discriminants,
without overwriting an interleaved neighbor. Unknown union tags are checked
before exposing known members. Evolution tests use original upstream schemas,
with independent C++ inputs and verification of unknown-field forwarding.

## Evidence and changes

- A protocol bug should have an independent fixture or another implementation
  that demonstrates the expected value, not only a roundtrip through this SDK.
- Change the generator and regenerate affected bindings together. CI rejects a
  committed interface that the current generator no longer reproduces.
- Preserve upstream fixture bytes and licensing; recorded hashes prevent a
  simplified schema from silently replacing the original compatibility case.
- Review public `.mbti` changes and resource/error behavior before publishing.
- Run the fresh Mooncakes consumer after publishing: checkout-only CI cannot
  prove that required host files and licenses were included in the package.
- Keep benchmark raw rounds, workload, environment and source snapshot. Compare
  equivalent work, disclose noise, and do not infer production use or a language
  ranking from this project's own examples.

The [conformance matrix](CONFORMANCE.md) records what is verified and by which
peer; [compatibility](COMPATIBILITY.md) records user-visible limits. Reports of
external deployments should only be added when the maintainer can substantiate
them and is authorized to name them.
