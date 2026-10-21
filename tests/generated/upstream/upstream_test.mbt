///|
test "unchanged upstream generic defaults aliases inherited brands and recursive swaps" {
  let message = @capnp.Builder::new()
  let root = @upstream.TestUseGenericsBuilder::init_root(message)
  root.init_basic().init_foo().set_int16_field(777)
  root.init_inner2().set_baz("explicit bound text")
  root.init_bind_enum_list().init_foo(2).set(1, @upstream.TestEnum::Garply)
  let read = @upstream.TestUseGenericsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(read.get_basic().get_foo().get_int16_field(), 777)
  assert_eq(read.get_inner2().get_baz(), "explicit bound text")
  assert_eq(read.get_bind_enum_list().get_foo().get(1).to_raw(), 7U)
  assert_eq(read.get_default().get_foo().get_int16_field(), 123)
  assert_eq(read.get_default().get_rev().get_foo(), "text")
  assert_eq(
    read.get_default().get_rev().get_rev().get_foo().get_int16_field(),
    321,
  )
  assert_eq(read.get_default_inner().get_bar(), "text")
  assert_eq(
    read.get_default_wrapper2().get_value().get_value().get_foo(),
    "text",
  )
  assert_eq(read.get_alias_inner2_bind().get_baz().get(1), 34U)
  assert_eq(
    read.get_alias_inner2_bind().get_inner_bound().get_foo().get_int16_field(),
    123,
  )
  assert_eq(read.get_use_aliases().get_rev_foo().get(2), 56U)
  assert_eq(
    @upstream.const_generic_constant()
    .get_rev()
    .get_rev()
    .get_foo()
    .get_int16_field(),
    321,
  )
}

///|
test "unchanged upstream constants cover every scalar and list element kind" {
  @upstream.const_test_constants_void_const()
  assert_true(@upstream.const_test_constants_bool_const())
  assert_eq(@upstream.const_test_constants_int8_const(), -123)
  assert_eq(@upstream.const_test_constants_int16_const(), -12345)
  assert_eq(@upstream.const_test_constants_int32_const(), -12345678)
  assert_eq(@upstream.const_test_constants_int64_const(), -123456789012345L)
  assert_eq(@upstream.const_test_constants_uint8_const(), 234)
  assert_eq(@upstream.const_test_constants_uint16_const(), 45678U)
  assert_eq(@upstream.const_test_constants_uint32_const(), 3456789012U)
  assert_eq(
    @upstream.const_test_constants_uint64_const(),
    12345678901234567890UL,
  )
  assert_eq(@upstream.const_test_constants_float32_const(), 1234.5F)
  assert_eq(@upstream.const_test_constants_float64_const(), -123.0e45)
  assert_eq(@upstream.const_test_constants_text_const(), "foo")
  assert_eq(@upstream.const_test_constants_data_const(), b"bar")
  assert_eq(@upstream.const_test_constants_enum_const().to_raw(), 5U)
  assert_eq(
    @upstream.const_test_constants_struct_const()
    .get_struct_field()
    .get_struct_field()
    .get_text_field(),
    "really nested",
  )
  assert_eq(@upstream.const_test_constants_void_list_const().length(), 6)
  @upstream.const_test_constants_void_list_const().get(5)
  assert_true(@upstream.const_test_constants_bool_list_const().get(3))
  assert_eq(@upstream.const_test_constants_int8_list_const().get(1), -111)
  assert_eq(@upstream.const_test_constants_int16_list_const().get(1), -11111)
  assert_eq(
    @upstream.const_test_constants_int32_list_const().get(1),
    -111111111,
  )
  assert_eq(
    @upstream.const_test_constants_int64_list_const().get(1),
    -1111111111111111111L,
  )
  assert_eq(@upstream.const_test_constants_uint8_list_const().get(1), 222)
  assert_eq(@upstream.const_test_constants_uint16_list_const().get(1), 44444U)
  assert_eq(
    @upstream.const_test_constants_uint32_list_const().get(0),
    3333333333U,
  )
  assert_eq(
    @upstream.const_test_constants_uint64_list_const().get(0),
    11111111111111111111UL,
  )
  assert_eq(@upstream.const_test_constants_float32_list_const().get(0), 5555.5F)
  assert_true(
    @upstream.const_test_constants_float32_list_const().get(3).is_nan(),
  )
  assert_eq(@upstream.const_test_constants_float64_list_const().get(0), 7777.75)
  assert_true(
    @upstream.const_test_constants_float64_list_const().get(1).is_pos_inf(),
  )
  assert_eq(@upstream.const_test_constants_text_list_const().get(2), "thud")
  assert_eq(@upstream.const_test_constants_data_list_const().get(2), b"rfc3092")
  assert_eq(
    @upstream.const_test_constants_struct_list_const().get(2).get_text_field(),
    "structlist 3",
  )
  assert_eq(
    @upstream.const_test_constants_enum_list_const().get(1).to_raw(),
    7U,
  )
  assert_eq(@upstream.const_non_ascii_text(), "♫ é ✓")
}

///|
test "unchanged upstream AnyPointer constants deep copy without schema rewriting" {
  let source = @upstream.const_any_pointer_constants()
  let message = @capnp.Builder::new()
  let target = @upstream.TestAnyPointerConstantsBuilder::init_root(message)
  target.set_any_kind_as_struct(source.get_any_kind_as_struct())
  target.set_any_struct_as_struct(source.get_any_struct_as_struct())
  target.set_any_kind_as_list(source.get_any_kind_as_list())
  target.set_any_list_as_list(source.get_any_list_as_list())
  let result = @upstream.TestAnyPointerConstantsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  let typed : @upstream.TestAllTypesReader = {
    inner: result.get_any_kind_as_struct().as_struct(),
  }
  assert_eq(typed.get_text_field(), "baz")
  let constrained : @upstream.TestAllTypesReader = {
    inner: result.get_any_struct_as_struct(),
  }
  assert_eq(constrained.get_struct_field().get_text_field(), "nested")
  assert_eq(result.get_any_kind_as_list().as_list().get_int32(1), -111111111)
  assert_eq(result.get_any_list_as_list().get_int32(0), 111111111)
}
