///|
test "generic bindings preserve text struct list nested ancestor and group types" {
  let message = @capnp.Builder::new()
  let root = @brands.UsesBuilder::init_root(message)
  let text = root.init_text_box()
  text.set_value("typed text")
  text.init_values(1).get(0).set_value("inline list")
  text.init_details().set_extra("group binding")
  text.init_next().set_value("recursive")
  let sample = root.init_sample_box().init_value()
  sample.set_id(12345678901234567890UL)
  sample.set_name("typed struct")
  let numbers = root.init_list_box().init_value(2)
  numbers.set(0, 1U)
  numbers.set(1, 4294967295U)
  let nested = root.init_nested()
  nested.set_left("ancestor binding")
  nested.set_right(b"\x00\xff")
  nested.init_same().set_left("inherited recursive binding")
  root.init_unbound().init_value().set_text("dynamic")
  let deep = root.init_deep()
  deep.set_first("first ancestor")
  deep.set_second(b"second ancestor")
  deep.init_third().set_name("third parameter")
  deep.init_fourth(1).set(0, 987U)
  let read = @brands.UsesReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(read.get_text_box().get_value(), "typed text")
  assert_eq(read.get_text_box().get_values().inner.element_size(), 7)
  assert_eq(read.get_text_box().get_values().get(0).get_value(), "inline list")
  assert_eq(read.get_text_box().get_details().get_extra(), "group binding")
  assert_eq(read.get_text_box().get_next().get_value(), "recursive")
  assert_eq(read.get_sample_box().get_value().get_id(), 12345678901234567890UL)
  assert_eq(read.get_list_box().get_value().get(1), 4294967295U)
  assert_eq(read.get_nested().get_left(), "ancestor binding")
  assert_eq(read.get_nested().get_right(), b"\x00\xff")
  assert_eq(
    read.get_nested().get_same().get_left(),
    "inherited recursive binding",
  )
  assert_eq(read.get_unbound().get_value().as_text(), "dynamic")
  assert_eq(read.get_deep().get_first(), "first ancestor")
  assert_eq(read.get_deep().get_second(), b"second ancestor")
  assert_eq(read.get_deep().get_third().get_name(), "third parameter")
  assert_eq(read.get_deep().get_fourth().get(0), 987U)
}

///|
test "scalar pointer and bound generic constants retain official values" {
  assert_true(@brands.const_flag())
  assert_eq(@brands.const_signed(), -9223372036854775807L - 1L)
  assert_eq(@brands.const_unsigned(), 18446744073709551615UL)
  assert_eq(@brands.const_text(), "literal")
  assert_eq(@brands.const_data(), b"\x00\xff\x01")
  assert_eq(@brands.const_choice().to_raw(), 1U)
  assert_eq(@brands.const_sample().get_id(), 123UL)
  assert_eq(@brands.const_list().get(1), 4294967295U)
  assert_eq(@brands.const_boxed().get_value().get_name(), "bound constant")
  assert_eq(@brands.const_nested_list().get(1).length(), 0)
  assert_eq(@brands.const_nested_list().get(2).get(1), "three")
  assert_eq(@brands.const_generic_boxes().get(1).get_value(), "second")
  assert_eq(@brands.const_opaque().as_struct().get_uint64(0), 123UL)
  assert_eq(@brands.const_opaque_struct().get_text(0), "constant")
  assert_eq(@brands.const_opaque_list().get_uint32(1), 4294967295U)
  assert_eq(@brands.const_root(), "root constant")
  assert_eq(@brands.const_root_field(), "separate constant")
}

///|
test "AnyList composite initializer avoids collisions with schema field methods" {
  let message = @capnp.Builder::new()
  let root = @brands.MethodNamesBuilder::init_root(message)
  root.init_foo_structs().set_name("ordinary field")
  root.init_foo_structs_inline(1, 1, 1).struct_at(0).set_text(0, "list item")
  let read = @brands.MethodNamesReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(read.get_foo_structs().get_name(), "ordinary field")
  assert_eq(read.get_foo().get_struct(0).get_text(0), "list item")
}

///|
test "AnyPointer constraints typed copy and capability indices" {
  let source = @capnp.Builder::new()
  let source_root = @brands.UsesBuilder::init_root(source)
  source_root.init_pointer().set_text("unknown payload")
  source_root.init_structure(1, 1).set_uint64(0, 42UL)
  source_root.init_list(4, 2).set_uint32(1, 99U)
  let read = @brands.UsesReader::from_message(
    @capnp.read_message(source.finish()),
  )
  let target = @capnp.Builder::new()
  let root = @brands.UsesBuilder::init_root(target)
  root.set_pointer(read.get_pointer())
  root.set_structure(read.get_structure())
  root.set_list(read.get_list())
  root.set_sample_box(@brands.const_boxed())
  root.init_capability().set_capability_index(7U)
  let result = @brands.UsesReader::from_message(
    @capnp.read_message(target.finish()),
  )
  assert_eq(result.get_pointer().as_text(), "unknown payload")
  assert_eq(result.get_structure().get_uint64(0), 42UL)
  assert_eq(result.get_list().get_uint32(1), 99U)
  assert_eq(result.get_sample_box().get_value().get_id(), 456UL)
  assert_eq(result.get_capability().capability_index(), 7U)
  try root.set_capability(result.get_capability()) catch {
    @capnp.Unsupported(_) => ()
    _ => fail("expected capability remapping error")
  } noraise {
    _ => fail("copied capability without remapping")
  }
}
