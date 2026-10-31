///|
/// A bounded arena producing one standard Cap'n Proto stream segment.
/// Handles share the arena; scalar writes do not copy the message.
pub struct Builder {
  priv arena : Array[Byte]
  priv max_words : Int32
}

///|
pub struct StructBuilder {
  priv owner : Builder
  priv data_start : Int32
  priv data_words : Int32
  priv pointer_count : Int32
}

///|
pub struct ListBuilder {
  priv owner : Builder
  priv start : Int32
  priv count : Int32
  priv size_code : Int32
  priv data_words : Int32
  priv pointer_count : Int32
}

///|
/// The default allocation limit is 64 MiB, including the root pointer.
pub fn Builder::new(max_words~ : Int32 = 8_388_608) -> Builder raise CapnpError {
  if max_words < 1 || max_words > 268_435_454 {
    raise Limit("builder max_words must be between 1 and 268435454")
  }
  { arena: Array::make(8, 0), max_words, }
}

///|
fn b_alloc(owner : Builder, words : Int32) -> Int32 raise CapnpError {
  let used = owner.arena.length() / 8
  if words < 0 || words > owner.max_words - used {
    raise Limit("single-segment builder allocation limit exceeded")
  }
  let start = owner.arena.length()
  for _ in 0..<(words * 8) {
    owner.arena.push(0)
  }
  start
}

///|
fn b_write(
  owner : Builder,
  offset : Int32,
  value : UInt64,
  width : Int32,
) -> Unit {
  for i in 0..<width {
    owner.arena[offset + i] = (value >> (i * 8)).to_byte()
  }
}

///|
fn b_struct_size(
  data_words : Int32,
  pointer_count : Int32,
) -> Unit raise CapnpError {
  if data_words < 0 ||
    data_words > 65535 ||
    pointer_count < 0 ||
    pointer_count > 65535 {
    raise Bounds(
      "struct data and pointer counts must fit unsigned 16-bit words",
    )
  }
}

///|
fn b_init_struct(
  owner : Builder,
  slot : Int32,
  data_words : Int32,
  pointer_count : Int32,
) -> StructBuilder raise CapnpError {
  b_struct_size(data_words, pointer_count)
  let start = b_alloc(owner, data_words + pointer_count)
  let offset = if data_words + pointer_count == 0 {
    0xfffffffcUL
  } else {
    ((start - slot) / 8 - 1).to_uint64() << 2
  }
  b_write(
    owner,
    slot,
    offset | (data_words.to_uint64() << 32) | (pointer_count.to_uint64() << 48),
    8,
  )
  { owner, data_start: start, data_words, pointer_count, }
}

///|
/// Allocate a new root. Reinitializing replaces the pointer; old arena space
/// remains allocated and is still charged to the allocation limit.
pub fn Builder::init_root(
  self : Builder,
  data_words : Int32,
  pointer_count : Int32,
) -> StructBuilder raise CapnpError {
  b_init_struct(self, 0, data_words, pointer_count)
}

///|
/// Return a snapshot with the standard single-segment stream framing.
pub fn Builder::finish(self : Builder) -> Bytes {
  let words = (self.arena.length() / 8).to_uint64()
  Bytes::makei(self.arena.length() + 8, fn(i) {
    if i < 4 {
      0
    } else if i < 8 {
      (words >> ((i - 4) * 8)).to_byte()
    } else {
      self.arena[i - 8]
    }
  })
}

///|
pub fn Builder::allocated_words(self : Builder) -> Int32 {
  self.arena.length() / 8
}

///|
fn b_data(
  handle : StructBuilder,
  offset : Int32,
  width : Int32,
) -> Int32 raise CapnpError {
  let size = handle.data_words * 8
  if offset < 0 || width < 0 || offset > size || width > size - offset {
    raise Bounds("field extends beyond struct data section")
  }
  handle.data_start + offset
}

///|
fn b_pointer(handle : StructBuilder, slot : Int32) -> Int32 raise CapnpError {
  if slot < 0 || slot >= handle.pointer_count {
    raise Bounds("pointer slot outside struct pointer section")
  }
  handle.data_start + handle.data_words * 8 + slot * 8
}

///|
pub fn StructBuilder::clear_pointer(
  self : StructBuilder,
  slot : Int32,
) -> Unit raise CapnpError {
  b_write(self.owner, b_pointer(self, slot), 0, 8)
}

///|
pub fn StructBuilder::clear_data(
  self : StructBuilder,
  byte_offset : Int32,
  byte_length : Int32,
) -> Unit raise CapnpError {
  let start = b_data(self, byte_offset, byte_length)
  for i in 0..<byte_length {
    self.owner.arena[start + i] = 0
  }
}

