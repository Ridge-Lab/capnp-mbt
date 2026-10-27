///|
fn main raise {
  let decoder = @capnp.FrameDecoder::new(max_message_bytes=1024 * 1024)
  while true {
    let chunk = @stdio.read_stdin_chunk()
    if chunk.is_empty() {
      break
    }
    for frame in decoder.feed(chunk) {
      @stdio.write_stdout(@process.summarize(frame))
    }
  }
  decoder.finish()
}
