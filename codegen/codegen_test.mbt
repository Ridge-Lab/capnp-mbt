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
test "runtime wrapper naming collisions allocate distinct symbols without schema edits" {
  let request = @fs.read_file_to_bytes("codegen/fixtures/collision.request.bin")
  let output = @codegen.generate(request)[0].content
  assert_true(output.contains("enum FooReader"))
  assert_true(output.contains("struct FooN"))
  assert_eq(output, @codegen.generate(request)[0].content)
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

///|
test "source info order comments annotations and compiler metadata cannot change generated values" {
  let request = @fs.read_file_to_bytes("codegen/fixtures/upstream.request.bin")
  let source = @capnp.read_message(request).root()
  let expected = @codegen.generate(request)[0].content
  let rewritten = @capnp.Builder::new()
  let root = rewritten.init_root(0, 4)
  let nodes = source.get_list(0)
  let shape = nodes.get_struct(0)
  let data_words = shape.data_size_bytes() / 8
  let pointers = shape.pointer_count()
  let target_nodes = root.init_struct_list(
    0,
    nodes.length(),
    data_words,
    pointers,
  )
  for i in 0..<nodes.length() {
    let node = nodes.get_struct(i)
    let target = target_nodes.struct_at(i)
    for word in 0..<data_words {
      target.set_uint64(word * 8, node.get_uint64(word * 8))
    }
    for slot in 0..<pointers {
      // Node.annotations is not part of any serialized default value.
      if slot != 2 {
        target.get_pointer(slot).set(node.get_pointer(slot))
      }
    }
  }
  root.get_pointer(1).set(source.get_pointer(1))
  // Both optional sourceInfo and compiler-version metadata may be absent.
  assert_eq(@codegen.generate(rewritten.finish())[0].content, expected)
  root.init_struct(2, 1, 0).set_uint16(0, 999U)
  let info = source.get_list(3)
  assert_true(info.length() > 2)
  let target_info = root.init_struct_list(3, info.length(), 2, 2)
  for i in 0..<info.length() {
    let original = info.get_struct(info.length() - i - 1)
    let target = target_info.struct_at(i)
    target.set_uint64(0, original.get_uint64(0))
    target.set_uint64(8, original.get_uint64(8))
    target.set_text(0, "platform-independent documentation override")
    target.get_pointer(1).set(original.get_pointer(1))
  }
  assert_true(rewritten.finish() != request)
  assert_eq(@codegen.generate(rewritten.finish())[0].content, expected)
}
