///|
fn reader_check_oracle(bytes : Bytes) -> Unit raise {
  let root = @capnp.read_message(bytes).root()
  // Field offsets come from `capnp compile -ocapnp fixtures/conformance.capnp`.
  assert_eq(root.data_size_bytes(), 56)
  assert_eq(root.pointer_count(), 17)
  assert_eq(root.get_bool(0, default=true), false)
  assert_eq(root.get_int8(1, default=-12), -128)
  assert_eq(root.get_int16(2, default=-300), -32768)
  assert_eq(root.get_int32(4, default=-70000), -2147483648)
  assert_eq(
    root.get_int64(8, default=-9007199254740993L),
    -9223372036854775808L,
  )
  assert_eq(root.get_uint8(16, default=250), 255)
  assert_eq(root.get_uint16(18, default=60000), 65535)
  assert_eq(root.get_uint32(20, default=4000000000), 4294967295)
  assert_eq(
    root.get_uint64(24, default=18446744073709551615UL),
    9007199254740993UL,
  )
  assert_eq(root.get_float32(32, default=1.5), 3.25)
  assert_eq(root.get_float64(40, default=-0.25), -12345.125)
  assert_eq(root.get_uint16(36, default=2), 1)
  assert_eq(root.get_text(0), "MoonBit 数据交换")
  assert_eq(root.get_data(1), b"\x00\xff\x80\x0a\x0d")
  let child = root.get_struct(2)
  assert_eq(child.get_uint64(0), 42UL)
  assert_eq(child.get_text(0), "parent")
  let children = root.get_list(3)
  assert_eq(children.length(), 2)
  assert_eq(children.get_struct(0).get_uint64(0), 1UL)
  assert_eq(children.get_struct(0).get_text(0), "first")
  assert_eq(children.get_struct(1).get_uint64(0), 18446744073709551615UL)
  assert_eq(children.get_struct(1).get_text(0), "last")
  let bits = root.get_list(4)
  assert_eq(bits.length(), 9)
  assert_eq([ for i in 0..<bits.length() => bits.get_bool(i) ], [
    true, false, true, true, false, false, true, false, true,
  ])
  let octets = root.get_list(5)
  assert_eq([ for i in 0..<octets.length() => octets.get_uint8(i) ], [
    0, 128, 255,
  ])
  let shorts = root.get_list(6)
  assert_eq([ for i in 0..<shorts.length() => shorts.get_int16(i) ], [
    -32768, 0, 32767,
  ])
  let ints = root.get_list(7)
  assert_eq([ for i in 0..<ints.length() => ints.get_int32(i) ], [
    -2147483648, 0, 2147483647,
  ])
  let longs = root.get_list(8)
  assert_eq([ for i in 0..<longs.length() => longs.get_int64(i) ], [
    -9223372036854775808L, 9007199254740993L,
  ])
  let floats = root.get_list(9)
  assert_eq([ for i in 0..<floats.length() => floats.get_float32(i) ], [
    0.0, -1.5, 3.25,
  ])
  let doubles = root.get_list(10)
  assert_eq([ for i in 0..<doubles.length() => doubles.get_float64(i) ], [
    -0.25, 123456789.125,
  ])
  let texts = root.get_list(11)
  assert_eq([ for i in 0..<texts.length() => texts.get_text(i) ], [
    "", "alpha", "中文",
  ])
  let blobs = root.get_list(12)
  assert_eq(blobs.get_data(0), b"")
  assert_eq(blobs.get_data(1), b"\x00\xff")
  let nested = root.get_list(13)
  assert_eq(nested.get_list(0).get_uint16(1), 2)
  assert_eq(nested.get_list(1).length(), 0)
  assert_eq(nested.get_list(2).get_uint16(0), 65535)
  let colors = root.get_list(14)
  assert_eq([ for i in 0..<colors.length() => colors.get_uint16(i) ], [0, 2, 1])
  assert_eq(root.get_uint16(38), 1)
  assert_eq(root.get_text(15), "active union")
  assert_eq(root.get_uint32(52), 7)
  assert_eq(root.get_text(16), "Ridge-Lab")
}

///|
test "reader decodes independently encoded official capnp fixture" {
  reader_check_oracle(@fs.read_file_to_bytes("fixtures/conformance.bin"))
}

///|
test "reader decodes official segmented fixture with far pointers" {
  let bytes = @fs.read_file_to_bytes("fixtures/conformance.segmented.bin")
  assert_true(@capnp.read_message(bytes).segment_count() > 1)
  reader_check_oracle(bytes)
}

///|
test "reader decodes packed official fixture after unpacking" {
  reader_check_oracle(
    @capnp.unpack(@fs.read_file_to_bytes("fixtures/conformance.packed.bin")),
  )
}

///|
test "reader applies scalar and pointer defaults to empty official fixture" {
  let root = @capnp.read_message(
    @fs.read_file_to_bytes("fixtures/defaults.bin"),
  ).root()
  assert_eq(root.get_bool(0, default=true), true)
  assert_eq(root.get_int8(1, default=-12), -12)
  assert_eq(root.get_int16(2, default=-300), -300)
  assert_eq(root.get_int32(4, default=-70000), -70000)
  assert_eq(root.get_int64(8, default=-9007199254740993L), -9007199254740993L)
  assert_eq(root.get_uint8(16, default=250), 250)
  assert_eq(root.get_uint16(18, default=60000), 60000)
  assert_eq(root.get_uint32(20, default=4000000000), 4000000000)
  assert_eq(
    root.get_uint64(24, default=18446744073709551615UL),
    18446744073709551615UL,
  )
  assert_eq(root.get_float32(32, default=1.5), 1.5)
  assert_eq(root.get_float64(40, default=-0.25), -0.25)
  assert_eq(root.get_text(0, default="default text"), "default text")
  assert_eq(root.get_data(1, default=b"\x01\x00\xff"), b"\x01\x00\xff")
  assert_eq(root.get_pointer(999).is_null(), true)
  assert_eq(root.get_uint64(10000, default=9UL), 9UL)
  assert_eq(root.get_struct(2).get_uint64(0), 0UL)
  assert_eq(root.get_list(3).length(), 0)
}

///|
test "reader primitive and pointer lists retain data when viewed as evolved struct lists" {
  let root = @capnp.read_message(
    @fs.read_file_to_bytes("fixtures/conformance.bin"),
  ).root()
  let words = root.get_list(7)
  assert_eq(words.get_struct(0).get_int32(0), -2147483648)
  assert_eq(words.get_struct(2).get_int32(0), 2147483647)
  assert_eq(words.get_struct(2).get_text(0), "")
  let texts = root.get_list(11)
  assert_eq(texts.get_struct(2).get_text(0), "中文")
  assert_eq(texts.get_struct(2).get_uint64(0), 0UL)
  let children = root.get_list(3)
  assert_eq(children.get_uint64(1), 18446744073709551615UL)
  assert_eq(children.get_text(1), "last")
}
