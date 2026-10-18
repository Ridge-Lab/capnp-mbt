# Interoperability fixtures

`conformance.capnp`, `conformance.txt` and `defaults.txt` were written for
this project and use the repository MIT license. Binary files are outputs
of the official Cap'n Proto 1.5.0 compiler, not outputs of this runtime.

From the repository root, with `capnp` on PATH:

```sh
capnp compile -o- fixtures/conformance.capnp > fixtures/conformance.request.bin
capnp encode fixtures/conformance.capnp Fixture < fixtures/conformance.txt > fixtures/conformance.bin
capnp encode --packed fixtures/conformance.capnp Fixture < fixtures/conformance.txt > fixtures/conformance.packed.bin
capnp encode --segment-size=2 fixtures/conformance.capnp Fixture < fixtures/conformance.txt > fixtures/conformance.segmented.bin
capnp encode fixtures/conformance.capnp Fixture < fixtures/defaults.txt > fixtures/defaults.bin
```

Use a shell that preserves binary redirection, such as Bash or `cmd.exe`.
The small segment size deliberately produces inter-segment pointers.
Cap'n Proto source: <https://github.com/capnproto/capnproto>, MIT license.

The data covers integer extremes, nonzero scalar defaults, float values,
UTF-8, binary data, nested structs, inline-composite lists, every primitive
list width, pointer lists, nested lists, enums, a union and a named group.
