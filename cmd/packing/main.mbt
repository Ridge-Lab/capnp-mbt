///|
fn main raise {
  let args = @stdio.args()
  guard args.length() == 4 && (args[1] == "pack" || args[1] == "unpack") else {
    println(
      "Usage: packing pack|unpack INPUT OUTPUT (use - for binary stdin/stdout)",
    )
    @stdio.exit(if args.length() == 2 && args[1] == "--help" { 0 } else { 2 })
    return
  }
  let input = if args[2] == "-" {
    @stdio.read_stdin()
  } else {
    @fs.read_file_to_bytes(args[2])
  }
  let output = if args[1] == "pack" {
    @capnp.pack(input)
  } else {
    @capnp.unpack(input)
  }
  if args[3] == "-" {
    @stdio.write_stdout(output)
  } else {
    @fs.write_bytes_to_file(args[3], output)
  }
}
