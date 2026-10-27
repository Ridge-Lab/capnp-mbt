///|
test "stream mean preserves small residuals after extreme cancellation" {
  for residual in [1.0, 1.0e-308] {
    let message = @capnp.Builder::new()
    let samples = @telemetry.BatchBuilder::init_root(message).init_samples(3)
    for i, value in [1.0e308, residual, -1.0e308] {
      samples.get(i).set_value(value)
    }
    let result = @telemetry.ReportReader::from_message(
      @capnp.read_message(@process.summarize(message.finish())),
    )
    assert_eq(result.get_statistics().get_mean(), residual / 3.0)
  }
}

///|
test "stream mean rounds subnormal ties and maximum finite values correctly" {
  let tiny = 1UL.reinterpret_as_double()
  let largest = 0x7fefffffffffffffUL.reinterpret_as_double()
  for
    pair in [
      ([tiny, tiny, tiny], tiny),
      ([tiny, 0.0], 0.0),
      ([tiny, tiny, 0.0], tiny),
      ([-tiny, 0.0], 0x8000000000000000UL.reinterpret_as_double()),
      ([largest, largest, largest], largest),
    ] {
    let (values, expected) = pair
    let message = @capnp.Builder::new()
    let samples = @telemetry.BatchBuilder::init_root(message).init_samples(
      values.length(),
    )
    for i, value in values {
      samples.get(i).set_value(value)
    }
    let result = @telemetry.ReportReader::from_message(
      @capnp.read_message(@process.summarize(message.finish())),
    )
    assert_eq(
      result.get_statistics().get_mean().reinterpret_as_uint64(),
      expected.reinterpret_as_uint64(),
    )
  }
}
