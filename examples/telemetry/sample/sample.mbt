///|
/// A reproducible batch containing valid readings, a missing reading and NaN.
pub fn make_batch() -> Bytes raise @capnp.CapnpError {
  let message = @capnp.Builder::new()
  let batch = @telemetry.BatchBuilder::init_root(message)
  batch.set_job_id(9007199254740993UL)
  batch.set_source("room-temperature")
  let values = [
    20.0,
    21.5,
    19.5,
    0.0,
    0x7ff8000000000000UL.reinterpret_as_double(),
    23.0,
  ]
  let samples = batch.init_samples(values.length())
  for index, value in values {
    let sample = samples.get(index)
    sample.set_timestamp_ns(
      1792281600000000000UL + index.to_uint64() * 1000000000UL,
    )
    sample.set_value(value)
    sample.set_quality(
      if index == 3 {
        @telemetry.Missing
      } else {
        @telemetry.Valid
      },
    )
  }
  message.finish()
}

///|
/// Check the independently computed report, including the 64-bit job ID.
pub fn verify_report(bytes : Bytes) -> Unit raise {
  let report = @telemetry.ReportReader::from_message(@capnp.read_message(bytes))
  assert_eq(report.get_job_id(), 9007199254740993UL)
  assert_eq(report.get_source(), "room-temperature")
  assert_eq(report.get_total(), 6U)
  assert_eq(report.get_accepted(), 4U)
  assert_eq(report.get_rejected(), 2U)
  assert_true(report.is_statistics())
  let statistics = report.get_statistics()
  assert_eq(statistics.get_mean(), 21.0)
  assert_eq(statistics.get_minimum(), 19.5)
  assert_eq(statistics.get_maximum(), 23.0)
}
