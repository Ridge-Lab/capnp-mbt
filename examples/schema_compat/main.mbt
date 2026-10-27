///|
fn verify_generic(value : @upstream.TestUseGenericsReader) -> Unit raise {
  let basic = value.get_basic()
  let foo = basic.get_foo()
  assert_eq(foo.get_int16_field(), 12345)
  assert_eq(foo.get_u_int64_field(), 18446744073709551615UL)
  assert_eq(foo.get_text_field(), "Python/C++ generic input")
  let payload : @upstream.TestAllTypesReader = {
    inner: basic.get_rev().get_foo().get_any_pointer_field().as_struct(),
  }
  assert_eq(payload.get_int32_field(), -23456)
  assert_eq(payload.get_text_field(), "opaque struct")
  let items = basic.get_list()
  assert_eq(items.length(), 2)
  for i in 0..<items.length() {
    assert_eq(items.get(i).get_foo().get_int16_field(), i + 100)
    assert_eq(
      items.get(i).get_bar().get_any_pointer_field().as_text(),
      "item-\{i}",
    )
  }
  let inner = value.get_inner2()
  assert_eq(inner.get_baz(), "ancestor-binding")
  let numbers = inner.get_bar().get_any_pointer_field().as_list()
  assert_eq(numbers.get_uint32(0), 12U)
  assert_eq(numbers.get_uint32(1), 34U)
  assert_eq(numbers.get_uint32(2), 4294967295U)
  assert_eq(inner.get_inner_bound().get_foo().get_int16_field(), 6789)
  assert_eq(inner.get_inner_unbound().get_foo().as_text(), "unbound ancestor")
  assert_eq(value.get_unspecified().get_foo().as_text(), "unbound parameter")
  assert_eq(value.get_bind_enum_list().get_foo().get(0).to_raw(), 0U)
  assert_eq(value.get_bind_enum_list().get_foo().get(1).to_raw(), 7U)
  assert_eq(value.get_bind_enum_list().get_foo().length(), 3)
  assert_eq(value.get_bind_enum_list().get_foo().get(2).to_raw(), 40000U)
  let defaults = value.get_default()
  assert_eq(defaults.get_foo().get_int16_field(), 123)
  assert_eq(defaults.get_rev().get_foo(), "text")
  assert_eq(defaults.get_rev().get_rev().get_foo().get_int16_field(), 321)
  assert_eq(value.get_alias_inner2_bind().get_baz().get(1), 34U)
  assert_eq(value.get_use_aliases().get_rev_foo().get(2), 56U)
}

///|
fn generic_reply(source : @upstream.TestUseGenericsReader) -> Bytes raise {
  let message = @capnp.Builder::new()
  let root = @upstream.TestUseGenericsBuilder::init_root(message)
  let basic = root.init_basic()
  let foo = basic.init_foo()
  foo.set_int16_field(23456)
  foo.set_u_int64_field(18446744073709551615UL)
  foo.set_text_field("MoonBit typed reply")
  basic
  .init_rev()
  .init_foo()
  .set_any_pointer_field(
    source.get_basic().get_rev().get_foo().get_any_pointer_field(),
  )
  let items = basic.init_list(2)
  for i in 0..<2 {
    items.get(i).init_foo().set_int16_field(i + 100)
    items.get(i).init_bar().init_any_pointer_field().set_text("item-\{i}")
  }
  let inner = root.init_inner2()
  inner.set_baz("ancestor-binding")
  inner
  .init_bar()
  .set_any_pointer_field(source.get_inner2().get_bar().get_any_pointer_field())
  inner.init_inner_bound().init_foo().set_int16_field(6789)
  inner.init_inner_unbound().init_foo().set_text("unbound ancestor")
  root.init_unspecified().init_foo().set_text("unbound parameter")
  let enums = root.init_bind_enum_list().init_foo(3)
  enums.set(0, @upstream.TestEnum::from_raw(0U))
  enums.set(1, @upstream.TestEnum::from_raw(7U))
  enums.set(2, @upstream.TestEnum::from_raw(40000U))
  message.finish()
}

