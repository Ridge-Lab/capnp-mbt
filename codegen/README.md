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
declarations, imported declarations, groups, unions and field defaults. Enum
values unknown to the schema retain their numeric representation.

- A struct `Person` produces `PersonReader` and `PersonBuilder`.
- `PersonReader::from_message(message)` reads a root view.
- `PersonBuilder::init_root(builder)` creates a root object.
- Fields use `get_display_name`, `set_display_name` and `init_children(length)`.
- List views expose `length()` and `get(index)`; list builders expose scalar
  `set(index, value)`, struct `get(index)` or nested-list `init(index, length)`.
- Union readers provide `which()` and `is_member()`. Reading an inactive member
  fails. A builder setter or initializer selects the member and clears overlapping
  storage without clearing adjacent non-union fields.
- A group's `get_group()` builder accessor preserves existing fields;
  `init_group()` resets that group's storage, including nested discriminants.
- Nested declaration names concatenate their enclosing declaration names.
  Imported same-name declarations receive a schema ID suffix. Built-in type
  names receive a `Schema` prefix; a field named `root` becomes `root_field`.
  Remaining generated-name collisions are rejected with a diagnostic before
  any output is returned.

Scalar defaults use the wire format's XOR semantics, including floating-point
bit patterns. Nonempty struct/list defaults are retained from the compiler
request, embedded once in the generated file and read when the actual pointer
is null. An explicitly initialized empty list therefore overrides a nonempty
default. This implementation prioritizes correct default semantics; large
schema requests containing pointer defaults can produce large generated files,
and repeatedly reading an absent pointer default reparses its embedded request.

Unsupported declarations fail explicitly: RPC interfaces, generic types,
AnyPointer fields and constant declarations. Annotations are accepted as metadata
and do not alter the wire layout. Request size is limited to 16 MiB, node count
to 10,000, and nested list/group/scope depth to 32; the binary reader's traversal
and nesting limits apply as well. This is not a full Cap'n Proto RPC system.

The project-authored `.capnp` fixtures in `fixtures/` are compiled with official
Cap'n Proto 1.5.0. Their `.request.bin` files are compiler outputs, not handcrafted
wire layouts. The generated bindings under `tests/generated/` are compiled and
executed against independent official binary fixtures and runtime builders.
