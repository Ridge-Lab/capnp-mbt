# Process a stream of telemetry batches

This example turns a sequence of ordinary Cap'n Proto `Batch` messages into a
sequence of `Report` messages, using the existing telemetry schema unchanged.
It is useful for pipe-based ingestion, message logs and offline batch jobs.
Python/C++ produces the data; a MoonBit process computes statistics and writes
results immediately; Python/C++ decodes and independently verifies them.

The MoonBit filter reads stdin in chunks of at most 8 KiB. `FrameDecoder` keeps
only an incomplete trailing frame and rejects a frame larger than 1 MiB before
buffering its body. Complete frames are processed and released as chunks arrive;
the entire input stream is never collected by the filter. The output is binary
stdout with no status text mixed in. Native and Node.js CLI adapters are supported.

From the repository root, with MoonBit `0.10.20+65efd5b93`, Node.js 24 and Python 3.12:

```sh
python -m pip install -r examples/telemetry/requirements.txt
moon build --target js --release examples/streaming
python examples/streaming/peer.py --jobs 128 --output work/stream-js -- node _build/js/release/build/examples/streaming/streaming.js
python examples/streaming/peer.py --packed --jobs 128 --output work/stream-js-packed -- node _build/js/release/build/examples/streaming/streaming.js --packed
moon build --target native --release examples/streaming
python examples/streaming/peer.py --jobs 128 --output work/stream-native -- _build/native/release/build/examples/streaming/streaming.exe
```

The independent peer writes irregular chunks of 1, 3, 17, 4093 and 8191 bytes,
including segmented messages larger than the filter's read chunk. Pipes may
coalesce writes; unit tests separately exercise every split of representative
frames. It checks all 128 ordered reports, IDs beyond JavaScript's safe integer
range, Unicode source names, empty batches, invalid quality, NaN/infinity, and
finite values whose unscaled sum would overflow. Reports use the original
schema's `empty` or `statistics` union alternative.

The processor sums finite binary64 values exactly with the SDK's BigInt in
units of 2^-1074, then rounds the rational mean once to nearest-even. This
preserves small residuals after cancellation and handles subnormal values.
Extreme and seeded random values are compared with Python's `Fraction` oracle.
The peer also sends two small requests one at a time and requires each response
before closing stdin or sending the next, catching buffered-read stalls.

The final checks reject a truncated last frame and an oversized header. A valid
prefix may already have produced output before a later error; consumers must
check process exit status. Error diagnostics go to stderr, never the binary
stdout stream. This is per-message processing, not an all-or-nothing
transaction across the whole stream. `reports.bin` can also be read by another
Cap'n Proto consumer using `Report` from `examples/telemetry/schema/telemetry.capnp`.

`--packed` switches both stdin and stdout to packed messages. The same schema,
computation and independent assertions apply; C++ produces and consumes packed
values directly. `PackedFrameDecoder` retains incomplete packing tokens and
expands at most 2 KiB at a time into the standard framer, with a 1 MiB expanded
frame limit and default 64 MiB/4,096-frame output budgets per feed. The filter
still reads at most 8 KiB at a time. It neither auto-detects the encoding nor
implements RPC. Packing is useful when the existing producer already sends
packed logs; it does not imply third-party deployment or a throughput advantage.
