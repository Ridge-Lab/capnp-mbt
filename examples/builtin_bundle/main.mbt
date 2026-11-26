///|
fn payload(m : @types.ModuleReader) -> (String, Bytes) raise {
  match m.which_case() {
    Src(bytes) => ("src", bytes)
    Wasm(bytes) => ("wasm", bytes)
    Data(bytes) => ("data", bytes)
    Json(text) => ("json", @utf8.encode(text))
    Unknown(other) => fail("Unknown module discriminant \{other}")
  }
}

///|
fn inspect(args : Array[String]) -> Unit raise {
  guard args is [_, "list", _] || args is [_, "extract", _, _, _] else {
    fail("Usage: builtin_bundle list BUNDLE | extract BUNDLE MODULE OUTPUT")
  }
  let message = @capnp.read_message(@fs.read_file_to_bytes(args[2]))
  let modules = @types.BundleReader::from_message(message).get_modules()
  if args[1] == "extract" {
    let mut selected = None
    for i in 0..<modules.length() {
      let m = modules.get(i)
      if m.get_name() == args[3] {
        guard selected is None else { fail("Ambiguous module name") }
        selected = Some(m)
      }
    }
    guard selected is Some(m) else { fail("Module not found") }
    guard !@fs.path_exists(args[4]) else { fail("Output already exists") }
    let (_, bytes) = payload(m)
    @fs.write_bytes_to_file(args[4], bytes)
    return
  }
  let items : Array[Json] = []
  for i in 0..<modules.length() {
    let m = modules.get(i)
    let (kind, bytes) = payload(m)
    items.push({
      "name": Json::string(m.get_name()),
      "kind": Json::string(kind),
      "type": Json::number(m.get_type().to_raw().to_double()),
      "bytes": Json::number(bytes.length().to_double()),
    })
  }
  println(Json::array(items).stringify())
}

///|
fn main {
  inspect(@stdio.args()) catch {
    e => @stdio.fail("builtin_bundle: \{e}")
  }
}
