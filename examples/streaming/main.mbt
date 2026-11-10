///|
fn run() -> Unit raise {
  let args = @stdio.args()
  guard args.length() == 1 || (args.length() == 2 && args[1] == "--packed") else {
    @stdio.write_stderr("Usage: streaming [--packed]\n")
    @stdio.exit(2)
    return
  }
  let packed = args.length() == 2
  let decoder = @capnp.FrameDecoder::new(max_message_bytes=1024 * 1024)
  let packed_decoder = @capnp.PackedFrameDecoder::new(
    max_message_bytes=1024 * 1024,
  )
  while true {
    let chunk = @stdio.read_stdin_chunk()
    if chunk.is_empty() {
      break
    }
    let frames = if packed {
      packed_decoder.feed(chunk)
    } else {
      decoder.feed(chunk)
    }
    for frame in frames {
      let report = @process.summarize(frame)
      @stdio.write_stdout(if packed { @capnp.pack(report) } else { report })
    }
  }
  if packed {
    packed_decoder.finish()
  } else {
    decoder.finish()
  }
}

///|
fn main {
  run() catch {
    error => @stdio.fail("streaming: \{error}")
  }
}
