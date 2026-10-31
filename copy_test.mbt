///|
test "opaque pointers initialize roots struct slots and pointer-list elements" {
  let message = @capnp.Builder::new()
  let pointer = message.root_pointer()
  assert_true(pointer.is_null())
  assert_eq(
    @capnp.read_message(message.finish()).root_pointer().kind(),
    @capnp.Null,
  )
  pointer.set_text("opaque 中文")
  let text = @capnp.read_message(message.finish()).root_pointer()
  assert_eq(text.kind(), @capnp.List)
  assert_eq(text.as_text(), "opaque 中文")
  pointer.set_data(b"\x00\xff")
  assert_eq(
    @capnp.read_message(message.finish()).root_pointer().as_data(),
    b"\x00\xff",
  )
  let root = pointer.init_struct(1, 2)
  root.set_uint64(0, 9007199254740993UL)
  root.get_pointer(0).set_text("slot")
  let list = root.get_pointer(1).init_list(6, 2)
  list.get_pointer(0).init_struct(1, 0).set_uint32(0, 42U)
  list.get_pointer(1).set_data(b"payload")
  let read = @capnp.read_message(message.finish()).root_pointer()
  assert_eq(read.kind(), @capnp.Struct)
  assert_eq(read.as_struct().get_text(0), "slot")
  assert_eq(
    read.as_struct().get_list(1).get_pointer(0).as_struct().get_uint32(0),
    42U,
  )
  assert_eq(read.as_struct().get_list(1).get_data(1), b"payload")
  pointer.clear()
  assert_true(pointer.is_null())
  ignore(pointer.init_struct(0, 0))
  let empty = @capnp.read_message(message.finish()).root_pointer()
  assert_false(empty.is_null())
  assert_eq(empty.kind(), @capnp.Struct)
  reader_error("bounds", () => ignore(root.get_pointer(2)))
  reader_error("bounds", () => ignore(list.get_pointer(-1)))
  let numbers = pointer.init_list(4, 1)
  reader_error("type", () => ignore(numbers.get_pointer(0)))
}

///|
test "opaque deep copy preserves every field in independent official multi-segment fixture" {
  let source = @capnp.read_message(
    @fs.read_file_to_bytes("fixtures/conformance.segmented.bin"),
  )
  assert_true(source.segment_count() > 1)
  let destination = @capnp.Builder::new()
  destination.root_pointer().set(source.root_pointer())
  assert_eq(@capnp.read_message(destination.finish()).segment_count(), 1)
  reader_check_oracle(destination.finish())
  let again = @capnp.Builder::new()
  again
  .root_pointer()
  .set_struct(@capnp.read_message(destination.finish()).root())
  reader_check_oracle(again.finish())
}

///|
test "opaque copy retains every list width and exact floating-point bit patterns" {
  for code in 0..<7 {
    let source = @capnp.Builder::new()
    let list = source.root_pointer().init_list(code, 9)
    match code {
      0 => list.set_void(8)
      1 => {
        list.set_bool(0, true)
        list.set_bool(8, true)
      }
      2 => list.set_uint8(8, 255)
      3 => list.set_uint16(8, 65535U)
      4 => list.set_uint32(8, 0x7fc00001U)
      5 => list.set_uint64(8, 0xfff8000000000001UL)
      _ => {
        list.get_pointer(0).set_text("nested")
        list.get_pointer(8).init_list(3, 2).set_uint16(1, 513U)
      }
    }
    let target = @capnp.Builder::new()
    target
    .root_pointer()
    .set_list(@capnp.read_message(source.finish()).root_pointer().as_list())
    let copied = @capnp.read_message(target.finish()).root_pointer().as_list()
    assert_eq(copied.element_size(), code)
    assert_eq(copied.length(), 9)
    match code {
      0 => ()
      1 => {
        assert_true(copied.get_bool(0))
        assert_true(copied.get_bool(8))
        assert_false(copied.get_bool(7))
      }
      2 => assert_eq(copied.get_uint8(8), 255)
      3 => assert_eq(copied.get_uint16(8), 65535U)
      4 => {
        assert_eq(copied.get_uint32(8), 0x7fc00001U)
        assert_true(copied.get_float32(8).is_nan())
      }
      5 => {
        assert_eq(copied.get_uint64(8), 0xfff8000000000001UL)
        assert_true(copied.get_float64(8).is_nan())
      }
      _ => {
        assert_eq(copied.get_text(0), "nested")
        assert_true(copied.get_pointer(1).is_null())
        assert_eq(copied.get_list(8).get_uint16(1), 513U)
      }
    }
  }
}