///|
pub fn StructBuilder::init_struct(
  self : StructBuilder,
  slot : Int32,
  data_words : Int32,
  pointer_count : Int32,
) -> StructBuilder raise CapnpError {
  b_init_struct(self.owner, b_pointer(self, slot), data_words, pointer_count)
}

///|
fn b_count(length : Int32) -> Unit raise CapnpError {
  if length < 0 || length > 536_870_911 {
    raise Bounds("list element count must fit unsigned 29 bits")
  }
}

///|
fn b_init_list(
  owner : Builder,
  slot : Int32,
  element_size : Int32,
  length : Int32,
) -> ListBuilder raise CapnpError {
  b_count(length)
  let words = match element_size {
    0 => 0
    1 => (length + 63) / 64
    2 => (length + 7) / 8
    3 => (length + 3) / 4
    4 => (length + 1) / 2
    5 | 6 => length
    _ =>
      raise TypeMismatch(
        "list element size must be 0..6; use init_struct_list for composite lists",
      )
  }
  let start = b_alloc(owner, words)
  let offset = ((start - slot) / 8 - 1).to_uint64()
  b_write(
    owner,
    slot,
    1UL |
    (offset << 2) |
    (element_size.to_uint64() << 32) |
    (length.to_uint64() << 35),
    8,
  )
  {
    owner,
    start,
    count: length,
    size_code: element_size,
    data_words: 0,
    pointer_count: 0,
  }
}

///|
fn b_init_struct_list(
  owner : Builder,
  slot : Int32,
  length : Int32,
  data_words : Int32,
  pointer_count : Int32,
) -> ListBuilder raise CapnpError {
  b_count(length)
  b_struct_size(data_words, pointer_count)
  let stride = data_words + pointer_count
  if stride > 0 &&
    length > (owner.max_words - owner.arena.length() / 8 - 1) / stride {
    raise Limit("composite list exceeds single-segment allocation limit")
  }
  let words = length * stride
  if words > 536_870_911 {
    raise Limit("composite list word count exceeds wire limit")
  }
  let tag = b_alloc(owner, words + 1)
  let offset = ((tag - slot) / 8 - 1).to_uint64()
  b_write(
    owner,
    slot,
    1UL | (offset << 2) | (7UL << 32) | (words.to_uint64() << 35),
    8,
  )
  b_write(
    owner,
    tag,
    (length.to_uint64() << 2) |
    (data_words.to_uint64() << 32) |
    (pointer_count.to_uint64() << 48),
    8,
  )
  {
    owner,
    start: tag + 8,
    count: length,
    size_code: 7,
    data_words,
    pointer_count,
  }
}

///|
/// Element size is the standard wire code: 0 void, 1 bit, 2 byte, 3 uint16,
/// 4 uint32, 5 uint64, 6 pointer. Struct lists use init_struct_list.
pub fn StructBuilder::init_list(
  self : StructBuilder,
  slot : Int32,
  element_size : Int32,
  length : Int32,
) -> ListBuilder raise CapnpError {
  b_init_list(self.owner, b_pointer(self, slot), element_size, length)
}

///|
pub fn StructBuilder::init_struct_list(
  self : StructBuilder,
  slot : Int32,
  length : Int32,
  data_words : Int32,
  pointer_count : Int32,
) -> ListBuilder raise CapnpError {
  b_init_struct_list(
    self.owner,
    b_pointer(self, slot),
    length,
    data_words,
    pointer_count,
  )
}

///|
fn b_blob(
  owner : Builder,
  slot : Int32,
  bytes : Bytes,
  text : Bool,
) -> Unit raise CapnpError {
  let max_length = if text { 536_870_910 } else { 536_870_911 }
  if bytes.length() > max_length {
    raise Limit("text or data exceeds list count limit")
  }
  let count = bytes.length() + (if text { 1 } else { 0 })
  let list = b_init_list(owner, slot, 2, count)
  for i in 0..<bytes.length() {
    owner.arena[list.start + i] = bytes[i]
  }
}

///|
pub fn StructBuilder::set_text(
  self : StructBuilder,
  slot : Int32,
  value : String,
) -> Unit raise CapnpError {
  b_blob(self.owner, b_pointer(self, slot), @utf8.encode(value), true)
}

///|
pub fn StructBuilder::set_data(
  self : StructBuilder,
  slot : Int32,
  value : Bytes,
) -> Unit raise CapnpError {
  b_blob(self.owner, b_pointer(self, slot), value, false)
}
