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

///|
priv struct CanonicalCheck {
  bytes : Bytes
  total_words : Int32
  mut next_word : Int32
  mut remaining_words : Int32
}

///|
fn CanonicalCheck::charge(
  self : CanonicalCheck,
  words : Int32,
) -> Unit raise CapnpError {
  if words < 0 || words > self.remaining_words {
    raise Limit("canonical verification traversal limit exceeded")
  }
  self.remaining_words -= words
}

///|
fn CanonicalCheck::word(self : CanonicalCheck, index : Int32) -> UInt64 {
  read_u64(self.bytes, index * 8)
}

///|
fn CanonicalCheck::check_pointer(
  self : CanonicalCheck,
  slot_word : Int32,
  depth : Int32,
  is_root : Bool,
) -> Unit raise CapnpError {
  let tag = self.word(slot_word)
  if tag == 0UL {
    if is_root {
      raise InvalidMessage(
        "canonical root must be an empty-struct pointer, not null",
      )
    }
    return
  }
  if depth <= 0 {
    raise Limit("canonical verification nesting limit exceeded")
  }
  let low = tag.to_uint()
  match low & 3U {
    0U => self.check_struct(slot_word, tag, depth)
    1U => {
      if is_root {
        raise InvalidMessage("canonical root pointer must be a struct")
      }
      self.check_list(slot_word, tag, depth)
    }
    2U => raise InvalidMessage("canonical segment cannot contain far pointers")
    _ => raise Unsupported("canonical segment cannot contain capabilities")
  }
}

///|
fn CanonicalCheck::check_struct(
  self : CanonicalCheck,
  slot_word : Int32,
  tag : UInt64,
  depth : Int32,
) -> Unit raise CapnpError {
  let offset = tag.to_uint().reinterpret_as_int() >> 2
  let data_words = ((tag >> 32) & 0xffffUL).to_int()
  let pointers = (tag >> 48).to_int()
  let total = data_words + pointers
  if total == 0 {
    if offset != -1 {
      raise InvalidMessage(
        "canonical empty struct must use offset -1 without body words",
      )
    }
    self.charge(1)
    return
  }
  if slot_word.to_int64() + 1L + offset.to_int64() != self.next_word.to_int64() {
    raise InvalidMessage(
      "canonical struct is not in contiguous preorder layout",
    )
  }
  if total > self.total_words - self.next_word {
    raise Bounds("canonical struct extends beyond segment")
  }
  self.charge(total)
  let body = self.next_word
  self.next_word += total
  if data_words > 0 && self.word(body + data_words - 1) == 0UL {
    raise InvalidMessage("canonical struct contains trailing zero data word")
  }
  if pointers > 0 && self.word(body + data_words + pointers - 1) == 0UL {
    raise InvalidMessage("canonical struct contains trailing null pointer")
  }
  for i in 0..<pointers {
    self.check_pointer(body + data_words + i, depth - 1, false)
  }
}

