///|
test "packed framing accepts every split including far pointers and run counts" {
  let frame = reader_frame([
    [0x0000000100000002UL],
    [0x0000000100000000UL, 42UL],
  ])
  let packed = @capnp.pack(frame)
  for split in 0..<=packed.length() {
    let decoder = @capnp.PackedFrameDecoder::new(
      max_message_bytes=frame.length(),
    )
    let outputs = decoder.feed(packed[:split].to_owned())
    outputs.append(decoder.feed(packed[split:].to_owned()))
    decoder.finish()
    assert_eq(outputs, [frame])
    assert_eq(@capnp.read_message(outputs[0]).root().get_uint64(0), 42UL)
    assert_eq(decoder.buffered_bytes(), 0)
  }
}

///|
test "packed framing agrees with batch unpack for zero dense sparse and random words" {
  let mut seed = 0x7a1934b5U
  // Lengths straddle the maximum 255 extra-word run and 2 KiB scratch boundary.
  for words in [0, 1, 7, 254, 255, 256, 257, 511, 1025] {
    for mode in 0..<4 {
      let data : Array[Byte] = []
      for i in 0..<(words * 8) {
        seed = seed * 1664525U + 1013904223U
        data.push(
          match mode {
            0 => 0
            1 => 0x5a
            2 => if i % 8 == 3 { 0x7f } else { 0 }
            _ => (seed >> 24).to_byte()
          },
        )
      }
      let builder = @capnp.Builder::new()
      builder.init_root(0, 1).set_data(0, Bytes::from_array(data[:]))
      let frame = builder.finish()
      let packed = @capnp.pack(frame)
      assert_eq(@capnp.unpack(packed), frame)
      for chunk_size in [1, 2, 7, 17, 255, 2047, 4093, packed.length()] {
        let decoder = @capnp.PackedFrameDecoder::new(
          max_message_bytes=frame.length(),
        )
        let outputs : Array[Bytes] = []
        let combined = packed + packed
        for pos = 0; pos < combined.length(); pos = pos + chunk_size {
          let end = Int32::min(pos + chunk_size, combined.length())
          outputs.append(decoder.feed(combined[pos:end].to_owned()))
          assert_true(decoder.buffered_bytes() <= frame.length())
        }
        decoder.finish()
        assert_eq(outputs, [frame, frame])
      }
    }
  }
}

///|
test "packed framing rejects every truncated token and frame prefix" {
  let frames = [
    reader_frame([[0UL]]),
    reader_frame([
      [0x0000000200000000UL, 0xfedcba9876543210UL, 0x1122334455667788UL],
    ]),
  ]
  for frame in frames {
    let packed = @capnp.pack(frame)
    for size in 1..<packed.length() {
      let decoder = @capnp.PackedFrameDecoder::new()
      assert_eq(decoder.feed(packed[:size].to_owned()), [])
      reader_error("invalid", () => decoder.finish())
      assert_eq(decoder.buffered_bytes(), 0)
      reader_error("invalid", () => ignore(decoder.feed(packed)))
      decoder.reset()
      assert_eq(decoder.feed(packed), [frame])
      decoder.finish()
      decoder.finish()
      reader_error("invalid", () => ignore(decoder.feed(b"")))
    }
  }
  let empty = @capnp.PackedFrameDecoder::new()
  assert_eq(empty.feed(b""), [])
  empty.finish()
}

///|
test "packed framing checks expanded frame limits and discards failing batches" {
  let frame = reader_frame([[0UL]])
  let decoder = @capnp.PackedFrameDecoder::new(
    max_segments=2,
    max_message_bytes=32,
  )
  for
    hostile in [
      b"\xff\xff\xff\xff\x00\x00\x00\x00", b"\x00\x00\x00\x00\xff\xff\xff\xff", b"\x00\x00\x00\x00\x05\x00\x00\x00",
    ] {
    reader_error("limit", () => {
      ignore(decoder.feed(@capnp.pack(frame + hostile)))
    })
    assert_eq(decoder.buffered_bytes(), 0)
    reader_error("invalid", () => decoder.finish())
    decoder.reset()
  }
  assert_eq(decoder.feed(@capnp.pack(frame)), [frame])
  decoder.finish()
  reader_error("limit", () => {
    ignore(@capnp.PackedFrameDecoder::new(max_segments=0))
  })
  reader_error("limit", () => {
    ignore(@capnp.PackedFrameDecoder::new(max_message_bytes=7))
  })
}

///|
test "packed raw runs may cross standard frame boundaries" {
  // Packing applies to words independently of framing. A valid alternative
  // encoding uses one raw run for both complete frames, including zero bytes.
  let frame = reader_frame([[0x0000000100000000UL, 42UL]])
  let stream = frame + frame
  let alternative = b"\xff" +
    stream[:8].to_owned() +
    b"\x05" +
    stream[8:].to_owned()
  assert_eq(@capnp.unpack(alternative), stream)
  let decoder = @capnp.PackedFrameDecoder::new(max_message_bytes=frame.length())
  let outputs : Array[Bytes] = []
  for i in 0..<alternative.length() {
    outputs.append(decoder.feed(alternative[i:i + 1].to_owned()))
  }
  decoder.finish()
  assert_eq(outputs, [frame, frame])
}

