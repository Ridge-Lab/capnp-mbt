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


def prepare(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
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
    message.init("bindEnumList").foo = ["foo", "garply"]
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
    print(f"pycapnp {capnp.__version__}: wrote segmented generic and AnyPointer inputs")


def verify(directory: Path) -> None:
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
        assert [str(item) for item in value.bindEnumList.foo] == ["foo", "garply"]
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
    compiler = capnp.load(str(UPSTREAM / "capnp" / "schema.capnp"), imports=[str(UPSTREAM)])
    with compiler.CodeGeneratorRequest.from_bytes((directory / "moon-compiler-request.bin").read_bytes()) as request:
        assert (request.capnpVersion.major, request.capnpVersion.minor) == (1, 5)
        assert request.requestedFiles[0].filename == "capnp/test.capnp"
        nodes = {node.displayName: node for node in request.nodes}
        generic = nodes["capnp/test.capnp:TestGenerics"]
        assert generic.isGeneric and len(generic.parameters) == 2
        constant = nodes["capnp/test.capnp:genericConstant"].const.value.struct
        assert constant.as_struct(SCHEMA.TestGenerics).foo.as_struct(SCHEMA.TestAllTypes).int16Field == 123
    print("Verified MoonBit output: bound/nested/unbound generics, AnyPointer kinds, defaults and constants")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "verify"))
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    (prepare if args.action == "prepare" else verify)(args.directory)
