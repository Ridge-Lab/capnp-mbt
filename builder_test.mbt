///|
test "builder emits independent standard stream bytes and snapshots" {
  let message = @capnp.Builder::new()
  let root = message.init_root(1, 1)
  root.set_uint64(0, 0x0102030405060708UL)
  root.set_text(0, "Hi")
  let bytes = message.finish()
  assert_eq(
    bytes, b"\x00\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\x01\x00\x01\x00\x08\x07\x06\x05\x04\x03\x02\x01\x01\x00\x00\x00\x1a\x00\x00\x00Hi\x00\x00\x00\x00\x00\x00",
  )
  root.set_uint64(0, 9)
  assert_eq(bytes[16], b'\x08')
  assert_eq(message.finish()[16], b'\x09')
  assert_eq(message.allocated_words(), 4)
}

///|
test "builder distinguishes empty struct and null pointers" {
  let message = @capnp.Builder::new()
  assert_eq(
    message.finish(),
    b"\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  ignore(message.init_root(0, 0))
  assert_eq(
    message.finish(),
    b"\x00\x00\x00\x00\x01\x00\x00\x00\xfc\xff\xff\xff\x00\x00\x00\x00",
  )
  let decoded = @capnp.read_message(message.finish()).root()
  assert_eq(decoded.data_size_bytes(), 0)
  assert_eq(decoded.pointer_count(), 0)
}

///|
test "builder zero length lists and exact allocation ceilings" {
  let minimal = @capnp.Builder::new(max_words=1)
  ignore(minimal.init_root(0, 0))
  assert_eq(minimal.allocated_words(), 1)
  let message = @capnp.Builder::new(max_words=7)
  let root = message.init_root(0, 4)
  root.set_data(0, b"")
  root.set_text(1, "")
  ignore(root.init_list(2, 5, 0))
  ignore(root.init_struct_list(3, 0, 2, 1))
  assert_eq(message.allocated_words(), 7)
  let read = @capnp.read_message(message.finish()).root()
  assert_eq(read.get_data(0, default=b"fallback"), b"")
  assert_eq(read.get_text(1, default="fallback"), "")
  assert_eq(read.get_list(2).length(), 0)
  assert_eq(read.get_list(3).length(), 0)
  let before = message.finish()
  builder_expect_error(() => root.set_text(0, "no room"))
  builder_expect_error(() => ignore(root.init_struct_list(0, 0, 0, 0)))
  assert_eq(message.finish(), before)
}

///|
test "builder scalar boundaries defaults and float sign bits" {
  let message = @capnp.Builder::new()
  let root = message.init_root(6, 0)
  root.set_bool(0, false, default=true)
  root.set_bool(1, true)
  root.set_uint8(1, 7, default=255)
  root.set_uint16(2, 65535, default=60000)
  root.set_uint32(4, 4294967295, default=4000000000)
  root.set_uint64(8, 0x8000000000000001UL, default=18446744073709551615)
  root.set_int8(16, -128, default=-12)
  root.set_int16(18, -32768, default=-300)
  root.set_int32(20, -2147483648, default=-70000)
  root.set_int64(24, -9223372036854775808L, default=-9007199254740993L)
  root.set_float32(32, -0.0, default=1.5)
  root.set_float64(40, -0.0, default=-0.25)
  let decoded = @capnp.read_message(message.finish()).root()
  assert_false(decoded.get_bool(0, default=true))
  assert_true(decoded.get_bool(1))
  assert_eq(decoded.get_uint8(1, default=255), b'\x07')
  assert_eq(decoded.get_uint16(2, default=60000), 65535U)
  assert_eq(decoded.get_uint32(4, default=4000000000), 4294967295U)
  assert_eq(
    decoded.get_uint64(8, default=18446744073709551615),
    0x8000000000000001UL,
  )
  assert_eq(decoded.get_int8(16, default=-12), -128)
  assert_eq(decoded.get_int16(18, default=-300), -32768)
  assert_eq(decoded.get_int32(20, default=-70000), -2147483648)
  assert_eq(
    decoded.get_int64(24, default=-9007199254740993L),
    -9223372036854775808L,
  )
  assert_eq(
    decoded.get_float32(32, default=1.5).reinterpret_as_uint(),
    0x80000000U,
  )
  assert_eq(
    decoded.get_float64(40, default=-0.25).reinterpret_as_uint64(),
    0x8000000000000000UL,
  )
  root.set_bool(0, true, default=true)
  root.set_bool(1, false)
  root.set_uint8(1, 255, default=255)
  root.set_uint16(2, 60000, default=60000)
  root.set_uint32(4, 4000000000, default=4000000000)
  root.set_uint64(8, 18446744073709551615, default=18446744073709551615)
  root.set_int8(16, -12, default=-12)
  root.set_int16(18, -300, default=-300)
  root.set_int32(20, -70000, default=-70000)
  root.set_int64(24, -9007199254740993L, default=-9007199254740993L)
  root.set_float32(32, 1.5, default=1.5)
  root.set_float64(40, -0.25, default=-0.25)
  let bytes = message.finish()
  for i in 16..<bytes.length() {
    assert_eq(bytes[i], b'\x00')
  }
}

///|
test "builder nested structs text data and shared arena handles" {
  let message = @capnp.Builder::new()
  let root = message.init_root(0, 4)
  let child = root.init_struct(0, 1, 1)
  root.set_text(1, "Moon 🌙 中文")
  root.set_data(2, b"\x00\x80\xff")
  root.set_text(3, "")
  child.set_uint64(0, 9007199254740993UL)
  child.set_text(0, "after arena growth")
  let read = @capnp.read_message(message.finish()).root()
  assert_eq(read.get_text(1), "Moon 🌙 中文")
  assert_eq(read.get_data(2), b"\x00\x80\xff")
  assert_eq(read.get_text(3), "")
  assert_eq(read.get_struct(0).get_uint64(0), 9007199254740993UL)
  assert_eq(read.get_struct(0).get_text(0), "after arena growth")
  root.clear_pointer(1)
  child.clear_data(0, 8)
  let cleared = @capnp.read_message(message.finish()).root()
  assert_eq(cleared.get_text(1, default="fallback"), "fallback")
  assert_eq(cleared.get_struct(0).get_uint64(0), 0UL)
}

///|
test "builder primitive lists cover all element sizes and numeric types" {
  let message = @capnp.Builder::new()
  let root = message.init_root(0, 11)
  let voids = root.init_list(0, 0, 3)
  voids.set_void(2)
  let bools = root.init_list(1, 1, 70)
  bools.set_bool(0, true)
  bools.set_bool(63, true)
  bools.set_bool(69, true)
  bools.set_bool(63, false)
  let u8 = root.init_list(2, 2, 2)
  u8.set_uint8(0, 255)
  u8.set_int8(1, -128)
  let u16 = root.init_list(3, 3, 2)
  u16.set_uint16(0, 65535)
  u16.set_int16(1, -32768)
  let u32 = root.init_list(4, 4, 2)
  u32.set_uint32(0, 4294967295)
  u32.set_int32(1, -2147483648)
  let u64 = root.init_list(5, 5, 2)
  u64.set_uint64(0, 18446744073709551615)
  u64.set_int64(1, -9223372036854775808L)
  root.init_list(6, 4, 1).set_float32(0, -1.25)
  root.init_list(7, 5, 1).set_float64(0, 3.141592653589793)
  let texts = root.init_list(8, 6, 2)
  texts.set_text(0, "first")
  texts.set_text(1, "二")
  let data = root.init_list(9, 6, 1)
  data.set_data(0, b"\x00\xff")
  let nested = root.init_list(10, 6, 1)
  nested.init_list(0, 3, 1).set_uint16(0, 12345)
  let read = @capnp.read_message(message.finish()).root()
  assert_eq(read.get_list(0).length(), 3)
  assert_true(read.get_list(1).get_bool(0))
  assert_false(read.get_list(1).get_bool(63))
  assert_true(read.get_list(1).get_bool(69))
  assert_eq(read.get_list(2).get_uint8(0), b'\xff')
  assert_eq(read.get_list(2).get_int8(1), -128)
  assert_eq(read.get_list(3).get_uint16(0), 65535U)
  assert_eq(read.get_list(3).get_int16(1), -32768)
  assert_eq(read.get_list(4).get_uint32(0), 4294967295U)
  assert_eq(read.get_list(4).get_int32(1), -2147483648)
  assert_eq(read.get_list(5).get_uint64(0), 18446744073709551615UL)
  assert_eq(read.get_list(5).get_int64(1), -9223372036854775808L)
  assert_eq(read.get_list(6).get_float32(0), -1.25F)
  assert_eq(read.get_list(7).get_float64(0), 3.141592653589793)
  assert_eq(read.get_list(8).get_text(0), "first")
  assert_eq(read.get_list(8).get_text(1), "二")
  assert_eq(read.get_list(9).get_data(0), b"\x00\xff")
  assert_eq(read.get_list(10).get_list(0).get_uint16(0), 12345U)
}

///|
test "builder inline composite lists and nested pointer lists" {
  let message = @capnp.Builder::new()
  let root = message.init_root(0, 3)
  let children = root.init_struct_list(0, 2, 1, 1)
  assert_eq(children.length(), 2)
  assert_eq(children.element_size(), 7)
  let first = children.struct_at(0)
  children.struct_at(1).set_uint64(0, 42)
  children.struct_at(1).set_text(0, "second")
  first.set_uint64(0, 24)
  first.set_text(0, "first")
  let nested = root.init_list(1, 6, 2)
  nested.init_struct_list(0, 1, 0, 1).struct_at(0).set_text(0, "inner")
  nested.init_struct(1, 1, 0).set_uint16(0, 7)
  ignore(root.init_struct_list(2, 3, 0, 0))
  let read = @capnp.read_message(message.finish()).root()
  let list = read.get_list(0)
  assert_eq(list.element_size(), 7)
  assert_eq(list.length(), 2)
  assert_eq(list.get_struct(0).get_uint64(0), 24UL)
  assert_eq(list.get_struct(0).get_text(0), "first")
  assert_eq(list.get_struct(1).get_uint64(0), 42UL)
  assert_eq(list.get_struct(1).get_text(0), "second")
  assert_eq(read.get_list(1).get_list(0).get_struct(0).get_text(0), "inner")
  assert_eq(read.get_list(1).get_pointer(1).as_struct().get_uint16(0), 7U)
  assert_eq(read.get_list(2).length(), 3)
  assert_eq(read.get_list(2).get_struct(2).data_size_bytes(), 0)
  nested.clear_pointer(1)
  assert_eq(
    @capnp.read_message(message.finish())
    .root()
    .get_list(1)
    .get_pointer(1)
    .as_struct()
    .data_size_bytes(),
    0,
  )
}

///|
fn builder_expect_error(
  action : () -> Unit raise @capnp.CapnpError,
) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("expected a typed builder error")
  }
}

