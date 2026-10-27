///|
pub suberror IOError {
  IOError(String)
}

///|
/// Read one bounded binary stdin chunk. Empty bytes mean EOF. The caller can
/// process and release each chunk instead of retaining the complete stream.
pub fn read_stdin_chunk(chunk_bytes? : Int = 8192) -> Bytes raise IOError {
  guard chunk_bytes > 0 && chunk_bytes <= 1024 * 1024 else {
    raise IOError("stdin chunk size must be between 1 byte and 1 MiB")
  }
  let chunk = Bytes::make(chunk_bytes, 0)
  let count = read_chunk(chunk, chunk.length())
  guard count >= 0 && count <= chunk.length() else {
    raise IOError("failed to read binary stdin chunk")
  }
  if count == chunk.length() {
    chunk
  } else {
    chunk[:count].to_owned()
  }
}

///|
pub fn read_stdin(max_bytes? : Int = 64 * 1024 * 1024) -> Bytes raise IOError {
  guard max_bytes >= 0 else { raise IOError("negative stdin byte limit") }
  let output = @buffer.Buffer()
  let chunk = Bytes::make(8192, 0)
  while true {
    let count = read_chunk(chunk, chunk.length())
    guard count >= 0 else { raise IOError("failed to read binary stdin") }
    if count == 0 {
      break
    }
    guard count <= max_bytes - output.length() else {
      raise IOError("stdin exceeds the configured byte limit")
    }
    output.write_bytes(chunk[:count])
  }
  output.to_bytes()
}

///|
pub fn write_stdout(data : Bytes) -> Unit raise IOError {
  guard write_chunk(data, data.length()) == data.length() else {
    raise IOError("failed to write binary stdout")
  }
}

///|
pub fn exit(code : Int) -> Unit {
  exit_impl(code)
}

///|
#cfg(target="js")
pub fn args() -> Array[String] {
  @env.args()[1:].to_owned()
}

///|
#cfg(not(target="js"))
pub fn args() -> Array[String] {
  @env.args()
}
