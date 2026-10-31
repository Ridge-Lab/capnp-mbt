///|
priv struct Specializer {
  original : Array[Node]
  output : Array[Node]
  instances : Map[String, UInt64]
  active : Map[UInt64, Array[Int32]]
  weights : Map[UInt64, Int32]
  mut next_id : UInt64
}

///|
fn binding_weight(state : Specializer, typ : SchemaType) -> Int32 {
  match typ {
    ListOf(child) => Int32::min(1000000, 1 + binding_weight(state, child))
    StructRef(id) => state.weights.get(id).unwrap_or(1)
    _ => 1
  }
}

///|
fn parameter_key(scope : UInt64, index : Int32) -> String {
  "\{scope}:\{index}"
}

///|
fn parameter_scopes(
  nodes : Array[Node],
  node : Node,
  depth : Int32,
) -> Array[Node] raise CodegenError {
  if depth > 64 {
    raise InvalidRequest("generic scope chain exceeds 64")
  }
  let scopes = if node.scope == 0UL {
    []
  } else {
    parameter_scopes(nodes, lookup(nodes, node.scope), depth + 1)
  }
  if !node.parameters.is_empty() {
    scopes.push(node)
  }
  scopes
}

///|
fn type_key(typ : SchemaType) -> String raise CodegenError {
  match typ {
    Scalar(tag) => "s\{tag}"
    EnumRef(id) => "e\{id}"
    StructRef(id) => "t\{id}"
    ListOf(element) => "l(" + type_key(element) + ")"
    AnyPointer(kind) => "a\{kind}"
    _ => raise InvalidRequest("unresolved type in generic binding")
  }
}

///|
fn instance_key(
  node : Node,
  scopes : Array[Node],
  env : Map[String, SchemaType],
) -> String raise CodegenError {
  let key = StringBuilder()
  key.write_string(node.id.to_string())
  for scope in scopes {
    for i in 0..<scope.parameters.length() {
      key.write_string(
        ":" +
        type_key(env.get(parameter_key(scope.id, i)).unwrap_or(AnyPointer(0))),
      )
    }
  }
  key.to_string()
}

///|
fn default_env(scopes : Array[Node]) -> Map[String, SchemaType] {
  let env : Map[String, SchemaType] = Map([])
  for scope in scopes {
    for i in 0..<scope.parameters.length() {
      env[parameter_key(scope.id, i)] = AnyPointer(0)
    }
  }
  env
}

///|
fn specialized_name(
  typ : SchemaType,
  nodes : Array[Node],
) -> String raise CodegenError {
  match typ {
    Scalar(tag) => symbol(scalar_method(tag), true)
    EnumRef(id) | StructRef(id) => node_name(lookup(nodes, id), nodes)
    ListOf(child) => "ListOf" + specialized_name(child, nodes)
    AnyPointer(0) => "AnyPointer"
    AnyPointer(1) => "AnyStruct"
    AnyPointer(2) => "AnyList"
    AnyPointer(_) => "Capability"
    _ => raise InvalidRequest("unresolved specialization name")
  }
}

///|
fn resolve_brand(
  state : Specializer,
  node : Node,
  brand : Array[BrandScope],
  current : Map[String, SchemaType],
  depth : Int32,
) -> Map[String, SchemaType] raise {
  let scopes = parameter_scopes(state.original, node, 0)
  let env = default_env(scopes)
  for branded in brand {
    let scope = lookup(state.original, branded.id)
    if !scopes.any(s => s.id == branded.id) && !scope.parameters.is_empty() {
      raise InvalidRequest(
        "brand references a scope outside the target's generic ancestry",
      )
    }
    match branded.binding {
      Inherit =>
        for i in 0..<scope.parameters.length() {
          let key = parameter_key(scope.id, i)
          env[key] = current.get(key).unwrap_or(AnyPointer(0))
        }
      Bind(values) => {
        if values.length() > scope.parameters.length() {
          raise InvalidRequest("too many generic parameter bindings")
        }
        for i, value in values {
          let resolved = resolve_type(state, value, current, depth + 1)
          match resolved {
            Scalar(0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11)
            | EnumRef(_) =>
              raise InvalidRequest(
                "Cap'n Proto generic parameters must bind pointer types",
              )
            _ => ()
          }
          env[parameter_key(scope.id, i)] = resolved
        }
      }
    }
  }
  env
}

///|
fn resolve_type(
  state : Specializer,
  typ : SchemaType,
  env : Map[String, SchemaType],
  depth : Int32,
) -> SchemaType raise {
  if depth > 128 {
    raise InvalidRequest("type specialization nesting exceeds 128")
  }
  match typ {
    Parameter(scope, index) => {
      let node = lookup(state.original, scope)
      if index < 0 || index >= node.parameters.length() {
        raise InvalidRequest("generic parameter index is out of range")
      }
      env.get(parameter_key(scope, index)).unwrap_or(AnyPointer(0))
    }
    BrandedRef(id, brand) => {
      let node = lookup(state.original, id)
      let bindings = resolve_brand(state, node, brand, env, depth + 1)
      StructRef(instantiate(state, node, bindings, None, depth + 1))
    }
    StructRef(id) => {
      let node = lookup(state.original, id)
      StructRef(
        instantiate(
          state,
          node,
          default_env(parameter_scopes(state.original, node, 0)),
          None,
          depth + 1,
        ),
      )
    }
    ListOf(child) => ListOf(resolve_type(state, child, env, depth + 1))
    AnyPointer(kind) => {
      if kind < 0 || kind > 3 {
        raise InvalidRequest("unknown AnyPointer constraint")
      }
      typ
    }
    _ => typ
  }
}

