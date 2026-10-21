///|
fn bytes_literal(bytes : Bytes) -> String {
  let out = StringBuilder()
  if bytes.length() > 4096 {
    out.write_string("{\n  let chunks : Array[Bytes] = [\n")
    for start = 0; start < bytes.length(); start = start + 4096 {
      let end = if start + 4096 < bytes.length() {
        start + 4096
      } else {
        bytes.length()
      }
      out.write_string(
        "    " + bytes_literal(bytes[start:end].to_owned()) + ",\n",
      )
    }
    out.write_string(
      "  ]\n  Bytes::makei(\{bytes.length()}, i => chunks[i / 4096][i % 4096])\n}",
    )
    return out.to_string()
  }
  out.write_string("b\"")
  for b in bytes {
    out.write_string("\\x" + b.to_hex())
  }
  out.write_string("\"")
  out.to_string()
}

///|
fn scalar_default(tag : Int, value : @capnp.StructReader) -> String raise {
  match tag {
    0 => "()"
    1 => value.get_bool(16).to_string()
    2 => value.get_int8(2).to_string()
    3 => value.get_int16(2).to_string()
    4 => value.get_int32(4).to_string()
    5 => "(" + value.get_uint64(8).to_string() + "UL).reinterpret_as_int64()"
    6 => value.get_uint8(2).to_string()
    7 => value.get_uint16(2).to_string() + "U"
    8 => value.get_uint32(4).to_string() + "U"
    9 => value.get_uint64(8).to_string() + "UL"
    10 =>
      "Float::reinterpret_from_uint(" + value.get_uint32(4).to_string() + "U)"
    11 => "(" + value.get_uint64(8).to_string() + "UL).reinterpret_as_double()"
    12 => value.get_text(0).escape(quote=true)
    _ => bytes_literal(value.get_data(0))
  }
}

///|
fn emit_block(out : StringBuilder, source : String) -> Unit {
  out.write_string("\n///|\n" + source + "\n")
}

///|
fn emit_enum(
  out : StringBuilder,
  node : Node,
  nodes : Array[Node],
) -> Unit raise CodegenError {
  let name = node_name(node, nodes)
  let fallback = enum_fallback(node)
  let cases = StringBuilder()
  let decode = StringBuilder()
  let encode = StringBuilder()
  for i, item in node.enumerants {
    let variant = symbol(item, true)
    cases.write_string("  " + variant + "\n")
    decode.write_string("    \{i}U => \{variant}\n")
    encode.write_string("    \{variant} => \{i}U\n")
  }
  emit_block(
    out,
    "pub(all) enum \{name} {\n\{cases.to_string()}  \{fallback}(UInt)\n}",
  )
  emit_block(
    out,
    "pub fn \{name}::from_raw(value : UInt) -> \{name} {\n  match value {\n\{decode.to_string()}    _ => \{fallback}(value)\n  }\n}",
  )
  emit_block(
    out,
    "pub fn \{name}::to_raw(self : \{name}) -> UInt {\n  match self {\n\{encode.to_string()}    \{fallback}(value) => value\n  }\n}",
  )
}

///|
fn enum_fallback(node : Node) -> String {
  let names = node.enumerants.map(name => symbol(name, true))
  let mut suffix = 0
  let mut candidate = "Unknown"
  while names.contains(candidate) {
    suffix += 1
    candidate = "UnknownValue" + suffix.to_string()
  }
  candidate
}

///|
fn field_method(field : Field) -> String {
  "get_" + field_name(field.name)
}

///|
fn list_name(owner : String, field : Field) -> String {
  owner + symbol(field.name, true) + "List"
}

