///|
/// Length of one standard (unpacked) Cap'n Proto frame at `offset`.
/// Returns `None` when more input is needed. Limits are checked from the
/// header before waiting for, or copying, the declared payload.
pub fn frame_length(
  input : Bytes,
  offset? : Int = 0,
  max_segments? : Int = 512,
  max_message_bytes? : Int = 64 * 1024 * 1024,
) -> Int? raise CapnpError {
  guard offset >= 0 && offset <= input.length() else {
    raise Bounds("frame offset is outside input")
  }
  guard max_segments > 0 && max_message_bytes >= 8 else {
    raise Limit("invalid frame limits")
  }
  if input.length() - offset < 4 {
    return None
  }
  let count = stream_u32(input, offset) + 1UL
  guard count <= max_segments.to_uint64() else {
    raise Limit("segment count exceeds the configured limit")
  }
  let header = (count + 2UL) / 2UL * 8UL
  guard header <= max_message_bytes.to_uint64() else {
    raise Limit("segment table exceeds the configured message limit")
  }
  if header > (input.length() - offset).to_uint64() {
    return None
  }
  let mut total = header
  for i in 0..<count.to_int() {
    total += stream_u32(input, offset + 4 + i * 4) * 8UL
    guard total <= max_message_bytes.to_uint64() else {
      raise Limit("message exceeds the configured byte limit")
    }
  }
  if total > (input.length() - offset).to_uint64() {
    None
  } else {
    Some(total.to_int())
  }
}

///|
fn stream_u32(input : Bytes, offset : Int) -> UInt64 {
  let mut result = 0UL
  for i in 0..<4 {
    result = result | (input[offset + i].to_uint64() << (i * 8))
  }
  result
}
