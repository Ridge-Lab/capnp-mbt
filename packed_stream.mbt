///|
priv enum PackedStage {
  Tag
  Word(Int32, Int32)
  Run(Int32)
  Raw(Int32)
}

///|
/// Incremental packed stream framing. Unlike unpack, no complete unpacked
/// stream is allocated. Frame limits apply to expanded bytes, per message.
pub struct PackedFrameDecoder {
  priv frames : FrameDecoder
  priv max_output_bytes_per_feed : Int32
  priv max_frames_per_feed : Int32
  priv word : Array[Byte]
  priv mut stage : PackedStage
  priv mut status : FrameStatus
}

///|
pub fn PackedFrameDecoder::new(
  max_segments~ : Int32 = 512,
  max_message_bytes~ : Int32 = 64 * 1024 * 1024,
  max_output_bytes_per_feed~ : Int32 = 64 * 1024 * 1024,
  max_frames_per_feed~ : Int32 = 4096,
) -> PackedFrameDecoder raise CapnpError {
  guard max_output_bytes_per_feed >= 8 && max_frames_per_feed >= 1 else {
    raise Limit("invalid packed output limits")
  }
  {
    frames: FrameDecoder::new(max_segments~, max_message_bytes~),
    max_output_bytes_per_feed,
    max_frames_per_feed,
    word: Array::make(8, 0),
    stage: Tag,
    status: Reading,
  }
}

///|
fn PackedFrameDecoder::collect(
  self : PackedFrameDecoder,
  pending : Array[Byte],
  outputs : Array[Bytes],
  previous : Int32,
) -> Int32 raise CapnpError {
  let mut total = previous
  for frame in self.frames.feed(Bytes::from_array(pending[:])) {
    guard outputs.length() < self.max_frames_per_feed &&
      frame.length() <= self.max_output_bytes_per_feed - total else {
      raise Limit("packed output batch exceeds configured feed limits")
    }
    total += frame.length()
    outputs.push(frame)
  }
  total
}

///|
/// Accept arbitrary packed fragments and return completed unpacked frames.
/// A packing or framing error discards this call's outputs and poisons the
/// decoder until reset. Earlier returned frames remain owned by the caller.
/// The temporary expansion buffer is at most 2 KiB; caller input/output and
/// allocator capacity are not included in the per-frame logical byte limit.
pub fn PackedFrameDecoder::feed(
  self : PackedFrameDecoder,
  chunk : Bytes,
) -> Array[Bytes] raise CapnpError {
  match self.status {
    Reading => ()
    Failed =>
      raise InvalidMessage("packed decoder failed; call reset before feeding")
    Finished =>
      raise InvalidMessage("packed decoder finished; call reset before feeding")
  }
  errdefer {
    self.frames.reset()
    self.stage = Tag
    self.status = Failed
  }
  let outputs : Array[Bytes] = []
  let pending : Array[Byte] = []
  let mut produced = 0
  let mut pos = 0
  while pos < chunk.length() {
    match self.stage {
      Tag => {
        self.stage = Word(chunk[pos].to_int(), 0)
        pos += 1
      }
      Word(tag, next) => {
        let mut index = next
        while index < 8 {
          if (tag & (1 << index)) == 0 {
            self.word[index] = 0
          } else {
            if pos == chunk.length() {
              break
            }
            self.word[index] = chunk[pos]
            pos += 1
          }
          index += 1
        }
        if index < 8 {
          self.stage = Word(tag, index)
        } else {
          if pending.length() > 2040 {
            produced = self.collect(pending, outputs, produced)
            pending.clear()
          }
          pending.append(self.word)
          self.stage = if tag == 0 || tag == 255 { Run(tag) } else { Tag }
        }
      }
      Run(tag) => {
        let size = chunk[pos].to_int() * 8
        pos += 1
        if tag == 255 {
          self.stage = if size == 0 { Tag } else { Raw(size) }
        } else {
          for _ in 0..<size {
            pending.push(0)
            if pending.length() == 2048 {
              produced = self.collect(pending, outputs, produced)
              pending.clear()
            }
          }
          self.stage = Tag
        }
      }
      Raw(remaining) => {
        let size = Int32::min(
          remaining,
          Int32::min(chunk.length() - pos, 2048 - pending.length()),
        )
        for i in 0..<size {
          pending.push(chunk[pos + i])
        }
        pos += size
        self.stage = if size == remaining { Tag } else { Raw(remaining - size) }
      }
    }
    if pending.length() == 2048 {
      produced = self.collect(pending, outputs, produced)
      pending.clear()
    }
  }
  if !pending.is_empty() {
    ignore(self.collect(pending, outputs, produced))
  }
  outputs
}

///|
/// Require both a complete packing token and a complete final frame at EOF.
pub fn PackedFrameDecoder::finish(
  self : PackedFrameDecoder,
) -> Unit raise CapnpError {
  match self.status {
    Failed =>
      raise InvalidMessage("packed decoder failed; call reset before finishing")
    Finished => ()
    Reading => {
      errdefer {
        self.frames.reset()
        self.stage = Tag
        self.status = Failed
      }
      match self.stage {
        Tag => ()
        _ => raise InvalidMessage("truncated packed token at end of stream")
      }
      self.frames.finish()
      self.status = Finished
    }
  }
}

///|
pub fn PackedFrameDecoder::reset(self : PackedFrameDecoder) -> Unit {
  self.frames.reset()
  self.stage = Tag
  self.status = Reading
}

///|
/// Expanded bytes of the unfinished frame, excluding the partial 8-byte word.
pub fn PackedFrameDecoder::buffered_bytes(self : PackedFrameDecoder) -> Int32 {
  self.frames.buffered_bytes()
}
