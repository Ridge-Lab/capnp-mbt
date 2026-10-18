///|
test "generated readers decode official compiler scalar and container oracle" {
  let bytes = @fs.read_file_to_bytes("fixtures/conformance.bin")
  let root = @generated.FixtureReader::from_message(@capnp.read_message(bytes))
  assert_false(root.get_boolean())
  assert_eq(root.get_i8(), -128)
  assert_eq(root.get_i16(), -32768)
  assert_eq(root.get_i32(), -2147483648)
  assert_eq(root.get_i64(), -9223372036854775808L)
  assert_eq(root.get_u8(), 255)
  assert_eq(root.get_u16(), 65535U)
  assert_eq(root.get_u32(), 4294967295U)
  assert_eq(root.get_u64(), 9007199254740993UL)
  assert_eq(root.get_f32(), 3.25F)
  assert_eq(root.get_f64(), -12345.125)
  assert_eq(root.get_color().to_raw(), 1U)
  assert_eq(root.get_text(), "MoonBit 数据交换")
  assert_eq(root.get_data(), b"\x00\xff\x80\x0a\x0d")
  assert_eq(root.get_child().get_id(), 42UL)
  assert_eq(root.get_children().get(1).get_id(), 18446744073709551615UL)
  assert_true(root.get_bools().get(8))
  assert_eq(root.get_bytes().get(2), 255)
  assert_eq(root.get_shorts().get(0), -32768)
  assert_eq(root.get_ints().get(0), -2147483648)
  assert_eq(root.get_longs().get(1), 9007199254740993L)
  assert_eq(root.get_floats().get(2), 3.25F)
  assert_eq(root.get_doubles().get(1), 123456789.125)
  assert_eq(root.get_texts().get(2), "中文")
  assert_eq(root.get_blobs().get(1), b"\x00\xff")
  assert_eq(root.get_nested().get(1).length(), 0)
  assert_eq(root.get_nested().get(2).get(0), 65535U)
  assert_eq(root.get_colors().get(1).to_raw(), 2U)
  assert_true(root.is_message())
  assert_eq(root.get_message(), "active union")
  assert_eq(root.get_metadata().get_revision(), 7U)
  assert_eq(root.get_metadata().get_author(), "Ridge-Lab")
  try root.get_code() catch {
    @capnp.CapnpError::TypeMismatch(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("inactive union field was readable")
  }
}

///|
test "all scalar defaults are restored from an empty struct" {
  let message = @capnp.Builder::new()
  ignore(message.init_root(0, 0))
  let root = @generated.FixtureReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_true(root.get_boolean())
  assert_eq(root.get_i8(), -12)
  assert_eq(root.get_i16(), -300)
  assert_eq(root.get_i32(), -70000)
  assert_eq(root.get_i64(), -9007199254740993L)
  assert_eq(root.get_u8(), 250)
  assert_eq(root.get_u16(), 60000U)
  assert_eq(root.get_u32(), 4000000000U)
  assert_eq(root.get_u64(), 18446744073709551615UL)
  assert_eq(root.get_f32(), 1.5F)
  assert_eq(root.get_f64(), -0.25)
  assert_eq(root.get_color().to_raw(), 2U)
  assert_eq(root.get_text(), "default text")
  assert_eq(root.get_data(), b"\x01\x00\xff")
  assert_eq(root.get_child().get_name(), "")
  assert_eq(root.get_children().length(), 0)
  assert_true(root.is_none())
}

///|
test "generated builders populate nested lists and switch union members" {
  let message = @capnp.Builder::new()
  let root = @generated.FixtureBuilder::init_root(message)
  root.set_boolean(false)
  root.set_i64(-9223372036854775808L)
  root.set_u64(18446744073709551615UL)
  root.set_text("")
  root.set_data(b"")
  root.set_color(@generated.Color::Unknown(123U))
  let children = root.init_children(2)
  children.get(0).set_id(100UL)
  children.get(1).set_name("second")
  let nested = root.init_nested(2)
  nested.init(0, 2).set(1, 60000U)
  ignore(nested.init(1, 0))
  root.init_metadata().set_author("preserved")
  root.set_message("discarded pointer")
  root.set_code(17U)
  let value = @generated.FixtureReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_false(value.get_boolean())
  assert_eq(value.get_i64(), -9223372036854775808L)
  assert_eq(value.get_u64(), 18446744073709551615UL)
  assert_eq(value.get_text(), "")
  assert_eq(value.get_data(), b"")
  assert_eq(value.get_color().to_raw(), 123U)
  assert_eq(value.get_children().get(0).get_id(), 100UL)
  assert_eq(value.get_children().get(1).get_name(), "second")
  assert_eq(value.get_nested().get(0).get(1), 60000U)
  assert_eq(value.get_nested().get(1).length(), 0)
  assert_eq(value.get_metadata().get_author(), "preserved")
  assert_true(value.is_code())
  assert_eq(value.get_code(), 17U)
  root.set_none()
  let cleared = @generated.FixtureReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_true(cleared.is_none())
  assert_eq(cleared.get_metadata().get_author(), "preserved")
}

///|
test "group get preserves fields while init resets only the group" {
  let message = @capnp.Builder::new()
  let root = @generated.FixtureBuilder::init_root(message)
  root.set_u64(123UL)
  root.set_message("outside group")
  let group = root.init_metadata()
  group.set_revision(42U)
  group.set_author("old")
  root.get_metadata().set_revision(43U)
  let before = @generated.FixtureReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(before.get_metadata().get_revision(), 43U)
  assert_eq(before.get_metadata().get_author(), "old")
  ignore(root.init_metadata())
  let after = @generated.FixtureReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(after.get_metadata().get_revision(), 0U)
  assert_eq(after.get_metadata().get_author(), "")
  assert_eq(after.get_u64(), 123UL)
  assert_eq(after.get_message(), "outside group")
}
