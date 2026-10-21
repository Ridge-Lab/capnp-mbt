///|
// Independent hand-authored wire vectors, not emitted by the project Builder.
fn reader_frame(segments : Array[Array[UInt64]]) -> Bytes {
  let output : Array[Byte] = []
  for i in 0..<4 {
    output.push(
      ((segments.length() - 1).reinterpret_as_uint() >> (8 * i)).to_byte(),
    )
  }
  for segment in segments {
    for i in 0..<4 {
      output.push((segment.length().reinterpret_as_uint() >> (8 * i)).to_byte())
    }
  }
  if segments.length() % 2 == 0 {
    for _ in 0..<4 {
      output.push(0)
    }
  }
  for segment in segments {
    for word in segment {
      for byte in word.to_le_bytes() {
        output.push(byte)
      }
    }
  }
  Bytes::from_array(output)
}

///|
fn reader_error(
  kind : String,
  action : () -> Unit raise @capnp.CapnpError,
) -> Unit raise {
  try action() catch {
    @capnp.CapnpError::Bounds(_) => assert_eq(kind, "bounds")
    @capnp.CapnpError::InvalidMessage(_) => assert_eq(kind, "invalid")
    @capnp.CapnpError::Limit(_) => assert_eq(kind, "limit")
    @capnp.CapnpError::TypeMismatch(_) => assert_eq(kind, "type")
    @capnp.CapnpError::Unsupported(_) => assert_eq(kind, "unsupported")
  } noraise {
    _ => fail("expected a structured reader error")
  }
}

///|
test "reader handles both far-pointer landing pad forms" {
  // The reference C++ reader accepts an all-zero landing tag as an empty
  // struct. It is not a null root: the original pointer was a far pointer.
  let far_empty = reader_frame([[0x0000000100000002UL], [0UL]])
  assert_eq(@capnp.read_message(far_empty).root_pointer().is_null(), false)
  assert_eq(
    @capnp.read_message(far_empty).root().get_uint64(0, default=42UL),
    42UL,
  )
  let single = reader_frame([
    [0x0000000100000002UL],
    [0x0000000100000000UL, 42UL],
  ])
  assert_eq(@capnp.read_message(single).root().get_uint64(0), 42UL)
  let double = reader_frame([
    [0x0000000100000006UL],
    [0x0000000200000002UL, 0x0000000100000000UL],
    [42UL],
  ])
  assert_eq(@capnp.read_message(double).root().get_uint64(0), 42UL)
  let double_list = reader_frame([
    [0x0000000100000006UL],
    [0x0000000200000002UL, 0x0000001c00000001UL],
    [0x0000000200000001UL, 3UL],
  ])
  let list = @capnp.read_message(double_list).root_pointer().as_list()
  assert_eq(list.length(), 3)
  assert_eq(list.get_uint32(0), 1)
  assert_eq(list.get_uint32(1), 2)
  assert_eq(list.get_uint32(2), 3)
}

///|
test "reader rejects malformed far pointers without following unbounded chains" {
  reader_error("bounds", () => {
    ignore(@capnp.read_message(reader_frame([[0x0000000200000002UL]])).root())
  })
  reader_error("bounds", () => {
    ignore(@capnp.read_message(reader_frame([[0x000000000000000eUL]])).root())
  })
  reader_error("invalid", () => {
    ignore(
      @capnp.read_message(
        reader_frame([[0x0000000100000002UL], [0x0000000100000002UL]]),
      ).root(),
    )
  })
  reader_error("invalid", () => {
    ignore(
      @capnp.read_message(
        reader_frame([
          [0x0000000100000006UL],
          [0x0000000200000006UL, 0x0000000100000000UL],
          [42UL],
        ]),
      ).root(),
    )
  })
  reader_error("invalid", () => {
    ignore(
      @capnp.read_message(
        reader_frame([
          [0x0000000100000006UL],
          [0x0000000200000002UL, 0x0000000100000004UL],
          [42UL],
        ]),
      ).root(),
    )
  })
}

