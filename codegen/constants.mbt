///|
fn constant_uses_pointer(node : Node) -> Bool {
  match node.constant_type {
    Some(StructRef(_) | ListOf(_) | AnyPointer(_)) => true
    _ => false
  }
}

///|
fn emit_constant(
  out : StringBuilder,
  node : Node,
  nodes : Array[Node],
) -> Unit raise {
  let name = node_name(node, nodes)
  let accessor = field_name("const" + name)
  guard node.constant_type is Some(typ) else {
    raise InvalidRequest("constant is missing its type")
  }
  let pointer = "capnp_schema_node(\{node.index}).get_struct(4).get_pointer(0)"
  match typ {
    Scalar(tag) =>
      emit_block(
        out,
        "pub fn \{accessor}() -> \{scalar_type(tag)} { \{scalar_default(tag, node.constant_value)} }",
      )
    EnumRef(id) => {
      let enum_name = node_name(lookup(nodes, id), nodes)
      emit_block(
        out,
        "pub fn \{accessor}() -> \{enum_name} { \{enum_name}::from_raw(\{node.constant_value.get_uint16(2)}U) }",
      )
    }
    StructRef(id) => {
      let target = node_name(lookup(nodes, id), nodes)
      emit_block(
        out,
        "pub fn \{accessor}() -> \{target}Reader raise @capnp.CapnpError { { inner: \{pointer}.as_struct() } }",
      )
    }
    ListOf(child) => {
      let list = name + "ConstantList"
      emit_list(out, list, child, nodes)
      emit_block(
        out,
        "pub fn \{accessor}() -> \{list}Reader raise @capnp.CapnpError { { inner: \{pointer}.as_list() } }",
      )
    }
    AnyPointer(kind) =>
      emit_block(
        out,
        "pub fn \{accessor}() -> \{any_reader_type(kind)} raise @capnp.CapnpError { \{any_read_expression(pointer, kind)} }",
      )
    _ => raise InvalidRequest("unresolved generic constant type")
  }
}

///|
fn any_reader_type(kind : Int) -> String {
  match kind {
    1 => "@capnp.StructReader"
    2 => "@capnp.ListReader"
    _ => "@capnp.PointerReader"
  }
}

///|
fn any_read_expression(pointer : String, kind : Int) -> String {
  match kind {
    1 => pointer + ".as_struct()"
    2 => pointer + ".as_list()"
    3 =>
      "{ let p = \{pointer}; if !p.is_null() { ignore(p.capability_index()) }; p }"
    _ => pointer
  }
}

///|
fn any_set_method(kind : Int) -> String {
  match kind {
    1 => "set_struct"
    2 => "set_list"
    _ => "set"
  }
}