///|
fn clone_node(node : Node, id : UInt64, scope : UInt64, name : String) -> Node {
  {
    id,
    scope,
    kind: node.kind,
    name: node.name,
    nested: node.nested,
    fields: [],
    enumerants: node.enumerants,
    data_words: node.data_words,
    pointers: node.pointers,
    group: node.group,
    discriminant_offset: node.discriminant_offset,
    discriminant_count: node.discriminant_count,
    index: node.index,
    base_symbol: Some(name),
    generated_symbol: Some(name),
    parameters: node.parameters,
    constant_type: None,
    constant_value: node.constant_value,
  }
}

///|
fn instantiate(
  state : Specializer,
  node : Node,
  env : Map[String, SchemaType],
  parent_id : UInt64?,
  depth : Int32,
) -> UInt64 raise {
  if node.kind != 1 {
    raise InvalidRequest("struct brand does not reference a struct")
  }
  if depth > 128 {
    raise InvalidRequest("generic expansion exceeds depth 128")
  }
  let scopes = parameter_scopes(state.original, node, 0)
  let key = instance_key(node, scopes, env)
  if state.instances.get(key) is Some(id) {
    return id
  }
  let unbound = instance_key(node, scopes, default_env(scopes)) == key
  let mut weight = 0
  for scope in scopes {
    for i in 0..<scope.parameters.length() {
      weight = Int32::min(
        1000000,
        weight +
        binding_weight(
          state,
          env.get(parameter_key(scope.id, i)).unwrap_or(AnyPointer(0)),
        ),
      )
    }
  }
  let stack = state.active.get(node.id).unwrap_or([])
  // A recursive edge which grows its argument graph cannot have a finite
  // monomorphization. Keep a lossless unbound view at that boundary. Two
  // increasing visits distinguish growth from a finite fixed specialization.
  if !unbound &&
    (
      (stack.length() >= 2 && stack.all(w => weight > w)) ||
      stack.length() >= 16
    ) {
    return instantiate(state, node, default_env(scopes), parent_id, depth + 1)
  }
  let id = if unbound {
    node.id
  } else {
    while state.original.any(n => n.id == state.next_id) {
      state.next_id += 1UL
    }
    let id = state.next_id
    state.next_id += 1UL
    id
  }
  let base = node_name(node, state.original)
  let name = if unbound {
    base
  } else {
    let args : Array[String] = []
    let mut name_length = base.length() + 2
    for scope in scopes {
      for i in 0..<scope.parameters.length() {
        let arg = specialized_name(
          env.get(parameter_key(scope.id, i)).unwrap_or(AnyPointer(0)),
          state.output,
        )
        name_length = Int32::min(1024, name_length + arg.length() + 3)
        if name_length <= 512 {
          args.push(arg)
        }
      }
    }
    if name_length > 512 {
      "SpecializedN" + id.to_string(radix=16)
    } else {
      base + "As" + args.join("And")
    }
  }
  if state.output.length() > state.original.length() + 1024 {
    raise UnsupportedSchema(
      "schema expands to more than 1024 generic specializations",
    )
  }
  let output = clone_node(node, id, parent_id.unwrap_or(node.scope), name)
  state.instances[key] = id // Reserve before resolving recursive fields.
  state.weights[id] = 1 + weight
  state.output.push(output)
  state.active[node.id] = stack
  stack.push(weight)
  for field in node.fields {
    let typ = if field.group {
      match field.typ {
        StructRef(group_id) =>
          StructRef(
            instantiate(
              state,
              lookup(state.original, group_id),
              env,
              Some(id),
              depth + 1,
            ),
          )
        _ => raise InvalidRequest("invalid group reference")
      }
    } else {
      resolve_type(state, field.typ, env, depth + 1)
    }
    output.fields.push({ ..field, typ, })
  }
  ignore(stack.pop())
  id
}

///|
fn specialize_nodes(nodes : Array[Node]) -> Array[Node] raise {
  // Validate raw IDs first; generated instances receive non-colliding internal IDs.
  let seen : Map[UInt64, Bool] = Map([])
  for node in nodes {
    if seen.contains(node.id) {
      raise InvalidRequest("duplicate schema node ID")
    }
    seen[node.id] = true
  }
  let state : Specializer = {
    original: nodes,
    output: [],
    instances: Map([]),
    active: Map([]),
    weights: Map([]),
    next_id: 1UL,
  }
  for node in nodes {
    if node.kind != 1 {
      state.output.push(node)
    }
  }
  for node in nodes {
    if node.kind == 1 {
      ignore(
        instantiate(
          state,
          node,
          default_env(parameter_scopes(nodes, node, 0)),
          None,
          0,
        ),
      )
    }
  }
  for i in 0..<state.output.length() {
    let node = state.output[i]
    if node.constant_type is Some(typ) {
      let resolved = resolve_type(state, typ, Map([]), 0)
      state.output[i] = { ..node, constant_type: Some(resolved), }
    }
  }
  state.output
}
