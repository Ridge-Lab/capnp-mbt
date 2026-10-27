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

///|
priv enum FrameStage {
  SegmentCount
  SegmentTable(Int)
  Payload
}

///|
priv enum FrameStatus {
  Reading
  Failed
  Finished
}

///|
/// Incrementally separate standard unpacked frames from arbitrary byte chunks.
/// Only the unfinished frame is retained between calls. The byte limit applies
/// to each frame and this buffer, not the combined frames returned by one feed.
/// Framing does not validate object pointers; pass completed frames to read_message.
pub struct FrameDecoder {
  priv max_segments : Int
  priv max_message_bytes : Int
  priv mut buffer : Array[Byte]
  priv mut expected : Int
  priv mut stage : FrameStage
  priv mut status : FrameStatus
}

///|
pub fn FrameDecoder::new(
  max_segments? : Int = 512,
  max_message_bytes? : Int = 64 * 1024 * 1024,
) -> FrameDecoder raise CapnpError {
  if max_segments < 1 || max_message_bytes < 8 {
    raise Limit("invalid frame decoder limits")
  }
  {
    max_segments,
    max_message_bytes,
    buffer: [],
    expected: 4,
    stage: SegmentCount,
    status: Reading,
  }
}

///|
fn FrameDecoder::clear_buffer(self : FrameDecoder) -> Unit {
  // Release the previous array instead of retaining a completed frame's capacity.
  self.buffer = []
  self.expected = 4
  self.stage = SegmentCount
}

///|
fn FrameDecoder::buffer_u32(self : FrameDecoder, offset : Int) -> UInt64 {
  let mut value = 0UL
  for i in 0..<4 {
    value = value | (self.buffer[offset + i].to_uint64() << (i * 8))
  }
  value
}

///|
/// Return complete frames in input order. A parsing error discards the partial
/// frame and enters the failed state; this call returns no frames on failure.
/// Previously returned frames remain valid. Call reset before reusing a failed
/// or finished decoder. Empty chunks are accepted while the decoder is open.
pub fn FrameDecoder::feed(
  self : FrameDecoder,
  chunk : Bytes,
) -> Array[Bytes] raise CapnpError {
  match self.status {
    Reading => ()
    Failed =>
      raise InvalidMessage("frame decoder failed; call reset before feeding")
    Finished =>
      raise InvalidMessage("frame decoder finished; call reset before feeding")
  }
  errdefer {
    self.clear_buffer()
    self.status = Failed
  }
  let frames : Array[Bytes] = []
  let mut pos = 0
  // Advancing in three stages scans the segment table only once. Payload bytes
  // are appended once and copied once when handed to the caller, independently
  // of how many chunks split a frame. No consumed prefix needs to be shifted.
  while pos < chunk.length() || self.buffer.length() == self.expected {
    let take = Int::min(
      self.expected - self.buffer.length(),
      chunk.length() - pos,
    )
    for i in 0..<take {
      self.buffer.push(chunk[pos + i])
    }
    pos += take
    if self.buffer.length() < self.expected {
      break
    }
    match self.stage {
      SegmentCount => {
        let count = self.buffer_u32(0) + 1UL
        if count > self.max_segments.to_uint64() {
          raise Limit("segment count exceeds the configured limit")
        }
        let header = (count + 2UL) / 2UL * 8UL
        if header > self.max_message_bytes.to_uint64() {
          raise Limit("segment table exceeds the configured message limit")
        }
        self.expected = header.to_int()
        self.stage = SegmentTable(count.to_int())
      }
      SegmentTable(count) => {
        let mut total = self.buffer.length().to_uint64()
        for i in 0..<count {
          total += self.buffer_u32(4 + i * 4) * 8UL
          if total > self.max_message_bytes.to_uint64() {
            raise Limit("message exceeds the configured byte limit")
          }
        }
        self.expected = total.to_int()
        self.stage = Payload
      }
      Payload => {
        frames.push(Bytes::from_array(self.buffer[:]))
        self.clear_buffer()
      }
    }
  }
  frames
}

///|
/// Finish a stream. An incomplete header or body raises InvalidMessage and
/// enters the failed state. Successful finish is idempotent and closes feeding.
pub fn FrameDecoder::finish(self : FrameDecoder) -> Unit raise CapnpError {
  match self.status {
    Failed =>
      raise InvalidMessage("frame decoder failed; call reset before finishing")
    Finished => ()
    Reading => {
      if !self.buffer.is_empty() {
        self.clear_buffer()
        self.status = Failed
        raise InvalidMessage("truncated frame at end of stream")
      }
      self.status = Finished
    }
  }
}

///|
/// Discard any unfinished frame and reopen the decoder with the same limits.
pub fn FrameDecoder::reset(self : FrameDecoder) -> Unit {
  self.clear_buffer()
  self.status = Reading
}

///|
pub fn FrameDecoder::buffered_bytes(self : FrameDecoder) -> Int {
  self.buffer.length()
}
