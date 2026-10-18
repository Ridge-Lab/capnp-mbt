///|
test "official compiler request deterministically generates typed bindings" {
  let request = @fs.read_file_to_bytes("fixtures/conformance.request.bin")
  let first = @codegen.generate(request)
  let second = @codegen.generate(request)
  assert_eq(first.length(), 1)
  assert_eq(first[0].path, "capnp_generated.mbt")
  assert_eq(first[0].content, second[0].content)
  assert_true(first[0].content.contains("struct FixtureReader"))
  assert_true(first[0].content.contains("get_uint64"))
  assert_true(first[0].content.contains("18446744073709551615UL"))
}

///|
test "malformed compiler input is rejected before producing files" {
  try @codegen.generate(b"not a capnp request") catch {
    @codegen.InvalidRequest(_) => ()
    _ => fail("unexpected diagnostic")
  } noraise {
    _ => fail("malformed request accepted")
  }
}

///|
test "RPC declarations report unsupported instead of generating an empty shell" {
  let request = @fs.read_file_to_bytes(
    "codegen/fixtures/unsupported.request.bin",
  )
  try @codegen.generate(request) catch {
    @codegen.UnsupportedSchema(message) =>
      assert_true(message.contains("RPC/interface"))
    _ => fail("unexpected diagnostic")
  } noraise {
    _ => fail("unsupported RPC declaration accepted")
  }
}

///|
test "runtime wrapper naming collisions fail before writing invalid source" {
  let request = @fs.read_file_to_bytes("codegen/fixtures/collision.request.bin")
  try @codegen.generate(request) catch {
    @codegen.UnsupportedSchema(message) =>
      assert_true(message.contains("collision: FooReader"))
    _ => fail("unexpected diagnostic")
  } noraise {
    _ => fail("generated type collision accepted")
  }
}

///|
test "generic schema requests produce an explicit unsupported diagnostic" {
  let request = @fs.read_file_to_bytes("codegen/fixtures/generic.request.bin")
  try @codegen.generate(request) catch {
    @codegen.UnsupportedSchema(message) =>
      assert_true(message.contains("generic"))
    _ => fail("unexpected diagnostic")
  } noraise {
    _ => fail("generic declaration accepted")
  }
}
