# Changelog

## 0.3.0

- Add bounded `FrameDecoder` incremental standard-frame decoding, explicit EOF validation, failure/finished states and reset. Test arbitrary splits, concatenated frames, hostile lengths and a 65,552-byte frame arriving one byte at a time.
- Add a pipe-based telemetry application using bounded stdin chunks. Python/C++ produces and verifies the unchanged protocol; MoonBit filters invalid readings and computes each report without retaining the entire stream. Exact binary64 accumulation preserves cancellation residuals and rounds the mean once, including subnormal ties. Check empty/all-invalid batches, 64-bit IDs, Unicode, overflowing intermediate sums and error exits.
- Read native stdin chunks with a single operating-system read, so an interactive sender can receive a reply before closing its input. Verify successive request/reply exchanges on native and Node.js.
- Verify original upstream old/new protocol evolution, unknown-field forwarding, nested unions, interleaved groups and unknown discriminant guards with independent Python/C++ peers.
- Add reproducible native/JS benchmarks with calibrated loops, warmup, raw rounds, checksums, environment and source hashes; publish measurements with their workload and noise limitations.
- Add Windows Node.js CI and Linux stream/benchmark checks. Extend installed-package verification to the new incremental API and distribution files; document the implementation and maintenance boundaries.

## 0.2.2

- Fix generation of large Text constants and defaults: escaped Unicode strings are split into bounded chunks rather than exceeding MoonBit's source-line limit. Add an official-compiler embed fixture and regression covering Unicode, escapes and explicit empty-value overrides.
- Reproduce both ordinary and segmented conformance canonical output in CI, in addition to the existing canonical boundary vectors.
- Verify published packages in a fresh Mooncakes consumer on all four backends. Check required distribution files, MIT notices, upstream hashes, installed native/Node.js compiler plugins, binary packing and preservation of existing output on invalid input.
- Run the published-package check on GitHub releases and manual workflow runs; require the release tag, manifest, CLI and installed package versions to agree. Pin README reproduction to this release and Cap'n Proto 1.5.0.

## 0.2.1

- Allocate generated type, list-wrapper, constant and field names without requiring edits to valid schemas that collide after MoonBit name normalization. Add a real compiler fixture covering wrapper names, generic specializations, flattened declarations and repeated field-name suffixes.
- Reject incompatible scalar/pointer views of inline-composite lists whose elements lack the corresponding section, matching the C++ reader while preserving valid struct-field defaults and list evolution.
- Extend the unchanged-schema peer to exchange unknown generic enum ordinal `40000`, compare embedded Text/Data with original bytes, and verify exact generic Brand scope and binding type IDs.
- Add a feature-to-evidence conformance matrix and a CI check that recompiles the collision fixture with official Cap'n Proto 1.5.0.

## 0.2.0

- Target Cap'n Proto 1.5.0 serialization, including generic brands, ancestor bindings, aliases, unbound parameters, and generic defaults/constants. Recursively growing specializations retain an unbound view instead of requiring schema edits.
- Generate AnyPointer, AnyStruct, AnyList and constant accessors. Accept interface declarations alongside data types without generating RPC clients or servers.
- Add opaque pointer builders and bounded schema-free copying that preserves unknown fields and rolls back destination changes on failure. Non-null capabilities require external table mapping and are rejected by deep copy.
- Add schema-independent canonicalization for struct-root messages, checked against reference-generated vectors for padding, list trimming, empty values, far pointers and preorder layout.
- Vendor unchanged MIT-licensed 1.5.0 schemas and dependencies with hashes. Add a Python/C++ ↔ MoonBit example using the original generic/AnyPointer protocol and constant values.
- Embed only canonicalized pointer defaults and constants in generated code, so unrelated compiler source metadata does not change the generated API across platforms.
- Document the serialization completion target, tested cases, resource limits and capability/RPC boundary.

## 0.1.0

- Framing, bounded readers, single-segment builders and packed encoding in MoonBit.
- Official compiler plugin generating typed readers/builders for supported schemas.
- Independent compiler fixtures, malformed-input regressions and generated API tests.
- Portable roundtrip and MoonBit → Python/C++ → MoonBit batch-processing example.
- Four-backend CI and separate interoperability checks.

The initial release did not include generics, AnyPointer, constants or canonicalization. See [compatibility](docs/COMPATIBILITY.md) for the current version's scope; RPC remains separate.
