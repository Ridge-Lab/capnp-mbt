# Sources and licensing

The repository is MIT licensed. The runtime is a MoonBit implementation of
the [Cap'n Proto encoding specification](https://capnproto.org/encoding.html).
The generator reads the official compiler's `CodeGeneratorRequest`; it does
not implement a second schema-language parser or field-layout algorithm.

| Material | Source | Use |
| --- | --- | --- |
| Wire layout, framing, packing and evolution rules | [Cap'n Proto](https://capnproto.org/encoding.html) | Implementation specification |
| Compiler request layout | [schema.capnp, v1.5.0](https://github.com/capnproto/capnproto/blob/v1.5.0/c%2B%2B/src/capnp/schema.capnp) | Interoperable schema bootstrap |
| Reference compiler | [capnproto/capnproto](https://github.com/capnproto/capnproto), MIT | Generate external fixtures and decode our output; not a runtime dependency |
| Python peer | [pycapnp](https://github.com/capnproto/pycapnp), BSD-2-Clause | Independent example peer; installed separately |
| CLI filesystem access | [moonbitlang/x](https://github.com/moonbitlang/x), Apache-2.0 | Package dependency; not copied into this repository |

Schemas and fixture values under `fixtures/` and `examples/telemetry/` were
written for this project. Binary fixtures are compiled outputs of those
schemas and values. Regeneration commands are in `fixtures/README.md`.

Generated MoonBit files are marked as generated and are not counted as
hand-written runtime or generator implementation. The project does not use
the MoonBit SWE-AGI Cap'n Proto benchmark solution.

Code and documentation were developed with AI assistance. The maintainer
is responsible for reviewing, testing, explaining and maintaining the work.
