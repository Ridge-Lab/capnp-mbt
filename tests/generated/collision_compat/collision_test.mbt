///|
test "legal schema names survive wrapper generic constant and field collisions" {
  let message = @capnp.Builder::new()
  let root = @collision_compat.UsesBuilder::init_root(message)
  root.init_foo().set_value(12U)
  root.set_status(@collision_compat.FooReader::Second)
  root.init_list().init_children(1).set(0, 34U)
  root.init_list_named().set_value("declared list-like name")
  root.init_bound().set_value("generic specialization")
  root.init_bound_named().set_value(56U)
  root.init_constant_named().set_value("declared constant-list name")
  root.init_nested().set_value(78U)
  root.init_nested_named().set_value("flat declaration")
  root.init_root_field(1).set(0, 90U)
  root.init_root_field_f10(1).set(0, 100U)
  root.init_root_field_f10_f11(1).set(0, 110U)
  let read = @collision_compat.UsesReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(read.get_foo().get_value(), 12U)
  assert_eq(read.get_status().to_raw(), 1U)
  assert_eq(read.get_list().get_children().get(0), 34U)
  assert_eq(read.get_list_named().get_value(), "declared list-like name")
  assert_eq(read.get_bound().get_value(), "generic specialization")
  assert_eq(read.get_bound_named().get_value(), 56U)
  assert_eq(
    read.get_constant_named().get_value(),
    "declared constant-list name",
  )
  assert_eq(read.get_nested().get_value(), 78U)
  assert_eq(read.get_nested_named().get_value(), "flat declaration")
  assert_eq(read.get_root_field().get(0), 90U)
  assert_eq(read.get_root_field_f10().get(0), 100U)
  assert_eq(read.get_root_field_f10_f11().get(0), 110U)
  assert_eq(@collision_compat.const_values().get(1), 4U)
}
