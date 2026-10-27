///|
struct SampleInput {
  timestamp : UInt64
  value : Double
  quality : @telemetry.Quality
}

///|
struct Fixture {
  samples : Array[SampleInput]
  plain : Array[Bytes]
  packed : Array[Bytes]
}

///|
enum Operation {
  Encode
  SelectedRead
  FullScan
  Pack
  Unpack
  OpaqueCopy
}

///|
fn Operation::name(self : Operation) -> String {
  match self {
    Encode => "encode"
    SelectedRead => "selected_read"
    FullScan => "full_scan"
    Pack => "pack"
    Unpack => "unpack"
    OpaqueCopy => "opaque_copy"
  }
}

///|
fn mix(checksum : UInt, value : UInt) -> UInt {
  checksum.lxor(value) * 16777619U
}

///|
fn mix_u64(checksum : UInt, value : UInt64) -> UInt {
  mix(mix(checksum, value.to_uint()), (value >> 32).to_uint())
}

///|
fn mix_text(checksum : UInt, value : String) -> UInt {
  let mut result = checksum
  for c in value {
    result = mix(result, c.to_int().reinterpret_as_uint())
  }
  result
}

///|
fn job_id(variant : Int) -> UInt64 {
  9007199254740993UL + variant.to_uint64()
}

///|
fn encode(
  samples : Array[SampleInput],
  variant : Int,
) -> Bytes raise @capnp.CapnpError {
  let message = @capnp.Builder::new()
  let root = @telemetry.BatchBuilder::init_root(message)
  root.set_job_id(job_id(variant))
  root.set_source("benchmark-room-中文")
  root.set_unit("celsius")
  let list = root.init_samples(samples.length())
  for i, input in samples {
    let item = list.get(i)
    item.set_timestamp_ns(input.timestamp)
    item.set_value(input.value)
    item.set_quality(input.quality)
  }
  message.finish()
}

///|
fn selected_read(bytes : Bytes) -> UInt raise @capnp.CapnpError {
  let root = @telemetry.BatchReader::from_message(@capnp.read_message(bytes))
  let samples = root.get_samples()
  let mut sum = mix_u64(2166136261U, root.get_job_id())
  sum = mix(sum, samples.length().reinterpret_as_uint())
  sum = mix_u64(sum, samples.get(0).get_value().reinterpret_as_uint64())
  mix_u64(
    sum,
    samples.get(samples.length() - 1).get_value().reinterpret_as_uint64(),
  )
}

///|
fn full_scan(bytes : Bytes) -> UInt raise @capnp.CapnpError {
  let root = @telemetry.BatchReader::from_message(@capnp.read_message(bytes))
  let samples = root.get_samples()
  let mut sum = mix_u64(2166136261U, root.get_job_id())
  sum = mix_text(sum, root.get_source())
  sum = mix_text(sum, root.get_unit())
  sum = mix(sum, samples.length().reinterpret_as_uint())
  for i in 0..<samples.length() {
    let sample = samples.get(i)
    sum = mix_u64(sum, sample.get_timestamp_ns())
    sum = mix_u64(sum, sample.get_value().reinterpret_as_uint64())
    sum = mix(sum, sample.get_quality().to_raw())
  }
  sum
}

///|
fn opaque_copy(bytes : Bytes) -> Bytes raise @capnp.CapnpError {
  let source = @capnp.read_message(bytes)
  let target = @capnp.Builder::new()
  target.root_pointer().set(source.root_pointer())
  target.finish()
}

///|
// Constant-size observation of an output allocation; full correctness checks
// are performed before measurement. This cost is included in all byte-producing
// operations. The checksum is emitted and checked after every measured batch.
fn fingerprint(bytes : Bytes) -> UInt {
  let mut sum = mix(2166136261U, bytes.length().reinterpret_as_uint())
  let head = if bytes.length() < 24 { bytes.length() } else { 24 }
  for i in 0..<head {
    sum = mix(sum, bytes[i].to_uint())
  }
  for i in 1..<9 {
    sum = mix(sum, bytes[bytes.length() * i / 9].to_uint())
  }
  sum
}

///|
fn run_one(
  fixture : Fixture,
  operation : Operation,
  variant : Int,
) -> UInt raise @capnp.CapnpError {
  match operation {
    Encode => fingerprint(encode(fixture.samples, variant))
    SelectedRead => selected_read(fixture.plain[variant])
    FullScan => full_scan(fixture.plain[variant])
    Pack => fingerprint(@capnp.pack(fixture.plain[variant]))
    Unpack => fingerprint(@capnp.unpack(fixture.packed[variant]))
    OpaqueCopy => fingerprint(opaque_copy(fixture.plain[variant]))
  }
}

///|
fn validate_batch(
  bytes : Bytes,
  inputs : Array[SampleInput],
  variant : Int,
) -> Unit raise {
  let root = @telemetry.BatchReader::from_message(@capnp.read_message(bytes))
  assert_eq(root.get_job_id(), job_id(variant))
  assert_eq(root.get_source(), "benchmark-room-中文")
  assert_eq(root.get_unit(), "celsius")
  let samples = root.get_samples()
  assert_eq(samples.length(), inputs.length())
  let mut expected = mix_u64(2166136261U, job_id(variant))
  expected = mix_text(expected, "benchmark-room-中文")
  expected = mix_text(expected, "celsius")
  expected = mix(expected, inputs.length().reinterpret_as_uint())
  for i, input in inputs {
    let sample = samples.get(i)
    assert_eq(sample.get_timestamp_ns(), input.timestamp)
    assert_eq(sample.get_value(), input.value)
    assert_eq(sample.get_quality().to_raw(), input.quality.to_raw())
    expected = mix_u64(expected, input.timestamp)
    expected = mix_u64(expected, input.value.reinterpret_as_uint64())
    expected = mix(expected, input.quality.to_raw())
  }
  assert_eq(full_scan(bytes), expected)
  let expected_selected = mix_u64(
    mix_u64(
      mix(
        mix_u64(2166136261U, job_id(variant)),
        inputs.length().reinterpret_as_uint(),
      ),
      inputs[0].value.reinterpret_as_uint64(),
    ),
    inputs[inputs.length() - 1].value.reinterpret_as_uint64(),
  )
  assert_eq(selected_read(bytes), expected_selected)
}

///|
fn make_fixture(count : Int) -> Fixture raise {
  let samples = Array::makei(count, i => {
    (
      {
        timestamp: 1700000000000000000UL + i.to_uint64() * 1000000UL,
        value: 18.0 + (i % 80).to_double() * 0.25,
        quality: @telemetry.Quality::from_raw((i % 3).reinterpret_as_uint()),
      } : SampleInput)
  })
  let plain : Array[Bytes] = []
  let packed : Array[Bytes] = []
  for variant in 0..<2 {
    let bytes = encode(samples, variant)
    validate_batch(bytes, samples, variant)
    let compressed = @capnp.pack(bytes)
    assert_eq(@capnp.unpack(compressed), bytes)
    let copy = opaque_copy(bytes)
    validate_batch(copy, samples, variant)
    assert_eq(
      @capnp.canonicalize(@capnp.read_message(copy)),
      @capnp.canonicalize(@capnp.read_message(bytes)),
    )
    plain.push(bytes)
    packed.push(compressed)
  }
  assert_eq(plain[0].length(), plain[1].length())
  assert_eq(packed[0].length(), packed[1].length())
  { samples, plain, packed, }
}
