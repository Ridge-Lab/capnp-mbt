///|
fn register_symbol(
  names : Map[String, Bool],
  name : String,
) -> Unit raise CodegenError {
  if names.contains(name) {
    raise UnsupportedSchema(
      "generated MoonBit type name collision: \{name}; rename the conflicting schema declaration",
    )
  }
  names[name] = true
}

///|
fn register_list(
  names : Map[String, Bool],
  name : String,
  element : SchemaType,
) -> Unit raise CodegenError {
  register_symbol(names, name + "Reader")
  register_symbol(names, name + "Builder")
  match element {
    ListOf(child) => register_list(names, name + "Item", child)
    _ => ()
  }
}

///|
fn validate_names(nodes : Array[Node]) -> Unit raise CodegenError {
  let names : Map[String, Bool] = Map([])
  let ids : Map[UInt64, Bool] = Map([])
  for node in nodes {
    if ids.contains(node.id) {
      raise InvalidRequest("duplicate schema node ID")
    }
    ids[node.id] = true
    if node.kind == 1 {
      let name = node_name(node, nodes)
      register_symbol(names, name + "Reader")
      register_symbol(names, name + "Builder")
      for field in node.fields {
        validate_field(node, field, nodes)
        match field.typ {
          ListOf(element) =>
            register_list(names, list_name(name, field), element)
          _ => ()
        }
      }
    } else if node.kind == 4 {
      register_symbol(names, field_name("const" + node_name(node, nodes)))
      if node.constant_type is Some(ListOf(element)) {
        register_list(names, node_name(node, nodes) + "ConstantList", element)
      }
    } else if node.kind == 2 {
      register_symbol(names, node_name(node, nodes))
      let variants : Map[String, Bool] = Map([])
      for variant in node.enumerants {
        register_symbol(variants, symbol(variant, true))
      }
    }
  }
}

///|
fn validate_type(
  typ : SchemaType,
  nodes : Array[Node],
) -> Unit raise CodegenError {
  match typ {
    EnumRef(id) =>
      if lookup(nodes, id).kind != 2 {
        raise InvalidRequest("enum type ID references another declaration kind")
      }
    StructRef(id) =>
      if lookup(nodes, id).kind != 1 {
        raise InvalidRequest(
          "struct type ID references another declaration kind",
        )
      }
    ListOf(element) => validate_type(element, nodes)
    Scalar(_) | AnyPointer(_) => ()
    BrandedRef(_, _) | Parameter(_, _) =>
      raise InvalidRequest("unresolved generic type after specialization")
  }
}

///|
fn validate_field(
  node : Node,
  field : Field,
  nodes : Array[Node],
) -> Unit raise CodegenError {
  validate_type(field.typ, nodes)
  if field.discriminant != 65535 &&
    field.discriminant >= node.discriminant_count {
    raise InvalidRequest("field discriminant exceeds union discriminant count")
  }
  if field.group {
    match field.typ {
      StructRef(id) => {
        let group = lookup(nodes, id)
        if !group.group || group.scope != node.id {
          raise InvalidRequest("group field has inconsistent scope/type")
        }
      }
      _ => raise InvalidRequest("group field must reference a group struct")
    }
  } else {
    let max_offset = match field.typ {
      Scalar(0) => 1
      Scalar(1) => node.data_words * 64
      Scalar(tag) =>
        if tag < 12 {
          node.data_words * 8 / scalar_width(tag)
        } else {
          node.pointers
        }
      EnumRef(_) => node.data_words * 4
      _ => node.pointers
    }
    if field.offset < 0 || field.offset >= max_offset {
      raise InvalidRequest(
        "field offset exceeds struct layout: \{node.name}.\{field.name}",
      )
    }
  }
}