///|
fn emit_list(
  out : StringBuilder,
  name : String,
  element : SchemaType,
  nodes : Array[Node],
) -> Unit raise {
  let reader = name + "Reader"
  let builder = name + "Builder"
  emit_block(out, "pub(all) struct \{reader} { inner : @capnp.ListReader }")
  emit_block(out, "pub(all) struct \{builder} { inner : @capnp.ListBuilder }")
  emit_block(
    out,
    "pub fn \{reader}::length(self : \{reader}) -> Int { self.inner.length() }",
  )
  emit_block(
    out,
    "pub fn \{builder}::length(self : \{builder}) -> Int { self.inner.length() }",
  )
  match element {
    Scalar(0) => {
      emit_block(
        out,
        "pub fn \{reader}::get(self : \{reader}, index : Int) -> Unit raise @capnp.CapnpError {\n  if index < 0 || index >= self.inner.length() { raise @capnp.CapnpError::Bounds(\"void list index\") }\n}",
      )
      emit_block(
        out,
        "pub fn \{builder}::set(self : \{builder}, index : Int) -> Unit raise @capnp.CapnpError {\n  if index < 0 || index >= self.inner.length() { raise @capnp.CapnpError::Bounds(\"void list index\") }\n}",
      )
    }
    Scalar(tag) => {
      let typ = scalar_type(tag)
      let accessor = scalar_method(tag)
      emit_block(
        out,
        "pub fn \{reader}::get(self : \{reader}, index : Int) -> \{typ} raise @capnp.CapnpError { self.inner.get_\{accessor}(index) }",
      )
      emit_block(
        out,
        "pub fn \{builder}::set(self : \{builder}, index : Int, value : \{typ}) -> Unit raise @capnp.CapnpError { self.inner.set_\{accessor}(index, value) }",
      )
    }
    EnumRef(id) => {
      let typ = node_name(lookup(nodes, id), nodes)
      emit_block(
        out,
        "pub fn \{reader}::get(self : \{reader}, index : Int) -> \{typ} raise @capnp.CapnpError { \{typ}::from_raw(self.inner.get_uint16(index)) }",
      )
      emit_block(
        out,
        "pub fn \{builder}::set(self : \{builder}, index : Int, value : \{typ}) -> Unit raise @capnp.CapnpError { self.inner.set_uint16(index, value.to_raw()) }",
      )
    }
    StructRef(id) => {
      let typ = node_name(lookup(nodes, id), nodes)
      emit_block(
        out,
        "pub fn \{reader}::get(self : \{reader}, index : Int) -> \{typ}Reader raise @capnp.CapnpError { { inner: self.inner.get_struct(index) } }",
      )
      emit_block(
        out,
        "pub fn \{builder}::get(self : \{builder}, index : Int) -> \{typ}Builder raise @capnp.CapnpError { { inner: self.inner.struct_at(index) } }",
      )
    }
    ListOf(child) => {
      let subname = name + "Item"
      emit_list(out, subname, child, nodes)
      emit_block(
        out,
        "pub fn \{reader}::get(self : \{reader}, index : Int) -> \{subname}Reader raise @capnp.CapnpError { { inner: self.inner.get_list(index) } }",
      )
      let init = match child {
        StructRef(id) => {
          let n = lookup(nodes, id)
          "self.inner.init_struct_list(index, length, \{n.data_words}, \{n.pointers})"
        }
        _ => "self.inner.init_list(index, \{element_size(child)}, length)"
      }
      emit_block(
        out,
        "pub fn \{builder}::init(self : \{builder}, index : Int, length : Int) -> \{subname}Builder raise @capnp.CapnpError { { inner: \{init} } }",
      )
    }
    AnyPointer(kind) => {
      let pointer = "self.inner.get_pointer(index)"
      emit_block(
        out,
        "pub fn \{reader}::get(self : \{reader}, index : Int) -> \{any_reader_type(kind)} raise @capnp.CapnpError { \{any_read_expression(pointer, kind)} }",
      )
      let validate = if kind == 3 {
        "if !value.is_null() { ignore(value.capability_index()) }; "
      } else {
        ""
      }
      emit_block(
        out,
        "pub fn \{builder}::set(self : \{builder}, index : Int, value : \{any_reader_type(kind)}) -> Unit raise @capnp.CapnpError { \{validate}self.inner.get_pointer(index).\{any_set_method(kind)}(value) }",
      )
      emit_block(
        out,
        "pub fn \{builder}::get(self : \{builder}, index : Int) -> @capnp.PointerBuilder raise @capnp.CapnpError { self.inner.get_pointer(index) }",
      )
    }
    _ => raise InvalidRequest("unresolved generic list element")
  }
}

