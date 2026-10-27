///|
test "stream processor agrees with the independent telemetry reference" {
  @sample.verify_report(@process.summarize(@sample.make_batch()))
}

///|
test "stream processor reports empty when every reading is invalid" {
  let message = @capnp.Builder::new()
  let batch = @telemetry.BatchBuilder::init_root(message)
  batch.set_job_id(18446744073709551615UL)
  batch.set_source("empty-sensor")
  let samples = batch.init_samples(3)
  samples.get(0).set_quality(@telemetry.Missing)
  samples.get(1).set_value(0x7ff0000000000000UL.reinterpret_as_double())
  samples.get(2).set_quality(@telemetry.Quality::from_raw(40000U))
  let result = @telemetry.ReportReader::from_message(
    @capnp.read_message(@process.summarize(message.finish())),
  )
  assert_eq(result.get_job_id(), 18446744073709551615UL)
  assert_eq(result.get_total(), 3U)
  assert_eq(result.get_accepted(), 0U)
  assert_eq(result.get_rejected(), 3U)
  assert_true(result.is_empty())
}

///|
test "stream processor avoids intermediate overflow for finite readings" {
  let message = @capnp.Builder::new()
  let batch = @telemetry.BatchBuilder::init_root(message)
  let samples = batch.init_samples(3)
  for i, value in [1.0e308, -1.0e308, 1.0e308] {
    samples.get(i).set_value(value)
  }
  let result = @telemetry.ReportReader::from_message(
    @capnp.read_message(@process.summarize(message.finish())),
  )
  let statistics = result.get_statistics()
  assert_true(statistics.get_mean() > 3.33e307)
  assert_true(statistics.get_mean() < 3.34e307)
  assert_eq(statistics.get_minimum(), -1.0e308)
  assert_eq(statistics.get_maximum(), 1.0e308)
}
