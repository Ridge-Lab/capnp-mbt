///|
fn kind(m : @schema.WorkerModuleReader) -> String raise {
  match m.which() {
    0U => "esModule"
    1U => "commonJsModule"
    2U => "text"
    3U => "data"
    4U => "wasm"
    5U => "json"
    6U => "obsolete"
    7U => "pythonModule"
    8U => "obsoletePythonRequirement"
    9U => "bundled"
    other => "unknown(\{other})"
  }
}

///|
fn payload(m : @schema.WorkerModuleReader) -> Bytes raise {
  match m.which() {
    0U => @utf8.encode(m.get_es_module())
    1U => @utf8.encode(m.get_common_js_module())
    2U => @utf8.encode(m.get_text())
    3U => m.get_data()
    4U => m.get_wasm()
    5U => @utf8.encode(m.get_json())
    7U => @utf8.encode(m.get_python_module())
    _ => fail("No supported embedded payload for \{kind(m)}")
  }
}

///|
#cfg(target="js")
fn arguments() -> Array[String] {
  @env.args()[2:].to_owned()
}

///|
#cfg(not(target="js"))
fn arguments() -> Array[String] {
  @env.args()[1:].to_owned()
}

///|
fn main raise {
  let args = arguments()
  let list = args.length() == 2 && args[0] == "list"
  guard list || (args.length() == 5 && args[0] == "extract") else {
    fail("Usage: list CONFIG | extract CONFIG SERVICE MODULE OUTPUT")
  }
  let bytes = @fs.read_file_to_bytes(args[1])
  let config = @schema.ConfigReader::from_message(@capnp.read_message(bytes))
  let services = config.get_services()
  let entries : Array[Json] = []
  let mut selected : @schema.WorkerModuleReader? = None
  for i in 0..<services.length() {
    let service = services.get(i)
    guard service.is_worker() else { continue }
    let worker = service.get_worker()
    guard worker.is_modules() else { continue }
    let owner = service.get_name()
    let modules = worker.get_modules()
    for j in 0..<modules.length() {
      let m = modules.get(j)
      let name = m.get_name()
      if list {
        entries.push({
          "service": Json::string(owner),
          "module": Json::string(name),
          "kind": Json::string(kind(m)),
        })
      } else if owner == args[2] && name == args[3] {
        guard selected is None else { fail("Ambiguous service/module pair") }
        selected = Some(m)
      }
    }
  }
  if list {
    println(Json::array(entries).stringify())
  } else {
    guard selected is Some(m) else { fail("Embedded module not found") }
    guard !@fs.path_exists(args[4]) else { fail("Output already exists") }
    @fs.write_bytes_to_file(args[4], payload(m))
  }
}
