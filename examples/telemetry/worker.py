"""A pycapnp peer: compute statistics from a MoonBit-produced binary batch.

This is an application example, not part of the MoonBit runtime or generator.
The input values are decoded by pycapnp's independent C++ implementation.
"""
from __future__ import annotations

import argparse
import math
import statistics
from pathlib import Path

import capnp


def process(input_path: Path, output_path: Path) -> None:
    schema = capnp.load(str(Path(__file__).parent / "schema" / "telemetry.capnp"))
    # The same schema is compiled into MoonBit types on the other side.
    with schema.Batch.from_bytes(input_path.read_bytes()) as batch:
        values = [sample.value for sample in batch.samples
                  if str(sample.quality) == "valid" and math.isfinite(sample.value)]
        report = schema.Report.new_message(
            jobId=batch.jobId,
            source=batch.source,
            total=len(batch.samples),
            accepted=len(values),
            rejected=len(batch.samples) - len(values),
        )
        if values:
            summary = report.init("statistics")
            summary.mean = statistics.fmean(values)
            summary.minimum = min(values)
            summary.maximum = max(values)
        else:
            report.empty = None
        output_path.write_bytes(report.to_bytes())
        print(f"processed job {batch.jobId}: {len(values)}/{len(batch.samples)} samples accepted")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    process(args.input, args.output)
