# Compatibility and limits

## Wire format

The runtime reads one standard framed message, with ordinary data/list pointers, single-far and double-far pointers. It validates pointers lazily when accessed. A successful `read_message` validates framing, not every object reachable from the root.

`frame_length` returns `None` for a partial frame and a length for a complete one. Use its `offset` for concatenated frames. `read_message` rejects trailing bytes. Packed messages first pass through `unpack`; packing is not auto-detected.

The writer emits one segment, including inline-composite struct lists. It does not emit far pointers, canonical messages, capabilities, or RPC envelopes. Its output can be consumed by the reference implementation.

## Schema generation

The compiler plugin reads the official `CodeGeneratorRequest`. Supported declarations are structs, nested structs/enums, enums and groups. Fields support scalar and pointer defaults, lists, unions and named groups. Imports are flattened into one generated MoonBit package. Unknown enum ordinals remain available through the generated unknown-value variant.

RPC interfaces, generic parameters, AnyPointer fields and constant declarations fail with a diagnostic. Annotations have no generated runtime behavior. Unsupported declarations in a request can cause rejection even if an application does not use them. This is not a replacement for the official schema parser or layout engine.

Identifiers are normalized to MoonBit spelling; ambiguous generated symbols are diagnosed. Renaming a schema declaration may require API changes in consumers even when its wire ID remains the same. Keep generated files and schema changes in the same review.

Missing scalar fields return schema defaults using XOR encoding. Missing pointers use the declared default or an empty value. Extra fields are ignored. Compatible list-to-struct upgrades are supported; arbitrary incompatible schema changes are not. Unknown union alternatives cannot be accessed through an unrelated known member. This is not a schema compatibility checker.

## Resource accounting

| API | Default limit | Meaning |
| --- | --- | --- |
| `read_message` | 8,388,608 traversal words | Shared across readers; repeated dereferences consume budget |
| `read_message` | depth 64 | Maximum nested pointer traversal |
| `read_message` | 512 segments | Segment table limit |
| `frame_length` | 64 MiB | Maximum framed message size |
| `unpack` | 64 MiB | Maximum decompressed bytes |
| `Builder::new` | 8,388,608 words | Maximum arena allocation |
| `codegen.generate` | 16 MiB input | Maximum compiler request size |

Set smaller limits when accepting untrusted input. `read_message` receives an already allocated `Bytes`: enforce a byte limit while reading from a transport, before allocating the buffer. CLI stdin is bounded to 64 MiB. The request-file path reads the file before checking the generator limit and is intended for trusted build inputs.

Views retain backing bytes. Text validates UTF-8 and converts to a string; Text/Data access copies data. No allocation-free application-access claim is made. The writer is append-only: replacing a pointer retains unreachable arena data. Reuse field builders or build a fresh message when appropriate. `finish()` snapshots the frame without invalidating builders.

Low-level struct numeric accessors use **byte offsets**; Bool uses **bit offsets**; pointer fields use **slot indexes**. Prefer generated APIs in application code.

Authentication, transport backpressure, framing policy, durable storage and application validation remain the caller's responsibility.
