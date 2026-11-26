///|
test "builtin bundle extracts src wasm data and json module payloads" {
  let builder = @capnp.Builder::new()
  let bundle = @types.BundleBuilder::init_root(builder)
  let modules = bundle.init_modules(4)
  let m0 = modules.get(0)
  m0.set_name("entry.js")
  m0.set_type(@types.ModuleType::Bundle)
  m0.set_src(b"export default 1;\n")
  let m1 = modules.get(1)
  m1.set_name("kernel.wasm")
  m1.set_type(@types.ModuleType::Builtin)
  m1.set_wasm(b"\x00asm\x01\x00\x00\x00")
  let m2 = modules.get(2)
  m2.set_name("blob.bin")
  m2.set_type(@types.ModuleType::Internal)
  m2.set_data(b"\x00\xff\x80")
  let m3 = modules.get(3)
  m3.set_name("meta.json")
  m3.set_type(@types.ModuleType::Internal)
  m3.set_json("{\"ok\":true,\"label\":\"音频\"}")
  let reader = @types.BundleReader::from_message(
    @capnp.read_message(builder.finish()),
  ).get_modules()
  assert_eq(reader.length(), 4)
  let (k0, p0) = payload(reader.get(0))
  assert_eq(k0, "src")
  assert_eq(p0, b"export default 1;\n")
  let (k1, p1) = payload(reader.get(1))
  assert_eq(k1, "wasm")
  assert_eq(p1, b"\x00asm\x01\x00\x00\x00")
  let (k2, p2) = payload(reader.get(2))
  assert_eq(k2, "data")
  assert_eq(p2, b"\x00\xff\x80")
  let (k3, p3) = payload(reader.get(3))
  assert_eq(k3, "json")
  assert_eq(p3, @utf8.encode("{\"ok\":true,\"label\":\"音频\"}"))
}

///|
test "builtin bundle rejects unknown module union discriminant" {
  let builder = @capnp.Builder::new()
  let bundle = @types.BundleBuilder::init_root(builder)
  let modules = bundle.init_modules(1)
  let m = modules.get(0)
  m.set_name("future")
  // Module union discriminant sits at byte offset 2 (uint16); 99 is unknown.
  m.inner.set_uint16(2, 99U)
  let reader = @types.BundleReader::from_message(
    @capnp.read_message(builder.finish()),
  ).get_modules()
  let mut rejected = false
  try ignore(payload(reader.get(0))) catch {
    _ => rejected = true
  } noraise {
    _ => ()
  }
  assert_true(rejected)
}
