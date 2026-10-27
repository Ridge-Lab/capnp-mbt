# Local Windows measurement — 0.3.0

This is one local run, not a performance ranking. All 36 cases and all seven measured rounds per case are retained in [the raw JSON](local-windows-x86_64.json). See [methodology](../README.md) for exactly what each operation includes.

- Measured source: `013a201199a9df0002376ba2910a7421341fe8c6`; working tree clean at measurement start.
- Windows 11 x86-64; Intel Family 6 Model 154 Stepping 3, 20 logical CPUs; MoonBit 0.10.14+7d59c7ec9; Node.js 24.14.1. Compiler/environment details are in the JSON.
- Release build; 200 ms minimum warmup, post-warmup calibration targeting 100 ms batches, seven measured rounds. Allocation, ordinary GC, dispatch and result checksums are included.
- Message sizes: 1 sample = 112 wire / 64 packed bytes; 32 samples = 856 / 540; 512 samples = 12,376 / 7,877.

## Complete results

Time is the median in microseconds per operation. Spread is `(maximum round − minimum round) / median round`; it is not a confidence interval. No rounds were removed.

| Target | Samples | Operation | Median µs/op | Round range / median |
| --- | ---: | --- | ---: | ---: |
| native | 1 | `encode` | 0.924 | 3.8% |
| native | 1 | `selected_read` | 0.560 | 141.1% |
| native | 1 | `full_scan` | 1.902 | 16.6% |
| native | 1 | `pack` | 0.687 | 23.8% |
| native | 1 | `unpack` | 0.720 | 8.9% |
| native | 1 | `opaque_copy` | 4.966 | 11.3% |
| native | 32 | `encode` | 4.624 | 9.6% |
| native | 32 | `selected_read` | 1.247 | 72.2% |
| native | 32 | `full_scan` | 6.480 | 32.5% |
| native | 32 | `pack` | 2.789 | 21.6% |
| native | 32 | `unpack` | 2.224 | 36.6% |
| native | 32 | `opaque_copy` | 14.074 | 20.2% |
| native | 512 | `encode` | 59.215 | 7.4% |
| native | 512 | `selected_read` | 0.572 | 134.4% |
| native | 512 | `full_scan` | 72.901 | 13.4% |
| native | 512 | `pack` | 27.232 | 23.2% |
| native | 512 | `unpack` | 23.392 | 12.2% |
| native | 512 | `opaque_copy` | 143.426 | 7.9% |
| js | 1 | `encode` | 3.599 | 6.2% |
| js | 1 | `selected_read` | 0.840 | 5.6% |
| js | 1 | `full_scan` | 3.767 | 10.2% |
| js | 1 | `pack` | 1.011 | 1.9% |
| js | 1 | `unpack` | 1.672 | 4.0% |
| js | 1 | `opaque_copy` | 10.116 | 22.8% |
| js | 32 | `encode` | 23.924 | 5.6% |
| js | 32 | `selected_read` | 1.546 | 55.3% |
| js | 32 | `full_scan` | 23.128 | 40.2% |
| js | 32 | `pack` | 13.650 | 9.2% |
| js | 32 | `unpack` | 17.112 | 16.6% |
| js | 32 | `opaque_copy` | 26.920 | 8.6% |
| js | 512 | `encode` | 298.725 | 16.3% |
| js | 512 | `selected_read` | 0.832 | 64.0% |
| js | 512 | `full_scan` | 289.594 | 8.4% |
| js | 512 | `pack` | 138.797 | 5.6% |
| js | 512 | `unpack` | 134.032 | 11.5% |
| js | 512 | `opaque_copy` | 231.357 | 4.1% |

## Interpretation

The selected-field cases are particularly noisy: native 1/32/512-sample spreads were 141.1%, 72.2% and 134.4%, respectively. They access only a few fields, and do not establish whole-message decoding throughput. This run supports reproducibility and identifies measurements needing quieter/longer repetition; it does not support a fine-grained native-versus-JS ranking or a regression threshold.

For the 512-sample workload, this run observed native encode/full-scan medians of about 59.2/72.9 µs and Node.js medians of about 298.7/289.6 µs. These are in-memory library operations on this machine, not end-to-end ingestion latency or network throughput. No C++/JSON competitor was timed, and no production deployment is implied.

Reproduce with the default runner options on an otherwise idle machine:

```sh
python scripts/run_benchmarks.py --output work/benchmarks/local.json
```
