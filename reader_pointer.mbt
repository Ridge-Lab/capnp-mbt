///|
// Resolve at most the two landing-pad words allowed by the wire format.
// Result: segment, body offset in words, resolved tag.
fn PointerReader::read_resolve(
  self : PointerReader,
) -> (Int32, Int32, UInt64) raise CapnpError {
  if self.depth <= 0 {
    raise Limit("message nesting limit exceeded")
  }
  let tag = read_word(self.state, self.segment, self.word)
  let low = tag.to_uint()
  if (low & 3) != 2 {
    let offset = low.reinterpret_as_int() >> 2
    // Pointer position is bounded by the actual Bytes length; signed addition
    // is checked in Int64 before narrowing to host indices.
    let target = self.word.to_int64() + 1 + offset.to_int64()
    if target < 0 || target > self.state.sizes[self.segment].to_int64() {
      raise Bounds("pointer offset outside segment")
    }
    return (self.segment, target.to_int(), tag)
  }
  let segment64 = tag >> 32
  if segment64 >= self.state.sizes.length().to_uint64() {
    raise Bounds("far pointer names unknown segment")
  }
  let segment = segment64.to_int()
  let pad = (low >> 3).reinterpret_as_int()
  if (low & 4) == 0 {
    let landing = read_word(self.state, segment, pad)
    read_charge(self.state, 1)
    let landing_low = landing.to_uint()
    if (landing_low & 3) > 1 {
      raise InvalidMessage(
        "single-far landing pad must be a struct or list pointer",
      )
    }
    let target = pad.to_int64() +
      1 +
      (landing_low.reinterpret_as_int() >> 2).to_int64()
    if target < 0 || target > self.state.sizes[segment].to_int64() {
      raise Bounds("far pointer target outside segment")
    }
    return (segment, target.to_int(), landing)
  }
  read_extent(self.state, segment, pad, 2)
  read_charge(self.state, 2)
  let landing = read_word(self.state, segment, pad)
  let object_tag = read_word(self.state, segment, pad + 1)
  let landing_low = landing.to_uint()
  if (landing_low & 7) != 2 {
    raise InvalidMessage(
      "double-far landing pad must begin with a single far pointer",
    )
  }
  if (object_tag.to_uint() & 3) > 1 || object_tag.to_uint() >> 2 != 0 {
    raise InvalidMessage("double-far tag has invalid kind or non-zero offset")
  }
  let object_segment64 = landing >> 32
  if object_segment64 >= self.state.sizes.length().to_uint64() {
    raise Bounds("double-far pointer names unknown segment")
  }
  let object_segment = object_segment64.to_int()
  let target = (landing_low >> 3).reinterpret_as_int()
  read_extent(self.state, object_segment, target, 0)
  (object_segment, target, object_tag)
}

///|
pub fn PointerReader::as_struct(
  self : PointerReader,
) -> StructReader raise CapnpError {
  if self.is_null() {
    return read_empty_struct(self.state, self.depth)
  }
  let (segment, target, tag) = PointerReader::read_resolve(self)
  match tag.to_uint() & 3 {
    0 => ()
    3 =>
      raise Unsupported("capability pointers require an RPC capability table")
    _ => raise TypeMismatch("expected struct pointer")
  }
  let data_words = ((tag >> 32) & 0xffff).to_int()
  let pointers = (tag >> 48).to_int()
  read_extent(self.state, segment, target, data_words + pointers)
  read_charge(self.state, data_words + pointers)
  {
    state: self.state,
    segment,
    start: target * 8,
    data_bytes: data_words * 8,
    pointer_start: target + data_words,
    pointer_count: pointers,
    depth: self.depth - 1,
  }
}

