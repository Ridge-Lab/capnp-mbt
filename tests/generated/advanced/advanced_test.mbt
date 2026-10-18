///|
test "compiled struct and recursive list defaults retain official schema values" {
  let message = @capnp.Builder::new()
  ignore(message.init_root(0, 0))
  let root = @advanced.DefaultsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(root.get_item().get_number(), 12)
  assert_eq(root.get_item().get_name(), "explicit")
  assert_eq(root.get_items().get(1).get_number(), 2)
  assert_eq(root.get_items().get(0).get_name(), "child default")
  assert_eq(root.get_numbers().get(1), 65535U)
  assert_eq(root.get_nested().get(0).get(0), "hello")
  assert_eq(root.get_nested().get(1).length(), 0)
  assert_eq(root.get_nested().get(2).get(1), "b")
  assert_true(root.get_nan().is_nan())
  assert_true(root.get_infinity().is_pos_inf())
  assert_eq(
    root.get_negative_zero().reinterpret_as_uint64(),
    0x8000000000000000UL,
  )
}

///|
test "initialized empty lists override nonempty compiled defaults" {
  let message = @capnp.Builder::new()
  let root = @advanced.DefaultsBuilder::init_root(message)
  ignore(root.init_items(0))
  ignore(root.init_numbers(0))
  let item = root.init_item()
  item.set_name("")
  let read = @advanced.DefaultsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(read.get_items().length(), 0)
  assert_eq(read.get_numbers().length(), 0)
  assert_eq(read.get_item().get_name(), "")
  assert_eq(read.get_item().get_number(), 7)
}

///|
test "union groups reset overlapping storage without touching adjacent fields" {
  let message = @capnp.Builder::new()
  let root = @advanced.SwitchingBuilder::init_root(message)
  root.set_owner("keep")
  root.set_code(18446744073709551615UL)
  let configuration = root.init_configuration()
  configuration.set_enabled(true)
  configuration.set_label("group text")
  let before = @advanced.SwitchingReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_true(before.get_preserved())
  assert_true(before.is_configuration())
  assert_true(before.get_configuration().get_enabled())
  assert_eq(before.get_configuration().get_label(), "group text")
  root.set_none()
  let after = @advanced.SwitchingReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_true(after.get_preserved())
  assert_eq(after.get_owner(), "keep")
  assert_true(after.is_none())
  let reset = root.init_configuration()
  ignore(reset)
  let reset_read = @advanced.SwitchingReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_false(reset_read.get_configuration().get_enabled())
  assert_eq(reset_read.get_configuration().get_label(), "")
}

///|
test "nested declarations and list of list of structs have typed accessors" {
  let message = @capnp.Builder::new()
  let root = @advanced.OuterBuilder::init_root(message)
  root.init_inner().set_value(123U)
  root.init_matrix(1).init(0, 2).get(1).set_value(999U)
  let read = @advanced.OuterReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(read.get_inner().get_value(), 123U)
  assert_eq(read.get_matrix().get(0).get(1).get_value(), 999U)
}

///|
test "void lists and remaining integer widths support typed access" {
  let message = @capnp.Builder::new()
  let root = @advanced.OtherListsBuilder::init_root(message)
  root.set_nothing()
  let empty = root.init_empties(100)
  empty.set(99)
  root.init_tiny(1).set(0, -128)
  root.init_words(1).set(0, 4294967295U)
  root.init_big(1).set(0, 18446744073709551615UL)
  root.init_root_field(1).set(0, 65535U)
  let read = @advanced.OtherListsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  read.get_nothing()
  assert_eq(read.get_empties().length(), 100)
  read.get_empties().get(99)
  assert_eq(read.get_tiny().get(0), -128)
  assert_eq(read.get_words().get(0), 4294967295U)
  assert_eq(read.get_big().get(0), 18446744073709551615UL)
  assert_eq(read.get_root_field().get(0), 65535U)
  try read.get_empties().get(100) catch {
    @capnp.CapnpError::Bounds(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("void list bounds were not checked")
  }
}