///|
fn copy_any(directory : String, kind : String) -> Unit raise {
  let bytes = @fs.read_file_to_bytes(directory + "/python-any-" + kind + ".bin")
  let source = @upstream.TestAnyPointerReader::from_message(
    @capnp.read_message(bytes),
  )
  let pointer = source.get_any_pointer_field()
  match kind {
    "struct" => {
      let value : @upstream.TestAllTypesReader = { inner: pointer.as_struct(), }
      assert_eq(value.get_int64_field(), -9223372036854775807L - 1)
      assert_eq(value.get_text_field(), "unknown fields survive copying")
    }
    "list" => {
      let values = pointer.as_list()
      assert_eq(values.get_int32(0), -2147483648)
      assert_eq(values.get_int32(2), 2147483647)
    }
    "text" => assert_eq(pointer.as_text(), "AnyPointer 中文")
    "data" => assert_eq(pointer.as_data(), b"\x00\xff\x01\x80")
    _ => assert_true(pointer.is_null())
  }
  let message = @capnp.Builder::new()
  @upstream.TestAnyPointerBuilder::init_root(message).set_any_pointer_field(
    pointer,
  )
  @fs.write_bytes_to_file(
    directory + "/moon-any-" + kind + ".bin",
    message.finish(),
  )
}

///|
fn write_struct(path : String, value : @capnp.StructReader) -> Unit raise {
  let message = @capnp.Builder::new()
  message.root_pointer().set_struct(value)
  @fs.write_bytes_to_file(path, message.finish())
}

///|
fn verify_compiler(directory : String) -> Unit raise {
  let source = @capnp.read_message(
    @fs.read_file_to_bytes("codegen/fixtures/upstream.request.bin"),
  )
  let request = @compiler.CodeGeneratorRequestReader::from_message(source)
  assert_eq(request.get_capnp_version().get_major(), 1U)
  assert_eq(request.get_capnp_version().get_minor().to_uint(), 5U)
  assert_eq(
    request.get_requested_files().get(0).get_filename(),
    "capnp/test.capnp",
  )
  let nodes = request.get_nodes()
  let mut generic_id = 0UL
  let mut all_types_id = 0UL
  let mut any_pointer_id = 0UL
  for i in 0..<nodes.length() {
    let node = nodes.get(i)
    match node.get_display_name() {
      "capnp/test.capnp:TestGenerics" => generic_id = node.get_id()
      "capnp/test.capnp:TestAllTypes" => all_types_id = node.get_id()
      "capnp/test.capnp:TestAnyPointer" => any_pointer_id = node.get_id()
      _ => ()
    }
  }
  assert_true(generic_id != 0UL && all_types_id != 0UL && any_pointer_id != 0UL)
  let mut saw_generic = false
  let mut saw_brand = false
  let mut saw_constant = false
  for i in 0..<nodes.length() {
    let node = nodes.get(i)
    let name = node.get_display_name()
    if name.has_suffix(":TestGenerics") {
      assert_true(node.get_is_generic())
      assert_eq(node.get_parameters().length(), 2)
      assert_eq(node.get_parameters().get(0).get_name(), "Foo")
      assert_eq(node.get_parameters().get(1).get_name(), "Bar")
      saw_generic = true
    }
    if name.has_suffix(":TestUseGenerics") {
      let fields = node.get_struct().get_fields()
      let bound_type = fields.get(0).get_slot().get_type().get_struct()
      assert_eq(fields.get(0).get_name(), "basic")
      assert_eq(bound_type.get_type_id(), generic_id)
      let scopes = bound_type.get_brand().get_scopes()
      assert_eq(scopes.length(), 1)
      let scope = scopes.get(0)
      assert_eq(scope.get_scope_id(), generic_id)
      assert_true(scope.is_bind())
      let bindings = scope.get_bind()
      assert_eq(bindings.length(), 2)
      assert_true(bindings.get(0).is_type() && bindings.get(1).is_type())
      assert_true(bindings.get(0).get_type().is_struct())
      assert_true(bindings.get(1).get_type().is_struct())
      assert_eq(
        bindings.get(0).get_type().get_struct().get_type_id(),
        all_types_id,
      )
      assert_eq(
        bindings.get(1).get_type().get_struct().get_type_id(),
        any_pointer_id,
      )
      assert_eq(
        bindings
        .get(0)
        .get_type()
        .get_struct()
        .get_brand()
        .get_scopes()
        .length(),
        0,
      )
      assert_eq(
        bindings
        .get(1)
        .get_type()
        .get_struct()
        .get_brand()
        .get_scopes()
        .length(),
        0,
      )
      saw_brand = true
    }
    if name.has_suffix(":genericConstant") {
      let pointer = node.get_const().get_value().get_struct()
      let value : @upstream.TestGenericsAsTestAllTypesAndTextReader = {
        inner: pointer.as_struct(),
      }
      assert_eq(value.get_foo().get_int16_field(), 123)
      assert_eq(value.get_rev().get_foo(), "text")
      saw_constant = true
    }
  }
  assert_true(saw_generic && saw_brand && saw_constant)
  let reply = @capnp.Builder::new()
  let root = @compiler.CodeGeneratorRequestBuilder::init_root(reply)
  root.set_nodes(nodes)
  root.set_requested_files(request.get_requested_files())
  root.set_capnp_version(request.get_capnp_version())
  root.set_source_info(request.get_source_info())
  @fs.write_bytes_to_file(
    directory + "/moon-compiler-request.bin",
    reply.finish(),
  )
}

