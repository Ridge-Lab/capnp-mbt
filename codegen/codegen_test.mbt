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
test "interface declarations coexist with serialization without RPC stubs" {
  let request = @fs.read_file_to_bytes(
    "codegen/fixtures/unsupported.request.bin",
  )
  let files = @codegen.generate(request)
  assert_eq(files.length(), 1)
  assert_true(files[0].content.contains("no RPC transport is generated"))
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
test "unbound generic schema exposes lossless dynamic pointer views" {
  let request = @fs.read_file_to_bytes("codegen/fixtures/generic.request.bin")
  let output = @codegen.generate(request)[0].content
  assert_true(output.contains("struct BoxReader"))
  assert_true(output.contains("-> @capnp.PointerReader"))
  assert_true(output.contains("-> @capnp.PointerBuilder"))
}

///|
test "recursive generic growth terminates without rejecting the schema" {
  let request = @fs.read_file_to_bytes("codegen/fixtures/growing.request.bin")
  let output = @codegen.generate(request)[0].content
  assert_true(output.contains("GrowingAsTextReader"))
  assert_true(output.contains("TreeAsPairAsTextAndTextReader"))
  assert_true(output.length() < 100000)
  assert_eq(output, @codegen.generate(request)[0].content)
}

///|
test "unchanged upstream schema compiler protocol and conformance declarations generate" {
  let protocol = @codegen.generate(
      @fs.read_file_to_bytes("codegen/fixtures/compiler.request.bin"),
    )[0].content
  assert_true(protocol.contains("CodeGeneratorRequestReader"))
  let upstream = @codegen.generate(
      @fs.read_file_to_bytes("codegen/fixtures/upstream.request.bin"),
    )[0].content
  assert_true(upstream.contains("TestUseGenericsReader"))
  assert_true(
    upstream.contains(
      "const_generic_constant() -> TestGenericsAsTestAllTypesAndTextReader",
    ),
  )
  assert_true(upstream.contains("const_any_pointer_constants()"))
}
