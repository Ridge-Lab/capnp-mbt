# Runtime benchmarks

These benchmarks measure Capnp-MBT's public runtime and generated telemetry bindings. They answer practical questions such as the cost of reading two fields versus visiting all samples, packing a batch, or copying a message without knowing its schema. They do not compare Capnp-MBT against C++, JSON, or another language.

From the repository root, with Python 3.10+, MoonBit 0.10.14+, Node.js and a working native C toolchain on `PATH`:

```sh
python scripts/run_benchmarks.py --output work/benchmarks/local.json
```

The default run builds release executables for native and JS in an isolated `work/benchmark-build` directory, then measures 1, 32 and 512 samples. Each operation calibrates its iteration count, warms up for at least 200 ms, calibrates again after warmup, and records seven rounds. The calibration target is at least 100 ms per batch; actual round durations are retained, so short or noisy rounds remain visible. Run on an otherwise idle machine and retain the full JSON when sharing a result.

```sh
# A short smoke run; use the defaults or longer runs for performance reporting.
python scripts/run_benchmarks.py --targets js --samples 1 32 512 --round-ms 10 --warmup-ms 10 --rounds 3

# Longer measurement, with a separate build directory and output record.
python scripts/run_benchmarks.py --round-ms 250 --warmup-ms 1000 --rounds 9 --target-dir work/benchmark-long --output work/benchmarks/long.json
```

On Windows, initialize the compiler environment supported by your MoonBit installation first. This project's local LLVM-MinGW setup also needs `CCC_OVERRIDE_OPTIONS=+-D_CRT_RAND_S` for the SDK's Windows `rand_s` declaration. The runner records that setting when present; it does not alter your compiler configuration. `--moon` and `--node` can select explicit executable paths.

## Workload and measured operations

The unchanged schema is [telemetry.capnp](../examples/telemetry/schema/telemetry.capnp), using its committed generated bindings. A batch has a 64-bit job ID above JavaScript's exact integer range, UTF-8 source text including Chinese characters, a unit, and an inline-composite list. Each sample has a 64-bit timestamp, a finite double and one of three quality enum values. Inputs are prepared before timing. Two otherwise identical batches alternate their job IDs so the loop observes changing results. Sizes and fingerprints are recorded for every case.

| Operation | Included in each timed iteration |
| --- | --- |
| `encode` | New builder, generated setters for all fields and samples, message framing with `finish()`, output fingerprint. Input-array preparation is excluded. |
| `selected_read` | Fresh `read_message`, generated root/list views, job ID, list length, first and last sample values, checksum. With one sample, both value accesses refer to that sample. |
| `full_scan` | Fresh `read_message`, generated getters for every field, both text decodes and every sample, checksum over the values. This traverses views; it does not allocate an application object per sample. |
| `pack` | Packing the prepared uncompressed message, including output allocation and fingerprint. |
| `unpack` | Unpacking the prepared packed message, including output allocation and fingerprint. Parsing the unpacked message is excluded. |
| `opaque_copy` | Fresh message reader and builder, deep copy through `root_pointer().set(...)`, `finish()` and output fingerprint. No generated schema is used during the copy. |

Every read starts with a fresh message and traversal budget. Timed loops include operation dispatch, checksum accumulation, allocation and any GC that occurs naturally. No process launch, compilation, filesystem I/O or JSON formatting is included. There is no forced GC or automatic outlier removal.

Before timing, the executable checks every decoded field against the input, checks exact `unpack(pack(bytes))` equality, and verifies opaque copies both field-by-field and by canonical bytes. Byte-producing operations observe the first up-to-24 output bytes plus eight evenly spaced bytes, together with the output length; they do not hash the whole output in the timed loop. Full correctness checks remain outside timing. Each iteration contributes a result checksum, and every calibration, warmup and measured batch verifies it against the expected alternating-input sum. Checksums are included in JSON. These checks help detect broken workloads and prevent the measured work from becoming an unused loop; they are not cryptographic integrity guarantees.

## Reading the result

The JSON contains the OS/architecture/CPU description, toolchain and Node versions, release build commands, Git revision and dirty state, SHA-256 hashes of benchmark and project-local dependency sources, all round times in microseconds, iteration counts, checksums, message sizes and derived rates. The runner rejects missing operations, invalid timing, incomplete warmup, inconsistent checksums, or source changes during measurement. Exit status is nonzero on a failed build or validation; it does not publish partial results as a successful run.

`median_ns_per_op` and `operations_per_second` use the median observed round. `min_ns_per_op`, `max_ns_per_op` and the range as a percentage of the median expose variability. `wire_mib_per_second` is **uncompressed-message-size-equivalent throughput**: it multiplies messages per second by complete wire size. In particular, selected reading does not touch all these bytes, so that number is not measured memory bandwidth. `serialized_input_equivalent_mib_per_second` uses packed size for unpack and is `null` for encode, which has no serialized input buffer.

Comparisons require the same workload, source/toolchain, settings and machine conditions. JIT, GC, CPU frequency, power policy and other processes can change results. The benchmark is single-threaded and in-memory; it does not establish network throughput, cold-start latency, arbitrary schema performance, or superiority over another implementation. The recorded native compiler candidates are tools available on `PATH`, not a claim that every candidate was used by MoonBit.

The executable also builds for the repository's Wasm targets through the SDK monotonic-clock implementation. The runner intentionally reports only native and Node.js measurements. A direct invocation accepts `SAMPLE_COUNT ROUND_MS WARMUP_MS ODD_ROUNDS`; sample count is bounded to 1–65536, durations to 1–60000 ms, and rounds to odd integers from 3–99.

## Published local run

The [0.3.0 Windows measurement](results/README.md) retains all 36 cases, raw rounds, source hashes and observed variability. Several selected-read cases are noisy; the report makes no cross-language superiority claim.
