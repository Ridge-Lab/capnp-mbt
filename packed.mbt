///|
/// Apply Cap'n Proto packing to a word-aligned byte sequence, including its
/// standard stream header when packing a complete message.
pub fn pack(input : Bytes) -> Bytes raise CapnpError {
  guard input.length() % 8 == 0 else {
    raise InvalidMessage("packed input must contain whole 8-byte words")
  }
  let out : Array[Byte] = []
  let mut pos = 0
  while pos < input.length() {
    let mut tag = 0
    for j in 0..<8 {
      if input[pos + j] != 0 { tag = tag | (1 << j) }
    }
    out.push(tag.to_byte())
    for j in 0..<8 {
      if (tag & (1 << j)) != 0 { out.push(input[pos + j]) }
    }
    pos += 8
    if tag == 0 {
      let mut count = 0
      while count < 255 && pos < input.length() {
        let mut zero = true
        for j in 0..<8 {
          if input[pos + j] != 0 { zero = false }
        }
        if !zero { break }
        count += 1
        pos += 8
      }
      out.push(count.to_byte())
    } else if tag == 255 {
      // Copy dense spans verbatim. Allow one zero byte per word, matching the
      // reference algorithm's tradeoff between tags and raw runs.
      let start = pos
      let mut count = 0
      while count < 255 && pos < input.length() {
        let mut zeroes = 0
        for j in 0..<8 {
          if input[pos + j] == 0 { zeroes += 1 }
        }
        if zeroes >= 2 { break }
        count += 1
        pos += 8
      }
      out.push(count.to_byte())
      for j in start..<pos { out.push(input[j]) }
    }
  }
  Bytes::from_array(out[:])
}

///|
/// Decode Cap'n Proto packing. Reject truncated runs and stop before an
/// allocation would exceed `max_output_bytes` (64 MiB by default).
pub fn unpack(
  input : Bytes,
  max_output_bytes? : Int = 64 * 1024 * 1024,
) -> Bytes raise CapnpError {
  guard max_output_bytes >= 0 else { raise Limit("negative unpack limit") }
  let out : Array[Byte] = []
  let mut pos = 0
  while pos < input.length() {
    guard out.length() <= max_output_bytes - 8 else {
      raise Limit("unpacked data exceeds the configured byte limit")
    }
    let tag = input[pos].to_int()
    pos += 1
    for j in 0..<8 {
      if (tag & (1 << j)) == 0 {
        out.push(0)
      } else {
        guard pos < input.length() else {
          raise InvalidMessage("truncated packed word")
        }
        out.push(input[pos])
        pos += 1
      }
    }
    if tag == 0 || tag == 255 {
      guard pos < input.length() else {
        raise InvalidMessage("missing packed run length")
      }
      let run_bytes = input[pos].to_int() * 8
      pos += 1
      guard run_bytes <= max_output_bytes - out.length() else {
        raise Limit("unpacked run exceeds the configured byte limit")
      }
      if tag == 0 {
        for _ in 0..<run_bytes { out.push(0) }
      } else {
        guard run_bytes <= input.length() - pos else {
          raise InvalidMessage("truncated raw run in packed data")
        }
        for j in 0..<run_bytes { out.push(input[pos + j]) }
        pos += run_bytes
      }
    }
  }
  Bytes::from_array(out[:])
}