///|
fn expect_inactive(action : () -> Unit raise @capnp.CapnpError) -> Unit raise {
  try action() catch {
    @capnp.CapnpError::TypeMismatch(_) => ()
    _ => fail("unexpected error for inactive union member")
  } noraise {
    _ => fail("unknown discriminant exposed a known union member")
  }
}

///|
fn verify_evolution(directory : String) -> Unit raise {
  let old_as_new = @upstream.TestNewVersionReader::from_message(
    @capnp.read_message(
      @fs.read_file_to_bytes(directory + "/python-old-version.bin"),
    ),
  )
  assert_eq(old_as_new.get_old1(), 123L)
  assert_eq(old_as_new.get_old2(), "old root")
  assert_eq(old_as_new.get_new1(), 987L)
  assert_eq(old_as_new.get_new2(), "baz")
  assert_eq(old_as_new.get_old3().get_old1(), -456L)
  assert_eq(old_as_new.get_old3().get_old2(), "old child")
  assert_eq(old_as_new.get_old3().get_new1(), 987L)
  assert_eq(old_as_new.get_old3().get_new2(), "baz")
  let old_reply = @capnp.Builder::new()
  let old = @upstream.TestOldVersionBuilder::init_root(old_reply)
  old.set_old1(777L)
  old.set_old2("MoonBit old root")
  let child = old.init_old3()
  child.set_old1(-777L)
  child.set_old2("MoonBit old child")
  @fs.write_bytes_to_file(
    directory + "/moon-old-version.bin",
    old_reply.finish(),
  )
  let new_as_old = @upstream.TestOldVersionReader::from_message(
    @capnp.read_message(
      @fs.read_file_to_bytes(directory + "/python-new-version.bin"),
    ),
  )
  assert_eq(new_as_old.get_old1(), 123L)
  assert_eq(new_as_old.get_old2(), "new root")
  assert_eq(new_as_old.get_old3().get_old1(), -456L)
  assert_eq(new_as_old.get_old3().get_old2(), "new child")
  // Forward through an older typed view without enumerating its known fields.
  write_struct(directory + "/moon-new-via-old.bin", new_as_old.inner)
  for alternative in ["a", "b"] {
    let upgraded = @upstream.TestNewUnionVersionReader::from_message(
      @capnp.read_message(
        @fs.read_file_to_bytes(
          directory + "/python-old-union-" + alternative + ".bin",
        ),
      ),
    )
    if alternative == "a" {
      assert_true(upgraded.is_a())
      assert_true(upgraded.get_a().is_a0())
      upgraded.get_a().get_a0()
    } else {
      assert_true(upgraded.is_b())
      assert_eq(upgraded.get_b(), 9007199254740993UL)
    }
  }
  let union_reply = @capnp.Builder::new()
  @upstream.TestNewUnionVersionBuilder::init_root(union_reply)
  .init_a()
  .set_a1(18446744073709551615UL)
  @fs.write_bytes_to_file(
    directory + "/moon-new-union.bin",
    union_reply.finish(),
  )
  let unknown = @upstream.TestOldUnionVersionReader::from_message(
    @capnp.read_message(
      @fs.read_file_to_bytes(directory + "/python-unknown-union.bin"),
    ),
  )
  assert_eq(unknown.which(), 4U)
  assert_false(unknown.is_a())
  assert_false(unknown.is_b())
  expect_inactive(() => unknown.get_a())
  expect_inactive(() => ignore(unknown.get_b()))
  write_struct(directory + "/moon-unknown-union.bin", unknown.inner)
}

