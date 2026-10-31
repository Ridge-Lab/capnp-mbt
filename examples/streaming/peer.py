"""Independent producer/verifier for a bounded MoonBit telemetry stream filter.

The existing telemetry schema is used unchanged. pycapnp decodes results with
the C++ implementation; the processor receives small, irregular pipe writes.
"""
from __future__ import annotations

import argparse
from fractions import Fraction
import math
from pathlib import Path
import queue
import random
import struct
import subprocess
import tempfile
import threading

import capnp


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = capnp.load(str(ROOT / "examples/telemetry/schema/telemetry.capnp"))
BASE_ID = 9007199254740993
SIZES = (0, 1, 3, 17, 257, 1024, 4097)


def readings(job: int) -> list[tuple[float, str]]:
    if job % 17 == 16:
        tiny = float.fromhex("0x0.0000000000001p-1022")
        largest = float.fromhex("0x1.fffffffffffffp+1023")
        cases = (
            [1e308, -1e308, 1e308], [1e308, 1.0, -1e308],
            [1e308, 1e-308, -1e308], [tiny, tiny, tiny],
            [tiny, 0.0], [tiny, tiny, 0.0], [largest, largest, largest],
            [-tiny, 0.0],
        )
        return [(value, "valid") for value in cases[(job // 17) % len(cases)]]
    if job % 17 == 15:
        rng = random.Random(job)
        values = []
        while len(values) < 16:
            value = struct.unpack("<d", rng.getrandbits(64).to_bytes(8, "little"))[0]
            if math.isfinite(value):
                values.append((value, "valid"))
        return values
    result = []
    for index in range(SIZES[job % len(SIZES)]):
        value = ((job * 19 + index * 7) % 2000 - 1000) / 8.0
        quality = "valid"
        if job % 9 == 5 or index % 13 == 7:
            quality = "sensorFault"
        elif index % 13 == 8:
            quality = "missing"
        elif index % 13 == 9:
            value = float("nan")
        elif index % 13 == 10:
            value = float("inf")
        elif index % 13 == 11:
            value = float("-inf")
        result.append((value, quality))
    return result


def encode(job: int) -> bytes:
    values = readings(job)
    batch = SCHEMA.Batch.new_message(num_first_segment_words=1)
    batch.jobId = BASE_ID + job
    batch.source = f"sensor/温度/{job}"
    samples = batch.init("samples", len(values))
    for index, (value, quality) in enumerate(values):
        samples[index].timestampNs = 1792281600000000000 + index * 1000000000
        samples[index].value = value
        samples[index].quality = quality
    return batch.to_bytes()


def verify(path: Path, jobs: int) -> None:
    count = 0
    with path.open("rb") as stream:
        for report in SCHEMA.Report.read_multiple(stream):
            assert count < jobs, "processor returned extra messages"
            readings_for_job = readings(count)
            values = [value for value, quality in readings_for_job
                      if quality == "valid" and math.isfinite(value)]
            assert report.jobId == BASE_ID + count
            assert report.source == f"sensor/温度/{count}"
            assert report.total == len(readings_for_job)
            assert report.accepted == len(values)
            assert report.rejected == len(readings_for_job) - len(values)
            if values:
                assert report.which() == "statistics"
                if count % 17 in (15, 16):
                    exact = sum((Fraction.from_float(value) for value in values), Fraction())
                    expected_mean = float(exact / len(values))
                else:
                    # These ordinary readings are exact multiples of 1/8 with
                    # a bounded sum; round once after the independent sum.
                    expected_mean = math.fsum(values) / len(values)
                assert report.statistics.mean == expected_mean, (count, report.statistics.mean, expected_mean)
                assert math.copysign(1.0, report.statistics.mean) == math.copysign(1.0, expected_mean)
                assert report.statistics.minimum == min(values)
                assert report.statistics.maximum == max(values)
            else:
                assert report.which() == "empty"
            count += 1
    assert count == jobs, f"expected {jobs} reports, got {count}"
    print(f"Verified {count} ordered reports with independent C++ decoding and Python calculations")


def verify_interactive(command: list[str]) -> None:
    responses: queue.Queue[bytes | BaseException] = queue.Queue()
    with tempfile.TemporaryFile() as errors:
        processor = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors)
        def receive() -> None:
            try:
                assert processor.stdout is not None
                def read_exact(size: int) -> bytes:
                    result = bytearray()
                    while len(result) < size:
                        part = processor.stdout.read(size - len(result))
                        if not part:
                            raise EOFError("processor closed before replying")
                        result.extend(part)
                    return bytes(result)
                for _ in range(2):
                    header = read_exact(8)
                    segments = int.from_bytes(header[:4], "little") + 1
                    assert 1 <= segments <= 512
                    header += read_exact(((segments + 2) // 2) * 8 - 8)
                    body_size = sum(int.from_bytes(header[4 + i * 4:8 + i * 4], "little") * 8
                                    for i in range(segments))
                    assert body_size + len(header) <= 1024 * 1024
                    responses.put(header + read_exact(body_size))
            except BaseException as error:
                responses.put(error)
        reader = threading.Thread(target=receive, daemon=True)
        try:
            reader.start()
            assert processor.stdin is not None
            for job in range(2):
                processor.stdin.write(encode(job))
                processor.stdin.flush()
                # Do not send the next request or close stdin before a reply.
                reply = responses.get(timeout=10)
                if isinstance(reply, BaseException):
                    raise reply
                with SCHEMA.Report.from_bytes(reply) as report:
                    assert report.jobId == BASE_ID + job
                    assert report.total == len(readings(job))
            processor.stdin.close()
            assert processor.wait(timeout=10) == 0
        finally:
            if processor.poll() is None:
                processor.kill()
            processor.wait()
            reader.join(timeout=5)
    print("Received two separate replies while stdin remained open")


def exercise(command: list[str], jobs: int, output: Path) -> None:
    verify_interactive(command)
    output.mkdir(parents=True, exist_ok=True)
    replies = output / "reports.bin"
    with replies.open("wb") as sink, tempfile.TemporaryFile() as errors:
        processor = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=sink, stderr=errors)
        write_errors: list[BaseException] = []
        input_bytes = 0
        def write_messages() -> None:
            nonlocal input_bytes
            try:
                assert processor.stdin is not None
                pattern = (1, 3, 17, 4093, 8191)
                chunk_index = 0
                for job in range(jobs):
                    message = encode(job)
                    input_bytes += len(message)
                    cursor = 0
                    while cursor < len(message):
                        size = pattern[chunk_index % len(pattern)]
                        processor.stdin.write(message[cursor:cursor + size])
                        processor.stdin.flush()
                        cursor += size
                        chunk_index += 1
                processor.stdin.close()
            except BaseException as error:
                write_errors.append(error)
        writer = threading.Thread(target=write_messages, daemon=True)
        try:
            writer.start()
            writer.join(timeout=120)
            if writer.is_alive():
                raise TimeoutError("processor stalled while accepting input")
            if write_errors:
                raise write_errors[0]
            status = processor.wait(timeout=120)
            errors.seek(0)
            error_text = errors.read().decode("utf-8", errors="replace")
            assert status == 0, error_text
        except BaseException:
            if processor.poll() is None:
                processor.kill()
            processor.wait()
            writer.join(timeout=5)
            raise
    verify(replies, jobs)
    print(f"Processed {input_bytes} input bytes with 8 KiB reads and a 1 MiB frame limit")

    # End-of-stream truncation must be detected, including after a valid prefix.
    truncated = subprocess.run(command, input=encode(0) + encode(1)[:-1],
                               capture_output=True, timeout=30)
    assert truncated.returncode != 0, "truncated final frame was silently accepted"
    assert truncated.stderr, "truncation must report a diagnostic on stderr"
    prefix = output / "prefix-before-error.bin"
    prefix.write_bytes(truncated.stdout)
    verify(prefix, 1)
    # Reject huge declarations from the header; do not wait to allocate payload.
    huge_header = (0).to_bytes(4, "little") + (0xFFFFFFFF).to_bytes(4, "little")
    invalid = subprocess.run(command, input=huge_header, capture_output=True, timeout=30)
    assert invalid.returncode != 0 and not invalid.stdout
    assert invalid.stderr, "oversized frame must report a diagnostic on stderr"
    print("Rejected truncated EOF and oversized frame header; earlier reports remain usable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=128)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("processor", nargs=argparse.REMAINDER,
                        help="Command following --, e.g. node path/to/streaming.js")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 100000:
        parser.error("jobs must be between 1 and 100000")
    command = args.processor
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("a processor command is required after --")
    exercise(command, args.jobs, args.output)


if __name__ == "__main__":
    main()
