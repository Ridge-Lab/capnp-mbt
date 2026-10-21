///|
fn field_uses_pointer_default(field : Field) -> Bool raise @capnp.CapnpError {
  if field.group {
    return false
  }
  match field.typ {
    StructRef(_)
    | BrandedRef(_, _)
    | Parameter(_, _)
    | ListOf(_)
    | AnyPointer(_) => !field.default_value.get_pointer(0).is_null()
    _ => false
  }
}

///|
// Retain only the pointer values consulted by generated accessors. The small
// lookup tree preserves original node/field indices and the helper's layout,
// but deliberately excludes sourceInfo, annotations and compiler metadata.
fn pointer_default_payload(nodes : Array[Node]) -> Bytes raise {
  let message = @capnp.Builder::new()
  let targets = message
    .init_root(0, 1)
    .init_struct_list(0, nodes.length(), 0, 5)
  // Use raw declarations exactly once. Instantiated generic views may replace
  // a parameter with Text/Data and inline its default; one such view must not
  // decide which pointer values remain available to every other view.
  for node in nodes {
    let target = targets.struct_at(node.index)
    if node.kind == 1 {
      let mut has_default = false
      for field in node.fields {
        if field_uses_pointer_default(field) {
          has_default = true
        }
      }
      if has_default {
        let fields = target.init_struct_list(3, node.fields.length(), 0, 4)
        for field in node.fields {
          if field_uses_pointer_default(field) {
            fields
            .struct_at(field.index)
            .init_struct(3, 0, 1)
            .get_pointer(0)
            .set(field.default_value.get_pointer(0))
          }
        }
      }
    } else if constant_uses_pointer(node) {
      let pointer = node.constant_value.get_pointer(0)
      if !pointer.is_null() {
        target.init_struct(4, 0, 1).get_pointer(0).set(pointer)
      }
    }
  }
  // Canonical layout removes allocation history, spare words and padding from
  // otherwise identical default values supplied by different compiler builds.
  let segment = @capnp.canonicalize(@capnp.read_message(message.finish()))
  let words = (segment.length() / 8).reinterpret_as_uint()
  // canonicalize returns a bare segment; generated readers consume framing.
  Bytes::makei(segment.length() + 8, i => {
    if i < 4 {
      0
    } else if i < 8 {
      ((words >> ((i - 4) * 8)) & 255U).to_byte()
    } else {
      segment[i - 8]
    }
  })
}
