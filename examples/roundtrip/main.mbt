///|
fn main raise {
  let bytes = @sample.make_batch()
  let packed = @capnp.pack(bytes)
  let batch = @telemetry.BatchReader::from_message(
    @capnp.read_message(@capnp.unpack(packed)),
  )
  assert_eq(batch.get_job_id(), 9007199254740993UL)
  assert_eq(batch.get_unit(), "celsius")
  let samples = batch.get_samples()
  assert_eq(samples.length(), 6)
  assert_eq(samples.get(0).get_timestamp_ns(), 1792281600000000000UL)
  assert_eq(samples.get(0).get_value(), 20.0)
  assert_true(samples.get(3).get_quality() is @telemetry.Missing)
  println(
    "Read job \{batch.get_job_id()} from \{batch.get_source()}: \{samples.length()} samples",
  )
  println(
    "Standard frame: \{bytes.length()} bytes; packed frame: \{packed.length()} bytes",
  )
}
