///|
test "schema Unknown variant and unknown future enum values remain distinct" {
  let message = @capnp.Builder::new()
  let root = @names.NamesBuilder::init_root(message)
  root.set_status(@names.Status::Unknown)
  root.set_string(@names.SchemaString::Filled)
  let known = @names.NamesReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(known.get_status().to_raw(), 0U)
  assert_eq(known.get_string().to_raw(), 1U)
  root.set_status(@names.Status::from_raw(40000U))
  let unknown = @names.NamesReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(unknown.get_status().to_raw(), 40000U)
}
