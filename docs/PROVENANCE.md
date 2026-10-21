# Sources and licensing

The repository is MIT licensed. The runtime implements the published Cap'n
Proto format in MoonBit; it is not an FFI wrapper. The generator consumes the
official compiler request instead of reimplementing parsing and field layout.
The compatibility baseline is the **v1.5.0** specification and schema.

| Material | Source and license | Use |
| --- | --- | --- |
| Encoding and schema-language rules | [Cap'n Proto v1.5.0 documentation](https://github.com/capnproto/capnproto/tree/v1.5.0/doc), MIT repository | Specification for runtime, generation and canonicalization |
| Compiler request schema | [schema.capnp v1.5.0](https://github.com/capnproto/capnproto/blob/v1.5.0/c%2B%2B/src/capnp/schema.capnp), MIT | Bootstrap decoder and existing-protocol fixture |
| Upstream schemas and embedded values | [Official C++ 1.5.0 distribution](https://capnproto.org/capnproto-c++-1.5.0.tar.gz), MIT | Unmodified `test.capnp`, imports, `stream.capnp`, compiler schema and required test data |
| Reference compiler | [capnproto/capnproto](https://github.com/capnproto/capnproto), MIT | Produce independent messages and canonical oracles; decode MoonBit output; no runtime dependency |
| Python peer | [pycapnp](https://github.com/capnproto/pycapnp), BSD-2-Clause | Separately installed Python binding to the C++ reference implementation |
| CLI filesystem access | [moonbitlang/x](https://github.com/moonbitlang/x), Apache-2.0 | Package dependency; not copied into this repository |

## Fixture categories

- `fixtures/upstream/capnproto-1.5.0/` contains byte-for-byte upstream files,
  including their copyright notices and [MIT license](../fixtures/upstream/capnproto-1.5.0/LICENSE.txt).
  The [manifest](../fixtures/upstream/capnproto-1.5.0/README.md) records source
  paths, hashes and dependencies. Local Git attributes preserve those bytes.
- `fixtures/upstream/oracle-1.5.0/` contains reference-generated expected
  outputs. Some inputs are upstream constants; the canonical boundary inputs
  are independently hand-authored wire vectors. Its [README](../fixtures/upstream/oracle-1.5.0/README.md)
  distinguishes these origins and provides generation commands and hashes.
- `codegen/fixtures/upstream.request.bin` and `compiler.request.bin` are
  official compiler outputs for the vendored upstream test and compiler schemas.
  Other `.capnp` schemas and values under `fixtures/`, `codegen/fixtures/` and
  `examples/telemetry/` were written for this project. Their binary messages or
  requests are compiled outputs. See [fixture regeneration](../fixtures/README.md).
- `examples/schema_compat/peer.py` is project-authored interoperability code
  that loads the unchanged upstream schema; it does not provide a simplified
  replacement protocol.

Generated MoonBit files are marked as generated. Bindings derived from the
upstream test protocol retain its provenance through the vendored source and
license; they are not counted as hand-written runtime or generator code. The
project does not use the MoonBit SWE-AGI Cap'n Proto benchmark solution.

Code and documentation were developed with AI assistance. The maintainer is
responsible for reviewing, testing, explaining and maintaining the work.
