///|
priv struct ReadState {
  bytes : Bytes
  offsets : Array[Int32]
  sizes : Array[Int32]
  mut remaining_words : Int32
}

///|
/// An immutable, framed Cap'n Proto message. Readers share its traversal budget.
pub struct Message {
  priv state : ReadState
  priv nesting_limit : Int32
}

///|
/// A lazy pointer. Its target is validated when it is dereferenced.
pub struct PointerReader {
  priv state : ReadState
  priv segment : Int32
  priv word : Int32
  priv depth : Int32
}

///|
/// A view of a struct's data and pointer sections.
pub struct StructReader {
  priv state : ReadState
  priv segment : Int32
  priv start : Int32
  priv data_bytes : Int32
  priv pointer_start : Int32
  priv pointer_count : Int32
  priv depth : Int32
}

///|
/// A lazy list view, including lists of inline composite structs.
pub struct ListReader {
  priv state : ReadState
  priv segment : Int32
  priv start : Int32
  priv count : Int32
  priv code : Int32
  priv stride : Int32
  priv data_words : Int32
  priv pointer_count : Int32
  priv depth : Int32
}

///|
fn read_u32(bytes : Bytes, pos : Int32) -> UInt32 {
  bytes[pos].to_uint() |
  (bytes[pos + 1].to_uint() << 8) |
  (bytes[pos + 2].to_uint() << 16) |
  (bytes[pos + 3].to_uint() << 24)
}

///|
fn read_u64(bytes : Bytes, pos : Int32) -> UInt64 {
  read_u32(bytes, pos).to_uint64() |
  (read_u32(bytes, pos + 4).to_uint64() << 32)
}

///|
fn read_charge(state : ReadState, words : Int32) -> Unit raise CapnpError {
  if words < 0 || words > state.remaining_words {
    raise Limit("message traversal limit exceeded")
  }
  state.remaining_words -= words
}

///|
fn read_extent(
  state : ReadState,
  segment : Int32,
  word : Int32,
  count : Int32,
) -> Unit raise CapnpError {
  if segment < 0 || segment >= state.sizes.length() {
    raise Bounds("segment index outside message")
  }
  let size = state.sizes[segment]
  if word < 0 || count < 0 || word > size || count > size - word {
    raise Bounds("object outside segment")
  }
}

///|
fn read_word(
  state : ReadState,
  segment : Int32,
  word : Int32,
) -> UInt64 raise CapnpError {
  read_extent(state, segment, word, 1)
  read_u64(state.bytes, state.offsets[segment] + word * 8)
}

///|
/// Read exactly one message using standard (unpacked) stream framing.
/// Trailing bytes are rejected; use frame_length to select a frame from a stream.
pub fn read_message(
  bytes : Bytes,
  traversal_limit_words~ : Int32 = 8388608,
  nesting_limit~ : Int32 = 64,
  max_segments~ : Int32 = 512,
) -> Message raise CapnpError {
  if traversal_limit_words < 0 || nesting_limit < 0 || max_segments < 1 {
    raise Limit("invalid reader limit")
  }
  if bytes.length() < 8 {
    raise InvalidMessage("truncated segment table")
  }
  let minus_one = read_u32(bytes, 0)
  if minus_one >= max_segments.reinterpret_as_uint() {
    raise Limit("too many message segments")
  }
  let count = minus_one.reinterpret_as_int() + 1
  if count > (bytes.length() - 4) / 4 {
    raise InvalidMessage("truncated segment table")
  }
  let header64 = (count.to_int64() + 2) / 2 * 8
  if header64 > bytes.length().to_int64() {
    raise InvalidMessage("truncated segment table padding")
  }
  let header = header64.to_int()
  let offsets : Array[Int32] = []
  let sizes : Array[Int32] = []
  let mut cursor = header
  for i in 0..<count {
    let size = read_u32(bytes, 4 + 4 * i)
    if size > ((bytes.length() - cursor) / 8).reinterpret_as_uint() {
      raise InvalidMessage("truncated message segment")
    }
    offsets.push(cursor)
    sizes.push(size.reinterpret_as_int())
    cursor += size.reinterpret_as_int() * 8
  }
  if cursor != bytes.length() {
    raise InvalidMessage("trailing bytes after framed message")
  }
  if sizes[0] == 0 {
    raise InvalidMessage("first segment has no root pointer")
  }
  {
    state: { bytes, offsets, sizes, remaining_words: traversal_limit_words, },
    nesting_limit,
  }
}

///|
pub fn Message::root_pointer(self : Message) -> PointerReader {
  { state: self.state, segment: 0, word: 0, depth: self.nesting_limit, }
}

///|
pub fn Message::root(self : Message) -> StructReader raise CapnpError {
  self.root_pointer().as_struct()
}

///|
pub fn Message::segment_count(self : Message) -> Int32 {
  self.state.sizes.length()
}

///|
pub fn Message::remaining_traversal_words(self : Message) -> Int32 {
  self.state.remaining_words
}

///|
fn read_null(state : ReadState, depth : Int32) -> PointerReader {
  { state, segment: 0, word: -1, depth, }
}

///|
pub fn PointerReader::is_null(self : PointerReader) -> Bool {
  self.word == -1 ||
  read_u64(self.state.bytes, self.state.offsets[self.segment] + self.word * 8) ==
  0
}

///|
fn read_empty_struct(state : ReadState, depth : Int32) -> StructReader {
  {
    state,
    segment: 0,
    start: 0,
    data_bytes: 0,
    pointer_start: 0,
    pointer_count: 0,
    depth,
  }
}

///|
fn read_empty_list(state : ReadState, depth : Int32) -> ListReader {
  {
    state,
    segment: 0,
    start: 0,
    count: 0,
    code: 0,
    stride: 0,
    data_words: 0,
    pointer_count: 0,
    depth,
  }
}