///|
test "builder refuses invalid geometry slots values and allocation without mutation" {
  builder_expect_error(() => ignore(@capnp.Builder::new(max_words=0)))
  builder_expect_error(() => ignore(@capnp.Builder::new(max_words=2147483647)))
  let message = @capnp.Builder::new(max_words=8)
  let root = message.init_root(1, 2)
  root.set_uint64(0, 123)
  let before = message.finish()
  builder_expect_error(() => ignore(root.init_struct(0, -1, 1)))
  builder_expect_error(() => ignore(root.init_struct(0, 65536, 0)))
  builder_expect_error(() => ignore(root.init_list(0, 5, 2147483647)))
  builder_expect_error(() => ignore(root.init_list(0, 7, 1)))
  builder_expect_error(() => {
    ignore(root.init_struct_list(0, 536870911, 65535, 65535))
  })
  builder_expect_error(() => ignore(root.init_list(-1, 2, 1)))
  builder_expect_error(() => root.set_text(2, "bad"))
  builder_expect_error(() => root.set_uint64(1, 1))
  builder_expect_error(() => root.set_bool(-1, true))
  builder_expect_error(() => root.set_bool(64, true))
  builder_expect_error(() => root.set_uint16(0, 65536))
  builder_expect_error(() => root.set_uint16(0, 0, default=65536))
  builder_expect_error(() => root.set_int8(0, 128))
  builder_expect_error(() => root.set_int16(0, -32769))
  builder_expect_error(() => root.clear_data(0, 2147483647))
  assert_eq(message.finish(), before)
  let list = root.init_list(0, 2, 1)
  builder_expect_error(() => list.set_uint8(1, 0))
  builder_expect_error(() => list.set_uint16(0, 0))
  builder_expect_error(() => ignore(list.struct_at(0)))
  builder_expect_error(() => list.set_text(0, "bad"))
  builder_expect_error(() => list.set_int8(0, -129))
  builder_expect_error(() => list.set_int16(0, 32768))
}
