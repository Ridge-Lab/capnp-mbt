///|
test "three levels of increasing list generic bindings retain payloads at dynamic boundary" {
  let message = @capnp.Builder::new()
  let root = @growing.UsesBuilder::init_root(message)
  let first = root.init_growing()
  first.set_value("first")
  let second = first.init_next()
  second.init_value(1).get(0).set_value("second")
  // Growing(List(Box(List(Box(Text))))) reaches the dynamic recursion boundary.
  let third = second.init_next()
  let boxes = third.init_value().init_struct_list(1, 0, 1)
  let nested = boxes.struct_at(0).init_struct_list(0, 1, 0, 1)
  nested.struct_at(0).set_text(0, "third")
  let read = @growing.UsesReader::from_message(
    @capnp.read_message(message.finish()),
  ).get_growing()
  assert_eq(read.get_value(), "first")
  assert_eq(read.get_next().get_value().get(0).get_value(), "second")
  assert_eq(
    read
    .get_next()
    .get_next()
    .get_value()
    .as_list()
    .get_struct(0)
    .get_list(0)
    .get_struct(0)
    .get_text(0),
    "third",
  )
  let copied = @capnp.Builder::new()
  @growing.UsesBuilder::init_root(copied).set_growing(read)
  let again = @growing.UsesReader::from_message(
    @capnp.read_message(copied.finish()),
  ).get_growing()
  assert_eq(
    again
    .get_next()
    .get_next()
    .get_value()
    .as_list()
    .get_struct(0)
    .get_list(0)
    .get_struct(0)
    .get_text(0),
    "third",
  )
}

///|
test "duplicating generic arguments terminate and retain deeply nested structure" {
  let message = @capnp.Builder::new()
  let first = @growing.UsesBuilder::init_root(message).init_tree()
  first.set_value("root")
  let second = first.init_next()
  let pair = second.init_value()
  pair.set_left("left")
  pair.set_right("right")
  let third = second.init_next()
  let pair2 = third.init_value().init_struct(0, 2)
  pair2.init_struct(0, 0, 2).set_text(1, "nested pair")
  let read = @growing.UsesReader::from_message(
    @capnp.read_message(message.finish()),
  ).get_tree()
  assert_eq(read.get_next().get_value().get_right(), "right")
  assert_eq(
    read.get_next().get_next().get_value().as_struct().get_struct(0).get_text(1),
    "nested pair",
  )
}
