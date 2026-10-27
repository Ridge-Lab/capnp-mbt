///|
test "upstream old and new versions retain recursive defaults and unknown fields" {
  let old_message = @capnp.Builder::new()
  let old = @upstream.TestOldVersionBuilder::init_root(old_message)
  old.set_old1(123L)
  old.init_old3().set_old2("child")
  let upgraded = @upstream.TestNewVersionReader::from_message(
    @capnp.read_message(old_message.finish()),
  )
  assert_eq(upgraded.get_old1(), 123L)
  assert_eq(upgraded.get_new1(), 987L)
  assert_eq(upgraded.get_new2(), "baz")
  assert_eq(upgraded.get_old3().get_old2(), "child")
  assert_eq(upgraded.get_old3().get_new1(), 987L)
  assert_eq(upgraded.get_old3().get_new2(), "baz")
  let new_message = @capnp.Builder::new()
  let new = @upstream.TestNewVersionBuilder::init_root(new_message)
  new.set_old1(456L)
  new.set_new1(-999L)
  new.set_new2("root extension")
  new.init_old3().set_new2("child extension")
  let older_view = @upstream.TestOldVersionReader::from_message(
    @capnp.read_message(new_message.finish()),
  )
  assert_eq(older_view.get_old1(), 456L)
  let copied = @capnp.Builder::new()
  copied.root_pointer().set_struct(older_view.inner)
  let recovered = @upstream.TestNewVersionReader::from_message(
    @capnp.read_message(copied.finish()),
  )
  assert_eq(recovered.get_new1(), -999L)
  assert_eq(recovered.get_new2(), "root extension")
  assert_eq(recovered.get_old3().get_new2(), "child extension")
}

///|
test "upstream union field upgrades into a group without changing older alternatives" {
  let message = @capnp.Builder::new()
  let old = @upstream.TestOldUnionVersionBuilder::init_root(message)
  old.set_a()
  let first = @upstream.TestNewUnionVersionReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_true(first.is_a())
  assert_true(first.get_a().is_a0())
  first.get_a().get_a0()
  old.set_b(9007199254740993UL)
  let second = @upstream.TestNewUnionVersionReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_true(second.is_b())
  assert_eq(second.get_b(), 9007199254740993UL)
  let nested = @capnp.Builder::new()
  let outer = @upstream.TestUnionInUnionBuilder::init_root(nested).get_outer()
  outer.init_inner().set_bar(-234)
  outer.set_baz(123456)
  let selected = @upstream.TestUnionInUnionReader::from_message(
    @capnp.read_message(nested.finish()),
  )
  assert_eq(selected.get_outer().get_baz(), 123456)
  try selected.get_outer().get_inner() catch {
    @capnp.CapnpError::TypeMismatch(_) => ()
    _ => fail("unexpected inactive nested union error")
  } noraise {
    _ => fail("inactive nested union remained readable")
  }
  ignore(outer.init_inner())
  let reset = @upstream.TestUnionInUnionReader::from_message(
    @capnp.read_message(nested.finish()),
  )
  assert_true(reset.get_outer().get_inner().is_foo())
  assert_eq(reset.get_outer().get_inner().get_foo(), 0)
}

///|
test "upstream interleaved group reset preserves adjacent data pointers and tags" {
  let message = @capnp.Builder::new()
  let root = @upstream.TestInterleavedGroupsBuilder::init_root(message)
  let first = root.get_group1()
  first.set_foo(100U)
  first.set_bar(1000UL)
  first.set_waldo("group-1")
  let first_corge = first.init_corge()
  first_corge.set_grault(10000UL)
  first_corge.set_garply(10U)
  first_corge.set_plugh("plugh-1")
  first_corge.set_xyzzy("xyzzy-1")
  let second = root.get_group2()
  second.set_foo(200U)
  second.set_bar(2000UL)
  second.set_waldo("group-2")
  let second_corge = second.init_corge()
  second_corge.set_grault(20000UL)
  second_corge.set_garply(20U)
  second_corge.set_plugh("plugh-2")
  second_corge.set_xyzzy("xyzzy-2")
  first.set_fred("replacement")
  let switched = @upstream.TestInterleavedGroupsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(switched.get_group1().get_fred(), "replacement")
  assert_eq(switched.get_group1().get_waldo(), "group-1")
  ignore(root.init_group1())
  let cleared = @upstream.TestInterleavedGroupsReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(cleared.get_group1().get_foo(), 0U)
  assert_eq(cleared.get_group1().get_bar(), 0UL)
  assert_eq(cleared.get_group1().get_waldo(), "")
  assert_eq(cleared.get_group1().get_qux(), 0U)
  for value in [switched, cleared] {
    let untouched = value.get_group2()
    assert_eq(untouched.get_foo(), 200U)
    assert_eq(untouched.get_bar(), 2000UL)
    assert_eq(untouched.get_waldo(), "group-2")
    assert_true(untouched.is_corge())
    assert_eq(untouched.get_corge().get_grault(), 20000UL)
    assert_eq(untouched.get_corge().get_garply(), 20U)
    assert_eq(untouched.get_corge().get_plugh(), "plugh-2")
    assert_eq(untouched.get_corge().get_xyzzy(), "xyzzy-2")
  }
}

///|
test "unknown upstream union discriminants cannot expose known fields and survive copying" {
  let message = @capnp.Builder::new()
  @upstream.TestUnionBuilder::init_root(message)
  .get_union0()
  .set_u0f0s32(123456)
  // These official schemas share the first discriminant's location. This
  // smaller view exercises an unknown tag; it does not redefine either schema.
  let unknown = @upstream.TestOldUnionVersionReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(unknown.which(), 4U)
  assert_false(unknown.is_a())
  assert_false(unknown.is_b())
  try unknown.get_a() catch {
    @capnp.CapnpError::TypeMismatch(_) => ()
    _ => fail("unexpected unknown union error")
  } noraise {
    _ => fail("unknown tag exposed a known union member")
  }
  let forwarded = @capnp.Builder::new()
  forwarded.root_pointer().set_struct(unknown.inner)
  let original_view = @upstream.TestUnionReader::from_message(
    @capnp.read_message(forwarded.finish()),
  )
  assert_eq(original_view.get_union0().get_u0f0s32(), 123456)
}