///|
fn verify_union_groups(directory : String) -> Unit raise {
  let nested = @upstream.TestUnionInUnionReader::from_message(
    @capnp.read_message(
      @fs.read_file_to_bytes(directory + "/python-nested-union.bin"),
    ),
  )
  assert_true(nested.get_outer().is_inner())
  assert_true(nested.get_outer().get_inner().is_bar())
  assert_eq(nested.get_outer().get_inner().get_bar(), -234)
  let nested_reply = @capnp.Builder::new()
  let outer = @upstream.TestUnionInUnionBuilder::init_root(nested_reply).get_outer()
  outer.init_inner().set_bar(-234)
  outer.set_baz(123456)
  @fs.write_bytes_to_file(
    directory + "/moon-nested-baz.bin",
    nested_reply.finish(),
  )
  ignore(outer.init_inner())
  @fs.write_bytes_to_file(
    directory + "/moon-nested-reset.bin",
    nested_reply.finish(),
  )
  let input = @upstream.TestInterleavedGroupsReader::from_message(
    @capnp.read_message(
      @fs.read_file_to_bytes(directory + "/python-interleaved.bin"),
    ),
  )
  let first = input.get_group1()
  let second = input.get_group2()
  assert_eq(first.get_foo(), 100U)
  assert_eq(first.get_bar(), 1000UL)
  assert_eq(first.get_waldo(), "group-1")
  assert_eq(first.get_corge().get_grault(), 10000UL)
  assert_eq(first.get_corge().get_garply(), 10U)
  assert_eq(first.get_corge().get_plugh(), "plugh-1")
  assert_eq(first.get_corge().get_xyzzy(), "xyzzy-1")
  assert_eq(second.get_foo(), 200U)
  assert_eq(second.get_bar(), 2000UL)
  assert_eq(second.get_waldo(), "group-2")
  assert_eq(second.get_corge().get_grault(), 20000UL)
  assert_eq(second.get_corge().get_garply(), 20U)
  assert_eq(second.get_corge().get_plugh(), "plugh-2")
  assert_eq(second.get_corge().get_xyzzy(), "xyzzy-2")
  let reply = @capnp.Builder::new()
  let root = @upstream.TestInterleavedGroupsBuilder::init_root(reply)
  let group1 = root.get_group1()
  group1.set_foo(first.get_foo())
  group1.set_bar(first.get_bar())
  group1.set_waldo(first.get_waldo())
  let corge1 = group1.init_corge()
  corge1.set_grault(first.get_corge().get_grault())
  corge1.set_garply(first.get_corge().get_garply())
  corge1.set_plugh(first.get_corge().get_plugh())
  corge1.set_xyzzy(first.get_corge().get_xyzzy())
  let group2 = root.get_group2()
  group2.set_foo(second.get_foo())
  group2.set_bar(second.get_bar())
  group2.set_waldo(second.get_waldo())
  let corge2 = group2.init_corge()
  corge2.set_grault(second.get_corge().get_grault())
  corge2.set_garply(second.get_corge().get_garply())
  corge2.set_plugh(second.get_corge().get_plugh())
  corge2.set_xyzzy(second.get_corge().get_xyzzy())
  group1.set_fred("replacement")
  @fs.write_bytes_to_file(directory + "/moon-interleaved.bin", reply.finish())
  ignore(root.init_group1())
  @fs.write_bytes_to_file(
    directory + "/moon-interleaved-reset.bin",
    reply.finish(),
  )
}

