///|
fn read_chunk(_data : Bytes, _size : Int32) -> Int32 {
  -1
}

///|
fn write_chunk(_data : Bytes, _size : Int32) -> Int32 {
  -1
}

///|
// This adapter does not provide a stderr host binding. Failure diagnostics are
// best-effort, so do not use println and risk polluting a binary stdout stream.
fn write_error_chunk(_data : Bytes, _size : Int32) -> Int32 {
  -1
}

///|
fn exit_impl(code : Int32) -> Unit {
  if code != 0 {
    abort("CLI failed with exit code \{code}")
  }
}
