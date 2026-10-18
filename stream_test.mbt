///|
test "frame length supports partial input and concatenated messages" {
  // One segment, one word, null root.
  let first = b"\x00\x00\x00\x00\x01\x00\x00\x00" + Bytes::make(8, 0)
  let stream = first + first
  for n in 0..<first.length() {
    assert_eq(@capnp.frame_length(first[:n].to_owned()), None)
  }
  assert_eq(@capnp.frame_length(stream), Some(16))
  assert_eq(@capnp.frame_length(stream, offset=16), Some(16))
  assert_eq(@capnp.frame_length(stream, offset=32), None)
}

///|
test "frame header accounts for even segment padding" {
  let input = b"\x01\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00" + Bytes::make(24, 0)
  assert_eq(@capnp.frame_length(input), Some(40))
  assert_eq(@capnp.frame_length(input[:39].to_owned()), None)
}

///|
test "frame limits reject hostile sizes before buffering payloads" {
  assert_true(try { ignore(@capnp.frame_length(b"\xff\xff\xff\xff")); false } catch { _ => true })
  assert_true(try { ignore(@capnp.frame_length(b"\x00\x00\x00\x00\xff\xff\xff\xff")); false } catch { _ => true })
  assert_true(try { ignore(@capnp.frame_length(b"", offset=-1)); false } catch { _ => true })
  assert_true(try { ignore(@capnp.frame_length(b"", max_segments=0)); false } catch { _ => true })
  assert_true(try { ignore(@capnp.frame_length(b"", max_message_bytes=0)); false } catch { _ => true })
}
