///|
/// Produce the canonical segment for a struct-root message, WITHOUT a segment table.
/// The input message's traversal and nesting limits still apply. Capabilities
/// cannot be canonicalized because their identity requires an external table.
pub fn canonicalize(
  message : Message,
  max_words~ : Int32 = 8_388_608,
  max_depth~ : Int32 = 64,
) -> Bytes raise CapnpError {
  if max_depth < 1 || max_depth > 256 {
    raise Limit("canonical depth must be between 1 and 256")
  }
  let owner = Builder::new(max_words~)
  if message.root_pointer().kind() == Capability {
    raise Unsupported("canonical encoding cannot contain capabilities")
  }
  // The standard canonical message root is a struct. A null root denotes an
  // empty struct and is normalized to the non-null offset -1 representation.
  let source = message.root()
  let (words, pointers) = canonical_shape(source)
  let target = owner.init_root(words, pointers)
  canonical_struct_into(target, source, max_depth - 1)
  let framed = owner.finish()
  framed[8:].to_owned()
}

///|
fn canonical_shape(source : StructReader) -> (Int32, Int32) raise CapnpError {
  let mut data_words = (source.data_bytes + 7) / 8
  let mut pointers = source.pointer_count
  while data_words > 0 && source.get_uint64((data_words - 1) * 8) == 0UL {
    data_words -= 1
  }
  while pointers > 0 && source.get_pointer(pointers - 1).is_null() {
    pointers -= 1
  }
  (data_words, pointers)
}

///|
fn canonical_struct_into(
  target : StructBuilder,
  source : StructReader,
  depth : Int32,
) -> Unit raise CapnpError {
  for i in 0..<target.data_words {
    target.set_uint64(i * 8, source.get_uint64(i * 8))
  }
  for i in 0..<target.pointer_count {
    canonical_pointer(
      target.owner,
      b_pointer(target, i),
      source.get_pointer(i),
      depth,
    )
  }
}

///|
fn canonical_pointer(
  owner : Builder,
  slot : Int32,
  source : PointerReader,
  depth : Int32,
) -> Unit raise CapnpError {
  if source.is_null() {
    b_write(owner, slot, 0UL, 8)
    return
  }
  if depth == 0 {
    raise Limit("canonical nesting limit exceeded")
  }
  let (_, _, tag) = PointerReader::read_resolve(source)
  match tag.to_uint() & 3 {
    0 => {
      let value = source.as_struct()
      let (words, pointers) = canonical_shape(value)
      let target = b_init_struct(owner, slot, words, pointers)
      canonical_struct_into(target, value, depth - 1)
    }
    1 => canonical_list(owner, slot, source.as_list(), depth - 1)
    3 => raise Unsupported("canonical encoding cannot contain capabilities")
    _ => raise InvalidMessage("unresolved pointer during canonicalization")
  }
}

///|
fn canonical_list(
  owner : Builder,
  slot : Int32,
  source : ListReader,
  depth : Int32,
) -> Unit raise CapnpError {
  if source.code == 7 {
    if source.data_words == 0 && source.pointer_count == 0 {
      ignore(b_init_struct_list(owner, slot, source.count, 0, 0))
      return
    }
    let mut words = 0
    let mut pointers = 0
    for i in 0..<source.count {
      let item = source.get_struct(i)
      let (w, p) = canonical_shape(item)
      words = if w > words { w } else { words }
      pointers = if p > pointers { p } else { pointers }
    }
    let target = b_init_struct_list(owner, slot, source.count, words, pointers)
    // Two passes keep auxiliary memory constant rather than retaining one
    // reader object per input element. Both passes consume traversal budget.
    for i in 0..<source.count {
      canonical_struct_into(target.struct_at(i), source.get_struct(i), depth)
    }
  } else {
    let target = b_init_list(owner, slot, source.code, source.count)
    if source.code == 6 {
      for i in 0..<source.count {
        canonical_pointer(
          owner,
          b_list_slot(target, i),
          source.get_pointer(i),
          depth,
        )
      }
    } else if source.code > 0 {
      let length = if source.code == 1 {
        (source.count + 7) / 8
      } else {
        source.count * source.stride
      }
      let begin = source.state.offsets[source.segment] + source.start
      for i in 0..<length {
        owner.arena[target.start + i] = source.state.bytes[begin + i]
      }
      // A partial bool byte has no semantic value above the final element.
      if source.code == 1 && source.count % 8 != 0 {
        let last = target.start + length - 1
        owner.arena[last] = owner.arena[last] &
          ((1 << (source.count % 8)) - 1).to_byte()
      }
    }
  }
}
