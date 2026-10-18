# Cap'n Proto for MoonBit

A MoonBit implementation of Cap'n Proto serialization, with a code generator
that consumes the official schema compiler's `CodeGeneratorRequest`.

Development version. The supported feature set and interoperability results
will be documented alongside the implementation. RPC is outside the initial
scope. No performance or compatibility claim should be inferred from this
scaffold.

Requires MoonBit 0.10.14 or newer. The runtime targets Wasm, Wasm GC,
JavaScript and native code. Schema compilation uses the official `capnp` tool.

## References

- [Encoding specification](https://capnproto.org/encoding.html)
- [Compiler plugin protocol](https://capnproto.org/otherlang.html)
- [Reference implementation](https://github.com/capnproto/capnproto), MIT

The wire implementation is written from the published specification; this
repository does not use the MoonBit SWE-AGI Cap'n Proto benchmark solution.
