///|
#module("node:fs")
extern "js" fn read_sync(
  fd : Int32,
  data : Bytes,
  offset : Int32,
  length : Int32,
) -> Int32 = "readSync"

///|
#module("node:fs")
extern "js" fn write_sync(
  fd : Int32,
  data : Bytes,
  offset : Int32,
  length : Int32,
) -> Int32 = "writeSync"

///|
extern "js" fn exit_impl(code : Int32) -> Unit =
  #| (code) => process.exit(code)

///|
extern "js" fn call_io(
  f : (Int32, Bytes, Int32, Int32) -> Int32,
  fd : Int32,
  data : Bytes,
  size : Int32,
) -> Int32 =
  #| (f, fd, data, size) => { try { return f(fd, data, 0, size); } catch (_) { return -1; } }

///|
fn read_chunk(data : Bytes, size : Int32) -> Int32 {
  call_io(read_sync, 0, data, size)
}

///|
fn write_chunk(data : Bytes, size : Int32) -> Int32 {
  call_io(write_sync, 1, data, size)
}
