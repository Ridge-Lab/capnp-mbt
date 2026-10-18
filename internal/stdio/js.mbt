///|
#module("node:fs")
extern "js" fn read_sync(fd : Int, data : Bytes, offset : Int, length : Int) -> Int = "readSync"

///|
#module("node:fs")
extern "js" fn write_sync(fd : Int, data : Bytes, offset : Int, length : Int) -> Int = "writeSync"

///|
extern "js" fn exit_impl(code : Int) -> Unit =
  #| (code) => process.exit(code)

///|
extern "js" fn call_io(f : (Int, Bytes, Int, Int) -> Int, fd : Int, data : Bytes, size : Int) -> Int =
  #| (f, fd, data, size) => { try { return f(fd, data, 0, size); } catch (_) { return -1; } }

///|
fn read_chunk(data : Bytes, size : Int) -> Int { call_io(read_sync, 0, data, size) }

///|
fn write_chunk(data : Bytes, size : Int) -> Int { call_io(write_sync, 1, data, size) }