///|
fn union_check(node : Node, field : Field) -> String {
  if field.discriminant == 65535 {
    ""
  } else {
    "  if self.inner.get_uint16(\{node.discriminant_offset}) != \{field.discriminant}U { raise @capnp.CapnpError::TypeMismatch(\"inactive union field\") }\n"
  }
}

///|
fn clear_fields(
  out : StringBuilder,
  fields : Array[Field],
  nodes : Array[Node],
  depth : Int,
) -> Unit raise CodegenError {
  if depth > 32 {
    raise InvalidRequest("recursive group")
  }
  for f in fields {
    if f.group {
      match f.typ {
        StructRef(id) => {
          let group = lookup(nodes, id)
          clear_fields(out, group.fields, nodes, depth + 1)
          if group.discriminant_count > 0 {
            out.write_string(
              "  self.inner.set_uint16(\{group.discriminant_offset}, 0U)\n",
            )
          }
        }
        _ => raise InvalidRequest("non-struct group")
      }
    } else {
      match f.typ {
        Scalar(0) => ()
        Scalar(1) =>
          out.write_string("  self.inner.set_bool(\{f.offset}, false)\n")
        Scalar(2 | 6) =>
          out.write_string("  self.inner.set_uint8(\{f.offset}, 0)\n")
        Scalar(3 | 7) | EnumRef(_) =>
          out.write_string("  self.inner.set_uint16(\{f.offset * 2}, 0U)\n")
        Scalar(4 | 8 | 10) =>
          out.write_string("  self.inner.set_uint32(\{f.offset * 4}, 0U)\n")
        Scalar(5 | 9 | 11) =>
          out.write_string("  self.inner.set_uint64(\{f.offset * 8}, 0UL)\n")
        _ => out.write_string("  self.inner.clear_pointer(\{f.offset})\n")
      }
    }
  }
}

///|
fn union_set(
  node : Node,
  field : Field,
  nodes : Array[Node],
) -> String raise CodegenError {
  if field.discriminant == 65535 {
    return ""
  }
  let out = StringBuilder()
  clear_fields(out, node.fields.filter(f => f.discriminant != 65535), nodes, 0)
  out.write_string(
    "  self.inner.set_uint16(\{node.discriminant_offset}, \{field.discriminant}U)\n",
  )
  out.to_string()
}

///|
fn pointer_expr(node : Node, field : Field) -> String raise {
  let ptr = field.default_value.get_pointer(0)
  if ptr.is_null() {
    return "self.inner.get_pointer(\{field.offset})"
  }
  "{ let p = self.inner.get_pointer(\{field.offset}); if p.is_null() { capnp_schema_default(\{node.index}, \{field.index}) } else { p } }"
}