///|
test "opaque composite copies preserve unknown fields and nested object sections" {
  let source = @capnp.Builder::new()
  let list = source.root_pointer().init_struct_list(2, 3, 2)
  let first = list.struct_at(0)
  first.set_uint64(16, 0xffffffffffffffffUL)
  first.get_pointer(1).set_text("unknown future field")
  let second = list.struct_at(1)
  second.set_uint32(8, 123U)
  second
  .get_pointer(0)
  .init_struct_list(1, 0, 1)
  .struct_at(0)
  .get_pointer(0)
  .set_data(b"nested")
  let target = @capnp.Builder::new()
  target.root_pointer().set(@capnp.read_message(source.finish()).root_pointer())
  let copied = @capnp.read_message(target.finish()).root_pointer().as_list()
  assert_eq(copied.element_size(), 7)
  assert_eq(copied.length(), 2)
  assert_eq(copied.get_struct(0).data_size_bytes(), 24)
  assert_eq(copied.get_struct(0).pointer_count(), 2)
  assert_eq(copied.get_struct(0).get_uint64(16), 0xffffffffffffffffUL)
  assert_eq(copied.get_struct(0).get_text(1), "unknown future field")
  assert_eq(copied.get_struct(1).get_uint32(8), 123U)
  assert_eq(
    copied.get_struct(1).get_list(0).get_struct(0).get_data(0),
    b"nested",
  )
  // A struct view obtained by schema evolution may have a partial data word.
  let primitive = source.root_pointer().init_list(2, 2)
  primitive.set_uint8(1, 0xa5)
  target
  .root_pointer()
  .set_struct(
    @capnp.read_message(source.finish()).root_pointer().as_list().get_struct(1),
  )
  assert_eq(@capnp.read_message(target.finish()).root().get_uint64(0), 0xa5UL)
}

///|
test "opaque copy distinguishes null empty struct and all empty list representations" {
  let source = @capnp.Builder::new()
  let target = @capnp.Builder::new()
  target.root_pointer().set_text("old")
  target.root_pointer().set(@capnp.read_message(source.finish()).root_pointer())
  assert_true(target.root_pointer().is_null())
  ignore(source.root_pointer().init_struct(0, 0))
  target.root_pointer().set(@capnp.read_message(source.finish()).root_pointer())
  assert_eq(
    @capnp.read_message(target.finish()).root_pointer().kind(),
    @capnp.Struct,
  )
  for code in 0..<8 {
    if code == 7 {
      ignore(source.root_pointer().init_struct_list(0, 2, 1))
    } else {
      ignore(source.root_pointer().init_list(code, 0))
    }
    target
    .root_pointer()
    .set(@capnp.read_message(source.finish()).root_pointer())
    let pointer = @capnp.read_message(target.finish()).root_pointer()
    assert_false(pointer.is_null())
    assert_eq(pointer.kind(), @capnp.List)
    assert_eq(pointer.as_list().element_size(), code)
    assert_eq(pointer.as_list().length(), 0)
  }
  ignore(source.root_pointer().init_struct_list(3, 0, 0))
  target.root_pointer().set(@capnp.read_message(source.finish()).root_pointer())
  assert_eq(
    @capnp.read_message(target.finish()).root_pointer().as_list().length(),
    3,
  )
}

