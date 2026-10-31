///|
#borrow(data)
extern "C" fn read_chunk(data : Bytes, size : Int32) -> Int32 = "capnp_mbt_stdin_read"

///|
#borrow(data)
extern "C" fn write_chunk(data : Bytes, size : Int32) -> Int32 = "capnp_mbt_stdout_write"

///|
#borrow(data)
extern "C" fn write_error_chunk(data : Bytes, size : Int32) -> Int32 = "capnp_mbt_stderr_write"

///|
extern "C" fn exit_impl(code : Int32) -> Unit = "capnp_mbt_exit"
