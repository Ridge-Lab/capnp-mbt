///|
#borrow(data)
extern "C" fn read_chunk(data : Bytes, size : Int) -> Int = "capnp_mbt_stdin_read"

///|
#borrow(data)
extern "C" fn write_chunk(data : Bytes, size : Int) -> Int = "capnp_mbt_stdout_write"

///|
extern "C" fn exit_impl(code : Int) -> Unit = "capnp_mbt_exit"
