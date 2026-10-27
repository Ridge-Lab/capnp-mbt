"""Independent Python/C++ peer for unchanged Cap'n Proto 1.5.0 schemas.

Run from the repository root. No replacement schema is created: both peers use
the original test.capnp, including its imports, generics, constants and RPC
declarations. The messages here contain data, not live RPC capabilities.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import capnp


ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / "fixtures" / "upstream" / "capnproto-1.5.0"
SCHEMA = capnp.load(str(UPSTREAM / "capnp" / "test.capnp"), imports=[str(UPSTREAM)])
INT32_LIST = capnp._ListSchema(capnp.types.Int32)
UINT32_LIST = capnp._ListSchema(capnp.types.UInt32)
UINT8_LIST = capnp._ListSchema(capnp.types.UInt8)
UINT16_LIST = capnp._ListSchema(capnp.types.UInt16)


def prepare_evolution(directory: Path) -> None:
    old = SCHEMA.TestOldVersion.new_message(num_first_segment_words=1)
    old.old1, old.old2 = 123, "old root"
    old.init("old3").old1 = -456
    old.old3.old2 = "old child"
    (directory / "python-old-version.bin").write_bytes(old.to_bytes())

    new = SCHEMA.TestNewVersion.new_message(num_first_segment_words=1)
    new.old1, new.old2 = 123, "new root"
    new.new1, new.new2 = -999, "root extension"
    child = new.init("old3")
    child.old1, child.old2 = -456, "new child"
    child.new1, child.new2 = -888, "child extension"
    (directory / "python-new-version.bin").write_bytes(new.to_bytes())

    for alternative in ("a", "b"):
        union = SCHEMA.TestOldUnionVersion.new_message()
        setattr(union, alternative, None if alternative == "a" else 9007199254740993)
        (directory / f"python-old-union-{alternative}.bin").write_bytes(union.to_bytes())

    nested = SCHEMA.TestUnionInUnion.new_message()
    nested.init("outer").init("inner").bar = -234
    (directory / "python-nested-union.bin").write_bytes(nested.to_bytes())

    interleaved = SCHEMA.TestInterleavedGroups.new_message(num_first_segment_words=1)
    for index in (1, 2):
        group = interleaved.init(f"group{index}")
        group.foo, group.bar, group.waldo = index * 100, index * 1000, f"group-{index}"
        corge = group.init("corge")
        corge.grault, corge.garply = index * 10000, index * 10
        corge.plugh, corge.xyzzy = f"plugh-{index}", f"xyzzy-{index}"
    (directory / "python-interleaved.bin").write_bytes(interleaved.to_bytes())

    # Both existing declarations put their discriminant at the same location.
    # The C++ builder emits a legal TestUnion alternative that the smaller
    # TestOldUnionVersion view does not know. No schema or bytes are modified.
    # This is a discriminant-guard test, not a claim these types are versions.
    larger_union = SCHEMA.TestUnion.new_message()
    larger_union.union0.u0f0s32 = 123456
    assert SCHEMA.TestUnion.schema.fields["union0"].schema.node.struct.discriminantOffset == SCHEMA.TestOldUnionVersion.schema.node.struct.discriminantOffset
    unknown = larger_union.to_bytes()
    with SCHEMA.TestOldUnionVersion.from_bytes(unknown) as smaller_view:
        for field in ("a", "b"):
            try:
                getattr(smaller_view, field)
            except capnp.KjException:
                pass
            else:
                raise AssertionError("C++ exposed a known member for an unknown discriminant")
    (directory / "python-unknown-union.bin").write_bytes(unknown)


def verify_evolution(directory: Path) -> None:
    with SCHEMA.TestNewVersion.from_bytes((directory / "moon-old-version.bin").read_bytes()) as value:
        assert (value.old1, value.old2) == (777, "MoonBit old root")
        assert (value.new1, value.new2) == (987, "baz")
        assert (value.old3.old1, value.old3.old2) == (-777, "MoonBit old child")
        assert (value.old3.new1, value.old3.new2) == (987, "baz")
    with SCHEMA.TestNewVersion.from_bytes((directory / "moon-new-via-old.bin").read_bytes()) as value:
        assert (value.old1, value.old2, value.new1, value.new2) == (123, "new root", -999, "root extension")
        assert (value.old3.old1, value.old3.old2, value.old3.new1, value.old3.new2) == (-456, "new child", -888, "child extension")
    upgraded = (directory / "moon-new-union.bin").read_bytes()
    with SCHEMA.TestNewUnionVersion.from_bytes(upgraded) as value:
        assert value.which() == "a" and value.a.which() == "a1"
        assert value.a.a1 == 18446744073709551615
    with SCHEMA.TestOldUnionVersion.from_bytes(upgraded) as value:
        assert value.which() == "a" and value.a is None
    with SCHEMA.TestUnionInUnion.from_bytes((directory / "moon-nested-baz.bin").read_bytes()) as value:
        assert value.outer.which() == "baz" and value.outer.baz == 123456
    with SCHEMA.TestUnionInUnion.from_bytes((directory / "moon-nested-reset.bin").read_bytes()) as value:
        assert value.outer.which() == "inner" and value.outer.inner.which() == "foo"
        assert value.outer.inner.foo == 0
    for name, reset in (("moon-interleaved.bin", False), ("moon-interleaved-reset.bin", True)):
        with SCHEMA.TestInterleavedGroups.from_bytes((directory / name).read_bytes()) as value:
            if reset:
                assert (value.group1.foo, value.group1.bar, value.group1.waldo) == (0, 0, "")
                assert value.group1.which() == "qux" and value.group1.qux == 0
            else:
                assert (value.group1.foo, value.group1.bar, value.group1.waldo) == (100, 1000, "group-1")
                assert value.group1.which() == "fred" and value.group1.fred == "replacement"
            assert (value.group2.foo, value.group2.bar, value.group2.waldo) == (200, 2000, "group-2")
            assert value.group2.which() == "corge"
            assert (value.group2.corge.grault, value.group2.corge.garply) == (20000, 20)
            assert (value.group2.corge.plugh, value.group2.corge.xyzzy) == ("plugh-2", "xyzzy-2")
    with SCHEMA.TestUnion.from_bytes((directory / "moon-unknown-union.bin").read_bytes()) as value:
        assert value.union0.which() == "u0f0s32" and value.union0.u0f0s32 == 123456


def prepare(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    prepare_evolution(directory)
    # A small initial segment deliberately exercises far-pointer decoding.
    message = SCHEMA.TestUseGenerics.new_message(num_first_segment_words=1)
    basic = message.init("basic")
    foo = basic.init("foo")
    foo.int16Field = 12345
    foo.uInt64Field = 18446744073709551615
    foo.textField = "Python/C++ generic input"
    reverse = basic.init("rev").init("foo")
    opaque = reverse.anyPointerField.as_struct(SCHEMA.TestAllTypes)
    opaque.int32Field = -23456
    opaque.textField = "opaque struct"
    items = basic.init("list", 2)
    for index, item in enumerate(items):
        item.init("foo").int16Field = index + 100
        item.init("bar").anyPointerField.set_as_text(f"item-{index}")
    inner = message.init("inner2")
    inner.baz = "ancestor-binding"
    numbers = inner.init("bar").anyPointerField.init_as_list(UINT32_LIST, 3)
    for index, number in enumerate([12, 34, 4294967295]):
        numbers[index] = number
    inner.init("innerBound").init("foo").int16Field = 6789
    inner.init("innerUnbound").foo.set_as_text("unbound ancestor")
    message.init("unspecified").foo.set_as_text("unbound parameter")
    # pycapnp's enum-list setter accepts named values, not an unknown integer.
    # Populate the unchanged generic's unbound view with the standard UInt16
    # representation, then read the same object with the original bound schema.
    # This uses C++ builders throughout, without editing schema or wire bytes.
    enum_message = capnp._MallocMessageBuilder()
    enum_values = enum_message.init_root(SCHEMA.TestGenerics).foo.init_as_list(UINT16_LIST, 3)
    for index, ordinal in enumerate([0, 7, 40000]):
        enum_values[index] = ordinal
    enum_schema = SCHEMA.TestUseGenerics.schema.fields["bindEnumList"].schema
    message.bindEnumList = enum_message.get_root(enum_schema)
    assert [item.raw for item in message.bindEnumList.foo] == [0, 7, 40000]
    plain = message.to_bytes()
    assert int.from_bytes(plain[:4], "little") > 0, "expected multiple segments"
    (directory / "python-generics.bin").write_bytes(plain)
    message.clear_write_flag()
    (directory / "python-generics.packed.bin").write_bytes(message.to_bytes_packed())

    for kind in ("struct", "list", "text", "data", "null"):
        value = SCHEMA.TestAnyPointer.new_message(num_first_segment_words=1)
        pointer = value.anyPointerField
        if kind == "struct":
            payload = pointer.as_struct(SCHEMA.TestAllTypes)
            payload.int64Field = -9223372036854775808
            payload.textField = "unknown fields survive copying"
        elif kind == "list":
            values = pointer.init_as_list(INT32_LIST, 3)
            for index, number in enumerate([-2147483648, 0, 2147483647]):
                values[index] = number
        elif kind == "text":
            pointer.set_as_text("AnyPointer 中文")
        elif kind == "data":
            values = pointer.init_as_list(UINT8_LIST, 4)
            for index, number in enumerate([0, 255, 1, 128]):
                values[index] = number
        (directory / f"python-any-{kind}.bin").write_bytes(value.to_bytes())

    constrained = SCHEMA.TestAnyOthers.new_message(num_first_segment_words=1)
    constrained.anyStructField.as_struct(SCHEMA.TestAllTypes).int32Field = -123456
    values = constrained.anyListField.init_as_list(INT32_LIST, 2)
    values[0], values[1] = 123, -456
    (directory / "python-constrained.bin").write_bytes(constrained.to_bytes())
    embedded_data = bytes(SCHEMA.embeddedData)
    embedded_text = SCHEMA.embeddedText.encode("utf-8")
    assert embedded_data == (UPSTREAM / "capnp/testdata/packed").read_bytes()
    assert embedded_text == (UPSTREAM / "capnp/testdata/short.txt").read_bytes()
    (directory / "python-embedded-data.bin").write_bytes(embedded_data)
    (directory / "python-embedded-text.bin").write_bytes(embedded_text)
    print(f"pycapnp {capnp.__version__}: wrote segmented generic and AnyPointer inputs")


def verify(directory: Path) -> None:
    verify_evolution(directory)
    with SCHEMA.TestUseGenerics.from_bytes((directory / "moon-generics.bin").read_bytes()) as value:
        assert value.basic.foo.int16Field == 23456
        assert value.basic.foo.uInt64Field == 18446744073709551615
        assert value.basic.foo.textField == "MoonBit typed reply"
        assert value.basic.rev.foo.anyPointerField.as_struct(SCHEMA.TestAllTypes).int32Field == -23456
        assert [item.foo.int16Field for item in value.basic.list] == [100, 101]
        assert value.basic.list[1].bar.anyPointerField.as_text() == "item-1"
        assert value.inner2.baz == "ancestor-binding"
        assert list(value.inner2.bar.anyPointerField.as_list(UINT32_LIST)) == [12, 34, 4294967295]
        assert value.inner2.innerBound.foo.int16Field == 6789
        assert value.inner2.innerUnbound.foo.as_text() == "unbound ancestor"
        assert value.unspecified.foo.as_text() == "unbound parameter"
        assert [item.raw for item in value.bindEnumList.foo] == [0, 7, 40000]
        # Absent pointers must retain the original schema's generic defaults.
        assert value.default.foo.int16Field == 123
        assert value.default.rev.foo == "text"
        assert value.default.rev.rev.foo.int16Field == 321
        assert list(value.aliasInner2Bind.baz) == [12, 34]
        assert list(value.useAliases.revFoo) == [12, 34, 56]

    for kind in ("struct", "list", "text", "data", "null"):
        with SCHEMA.TestAnyPointer.from_bytes((directory / f"moon-any-{kind}.bin").read_bytes()) as value:
            pointer = value.anyPointerField
            if kind == "struct":
                payload = pointer.as_struct(SCHEMA.TestAllTypes)
                assert payload.int64Field == -9223372036854775808
                assert payload.textField == "unknown fields survive copying"
            elif kind == "list":
                assert list(pointer.as_list(INT32_LIST)) == [-2147483648, 0, 2147483647]
            elif kind == "text":
                assert pointer.as_text() == "AnyPointer 中文"
            elif kind == "data":
                assert bytes(pointer.as_list(UINT8_LIST)) == b"\x00\xff\x01\x80"
            else:
                assert not value._has("anyPointerField")

    with SCHEMA.TestAnyOthers.from_bytes((directory / "moon-constrained.bin").read_bytes()) as value:
        assert value.anyStructField.as_struct(SCHEMA.TestAllTypes).int32Field == -123456
        assert list(value.anyListField.as_list(INT32_LIST)) == [123, -456]
        assert not value._has("capabilityField")
    with SCHEMA.TestGenerics.from_bytes((directory / "moon-generic-constant.bin").read_bytes()) as value:
        assert value.foo.as_struct(SCHEMA.TestAllTypes).int16Field == 123
        assert value.rev.foo.as_text() == "text"
        assert value.rev.rev.foo.as_struct(SCHEMA.TestAllTypes).int16Field == 321
    with SCHEMA.TestAnyPointerConstants.from_bytes((directory / "moon-any-constants.bin").read_bytes()) as value:
        assert value.anyKindAsStruct.as_struct(SCHEMA.TestAllTypes).int16Field == 3456
        assert value.anyStructAsStruct.as_struct(SCHEMA.TestAllTypes).textField == "baz"
        assert list(value.anyKindAsList.as_list(INT32_LIST)) == [111111111, -111111111]
        assert list(value.anyListAsList.as_list(INT32_LIST)) == [111111111, -111111111]
    with SCHEMA.TestAllTypes.from_bytes((directory / "moon-embedded-constant.bin").read_bytes()) as value:
        assert value.uInt64Field == 12345678901234567890
        assert value.structField.textField == "baz"
        assert list(value.int32List) == [111111111, -111111111]
    assert (directory / "moon-embedded-data.bin").read_bytes() == bytes(SCHEMA.embeddedData)
    assert (directory / "moon-embedded-data.bin").read_bytes() == (UPSTREAM / "capnp/testdata/packed").read_bytes()
    assert (directory / "moon-embedded-text.bin").read_bytes() == SCHEMA.embeddedText.encode("utf-8")
    assert (directory / "moon-embedded-text.bin").read_bytes() == (UPSTREAM / "capnp/testdata/short.txt").read_bytes()
    verify_compiler_request(directory / "moon-compiler-request.bin")
    print("Verified MoonBit output: generics, AnyPointer, constants, schema evolution and union/group transitions")


def verify_compiler_request(path: Path) -> None:
    compiler = capnp.load(str(UPSTREAM / "capnp" / "schema.capnp"), imports=[str(UPSTREAM)])
    with compiler.CodeGeneratorRequest.from_bytes(path.read_bytes()) as request:
        assert (request.capnpVersion.major, request.capnpVersion.minor) == (1, 5)
        assert request.requestedFiles[0].filename == "capnp/test.capnp"
        nodes = {node.displayName: node for node in request.nodes}
        generic = nodes["capnp/test.capnp:TestGenerics"]
        assert generic.isGeneric and len(generic.parameters) == 2
        assert generic.id == SCHEMA.TestGenerics.schema.node.id
        assert [parameter.name for parameter in generic.parameters] == ["Foo", "Bar"]
        use_generics = nodes["capnp/test.capnp:TestUseGenerics"]
        basic = next(field for field in use_generics.struct.fields if field.name == "basic")
        assert basic.which() == "slot" and basic.slot.type.which() == "struct"
        bound_type = basic.slot.type.struct
        assert bound_type.typeId == SCHEMA.TestGenerics.schema.node.id
        assert len(bound_type.brand.scopes) == 1
        scope = bound_type.brand.scopes[0]
        assert scope.scopeId == SCHEMA.TestGenerics.schema.node.id and scope.which() == "bind"
        assert len(scope.bind) == 2
        expected_ids = [SCHEMA.TestAllTypes.schema.node.id, SCHEMA.TestAnyPointer.schema.node.id]
        for binding, expected_id in zip(scope.bind, expected_ids):
            assert binding.which() == "type" and binding.type.which() == "struct"
            assert binding.type.struct.typeId == expected_id
            assert len(binding.type.struct.brand.scopes) == 0
        constant = nodes["capnp/test.capnp:genericConstant"].const.value.struct
        assert constant.as_struct(SCHEMA.TestGenerics).foo.as_struct(SCHEMA.TestAllTypes).int16Field == 123


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "verify"))
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    (prepare if args.action == "prepare" else verify)(args.directory)
