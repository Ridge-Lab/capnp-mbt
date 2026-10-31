///|
fn run_iterations(
  fixture : Fixture,
  operation : Operation,
  iterations : Int32,
) -> UInt32 raise @capnp.CapnpError {
  let mut checksum = 0U
  for i in 0..<iterations {
    checksum += run_one(fixture, operation, i % 2)
  }
  checksum
}

///|
fn expected_checksum(
  first : UInt32,
  second : UInt32,
  iterations : Int32,
) -> UInt32 {
  first * ((iterations + 1) / 2).reinterpret_as_uint() +
  second * (iterations / 2).reinterpret_as_uint()
}

///|
fn measured_batch(
  fixture : Fixture,
  operation : Operation,
  iterations : Int32,
  first : UInt32,
  second : UInt32,
) -> (Double, UInt32) raise {
  let start = @bench.monotonic_clock_start()
  let checksum = run_iterations(fixture, operation, iterations)
  let elapsed_us = @bench.monotonic_clock_end(start)
  assert_eq(checksum, expected_checksum(first, second, iterations))
  assert_true(elapsed_us >= 0.0 && elapsed_us < 1.0e15)
  (elapsed_us, checksum)
}

///|
fn measure(
  fixture : Fixture,
  operation : Operation,
  round_ms : Int32,
  warmup_ms : Int32,
  rounds : Int32,
) -> Unit raise {
  let first = run_one(fixture, operation, 0)
  let second = run_one(fixture, operation, 1)
  let target_us = round_ms.to_double() * 1000.0
  let mut iterations = 1
  let mut calibration_us = 0.0
  // Calibration and warmup are excluded from the reported rounds. The cap
  // bounds work on unexpectedly coarse/broken clocks; zero timing is an error.
  while iterations <= 16777216 {
    let (elapsed, _) = measured_batch(
      fixture, operation, iterations, first, second,
    )
    calibration_us = elapsed
    if elapsed >= target_us || iterations == 16777216 {
      break
    }
    iterations *= 2
  }
  assert_true(calibration_us > 0.0)
  let warmup_start = @bench.monotonic_clock_start()
  let mut warmup_batches = 0
  while @bench.monotonic_clock_end(warmup_start) <
        warmup_ms.to_double() * 1000.0 {
    let (_, _) = measured_batch(fixture, operation, iterations, first, second)
    warmup_batches += 1
  }
  let warmup_us = @bench.monotonic_clock_end(warmup_start)
  // JS may optimize during warmup. Recheck the batch size with the warmed
  // code before fixing the iteration count for all reported rounds.
  while iterations <= 16777216 {
    let (elapsed, _) = measured_batch(
      fixture, operation, iterations, first, second,
    )
    calibration_us = elapsed
    if elapsed >= target_us || iterations == 16777216 {
      break
    }
    iterations *= 2
  }
  let times : Array[Double] = []
  let checksums : Array[UInt32] = []
  for _ in 0..<rounds {
    let (elapsed, checksum) = measured_batch(
      fixture, operation, iterations, first, second,
    )
    assert_true(elapsed > 0.0)
    times.push(elapsed)
    checksums.push(checksum)
  }
  let sorted = times.copy()
  sorted.sort()
  let median_us = sorted[rounds / 2]
  let ns_per_op = median_us * 1000.0 / iterations.to_double()
  let wire_bytes = fixture.plain[0].length()
  let packed_bytes = fixture.packed[0].length()
  let input_bytes = match operation {
    Encode => 0
    Unpack => packed_bytes
    _ => wire_bytes
  }
  let rate = 1000000.0 * iterations.to_double() / median_us
  let wire_mib_per_second = rate * wire_bytes.to_double() / 1048576.0
  let raw_times = times.map(t => t.to_string()).join(",")
  let raw_checksums = checksums.map(c => c.to_string()).join(",")
  println(
    "{\"operation\":\"\{operation.name()}\",\"sample_count\":\{fixture.samples.length()},\"wire_bytes\":\{wire_bytes},\"packed_bytes\":\{packed_bytes},\"input_bytes\":\{input_bytes},\"iterations\":\{iterations},\"round_target_ms\":\{round_ms},\"calibration_us\":\{calibration_us},\"warmup_us\":\{warmup_us},\"warmup_batches\":\{warmup_batches},\"round_us\":[\{raw_times}],\"checksums\":[\{raw_checksums}],\"variant_checksums\":[\{first},\{second}],\"median_ns_per_op\":\{ns_per_op},\"operations_per_second\":\{rate},\"wire_mib_per_second\":\{wire_mib_per_second}}",
  )
}

///|
fn parse_positive(text : String, maximum : Int32) -> Int32? {
  if text.length() == 0 {
    return None
  }
  let mut result = 0
  for c in text {
    let digit = c.to_int() - '0'.to_int()
    if digit < 0 || digit > 9 || result > (maximum - digit) / 10 {
      return None
    }
    result = result * 10 + digit
  }
  if result < 1 || result > maximum {
    None
  } else {
    Some(result)
  }
}

///|
fn main raise {
  let args = @stdio.args()
  guard args.length() == 5 else {
    println("Usage: benchmarks SAMPLE_COUNT ROUND_MS WARMUP_MS ODD_ROUNDS")
    @stdio.exit(2)
    return
  }
  guard (
      parse_positive(args[1], 65536),
      parse_positive(args[2], 60000),
      parse_positive(args[3], 60000),
      parse_positive(args[4], 99),
    )
    is (Some(count), Some(round_ms), Some(warmup_ms), Some(rounds)) &&
    rounds >= 3 &&
    rounds % 2 == 1 else {
    println(
      "Invalid arguments: samples 1..65536; round/warmup ms 1..60000; odd rounds 3..99",
    )
    @stdio.exit(2)
    return
  }
  let fixture = make_fixture(count)
  for operation in [Encode, SelectedRead, FullScan, Pack, Unpack, OpaqueCopy] {
    measure(fixture, operation, round_ms, warmup_ms, rounds)
  }
}
