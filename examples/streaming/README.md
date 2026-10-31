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

From the repository root, with MoonBit `0.10.16+b1a0e846e`, Node.js 24 and Python 3.12:

```sh
python -m pip install -r examples/telemetry/requirements.txt
moon build --target js --release examples/streaming
python examples/streaming/peer.py --jobs 128 --output work/stream-js -- node _build/js/release/build/examples/streaming/streaming.js
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
check process exit status. This is per-message processing, not an all-or-nothing
transaction across the whole stream. `reports.bin` can also be read by another
Cap'n Proto consumer using `Report` from `examples/telemetry/schema/telemetry.capnp`.

The filter accepts unpacked standard frames. It does not auto-detect packed
data, add a network protocol, implement RPC, or claim external production usage.