///|
test "a dense word cannot publish a frame before its complete token arrives" {
  // Official capnp 1.5.0 encode --packed of Box {val @0 :UInt64} with
  // val=0x1122334455667788. The final 00 is a required run count.
  let packed = b"\x10\x02\x10\x01\xff\x88\x77\x66\x55\x44\x33\x22\x11\x00"
  let frame = @capnp.unpack(packed)
  let end = packed.length() - 1
  for split in 0..<=end {
    let decoder = @capnp.PackedFrameDecoder::new()
    assert_eq(decoder.feed(packed[:split].to_owned()), [])
    assert_eq(decoder.feed(packed[split:end].to_owned()), [])
    reader_error("invalid", () => decoder.finish())
    decoder.reset()
    assert_eq(decoder.feed(packed + packed[:end].to_owned()), [frame])
    assert_eq(decoder.feed(packed[end:].to_owned()), [frame])
    decoder.finish()
  }
  // A dense run containing two frames can be fragmented after the nominal
  // end of the first frame. No frame from the run is visible on a short read.
  let pair = frame + frame
  let token = b"\xff" + pair[:8].to_owned() + b"\x05" + pair[8:].to_owned()
  let decoder = @capnp.PackedFrameDecoder::new()
  assert_eq(decoder.feed(token[:token.length() - 1].to_owned()), [])
  assert_eq(decoder.feed(token[token.length() - 1:].to_owned()), [frame, frame])
  decoder.finish()
}

///|
test "packed output batches cap byte expansion and tiny frame counts" {
  let frame = reader_frame([[0UL]])
  let bytes = @capnp.pack(frame + frame)
  let by_bytes = @capnp.PackedFrameDecoder::new(
    max_output_bytes_per_feed=frame.length(),
  )
  reader_error("limit", () => ignore(by_bytes.feed(bytes)))
  assert_eq(by_bytes.buffered_bytes(), 0)
  by_bytes.reset()
  assert_eq(by_bytes.feed(@capnp.pack(frame)), [frame])
  // Budgets reset for the next call rather than limiting stream lifetime.
  assert_eq(by_bytes.feed(@capnp.pack(frame)), [frame])
  by_bytes.finish()
  let by_count = @capnp.PackedFrameDecoder::new(max_frames_per_feed=2)
  // One zero run expands to 256 eight-byte frames. A frame can be separated
  // without having a valid root pointer; read_message checks object validity.
  reader_error("limit", () => ignore(by_count.feed(b"\x00\xff")))
  assert_eq(by_count.buffered_bytes(), 0)
  reader_error("invalid", () => ignore(by_count.feed(b"")))
  reader_error("limit", () => {
    ignore(@capnp.PackedFrameDecoder::new(max_frames_per_feed=0))
  })
  reader_error("limit", () => {
    ignore(@capnp.PackedFrameDecoder::new(max_output_bytes_per_feed=7))
  })
}

///|
test "deterministic packed fuzzing matches batch unpack and never panics on corruption" {
  let mut seed = 0x51a9c3e7U
  let next_byte = fn() -> Byte {
    seed = seed * 1664525U + 1013904223U
    (seed >> 24).to_byte()
  }
  let decoder = @capnp.PackedFrameDecoder::new(
    max_segments=16,
    max_message_bytes=4096,
    max_output_bytes_per_feed=4096,
    max_frames_per_feed=16,
  )
  let valid_frame = reader_frame([[0x0000000100000000UL, 0x123456789abcdef0UL]])
  let valid_packed = @capnp.pack(valid_frame)
  // 256 deterministic corrupted/fuzzed packed streams must either decode cleanly
  // or fail with structured CapnpError, and reset() must always restore health.
  for case_index in 0..<256 {
    let length = 1 + case_index % 48
    let raw : Array[Byte] = []
    for _ in 0..<length {
      raw.push(next_byte())
    }
    let payload = Bytes::from_array(raw[:])
    let mut batch_ok = false
    let mut batch_out = b""
    try {
      batch_out = @capnp.unpack(payload, max_output_bytes=4096)
      batch_ok = true
    } catch {
      _ => ()
    }
    let split = case_index % (length + 1)
    let mut stream_ok = false
    let stream_out : Array[Byte] = []
    try {
      for f in decoder.feed(payload[:split].to_owned()) {
        for b in f {
          stream_out.push(b)
        }
      }
      for f in decoder.feed(payload[split:].to_owned()) {
        for b in f {
          stream_out.push(b)
        }
      }
      decoder.finish()
      stream_ok = true
    } catch {
      _ => ()
    }
    if stream_ok {
      // Any stream accepted as complete frames must match batch unpack byte-for-byte.
      assert_true(batch_ok)
      assert_eq(Bytes::from_array(stream_out[:]), batch_out)
    }
    decoder.reset()
    assert_eq(decoder.feed(valid_packed), [valid_frame])
    decoder.finish()
    decoder.reset()
  }
}
