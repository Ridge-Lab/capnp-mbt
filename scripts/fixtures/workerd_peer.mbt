///|
fn main raise {
  let args = @env.args()
  let bytes = @base64.decode(args[args.length() - 1])
  let modules = @types.BundleReader::from_message(@capnp.read_message(bytes)).get_modules()
  assert_eq(modules.length(), 4)
  let message = @capnp.Builder::new()
  let reply = @types.BundleBuilder::init_root(message).init_modules(4)
  for i in 0..<modules.length() {
    let src = modules.get(i)
    let dst = reply.get(3 - i)
    dst.set_name("verified/" + src.get_name())
    dst.set_type(src.get_type())
    dst.set_ts_declaration(src.get_ts_declaration())
    dst.set_compile_cache(src.get_compile_cache())
    match i {
      0 => {
        assert_true(src.is_src())
        dst.set_src(src.get_src())
      }
      1 => {
        assert_true(src.is_wasm())
        dst.set_wasm(src.get_wasm())
      }
      2 => {
        assert_true(src.is_data())
        dst.set_data(src.get_data())
      }
      _ => {
        assert_true(src.is_json())
        dst.set_json(src.get_json())
      }
    }
  }
  println(@base64.encode(message.finish()))
}