///|
fn emit_struct(
  out : StringBuilder,
  node : Node,
  nodes : Array[Node],
) -> Unit raise {
  let name = node_name(node, nodes)
  let reader = name + "Reader"
  let builder = name + "Builder"
  emit_block(out, "pub(all) struct \{reader} { inner : @capnp.StructReader }")
  emit_block(out, "pub(all) struct \{builder} { inner : @capnp.StructBuilder }")
  if !node.group {
    emit_block(
      out,
      "pub fn \{reader}::from_message(message : @capnp.Message) -> \{reader} raise @capnp.CapnpError { { inner: message.root() } }",
    )
    emit_block(
      out,
      "pub fn \{builder}::init_root(message : @capnp.Builder) -> \{builder} raise @capnp.CapnpError { { inner: message.init_root(\{node.data_words}, \{node.pointers}) } }",
    )
  }
  if node.discriminant_count > 0 {
    emit_block(
      out,
      "pub fn \{reader}::which(self : \{reader}) -> UInt raise @capnp.CapnpError { self.inner.get_uint16(\{node.discriminant_offset}) }",
    )
  }
  for field in node.fields {
    let accessor = field_method(field)
    let suffix = field_name(field.name)
    let check = union_check(node, field)
    let activate = union_set(node, field, nodes)
    if field.discriminant != 65535 {
      emit_block(
        out,
        "pub fn \{reader}::is_\{suffix}(self : \{reader}) -> Bool raise @capnp.CapnpError { self.inner.get_uint16(\{node.discriminant_offset}) == \{field.discriminant}U }",
      )
    }
    match field.typ {
      Scalar(tag) => {
        let typ = scalar_type(tag)
        let op = scalar_method(tag)
        let default = scalar_default(tag, field.default_value)
        let pos = field.offset * scalar_width(tag)
        let get = if tag == 0 {
          "{ ignore(self); () }"
        } else if tag >= 12 {
          "self.inner.get_pointer(\{field.offset}).as_\{op}(default=\{default})"
        } else {
          "self.inner.get_\{op}(\{pos}, default=\{default})"
        }
        let set = if tag == 0 {
          "  ignore(self)\n"
        } else if tag >= 12 {
          "  self.inner.set_\{op}(\{field.offset}, value)\n"
        } else {
          "  self.inner.set_\{op}(\{pos}, value, default=\{default})\n"
        }
        let effect = if tag == 0 && field.discriminant == 65535 {
          ""
        } else {
          " raise @capnp.CapnpError"
        }
        emit_block(
          out,
          "pub fn \{reader}::\{accessor}(self : \{reader}) -> \{typ}\{effect} {\n\{check}  \{get}\n}",
        )
        let param = if tag == 0 { "" } else { ", value : \{typ}" }
        emit_block(
          out,
          "pub fn \{builder}::set_\{suffix}(self : \{builder}\{param}) -> Unit\{effect} {\n\{activate}\{set}}",
        )
      }
      EnumRef(id) => {
        let typ = node_name(lookup(nodes, id), nodes)
        let default = field.default_value.get_uint16(2)
        let pos = field.offset * 2
        emit_block(
          out,
          "pub fn \{reader}::\{accessor}(self : \{reader}) -> \{typ} raise @capnp.CapnpError {\n\{check}  \{typ}::from_raw(self.inner.get_uint16(\{pos}, default=\{default}U))\n}",
        )
        emit_block(
          out,
          "pub fn \{builder}::set_\{suffix}(self : \{builder}, value : \{typ}) -> Unit raise @capnp.CapnpError {\n\{activate}  self.inner.set_uint16(\{pos}, value.to_raw(), default=\{default}U)\n}",
        )
      }
      StructRef(id) => {
        let child = lookup(nodes, id)
        let typ = node_name(child, nodes)
        let ptr = if field.group {
          "self.inner"
        } else {
          pointer_expr(node, field) + ".as_struct()"
        }
        let effect = if field.group && field.discriminant == 65535 {
          ""
        } else {
          " raise @capnp.CapnpError"
        }
        emit_block(
          out,
          "pub fn \{reader}::\{accessor}(self : \{reader}) -> \{typ}Reader\{effect} {\n\{check}  { inner: \{ptr} }\n}",
        )
        let init = if field.group {
          "self.inner"
        } else {
          "self.inner.init_struct(\{field.offset}, \{child.data_words}, \{child.pointers})"
        }
        let group_reset = StringBuilder()
        if field.group && field.discriminant == 65535 {
          clear_fields(group_reset, child.fields, nodes, 0)
          if child.discriminant_count > 0 {
            group_reset.write_string(
              "  self.inner.set_uint16(\{child.discriminant_offset}, 0U)\n",
            )
          }
          emit_block(
            out,
            "pub fn \{builder}::get_\{suffix}(self : \{builder}) -> \{typ}Builder { { inner: self.inner } }",
          )
        }
        let init_effect = if field.group &&
          activate == "" &&
          group_reset.is_empty() {
          ""
        } else {
          " raise @capnp.CapnpError"
        }
        emit_block(
          out,
          "pub fn \{builder}::init_\{suffix}(self : \{builder}) -> \{typ}Builder\{init_effect} {\n\{activate}\{group_reset.to_string()}  { inner: \{init} }\n}",
        )
        if !field.group {
          emit_block(
            out,
            "pub fn \{builder}::set_\{suffix}(self : \{builder}, value : \{typ}Reader) -> Unit raise @capnp.CapnpError {\n\{activate}  self.inner.get_pointer(\{field.offset}).set_struct(value.inner)\n}",
          )
        }
      }
      ListOf(element) => {
        let typ = list_name(name, field)
        emit_list(out, typ, element, nodes)
        let ptr = pointer_expr(node, field)
        emit_block(
          out,
          "pub fn \{reader}::\{accessor}(self : \{reader}) -> \{typ}Reader raise @capnp.CapnpError {\n\{check}  { inner: \{ptr}.as_list() }\n}",
        )
        let init = match element {
          StructRef(id) => {
            let child = lookup(nodes, id)
            "self.inner.init_struct_list(\{field.offset}, length, \{child.data_words}, \{child.pointers})"
          }
          _ =>
            "self.inner.init_list(\{field.offset}, \{element_size(element)}, length)"
        }
        emit_block(
          out,
          "pub fn \{builder}::init_\{suffix}(self : \{builder}, length : Int) -> \{typ}Builder raise @capnp.CapnpError {\n\{activate}  { inner: \{init} }\n}",
        )
        emit_block(
          out,
          "pub fn \{builder}::set_\{suffix}(self : \{builder}, value : \{typ}Reader) -> Unit raise @capnp.CapnpError {\n\{activate}  self.inner.get_pointer(\{field.offset}).set_list(value.inner)\n}",
        )
      }
      AnyPointer(kind) => {
        let pointer = pointer_expr(node, field)
        emit_block(
          out,
          "pub fn \{reader}::\{accessor}(self : \{reader}) -> \{any_reader_type(kind)} raise @capnp.CapnpError {\n\{check}  \{any_read_expression(pointer, kind)}\n}",
        )
        let validate = if kind == 3 {
          "  if !value.is_null() { ignore(value.capability_index()) }\n"
        } else {
          ""
        }
        emit_block(
          out,
          "pub fn \{builder}::set_\{suffix}(self : \{builder}, value : \{any_reader_type(kind)}) -> Unit raise @capnp.CapnpError {\n\{validate}\{activate}  self.inner.get_pointer(\{field.offset}).\{any_set_method(kind)}(value)\n}",
        )
        match kind {
          1 =>
            emit_block(
              out,
              "pub fn \{builder}::init_\{suffix}(self : \{builder}, data_words : Int, pointer_count : Int) -> @capnp.StructBuilder raise @capnp.CapnpError {\n\{activate}  self.inner.init_struct(\{field.offset}, data_words, pointer_count)\n}",
            )
          2 => {
            emit_block(
              out,
              "pub fn \{builder}::init_\{suffix}(self : \{builder}, element_size : Int, length : Int) -> @capnp.ListBuilder raise @capnp.CapnpError {\n\{activate}  self.inner.init_list(\{field.offset}, element_size, length)\n}",
            )
            let mut extra = suffix + "_structs"
            while node.fields.any(f => field_name(f.name) == extra) {
              extra += "_inline"
            }
            emit_block(
              out,
              "pub fn \{builder}::init_\{extra}(self : \{builder}, length : Int, data_words : Int, pointer_count : Int) -> @capnp.ListBuilder raise @capnp.CapnpError {\n\{activate}  self.inner.init_struct_list(\{field.offset}, length, data_words, pointer_count)\n}",
            )
          }
          _ =>
            emit_block(
              out,
              "pub fn \{builder}::init_\{suffix}(self : \{builder}) -> @capnp.PointerBuilder raise @capnp.CapnpError {\n\{activate}  let pointer = self.inner.get_pointer(\{field.offset})\n  pointer.clear()\n  pointer\n}",
            )
        }
        if field.discriminant == 65535 {
          emit_block(
            out,
            "pub fn \{builder}::get_\{suffix}(self : \{builder}) -> @capnp.PointerBuilder raise @capnp.CapnpError { self.inner.get_pointer(\{field.offset}) }",
          )
        }
      }
      _ => raise InvalidRequest("unresolved generic field type")
    }
  }
}
