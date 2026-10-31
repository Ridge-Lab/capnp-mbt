# Compatibility and limits

Version 0.3.1 uses **Cap'n Proto 1.5.0** as its serialization baseline. The
[standard target](SERIALIZATION-STANDARD.md) defines the endpoint; the
[unchanged-schema example](../examples/schema_compat/README.md) records a
reproducible interoperability case. This is not a claim that every schema or
every feature of the C++ SDK has been tested.

## Messages and dynamic values

`read_message` accepts exactly one standard framed message, including ordinary,
single-far and double-far pointers. It checks framing immediately and validates
objects lazily on access. Success does not validate every reachable object.
`frame_length` identifies partial and concatenated frames. Packed input must
first pass through `unpack`; packing is not auto-detected.

`FrameDecoder` accepts arbitrary chunks of standard unpacked frames. `feed`
returns complete frames and retains only the unfinished tail. Segment counts,
table size and declared frame length are checked before waiting for the body.
`finish` detects truncated EOF; a successful finish is idempotent and closes
feeding. Any framing error clears the tail and enters a failed state. Call
`reset` to reuse a failed or finished decoder. If a feed call fails, none of
that call's frames are returned; frames returned by earlier calls remain valid.
The limit applies to each frame and logical tail-buffer length, not the total
size of a returned batch or peak process memory. Framing alone does not validate
object pointers. The implementation scans each table once and appends body
bytes once, avoiding repeated parsing or shifting of a growing prefix.

The writer emits one segment and inline-composite struct lists. `finish()`
returns a snapshot with stream framing. `canonicalize(message)` instead returns
an unpacked canonical **segment without the segment table**. Its root must be
a struct; null roots normalize to empty structs and list roots are rejected.
Canonicalization preserves pointer order, trims zero sections, clears unused
list padding and rejects capabilities. Ordinary writer output is not promised
to be canonical.

`PointerReader`/`PointerBuilder` expose opaque values. Text and Data are byte
lists on the wire; their intended meaning comes from the schema or caller.
`set`, `set_struct` and `set_list` copy all on-wire fields and child objects,
including fields unknown to the caller. Copies are independent; source aliases
are duplicated. On `CapnpError`, the destination slot and new arena allocations
are restored, while the source traversal budget remains consumed.

## Generated APIs

The plugin consumes the official compiler's `CodeGeneratorRequest`. It generates
structs, enums, groups, unions, nested declarations, lists, scalar/pointer
defaults, AnyPointer/AnyStruct/AnyList and constants. The official compiler
resolves imports, aliases, constant expressions and embedded values. Imports
are flattened into one MoonBit package. Foreign annotations have no generated
runtime behavior. Interface declarations are accepted alongside data types;
they do not produce RPC stubs.

Generic brands resolve explicit and inherited bindings, including parameters
from enclosing scopes. Known bindings produce typed wrappers. Omitted bindings
remain AnyPointer. When a recursive generic would require indefinitely growing
specializations, that edge uses an unbound view with public `.inner` handles.
Data remains accessible without changing the schema, but static type knowledge
at that boundary must be supplied by the caller. Generation has request-size,
scope/type-depth and specialization-count limits.

Top-level and nested constants are exposed through generated `const_*()`
accessors. Pointer constants and non-empty defaults retain the compiler-resolved
values in a compact embedded value table. Source positions, annotations and
other unrelated compiler metadata are omitted from that table. Generated files
do not implement a runtime schema parser.
Large Text constants and defaults are emitted as bounded, escaped string chunks
joined at runtime, so Unicode content does not exceed MoonBit's source-line limit.

Unknown enum ordinals remain available through the generated unknown-value
variant. Missing fields return schema defaults; extra fields can be skipped or
preserved by opaque copying. Compatible list-to-struct evolution is supported.
Scalar or pointer views of an inline-composite list require the corresponding
data or pointer section, matching the reference implementation; absent sections
are not silently treated as valid values of an incompatible list type. Struct
views still supply defaults for missing fields. Bit lists cannot evolve into
struct lists under the encoding specification.
Unknown union alternatives are not exposed as unrelated known members.
Arbitrary incompatible schema changes are not repaired automatically.

Identifiers are normalized to MoonBit spelling. Name allocation includes
Reader/Builder types, generated list wrappers, concrete generic instances and
constant accessors. Conflicts use deterministic declaration-ID or field/enum
ordinal suffixes, so a valid source schema does not need renaming to avoid a
MoonBit symbol collision. Ordinary non-conflicting API names are preserved.
Keep schema and generated API changes in the same review even when their wire
IDs remain compatible.

## Capability boundary

Null interface/Capability fields are supported. The explicit low-level
`capability_index` and `set_capability_index` APIs inspect/store a UInt32 index;
they do not create, transport or authorize a capability. A non-null index needs
an external capability table. Deep copy rejects it because no table remapping
is available; canonicalization rejects it as well. RPC calls, servers, promise
pipelining and distributed capability lifetime management are outside this SDK.

## Resource accounting

| API | Default limit | Meaning |
| --- | --- | --- |
| `read_message` | 8,388,608 traversal words; depth 64; 512 segments | Shared across views; repeated dereferences and far-pointer inspection consume budget |
| `frame_length` | 64 MiB | Maximum framed message size |
| `FrameDecoder::new` | 64 MiB/frame; 512 segments | Unfinished frame retained between feed calls; returned batches are controlled by the caller's chunk size |
| `unpack` | 64 MiB | Maximum decompressed bytes |
| `Builder::new` | 8,388,608 words | Arena allocation, including the root pointer |
| Opaque deep copy | 8,388,608 words; depth 64 | Independent copy budget, in addition to reader and destination limits |
| `canonicalize` | 8,388,608 output words; depth 64 | Output allocation and recursive depth, in addition to reader limits |
| `codegen.generate` | 16 MiB input | Maximum compiler request size |

Copy depth accepts 0..256; canonical depth accepts 1..256. Empty-list and
zero-size-struct amplification is accounted for. These limits are not promises
of a particular peak process memory use.

Enforce a transport byte limit **before** allocating input `Bytes`.
`read_message` receives an already allocated buffer. The compiler and packing
CLIs' whole-input stdin adapter is bounded to 64 MiB. The streaming example
instead reads at most 8 KiB at a time and limits each frame to 1 MiB, without
limiting the cumulative stream length. The request-file path reads the file
before checking the generator limit and is intended for trusted build inputs.

Views retain backing bytes. Text validates UTF-8; Text/Data access materializes
values. The writer is append-only: replacing a pointer retains unreachable arena
data. `finish()` does not invalidate builder handles. Received messages are not
edited in place.

Low-level numeric offsets are **bytes**, Bool offsets are **bits**, and pointer
indexes are **slots**. Authentication, transport policy and application-level
validation remain the caller's responsibility.