///|
pub fn PointerReader::as_list(
  self : PointerReader,
) -> ListReader raise CapnpError {
  if self.is_null() {
    return read_empty_list(self.state, self.depth)
  }
  let (segment, target, tag) = PointerReader::read_resolve(self)
  match tag.to_uint() & 3 {
    1 => ()
    3 =>
      raise Unsupported("capability pointers require an RPC capability table")
    _ => raise TypeMismatch("expected list pointer")
  }
  let upper = (tag >> 32).to_uint()
  let code = (upper & 7).reinterpret_as_int()
  let count = (upper >> 3).reinterpret_as_int()
  if code == 7 {
    read_extent(self.state, segment, target, count + 1)
    let element_tag = read_word(self.state, segment, target)
    if (element_tag.to_uint() & 3) != 0 {
      raise InvalidMessage("inline composite tag must describe a struct")
    }
    let elements = (element_tag.to_uint() >> 2).reinterpret_as_int()
    let data_words = ((element_tag >> 32) & 0xffff).to_int()
    let pointers = (element_tag >> 48).to_int()
    let stride = data_words + pointers
    if stride != 0 && elements > count / stride {
      raise Bounds("inline composite elements exceed declared word count")
    }
    // Zero-width lists can amplify into arbitrarily many logical objects.
    read_charge(self.state, if stride == 0 { elements + 1 } else { count + 1 })
    return {
      state: self.state,
      segment,
      start: (target + 1) * 8,
      count: elements,
      code,
      stride: stride * 8,
      data_words,
      pointer_count: pointers,
      depth: self.depth - 1,
    }
  }
  let stride = match code {
    0 => 0
    1 => 0
    2 => 1
    3 => 2
    4 => 4
    _ => 8
  }
  let words64 = if code == 1 {
    (count.to_int64() + 63) / 64
  } else {
    (count.to_int64() * stride.to_int64() + 7) / 8
  }
  if words64 > self.state.sizes[segment].to_int64() {
    raise Bounds("list word count exceeds segment")
  }
  read_extent(self.state, segment, target, words64.to_int())
  read_charge(self.state, if code == 0 { count } else { words64.to_int() })
  {
    state: self.state,
    segment,
    start: target * 8,
    count,
    code,
    stride,
    data_words: 0,
    pointer_count: 0,
    depth: self.depth - 1,
  }
}

///|
pub fn PointerReader::as_data(
  self : PointerReader,
  default~ : Bytes = b"",
) -> Bytes raise CapnpError {
  if self.is_null() {
    return default
  }
  let list = self.as_list()
  if list.code != 2 {
    raise TypeMismatch("expected byte list")
  }
  let start = self.state.offsets[list.segment] + list.start
  self.state.bytes[start:start + list.count].to_owned()
}

///|
pub fn PointerReader::as_text(
  self : PointerReader,
  default~ : String = "",
) -> String raise CapnpError {
  if self.is_null() {
    return default
  }
  let list = self.as_list()
  if list.code != 2 {
    raise TypeMismatch("expected text byte list")
  }
  if list.count == 0 {
    raise InvalidMessage("text is missing its NUL terminator")
  }
  let start = self.state.offsets[list.segment] + list.start
  if self.state.bytes[start + list.count - 1] != 0 {
    raise InvalidMessage("text is missing its NUL terminator")
  }
  @utf8.decode(self.state.bytes[start:start + list.count - 1]) catch {
    _ => raise InvalidMessage("text contains invalid UTF-8")
  }
}

///|
pub fn StructReader::get_pointer(
  self : StructReader,
  index : Int32,
) -> PointerReader raise CapnpError {
  if index < 0 {
    raise Bounds("negative struct pointer index")
  }
  if index >= self.pointer_count {
    return read_null(self.state, self.depth)
  }
  {
    state: self.state,
    segment: self.segment,
    word: self.pointer_start + index,
    depth: self.depth,
  }
}

///|
pub fn StructReader::get_struct(
  self : StructReader,
  index : Int32,
) -> StructReader raise CapnpError {
  self.get_pointer(index).as_struct()
}

///|
pub fn StructReader::get_list(
  self : StructReader,
  index : Int32,
) -> ListReader raise CapnpError {
  self.get_pointer(index).as_list()
}

///|
pub fn StructReader::get_text(
  self : StructReader,
  index : Int32,
  default~ : String = "",
) -> String raise CapnpError {
  self.get_pointer(index).as_text(default~)
}

///|
pub fn StructReader::get_data(
  self : StructReader,
  index : Int32,
  default~ : Bytes = b"",
) -> Bytes raise CapnpError {
  self.get_pointer(index).as_data(default~)
}

///|
pub fn StructReader::data_size_bytes(self : StructReader) -> Int32 {
  self.data_bytes
}

///|
pub fn StructReader::pointer_count(self : StructReader) -> Int32 {
  self.pointer_count
}
