///|
test "incremental framing accepts every split of a segmented frame" {
  let wire = reader_frame([[0x0000000100000002UL], [0x0000000100000000UL, 42UL]])
  for split in 0..<=wire.length() {
    let decoder = @capnp.FrameDecoder::new()
    let first = decoder.feed(wire[:split].to_owned())
    let second = decoder.feed(wire[split:].to_owned())
    assert_eq(first.length() + second.length(), 1)
    let frame = if first.is_empty() { second[0] } else { first[0] }
    assert_eq(frame, wire)
    assert_eq(@capnp.read_message(frame).root().get_uint64(0), 42UL)
    assert_eq(decoder.buffered_bytes(), 0)
    decoder.finish()
  }
}

///|
test "incremental framing separates concatenated frames across small chunks" {
  let first = reader_frame([[0UL]])
  let second = reader_frame([[0x0000000100000000UL, 123UL]])
  let third = reader_frame([
    [0x0000000100000006UL],
    [0x0000000200000002UL, 0x0000000100000000UL],
    [456UL],
  ])
  let stream = first + second + third
  for size in [1, 3, 7, 8, 13, 64, stream.length()] {
    let decoder = @capnp.FrameDecoder::new()
    let frames : Array[Bytes] = []
    for offset = 0; offset < stream.length(); offset = offset + size {
      let end = Int::min(offset + size, stream.length())
      frames.append(decoder.feed(stream[offset:end].to_owned()))
    }
    decoder.finish()
    assert_eq(frames, [first, second, third])
    assert_eq(@capnp.read_message(frames[2]).root().get_uint64(0), 456UL)
    assert_eq(decoder.buffered_bytes(), 0)
  }
}

///|
test "incremental framing retains only the unfinished tail and applies per-frame limits" {
  let frame = reader_frame([[0x0000000100000000UL, 7UL]])
  let decoder = @capnp.FrameDecoder::new(max_message_bytes=frame.length())
  // The combined output may exceed the limit, which applies to each frame.
  assert_eq(decoder.feed(frame + frame + frame[:5].to_owned()), [frame, frame])
  assert_eq(decoder.buffered_bytes(), 5)
  assert_eq(decoder.feed(b""), [])
  assert_eq(decoder.buffered_bytes(), 5)
  assert_eq(decoder.feed(frame[5:].to_owned()), [frame])
  assert_eq(decoder.buffered_bytes(), 0)
  decoder.finish()
  decoder.finish()
  reader_error("invalid", () => ignore(decoder.feed(b"")))
  decoder.reset()
  assert_eq(decoder.feed(frame), [frame])
  decoder.finish()
}

///|
test "incremental framing rejects hostile headers before buffering bodies and can reset" {
  let frame = reader_frame([[0UL]])
  let decoder = @capnp.FrameDecoder::new(max_segments=2, max_message_bytes=32)
  let bad_headers = [
    b"\xff\xff\xff\xff", // segment count is rejected after four bytes
     b"\x00\x00\x00\x00\xff\xff\xff\xff", // enormous declared body
     b"\x01\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00", // combined segments exceed the limit
  ]
  for header in bad_headers {
    decoder.reset()
    // No partial output is returned even if a valid frame precedes the error.
    reader_error("limit", () => ignore(decoder.feed(frame + header)))
    assert_eq(decoder.buffered_bytes(), 0)
    reader_error("invalid", () => ignore(decoder.feed(frame)))
    reader_error("invalid", () => decoder.finish())
    decoder.reset()
    assert_eq(decoder.feed(frame), [frame])
    decoder.finish()
  }
  let tiny = @capnp.FrameDecoder::new(max_message_bytes=8)
  reader_error("limit", () => ignore(tiny.feed(b"\x01\x00\x00\x00")))
  assert_eq(tiny.buffered_bytes(), 0)
}

///|
test "incremental framing reports every truncated prefix and resets open streams" {
  let frame = reader_frame([
    [0x0000000100000002UL],
    [0x0000000100000000UL, 42UL],
  ])
  for length in 1..<frame.length() {
    let decoder = @capnp.FrameDecoder::new()
    assert_eq(decoder.feed(frame[:length].to_owned()), [])
    assert_eq(decoder.buffered_bytes(), length)
    reader_error("invalid", () => decoder.finish())
    assert_eq(decoder.buffered_bytes(), 0)
    reader_error("invalid", () => decoder.finish())
    reader_error("invalid", () => ignore(decoder.feed(frame)))
    decoder.reset()
    assert_eq(decoder.feed(frame), [frame])
    decoder.finish()
  }
  let decoder = @capnp.FrameDecoder::new()
  ignore(decoder.feed(frame[:5].to_owned()))
  decoder.reset()
  assert_eq(decoder.buffered_bytes(), 0)
  assert_eq(decoder.feed(frame), [frame])
  decoder.finish()
  let empty = @capnp.FrameDecoder::new()
  empty.finish()
  empty.finish()
}

///|
test "incremental framing validates configured limits" {
  reader_error("limit", () => ignore(@capnp.FrameDecoder::new(max_segments=0)))
  reader_error("limit", () => ignore(@capnp.FrameDecoder::new(max_segments=-1)))
  for limit in [-1, 0, 7] {
    reader_error("limit", () => {
      ignore(@capnp.FrameDecoder::new(max_message_bytes=limit))
    })
  }
}

///|
test "incremental framing handles a large frame arriving one byte at a time" {
  // One segment with 8,193 words: root pointer plus 8,192 data words.
  // This independent frame exercises the long payload path without repeatedly
  // rebuilding or rescanning an ever-growing prefix for each incoming byte.
  let frame = b"\x00\x00\x00\x00\x01\x20\x00\x00" +
    b"\x00\x00\x00\x00\x00\x20\x00\x00" +
    Bytes::make(65536, 0x5a)
  let decoder = @capnp.FrameDecoder::new(max_message_bytes=frame.length())
  let mut emitted = 0
  for i in 0..<frame.length() {
    for output in decoder.feed(frame[i:i + 1].to_owned()) {
      assert_eq(output, frame)
      emitted += 1
    }
  }
  assert_eq(emitted, 1)
  assert_eq(decoder.buffered_bytes(), 0)
  decoder.finish()
}