///|
test "opaque copy resolves double-far pointers and rejects unmapped capabilities" {
  let far = reader_frame([
    [0x0000000100000006UL],
    [0x0000000200000002UL, 0x0000000100000000UL],
    [42UL],
  ])
  let target = @capnp.Builder::new()
  target.root_pointer().set(@capnp.read_message(far).root_pointer())
  assert_eq(@capnp.read_message(target.finish()).root().get_uint64(0), 42UL)
  let far_list = reader_frame([
    [0x0000000100000006UL],
    [0x0000000200000002UL, 0x0000001c00000001UL],
    [0x0000000200000001UL, 3UL],
  ])
  target.root_pointer().set(@capnp.read_message(far_list).root_pointer())
  assert_eq(
    @capnp.read_message(target.finish()).root_pointer().as_list().get_uint32(2),
    3U,
  )
  let far_empty = reader_frame([[0x0000000100000002UL], [0UL]])
  target.root_pointer().set(@capnp.read_message(far_empty).root_pointer())
  assert_eq(
    @capnp.read_message(target.finish()).root_pointer().kind(),
    @capnp.Struct,
  )
  let source = @capnp.Builder::new()
  let root = source.root_pointer().init_struct(0, 1)
  root.get_pointer(0).set_capability_index(4294967295U)
  let cap = @capnp.read_message(source.finish()).root().get_pointer(0)
  assert_eq(cap.kind(), @capnp.Capability)
  assert_eq(cap.capability_index(), 4294967295U)
  let before = target.finish()
  reader_error("unsupported", () => {
    target
    .root_pointer()
    .set(@capnp.read_message(source.finish()).root_pointer())
  })
  assert_eq(target.finish(), before)
  reader_error("unsupported", () => target.root_pointer().set(cap))
  assert_eq(target.finish(), before)
  reader_error("type", () => {
    ignore(@capnp.read_message(far).root_pointer().capability_index())
  })
  reader_error("invalid", () => {
    ignore(
      @capnp.read_message(reader_frame([[7UL, 0UL, 0UL]])).root_pointer().kind(),
    )
  })
}

///|
test "failed deep copies roll back existing target and every appended arena byte" {
  let source = @capnp.Builder::new()
  let root = source.root_pointer().init_struct(1, 1)
  root.set_uint64(0, 42UL)
  root.set_text(0, "this nested object exceeds capacity")
  let target = @capnp.Builder::new(max_words=6)
  target.root_pointer().set_text("keep")
  let before = target.finish()
  let words = target.allocated_words()
  reader_error("limit", () => {
    target
    .root_pointer()
    .set(@capnp.read_message(source.finish()).root_pointer())
  })
  assert_eq(target.finish(), before)
  assert_eq(target.allocated_words(), words)
  let unrestricted = @capnp.Builder::new()
  unrestricted.root_pointer().set_data(b"keep")
  let snapshot = unrestricted.finish()
  reader_error("limit", () => {
    unrestricted
    .root_pointer()
    .set(@capnp.read_message(source.finish()).root_pointer(), max_words=2)
  })
  assert_eq(unrestricted.finish(), snapshot)
  reader_error("limit", () => {
    unrestricted
    .root_pointer()
    .set(@capnp.read_message(source.finish()).root_pointer(), max_depth=1)
  })
  assert_eq(unrestricted.finish(), snapshot)
  reader_error("limit", () => {
    unrestricted
    .root_pointer()
    .set(@capnp.read_message(source.finish()).root_pointer(), max_depth=257)
  })
  assert_eq(unrestricted.finish(), snapshot)
  // Parent allocation succeeds before a malformed child is reached.
  let malformed = reader_frame([[0x0001000000000000UL, 0x000000017ffffffcUL]])
  reader_error("bounds", () => {
    unrestricted
    .root_pointer()
    .set(@capnp.read_message(malformed).root_pointer())
  })
  assert_eq(unrestricted.finish(), snapshot)
}

