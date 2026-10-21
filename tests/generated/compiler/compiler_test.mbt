///|
test "unchanged schema capnp bindings read and copy the actual official compiler request" {
  let bytes = @fs.read_file_to_bytes("codegen/fixtures/upstream.request.bin")
  let source = @compiler.CodeGeneratorRequestReader::from_message(
    @capnp.read_message(bytes),
  )
  assert_eq(source.get_capnp_version().get_major(), 1U)
  assert_eq(source.get_capnp_version().get_minor(), 5)
  assert_eq(source.get_requested_files().length(), 1)
  assert_eq(
    source.get_requested_files().get(0).get_filename(),
    "capnp/test.capnp",
  )
  let nodes = source.get_nodes()
  assert_true(nodes.length() > 100)
  let mut found_generic = false
  for i in 0..<nodes.length() {
    let node = nodes.get(i)
    if node.get_display_name() == "capnp/test.capnp:TestGenerics" {
      found_generic = true
      assert_true(node.get_is_generic())
      assert_eq(node.get_parameters().length(), 2)
      assert_eq(node.get_parameters().get(0).get_name(), "Foo")
      assert_true(node.is_struct())
      assert_true(node.get_struct().get_fields().length() > 2)
    }
  }
  assert_true(found_generic)
  let target = @capnp.Builder::new()
  target.root_pointer().set_struct(source.inner)
  let copy = @compiler.CodeGeneratorRequestReader::from_message(
    @capnp.read_message(target.finish()),
  )
  assert_eq(copy.get_nodes().length(), source.get_nodes().length())
  assert_eq(
    copy.get_requested_files().get(0).get_filename(),
    "capnp/test.capnp",
  )
  assert_eq(
    @capnp.canonicalize(@capnp.read_message(bytes)),
    @capnp.canonicalize(@capnp.read_message(target.finish())),
  )
}
