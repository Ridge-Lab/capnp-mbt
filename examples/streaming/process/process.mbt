///|
/// Summarize one Batch from the existing telemetry protocol. Invalid quality
/// markers and non-finite readings are rejected; the original job ID is kept.
pub fn summarize(bytes : Bytes) -> Bytes raise @capnp.CapnpError {
  let batch = @telemetry.BatchReader::from_message(@capnp.read_message(bytes))
  let samples = batch.get_samples()
  let mut accepted = 0
  let mut minimum = 0.0
  let mut maximum = 0.0
  let mut total = @bigint.BigInt::from_int(0)
  for i in 0..<samples.length() {
    let sample = samples.get(i)
    let value = sample.get_value()
    if sample.get_quality().to_raw() == 0U && !value.is_nan() && !value.is_inf() {
      if accepted == 0 {
        minimum = value
        maximum = value
      } else {
        if value < minimum {
          minimum = value
        }
        if value > maximum {
          maximum = value
        }
      }
      total = total + finite_units(value)
      accepted += 1
    }
  }
  let message = @capnp.Builder::new()
  let report = @telemetry.ReportBuilder::init_root(message)
  report.set_job_id(batch.get_job_id())
  report.set_source(batch.get_source())
  report.set_total(samples.length().reinterpret_as_uint())
  report.set_accepted(accepted.reinterpret_as_uint())
  report.set_rejected((samples.length() - accepted).reinterpret_as_uint())
  if accepted == 0 {
    report.set_empty()
  } else {
    let statistics = report.init_statistics()
    statistics.set_mean(rounded_mean(total, accepted))
    statistics.set_minimum(minimum)
    statistics.set_maximum(maximum)
  }
  message.finish()
}
