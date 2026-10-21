# Schema compiler

`generate(request)` accepts the binary `CodeGeneratorRequest` written by the
official `capnp compile -o-` command. It emits one `capnp_generated.mbt` file;
the command-line plugin creates a `moon.pkg` importing `Ridge-Lab/capnp` when
the output directory does not already contain one. All requested declarations
and their imported nodes share that MoonBit package.

The input is the compiler protocol, not source text. Bootstrap field offsets
are taken from `capnp 1.5.0` running `capnpc-capnp` on upstream `schema.capnp`.
The protocol definition is maintained by the [Cap'n Proto project](https://github.com/capnproto/capnproto/blob/v1.5.0/c%2B%2B/src/capnp/schema.capnp).

Generated APIs include scalar fields, exact 64-bit integers, text/data, enums,
structs, every scalar list encoding, nested lists, lists of structs, nested
declarations, imported declarations, groups, unions, field defaults, generic
brands, AnyPointer constraints and constants. Enum values unknown to the schema
retain their numeric representation. `using` aliases are resolved by the official
compiler, so callers can use existing schema sources directly.

- A struct `Person` produces `PersonReader` and `PersonBuilder`.
- `PersonReader::from_message(message)` reads a root view.
- `PersonBuilder::init_root(builder)` creates a root object.
- Fields use `get_display_name`, `set_display_name` and `init_children(length)`.
- List views expose `length()` and `get(index)`; list builders expose scalar
  `set(index, value)`, struct `get(index)` or nested-list `init(index, length)`.
- Struct and list pointer fields also expose `set_field(reader)` to deep-copy a
  value from another message, including fields unknown to the generated schema.
- `const name :Type = ...` produces `const_name()`. Scalar, enum, text/data,
  struct, list, generic and AnyPointer constant values come from the official
  compiler's evaluated `Value`, including imported references and embedded data.
- Union readers provide `which()` and `is_member()`. Reading an inactive member
  fails. A builder setter or initializer selects the member and clears overlapping
  storage without clearing adjacent non-union fields.
- A group's `get_group()` builder accessor preserves existing fields;
  `init_group()` resets that group's storage, including nested discriminants.
- Nested declaration names concatenate their enclosing declaration names.
  Imported same-name declarations receive a schema ID suffix. Built-in type
  names receive a `Schema` prefix; a field named `root` becomes `root_field`.
  A final allocation pass includes every generated Reader/Builder, list wrapper,
  generic specialization and constant accessor. Collisions receive a stable
  schema or specialization ID suffix, leaving ordinary names unchanged. Field
  name collisions receive `_f` plus their schema field index, with another suffix
  if that name is also occupied. Existing schemas therefore do not need to be
  renamed just because a declaration resembles a generated type or method.

Scalar defaults use the wire format's XOR semantics, including floating-point
bit patterns. Pointer defaults and constants are copied from the compiler
request into a compact canonical payload, embedded once in the generated file.
Only the referenced values and their lookup indices are retained; source-info
order, documentation, annotations and compiler metadata cannot affect this
payload. Defaults are read when the actual pointer is null. An explicitly
initialized empty list therefore overrides a nonempty default. Large default
values can still produce large generated files, and repeatedly reading an
absent pointer default reparses the compact payload.

`Box(Text)` generates `BoxAsTextReader` and `BoxAsTextBuilder`, whose field
accessors use `String`; `Box(List(UInt32))` has a typed list accessor. Brand
bindings include enclosing scopes, inherited bindings, nested generic types and
recursive permutations. An omitted binding produces the unbound prototype:
its parameter fields expose `PointerReader`/`PointerBuilder` rather than guessing
a concrete type. Generic lists of a known struct use inline-composite encoding.

Some legal schemas expand without a finite set of static specializations, such
as `Tree(T)` containing `Tree(Pair(T, T))`. At an edge with repeated parameter
growth, the generated accessor returns the target's unbound prototype. The
entire object remains readable and writable through its public `.inner` handle;
only static type information at that edge becomes dynamic. The tests write,
read and deep-copy three levels beyond such boundaries. This is a finite typed
view API over the complete wire value, not infinite static monomorphization.
Long specialized type names use deterministic internal ID suffixes.

AnyPointer fields expose pointer handles. AnyStruct and AnyList readers check
the pointer kind and return `StructReader` or `ListReader`; their setters copy
the matching object. Builders can initialize dynamic structs and scalar,
pointer or inline-composite lists. Capability/interface fields expose an opaque
capability index only. Non-null capabilities require a capability table, so
generic deep-copy operations reject them instead of transferring an index into
an unrelated message. Explicit index access does not provide RPC dispatch or
capability-table remapping. Interface declarations and their serialization
parameter structs can coexist with ordinary data schemas; no RPC stubs or
transport are generated. Annotations remain layout-neutral metadata.

Request size is limited to 16 MiB, node count to 10,000, and nested list/group/
scope depth to 32. Generic expansion has a depth limit of 128 and an additional
1,024-instance budget; recursive growth falls back to dynamic views before
exhausting these limits. The binary reader's traversal and nesting limits also
apply. Malformed requests produce diagnostics before output is returned.

The project-authored `.capnp` fixtures in `fixtures/` are compiled with official
Cap'n Proto 1.5.0. Their `.request.bin` files are compiler outputs, not handcrafted
wire layouts. The generated bindings under `tests/generated/` are compiled and
executed against independent official binary fixtures and runtime builders.
In addition, `tests/generated/upstream` is generated from the complete unchanged
upstream `capnp/test.capnp`, and `tests/generated/compiler` from the unchanged
`capnp/schema.capnp`. These compile the real generic, constant and compiler
protocol declarations, rather than a hand-written approximation of their layout.