///|
fn main raise {
  let args = @stdio.args()
  guard args.length() == 2 else {
    println(
      "Usage: schema_compat DIRECTORY (first run peer.py prepare DIRECTORY)",
    )
    @stdio.exit(2)
    return
  }
  let directory = args[1]
  verify_evolution(directory)
  verify_union_groups(directory)
  let raw = @fs.read_file_to_bytes(directory + "/python-generics.bin")
  let message = @capnp.read_message(raw)
  assert_true(message.segment_count() > 1)
  let source = @upstream.TestUseGenericsReader::from_message(message)
  verify_generic(source)
  let packed = @fs.read_file_to_bytes(directory + "/python-generics.packed.bin")
  verify_generic(
    @upstream.TestUseGenericsReader::from_message(
      @capnp.read_message(@capnp.unpack(packed)),
    ),
  )
  @fs.write_bytes_to_file(
    directory + "/moon-generics.bin",
    generic_reply(source),
  )
  for kind in ["struct", "list", "text", "data", "null"] {
    copy_any(directory, kind)
  }
  let constrained = @upstream.TestAnyOthersReader::from_message(
    @capnp.read_message(
      @fs.read_file_to_bytes(directory + "/python-constrained.bin"),
    ),
  )
  let typed : @upstream.TestAllTypesReader = {
    inner: constrained.get_any_struct_field(),
  }
  assert_eq(typed.get_int32_field(), -123456)
  assert_eq(constrained.get_any_list_field().get_int32(1), -456)
  assert_true(constrained.get_capability_field().is_null())
  let reply = @capnp.Builder::new()
  let target = @upstream.TestAnyOthersBuilder::init_root(reply)
  target.set_any_struct_field(constrained.get_any_struct_field())
  target.set_any_list_field(constrained.get_any_list_field())
  @fs.write_bytes_to_file(directory + "/moon-constrained.bin", reply.finish())
  write_struct(
    directory + "/moon-generic-constant.bin",
    @upstream.const_generic_constant().inner,
  )
  write_struct(
    directory + "/moon-any-constants.bin",
    @upstream.const_any_pointer_constants().inner,
  )
  write_struct(
    directory + "/moon-embedded-constant.bin",
    @upstream.const_embedded_struct().inner,
  )
  let embedded_data = @upstream.const_embedded_data()
  let embedded_text = @upstream.const_embedded_text()
  assert_eq(
    embedded_data,
    @fs.read_file_to_bytes(directory + "/python-embedded-data.bin"),
  )
  assert_eq(
    embedded_text,
    @fs.read_file_to_string(directory + "/python-embedded-text.bin"),
  )
  @fs.write_bytes_to_file(directory + "/moon-embedded-data.bin", embedded_data)
  @fs.write_string_to_file(directory + "/moon-embedded-text.bin", embedded_text)
  verify_compiler(directory)
  println(
    "Verified unchanged upstream schema values; wrote typed reply and constants",
  )
}
