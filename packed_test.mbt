///|
test "packing matches published sparse words" {
  let plain = b"\x08\x00\x00\x00\x03\x00\x02\x00\x19\x00\x00\x00\xaa\x01\x00\x00"
  let packed = b"\x51\x08\x03\x02\x31\x19\xaa\x01"
  assert_eq(@capnp.pack(plain), packed)
  assert_eq(@capnp.unpack(packed), plain)
}

///|
test "packing empty, zero and dense runs" {
  assert_eq(@capnp.pack(b""), b"")
  assert_eq(@capnp.unpack(b""), b"")
  assert_eq(@capnp.pack(Bytes::make(32, 0)), b"\x00\x03")
  let dense = Bytes::make(32, 0x8a)
  assert_eq(@capnp.pack(dense), b"\xff" + Bytes::make(8, 0x8a) + b"\x03" + Bytes::make(24, 0x8a))
  assert_eq(@capnp.unpack(@capnp.pack(dense)), dense)
  // Crossing the 255-word run-length boundary must start another tag.
  let zeroes = Bytes::make(4096, 0)
  assert_eq(@capnp.pack(zeroes), b"\x00\xff\x00\xff")
  assert_eq(@capnp.unpack(@capnp.pack(zeroes)), zeroes)
}

///|
test "packing handles each byte mask and dense run transition" {
  let words : Array[Byte] = []
  for mask in 0..<256 {
    for bit in 0..<8 { words.push(if (mask & (1 << bit)) == 0 { 0 } else { (bit + 1).to_byte() }) }
  }
  let data = Bytes::from_array(words[:])
  assert_eq(@capnp.unpack(@capnp.pack(data)), data)
  let almost_dense = b"\x00\x01\x02\x03\x04\x05\x06\x07"
  let mixed = Bytes::make(8, 7) + almost_dense + Bytes::make(8, 0) + Bytes::make(8, 9)
  assert_eq(@capnp.unpack(@capnp.pack(mixed)), mixed)
}

///|
test "packing rejects partial words, truncated data and expansion limits" {
  assert_true(try { ignore(@capnp.pack(b"x")); false } catch { _ => true })
  for malformed in [b"\x00", b"\x01", b"\xffabcdefg", b"\xffabcdefgh", b"\xffabcdefgh\x01x"] {
    assert_true(try { ignore(@capnp.unpack(malformed)); false } catch { _ => true })
  }
  assert_true(try { ignore(@capnp.unpack(b"\x00\xff", max_output_bytes=2047)); false } catch { _ => true })
  assert_eq(@capnp.unpack(b"\x00\xff", max_output_bytes=2048).length(), 2048)
  assert_true(try { ignore(@capnp.unpack(b"\x00\x00", max_output_bytes=7)); false } catch { _ => true })
  assert_true(try { ignore(@capnp.unpack(b"", max_output_bytes=-1)); false } catch { _ => true })
}