///|
test "reader validates framing lengths limits and exact consumption" {
  let bytes = @fs.read_file_to_bytes("fixtures/conformance.bin")
  for n in 0..<bytes.length() {
    reader_error("invalid", () => {
      ignore(@capnp.read_message(bytes[:n].to_owned()))
    })
  }
  reader_error("invalid", () => ignore(@capnp.read_message(bytes + b"\x00")))
  reader_error("invalid", () => ignore(@capnp.read_message(reader_frame([[]]))))
  reader_error("limit", () => {
    ignore(@capnp.read_message(reader_frame([[0UL]]), max_segments=0))
  })
  reader_error("limit", () => {
    ignore(@capnp.read_message(reader_frame([[0UL]]), nesting_limit=-1))
  })
  reader_error("limit", () => {
    ignore(@capnp.read_message(reader_frame([[0UL]]), traversal_limit_words=-1))
  })
  reader_error("limit", () => {
    ignore(@capnp.read_message(reader_frame([[0UL], []]), max_segments=1))
  })
  reader_error("limit", () => {
    ignore(@capnp.read_message(b"\xff\xff\xff\xff\x00\x00\x00\x00"))
  })
}

///|
test "reader lazy pointer validation enforces segment and object extents" {
  let vectors = [
    [0x000000017ffffffcUL], // excessive positive offset
    [0x0000000180000000UL], // excessive negative offset
    [0x0000000100000000UL], // data extends past segment
    [0x0001000000000000UL], // pointer section extends past segment
    [0xfffffffd00000001UL], // enormous 64-bit-element list
    [0x0000000f00000001UL, 0x0000000100000008UL], // composite wants two data words, declares one
    [0x0000000700000001UL, 1UL], // non-struct composite tag
  ]
  for i, vector in vectors {
    let message = @capnp.read_message(reader_frame([vector]))
    reader_error(if i == 6 { "invalid" } else { "bounds" }, () => {
      if i < 4 {
        ignore(message.root())
      } else {
        ignore(message.root_pointer().as_list())
      }
    })
  }
}

///|
test "reader shared traversal and nesting budgets stop cycles and repeated alias reads" {
  let cycle = reader_frame([[0x00010000fffffffcUL]])
  let root = @capnp.read_message(cycle, nesting_limit=3).root()
  let second = root.get_struct(0)
  let third = second.get_struct(0)
  reader_error("limit", () => ignore(third.get_struct(0)))
  let message = @capnp.read_message(cycle, traversal_limit_words=2)
  let first = message.root()
  ignore(first.get_struct(0))
  assert_eq(message.remaining_traversal_words(), 0)
  reader_error("limit", () => ignore(first.get_struct(0)))
  let root_zero = reader_frame([[0x00000000fffffffcUL]])
  reader_error("limit", () => {
    ignore(@capnp.read_message(root_zero, nesting_limit=0).root())
  })
}

///|
test "reader charges virtual words for void and zero-size composite lists" {
  // Ten Void entries take no physical words but ten traversal words.
  let voids = reader_frame([[0x0000005000000001UL]])
  reader_error("limit", () => {
    ignore(
      @capnp.read_message(voids, traversal_limit_words=9)
      .root_pointer()
      .as_list(),
    )
  })
  assert_eq(
    @capnp.read_message(voids, traversal_limit_words=10)
    .root_pointer()
    .as_list()
    .length(),
    10,
  )
  // Ten empty structs plus one tag word consume eleven traversal words.
  let empty_structs = reader_frame([[0x0000000700000001UL, 40UL]])
  reader_error("limit", () => {
    ignore(
      @capnp.read_message(empty_structs, traversal_limit_words=10)
      .root_pointer()
      .as_list(),
    )
  })
  let list = @capnp.read_message(empty_structs, traversal_limit_words=11)
    .root_pointer()
    .as_list()
  assert_eq(list.get_struct(9).get_uint64(0, default=99UL), 99UL)
}

///|
test "reader preserves text BOM embedded NUL and rejects malformed UTF8 or terminators" {
  let bom = reader_frame([[0x0000003200000001UL, 0x0000006100bfbbefUL]])
  assert_eq(
    @capnp.read_message(bom).root_pointer().as_text(),
    "\u{feff}\u0000a",
  )
  let invalid_utf8 = reader_frame([[0x0000001a00000001UL, 0x00000000000080c0UL]])
  reader_error("invalid", () => {
    ignore(@capnp.read_message(invalid_utf8).root_pointer().as_text())
  })
  let no_nul = reader_frame([[0x0000000a00000001UL, 65UL]])
  reader_error("invalid", () => {
    ignore(@capnp.read_message(no_nul).root_pointer().as_text())
  })
  let empty_no_nul = reader_frame([[0x0000000200000001UL]])
  reader_error("invalid", () => {
    ignore(@capnp.read_message(empty_no_nul).root_pointer().as_text())
  })
}

