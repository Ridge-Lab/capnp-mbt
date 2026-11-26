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

///|
test "is_canonical and read_canonical verify every official canonical oracle vector" {
  let paths = [
    "fixtures/conformance.canonical.bin", "fixtures/upstream/oracle-1.5.0/null-root.canonical.bin",
    "fixtures/upstream/oracle-1.5.0/bool-padding.canonical.bin", "fixtures/upstream/oracle-1.5.0/data-padding.canonical.bin",
    "fixtures/upstream/oracle-1.5.0/inline-trim.canonical.bin", "fixtures/upstream/oracle-1.5.0/inline-all-zero.canonical.bin",
    "fixtures/upstream/oracle-1.5.0/empty-list-order.canonical.bin", "fixtures/upstream/oracle-1.5.0/nested-far.canonical.bin",
    "fixtures/upstream/oracle-1.5.0/far-empty-child.canonical.bin", "fixtures/upstream/oracle-1.5.0/reverse-allocation.canonical.bin",
  ]
  for path in paths {
    let segment = @fs.read_file_to_bytes(path)
    assert_true(@capnp.is_canonical(segment))
    let decoded = @capnp.read_canonical(segment)
    assert_eq(decoded.segment_count(), 1)
    assert_eq(@capnp.canonicalize(decoded), segment)
  }
  // Confirm zero-copy canonical decoding exposes the exact conformance values.
  let conformance = @capnp.read_canonical(
    @fs.read_file_to_bytes("fixtures/conformance.canonical.bin"),
  ).root()
  assert_eq(conformance.get_text(0), "MoonBit 数据交换")
  assert_eq(conformance.get_data(1), b"\x00\xff\x80\x0a\x0d")
}

///|
test "is_canonical and read_canonical reject every non-canonical wire violation" {
  // Strip 8-byte single-segment frame header from non-canonical oracle inputs.
  for
    name in [
      "null-root", "bool-padding", "data-padding", "inline-trim", "inline-all-zero",
      "reverse-allocation",
    ] {
    let framed = @fs.read_file_to_bytes(
      "fixtures/upstream/oracle-1.5.0/" + name + ".bin",
    )
    let bare = framed[8:].to_owned()
    assert_false(@capnp.is_canonical(bare))
    try ignore(@capnp.read_canonical(bare)) catch {
      @capnp.CapnpError::InvalidMessage(_) | @capnp.CapnpError::Bounds(_) => ()
      _ => fail("expected non-canonical rejection for \{name}")
    } noraise {
      _ => fail("accepted non-canonical vector \{name}")
    }
  }
  // Empty, unaligned, list root, far pointer, untrimmed sections, aliased child.
  let invalid_segments : Array[Bytes] = [
    b"", b"\x00\x00\x00\x00\x00\x00\x00", b"\xfc\xff\xff\xff\x00\x00\x00\x00\x00", // trailing unaligned byte
     b"\xfc\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", // trailing unreachable word
     b"\x00\x00\x00\x00\x00\x00\x00\x00", // null root instead of offset -1 empty struct
     b"\x01\x00\x00\x00\x02\x00\x00\x00", // list root (empty byte list)
     b"\x02\x00\x00\x00\x00\x00\x00\x00", // far pointer root
     b"\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", // untrimmed zero data word
     b"\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00", // untrimmed null pointer
    // Aliased child: struct with 2 pointers both pointing to the same data word.
     b"\x00\x00\x00\x00\x00\x00\x02\x00\x04\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x2a\x00\x00\x00\x00\x00\x00\x00",
  ]
  for segment in invalid_segments {
    assert_false(@capnp.is_canonical(segment))
    reader_error("invalid", () => ignore(@capnp.read_canonical(segment)))
  }
  // Truncated canonical struct root is rejected with Bounds.
  let truncated_struct = b"\x00\x00\x00\x00\x02\x00\x00\x00"
  assert_false(@capnp.is_canonical(truncated_struct))
  reader_error("bounds", () => ignore(@capnp.read_canonical(truncated_struct)))
  // Capability root is rejected as Unsupported by read_canonical and false by is_canonical.
  let capability_root = b"\x03\x00\x00\x00\x00\x00\x00\x00"
  assert_false(@capnp.is_canonical(capability_root))
  reader_error("unsupported", () => {
    ignore(@capnp.read_canonical(capability_root))
  })
  // Budget limits are enforced rather than silently returning false.
  let valid = @fs.read_file_to_bytes("fixtures/conformance.canonical.bin")
  reader_error("limit", () => {
    ignore(@capnp.is_canonical(valid, traversal_limit_words=1))
  })
  reader_error("limit", () => {
    ignore(@capnp.is_canonical(valid, nesting_limit=1))
  })
  reader_error("limit", () => {
    ignore(@capnp.read_canonical(valid, traversal_limit_words=-1))
  })
}
