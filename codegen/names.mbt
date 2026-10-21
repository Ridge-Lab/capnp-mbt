///|
fn generated_field_name(field : Field) -> String {
  field.generated_name.unwrap_or(field_name(field.name))
}

///|
fn enum_variants(node : Node) -> Array[String] {
  let names : Map[String, Bool] = Map([])
  let result : Array[String] = []
  for index, raw in node.enumerants {
    let base = symbol(raw, true)
    let mut name = base
    let mut attempt = 0
    while names.contains(name) {
      name = base + "V" + index.to_string()
      if attempt > 0 {
        name += "N" + attempt.to_string()
      }
      attempt += 1
    }
    names[name] = true
    result.push(name)
  }
  result
}

///|
fn allocate_field_names(node : Node) -> Unit {
  let names : Map[String, Bool] = Map([])
  for field in node.fields {
    let base = field_name(field.name)
    let mut name = base
    let mut attempt = 0
    while names.contains(name) {
      name = base + "_f" + field.index.to_string()
      if attempt > 0 {
        name += "_n" + attempt.to_string()
      }
      attempt += 1
    }
    if name != base {
      field.generated_name = Some(name)
    }
    names[name] = true
  }
}

///|
fn list_symbols(
  result : Array[String],
  base : String,
  element : SchemaType,
) -> Unit {
  result.push(base + "Reader")
  result.push(base + "Builder")
  if element is ListOf(child) {
    list_symbols(result, base + "Item", child)
  }
}

///|
fn node_symbols(node : Node, name : String) -> Array[String] {
  let result : Array[String] = []
  match node.kind {
    1 => {
      result.push(name + "Reader")
      result.push(name + "Builder")
      for field in node.fields {
        if field.typ is ListOf(element) {
          list_symbols(result, list_name(name, field), element)
        }
      }
    }
    2 => result.push(name)
    4 => {
      result.push(field_name("const" + name))
      if node.constant_type is Some(ListOf(element)) {
        list_symbols(result, name + "ConstantList", element)
      }
    }
    _ => ()
  }
  result
}

///|
// Allocate against the complete emitted surface, not only schema declaration
// names. Reader/Builder and list wrappers can also collide with valid user names.
fn allocate_names(nodes : Array[Node]) -> Unit raise CodegenError {
  let occupied : Map[String, Bool] = Map([])
  for node in nodes {
    if node.kind == 1 {
      allocate_field_names(node)
    }
    let base = node_name(node, nodes)
    let mut name = base
    let mut symbols = node_symbols(node, name)
    let mut attempt = 0
    while symbols.any(s => occupied.contains(s)) {
      name = base + "N" + node.id.to_string(radix=16)
      if attempt > 0 {
        name += "C" + attempt.to_string()
      }
      attempt += 1
      symbols = node_symbols(node, name)
    }
    node.generated_symbol = Some(name)
    for generated in symbols {
      if occupied.contains(generated) {
        raise InvalidRequest("duplicate generated symbols inside a declaration")
      }
      occupied[generated] = true
    }
  }
}
