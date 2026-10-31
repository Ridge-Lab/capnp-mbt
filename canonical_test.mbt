///|
fn canonical_word(bytes : Bytes, offset : Int32) -> UInt64 {
  let mut value = 0UL
  for i in 0..<8 {
    value = value | (bytes[offset + i].to_uint64() << (i * 8))
  }
  value
}

///|
test "canonical segments match the independent official converter" {
  let expected = @fs.read_file_to_bytes("fixtures/conformance.canonical.bin")
  let ordinary = @fs.read_file_to_bytes("fixtures/conformance.bin")
  let segmented = @fs.read_file_to_bytes("fixtures/conformance.segmented.bin")
  assert_eq(@capnp.canonicalize(@capnp.read_message(ordinary)), expected)
  assert_eq(@capnp.canonicalize(@capnp.read_message(segmented)), expected)
  let null_root = @fs.read_file_to_bytes(
    "fixtures/upstream/oracle-1.5.0/null-root.bin",
  )
  let null_canonical = @fs.read_file_to_bytes(
    "fixtures/upstream/oracle-1.5.0/null-root.canonical.bin",
  )
  assert_eq(@capnp.canonicalize(@capnp.read_message(null_root)), null_canonical)
  for
    name in [
      "bool-padding", "data-padding", "inline-trim", "inline-all-zero", "empty-list-order",
      "nested-far", "far-empty-child", "reverse-allocation",
    ] {
    let path = "fixtures/upstream/oracle-1.5.0/" + name
    let input = @fs.read_file_to_bytes(path + ".bin")
    let canonical = @fs.read_file_to_bytes(path + ".canonical.bin")
    assert_eq(@capnp.canonicalize(@capnp.read_message(input)), canonical)
  }
}

///|
test "canonical structs trim zero sections and preserve empty presence" {
  let message = @capnp.Builder::new()
  let root = message.init_root(4, 4)
  root.set_uint64(0, 42UL)
  ignore(root.init_struct(0, 3, 2))
  let flat = @capnp.canonicalize(@capnp.read_message(message.finish()))
  // Root pointer + one data word + one pointer; empty struct has no body.
  assert_eq(flat.length(), 24)
  assert_eq(canonical_word(flat, 0), (1UL << 32) | (1UL << 48))
  assert_eq(canonical_word(flat, 8), 42UL)
  assert_eq(canonical_word(flat, 16), 0xfffffffcUL)
}

///|
test "canonical struct lists use uniform minimum sections and preorder" {
  let message = @capnp.Builder::new()
  let root = message.init_root(0, 1)
  let list = root.init_struct_list(0, 2, 4, 3)
  list.struct_at(0).set_uint64(8, 9UL)
  list.struct_at(1).set_text(0, "x")
  let flat = @capnp.canonicalize(@capnp.read_message(message.finish()))
  assert_eq(flat.length(), 80)
  assert_eq((canonical_word(flat, 16) >> 32) & 0xffffUL, 2UL)
  assert_eq(canonical_word(flat, 16) >> 48, 1UL)
}

///|
test "canonicalization enforces output limit and rejects capabilities" {
  let message = @capnp.Builder::new()
  message.init_root(1, 0).set_uint64(0, 1UL)
  reader_error("limit", () => {
    ignore(
      @capnp.canonicalize(@capnp.read_message(message.finish()), max_words=1),
    )
  })
  let cap = b"\x00\x00\x00\x00\x01\x00\x00\x00\x03\x00\x00\x00\x00\x00\x00\x00"
  reader_error("unsupported", () => {
    ignore(@capnp.canonicalize(@capnp.read_message(cap)))
  })
  let list_message = @capnp.Builder::new()
  list_message.root_pointer().set_text("list root")
  reader_error("type", () => {
    ignore(@capnp.canonicalize(@capnp.read_message(list_message.finish())))
  })
}

///|
test "canonical recursion is independently bounded even with permissive reader" {
  let cycle = b"\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\xfc\xff\xff\xff\x00\x00\x01\x00"
  reader_error("limit", () => {
    ignore(
      @capnp.canonicalize(
        @capnp.read_message(cycle, nesting_limit=1000000),
        max_depth=20,
      ),
    )
  })
  let empty = @capnp.Builder::new().finish()
  reader_error("limit", () => {
    ignore(@capnp.canonicalize(@capnp.read_message(empty), max_depth=257))
  })
}
