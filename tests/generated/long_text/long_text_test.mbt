///|
test "large embedded Text constants and defaults preserve Unicode and escapes" {
  let expected = @fs.read_file_to_string("codegen/fixtures/long-text.utf8.bin")
  assert_eq(expected, "\"\\\n中文λ🚀".repeat(8192) + "\n")
  assert_eq(@long_text.const_document(), expected)
  let message = @capnp.Builder::new()
  let root = @long_text.DocumentBuilder::init_root(message)
  let defaulted = @long_text.DocumentReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(defaulted.get_text(), expected)
  root.set_text("")
  let explicit_empty = @long_text.DocumentReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(explicit_empty.get_text(), "")
  root.set_text(expected)
  let explicit_text = @long_text.DocumentReader::from_message(
    @capnp.read_message(message.finish()),
  )
  assert_eq(explicit_text.get_text(), expected)
}
