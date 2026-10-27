///|
// Every finite binary64 value is an integer multiple of 2^-1074. Accumulate
// those units exactly so neither overflow nor cancellation discards a reading.
fn finite_units(value : Double) -> @bigint.BigInt {
  let bits = value.reinterpret_as_uint64()
  let exponent = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction = bits & 0x000fffffffffffffUL
  let magnitude = if exponent == 0 {
    @bigint.BigInt::from_uint64(fraction)
  } else {
    @bigint.BigInt::from_uint64(fraction | 0x0010000000000000UL) <<
    (exponent - 1)
  }
  if bits >> 63 == 0UL {
    magnitude
  } else {
    -magnitude
  }
}

///|
// Round the exact rational mean once, to nearest binary64 with ties to even.
// A mean of finite values cannot exceed the largest input's magnitude.
fn rounded_mean(total : @bigint.BigInt, count : Int) -> Double {
  let negative = total.compare_int(0) < 0
  let magnitude = if negative { -total } else { total }
  let divisor = @bigint.BigInt::from_int(count)
  let length = (magnitude / divisor).bit_length()
  let mut shift = Int::max(0, length - 53)
  let denominator = divisor << shift
  let mut mantissa = (magnitude / denominator).to_uint64()
  let twice_remainder = (magnitude % denominator) << 1
  let relation = twice_remainder.compare(denominator)
  if relation > 0 || (relation == 0 && (mantissa & 1UL) != 0UL) {
    mantissa += 1UL
  }
  if mantissa == 0x0020000000000000UL {
    mantissa = mantissa >> 1
    shift += 1
  }
  let magnitude_bits = if mantissa < 0x0010000000000000UL {
    mantissa
  } else {
    ((shift + 1).to_uint64() << 52) | (mantissa - 0x0010000000000000UL)
  }
  let sign = if negative { 0x8000000000000000UL } else { 0UL }
  (magnitude_bits | sign).reinterpret_as_double()
}