///|
test "opaque copy bounds cycles repeated views and virtual-size amplification" {
  let target = @capnp.Builder::new()
  let before = target.finish()
  let cycle = reader_frame([[0x00010000fffffffcUL]])
  reader_error("limit", () => {
    target
    .root_pointer()
    .set(
      @capnp.read_message(cycle, nesting_limit=100).root_pointer(),
      max_depth=8,
    )
  })
  assert_eq(target.finish(), before)
  let source = @capnp.Builder::new()
  source.root_pointer().init_struct(1, 0).set_uint64(0, 42UL)
  reader_error("limit", () => {
    target
    .root_pointer()
    .set(
      @capnp.read_message(source.finish(), traversal_limit_words=0).root_pointer(),
    )
  })
  assert_eq(target.finish(), before)
  ignore(source.root_pointer().init_list(0, 100))
  reader_error("limit", () => {
    target
    .root_pointer()
    .set_list(
      @capnp.read_message(source.finish()).root_pointer().as_list(),
      max_words=99,
    )
  })
  assert_eq(target.finish(), before)
  ignore(source.root_pointer().init_struct_list(100, 0, 0))
  reader_error("limit", () => {
    target
    .root_pointer()
    .set_list(
      @capnp.read_message(source.finish()).root_pointer().as_list(),
      max_words=100,
    )
  })
  assert_eq(target.finish(), before)
  // Two pointers alias one independently encoded source object. Copy each edge.
  let aliases = reader_frame([
    [0x0002000000000000UL, 0x0000000100000004UL, 0x0000000100000000UL, 42UL],
  ])
  target.root_pointer().set(@capnp.read_message(aliases).root_pointer())
  assert_eq(target.allocated_words(), 5)
  let read = @capnp.read_message(target.finish()).root()
  assert_eq(read.get_struct(0).get_uint64(0), 42UL)
  assert_eq(read.get_struct(1).get_uint64(0), 42UL)
}

///|
test "mutated official pointer and framing bytes remain bounded and copies fail atomically" {
  let wire = @fs.read_file_to_bytes("fixtures/conformance.segmented.bin")
  // Exercise each bit of the segment table, far landing pointers, and first
  // objects from an external compiler fixture rather than our own builder.
  for pos in 0..<Int32::min(128, wire.length()) {
    for bit in 0..<8 {
      let altered = Bytes::makei(wire.length(), i => {
        if i == pos {
          wire[i] ^ (1 << bit).to_byte()
        } else {
          wire[i]
        }
      })
      let target = @capnp.Builder::new(max_words=256)
      target.root_pointer().set_data(b"unchanged")
      let before = target.finish()
      try {
        let source = @capnp.read_message(
          altered,
          max_segments=64,
          nesting_limit=8,
          traversal_limit_words=256,
        )
        target
        .root_pointer()
        .set(source.root_pointer(), max_depth=8, max_words=256)
      } catch {
        _ => assert_eq(target.finish(), before)
      } noraise {
        _ => {
          // A bit flip can change the root from struct to list. The standard
          // canonical-message operation accepts struct roots; arbitrary root
          // pointers are still valid input to the schema-free copy API.
          let original = @capnp.read_message(
            altered,
            max_segments=64,
            nesting_limit=8,
            traversal_limit_words=256,
          )
          let copied = @capnp.read_message(target.finish())
          assert_eq(
            original.root_pointer().kind(),
            copied.root_pointer().kind(),
          )
          match original.root_pointer().kind() {
            @capnp.Struct | @capnp.Null =>
              assert_eq(
                @capnp.canonicalize(original, max_words=256),
                @capnp.canonicalize(copied, max_words=256),
              )
            @capnp.List => {
              let source_list = original.root_pointer().as_list()
              let target_list = copied.root_pointer().as_list()
              assert_eq(source_list.length(), target_list.length())
              assert_eq(source_list.element_size(), target_list.element_size())
            }
            @capnp.Capability => fail("capability escaped copy rejection")
          }
        }
      }
    }
  }
}