///|
fn CanonicalCheck::check_list(
  self : CanonicalCheck,
  slot_word : Int32,
  tag : UInt64,
  depth : Int32,
) -> Unit raise CapnpError {
  let offset = tag.to_uint().reinterpret_as_int() >> 2
  if slot_word.to_int64() + 1L + offset.to_int64() != self.next_word.to_int64() {
    raise InvalidMessage("canonical list is not in contiguous preorder layout")
  }
  let upper = (tag >> 32).to_uint()
  let code = (upper & 7U).reinterpret_as_int()
  let count = (upper >> 3).reinterpret_as_int()
  if code == 7 {
    if count > self.total_words - 1 - self.next_word {
      raise Bounds("canonical composite list extends beyond segment")
    }
    let tag_word = self.next_word
    let element_tag = self.word(tag_word)
    if (element_tag.to_uint() & 3U) != 0U {
      raise InvalidMessage("canonical composite list tag must be a struct tag")
    }
    let elements = (element_tag.to_uint() >> 2).reinterpret_as_int()
    let data_words = ((element_tag >> 32) & 0xffffUL).to_int()
    let pointers = (element_tag >> 48).to_int()
    let stride = data_words + pointers
    if elements.to_int64() * stride.to_int64() != count.to_int64() {
      raise InvalidMessage(
        "canonical composite list word count does not match elements * stride",
      )
    }
    self.charge(if stride == 0 { elements + 1 } else { count + 1 })
    let body = tag_word + 1
    self.next_word = body + count
    if elements == 0 {
      if data_words != 0 || pointers != 0 {
        raise InvalidMessage(
          "canonical empty composite list must have zero-sized element shape",
        )
      }
      return
    }
    if data_words > 0 {
      let mut any_nonzero = false
      for i in 0..<elements {
        if self.word(body + i * stride + data_words - 1) != 0UL {
          any_nonzero = true
          break
        }
      }
      if !any_nonzero {
        raise InvalidMessage(
          "canonical composite list contains untrimmed trailing zero data word",
        )
      }
    }
    if pointers > 0 {
      let mut any_nonnull = false
      for i in 0..<elements {
        if self.word(body + i * stride + data_words + pointers - 1) != 0UL {
          any_nonnull = true
          break
        }
      }
      if !any_nonnull {
        raise InvalidMessage(
          "canonical composite list contains untrimmed trailing null pointer",
        )
      }
    }
    for i in 0..<elements {
      let ptr_base = body + i * stride + data_words
      for p in 0..<pointers {
        self.check_pointer(ptr_base + p, depth - 1, false)
      }
    }
    return
  }
  if code == 0 {
    self.charge(count)
    return
  }
  if code == 6 {
    if count > self.total_words - self.next_word {
      raise Bounds("canonical pointer list extends beyond segment")
    }
    self.charge(count)
    let start = self.next_word
    self.next_word += count
    for i in 0..<count {
      self.check_pointer(start + i, depth - 1, false)
    }
    return
  }
  let words64 = if code == 1 {
    (count.to_int64() + 63L) / 64L
  } else {
    let stride = match code {
      2 => 1L
      3 => 2L
      4 => 4L
      _ => 8L
    }
    (count.to_int64() * stride + 7L) / 8L
  }
  if words64 > (self.total_words - self.next_word).to_int64() {
    raise Bounds("canonical scalar list extends beyond segment")
  }
  let words = words64.to_int()
  self.charge(words)
  let base_byte = self.next_word * 8
  let total_bytes = words * 8
  let used_bytes = if code == 1 {
    (count + 7) / 8
  } else {
    let stride = match code {
      2 => 1
      3 => 2
      4 => 4
      _ => 8
    }
    count * stride
  }
  if code == 1 && count % 8 != 0 {
    let mask = ((1 << (count % 8)) - 1).to_byte()
    if (self.bytes[base_byte + used_bytes - 1] & mask.lnot()) != 0 {
      raise InvalidMessage(
        "canonical bit list has nonzero unused trailing bits",
      )
    }
  }
  for i in used_bytes..<total_bytes {
    if self.bytes[base_byte + i] != 0 {
      raise InvalidMessage("canonical list has nonzero word padding bytes")
    }
  }
  self.next_word += words
}

///|
fn verify_canonical_segment(
  segment : Bytes,
  traversal_limit_words : Int32,
  nesting_limit : Int32,
) -> Unit raise CapnpError {
  if traversal_limit_words < 0 || nesting_limit < 0 {
    raise Limit("invalid canonical verification limit")
  }
  if segment.length() < 8 || segment.length() % 8 != 0 {
    raise InvalidMessage(
      "canonical segment must be a nonempty multiple of 8 bytes",
    )
  }
  let total_words = segment.length() / 8
  let check : CanonicalCheck = {
    bytes: segment,
    total_words,
    next_word: 1,
    remaining_words: traversal_limit_words,
  }
  check.check_pointer(0, nesting_limit, true)
  if check.next_word != total_words {
    raise InvalidMessage(
      "canonical segment contains unreachable trailing words",
    )
  }
}

///|
/// Verify whether a bare segment (without a segment table) satisfies the
/// Cap'n Proto 1.5.0 canonical encoding rules: struct root, single segment,
/// contiguous preorder layout, trimmed struct sections, cleared padding, and
/// no far pointers or capabilities. Returns `false` for non-canonical or
/// malformed wire layouts; raises `Limit` if configured limits are invalid or
/// exceeded.
pub fn is_canonical(
  segment : Bytes,
  traversal_limit_words~ : Int32 = 8_388_608,
  nesting_limit~ : Int32 = 64,
) -> Bool raise CapnpError {
  verify_canonical_segment(segment, traversal_limit_words, nesting_limit) catch {
    Limit(message) => raise Limit(message)
    _ => return false
  }
  true
}

///|
/// Strictly verify a bare canonical segment (without a segment table) and
/// return a zero-copy `Message` view over it. Rejects non-canonical layouts,
/// capabilities, far pointers, dirty padding and unreachable words.
pub fn read_canonical(
  segment : Bytes,
  traversal_limit_words~ : Int32 = 8_388_608,
  nesting_limit~ : Int32 = 64,
) -> Message raise CapnpError {
  verify_canonical_segment(segment, traversal_limit_words, nesting_limit)
  {
    state: {
      bytes: segment,
      offsets: [0],
      sizes: [segment.length() / 8],
      remaining_words: traversal_limit_words,
    },
    nesting_limit,
  }
}