///|
test "reader reports bounds and type errors through public accessors" {
  let root = @capnp.read_message(
    @fs.read_file_to_bytes("fixtures/conformance.bin"),
  ).root()
  reader_error("bounds", () => ignore(root.get_pointer(-1)))
  reader_error("bounds", () => ignore(root.get_uint64(-1)))
  reader_error("bounds", () => ignore(root.get_bool(-1)))
  reader_error("bounds", () => ignore(root.get_int8(0, default=128)))
  reader_error("bounds", () => ignore(root.get_int16(0, default=-32769)))
  reader_error("bounds", () => ignore(root.get_uint16(0, default=65536)))
  let bits = root.get_list(4)
  reader_error("type", () => ignore(bits.get_struct(0)))
  reader_error("bounds", () => ignore(bits.get_bool(-1)))
  reader_error("bounds", () => ignore(bits.get_bool(bits.length())))
  reader_error("type", () => ignore(root.get_struct(0)))
  reader_error("type", () => ignore(root.get_list(2)))
  reader_error("type", () => ignore(root.get_list(7).get_uint8(0)))
  reader_error("type", () => ignore(root.get_list(7).get_pointer(0)))
  reader_error("type", () => ignore(root.get_list(7).get_bool(0)))
  let cap = @capnp.read_message(reader_frame([[3UL]]))
  reader_error("unsupported", () => ignore(cap.root()))
}

///|
test "reader schema evolution preserves old fields and supplies new field defaults" {
  // Version 1 has one data word and no pointers. Version 2 adds a second
  // data word and pointer fields; readers must use the on-wire section size.
  let old_wire = reader_frame([[0x0000000100000000UL, 123UL]])
  let old_as_new = @capnp.read_message(old_wire).root()
  assert_eq(old_as_new.data_size_bytes(), 8)
  assert_eq(old_as_new.pointer_count(), 0)
  assert_eq(old_as_new.get_uint32(0), 123)
  assert_eq(old_as_new.get_uint32(8, default=99), 99)
  assert_eq(old_as_new.get_bool(64, default=true), true)
  assert_eq(old_as_new.get_text(0, default="new field"), "new field")
  assert_eq(old_as_new.get_data(1, default=b"\x01\x02"), b"\x01\x02")
  assert_eq(old_as_new.get_list(2).length(), 0)
  let new_child = old_as_new.get_struct(3)
  assert_eq(new_child.get_uint64(0, default=42UL), 42UL)
  // An old reader ignores the second data word of a newer writer's struct.
  let new_wire = reader_frame([[0x0000000200000000UL, 123UL, 456UL]])
  let new_as_old = @capnp.read_message(new_wire).root()
  assert_eq(new_as_old.get_uint32(0), 123)
  assert_eq(new_as_old.get_uint64(8), 456UL)
}

///|
test "reader rejects incompatible primitive views without losing struct defaults" {
  // Independent pycapnp/C++ output using unchanged upstream test.capnp:
  // TestAnyPointer.anyPointerField = List(TestAnyPointer), one Text payload.
  // The reference reader rejects interpreting its pointer-only elements as
  // UInt32. Missing fields on a genuine struct view still use schema defaults.
  let pointer_only = @capnp.read_message(
      reader_frame([
        [
          0x0001000000000000UL, 0x0000000f00000001UL, 0x0001000000000004UL, 0x0000003200000001UL,
          0x00000065756c6176UL,
        ],
      ]),
    )
    .root()
    .get_list(0)
  assert_eq(pointer_only.get_text(0), "value")
  reader_error("type", () => ignore(pointer_only.get_uint32(0)))
  assert_eq(pointer_only.get_struct(0).get_uint32(0, default=99), 99)
  // Likewise, List(TestEmptyStruct) cannot be viewed as List(Text), while
  // fields added to the empty struct remain legal and read their defaults.
  let empty_structs = @capnp.read_message(
      reader_frame([[0x0001000000000000UL, 0x0000000700000001UL, 4UL]]),
    )
    .root()
    .get_list(0)
  reader_error("type", () => ignore(empty_structs.get_pointer(0)))
  reader_error("type", () => ignore(empty_structs.get_uint8(0)))
  assert_eq(
    empty_structs.get_struct(0).get_text(0, default="new field"),
    "new field",
  )
  assert_eq(empty_structs.get_struct(0).get_uint64(0, default=42UL), 42UL)
  let voids = @capnp.read_message(reader_frame([[0x0000000800000001UL]]))
    .root_pointer()
    .as_list()
  assert_eq(voids.get_struct(0).get_uint32(0, default=7), 7)
}
