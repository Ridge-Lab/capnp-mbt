///|
fn read_chunk(_data : Bytes, _size : Int32) -> Int32 {
  -1
}

///|
fn write_chunk(_data : Bytes, _size : Int32) -> Int32 {
  -1
}

///|
fn exit_impl(code : Int32) -> Unit {
  if code != 0 {
    abort("CLI failed with exit code \{code}")
  }
}
