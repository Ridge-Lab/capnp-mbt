///|
suberror CliError {
  CliError(String)
}

///|
fn ensure_dir(path : String) -> Unit raise {
  if path == "" || path == "." || @fs.path_exists(path) {
    return
  }
  let normalized = path.replace(old="\\", new="/")
  let parts = normalized.split("/").to_array()
  let mut current = if normalized.has_prefix("/") { "/" } else { "" }
  for part in parts {
    if part == "" {
      continue
    }
    current = if current == "" || current == "/" {
      current + part.to_owned()
    } else {
      current + "/" + part.to_owned()
    }
    if !@fs.path_exists(current) {
      @fs.create_dir(current)
    }
  }
}

///|
fn safe_output_path(path : String) -> Bool {
  if path == "" ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains(":") ||
    !path.has_suffix(".mbt") {
    return false
  }
  for part in path.split("/") {
    if part == "" || part == "." || part == ".." {
      return false
    }
  }
  true
}

///|
fn main raise {
  let args = @stdio.args()
  let mut input : String? = None
  let mut output = "."
  let mut i = 1
  while i < args.length() {
    if args[i] == "--help" {
      println("capnpc-moonbit 0.2.0 — Cap'n Proto compiler plugin")
      println(
        "Usage: capnp compile -o/path/to/capnpc-moonbit[:OUTPUT] schema.capnp",
      )
      println("Or: capnpc-moonbit --request REQUEST.bin --out OUTPUT")
      return
    }
    if args[i] == "--version" {
      println("capnpc-moonbit 0.2.0")
      return
    }
    guard i + 1 < args.length() else {
      raise CliError("missing value for \{args[i]}")
    }
    match args[i] {
      "--request" => input = Some(args[i + 1])
      "--out" => output = args[i + 1]
      _ => raise CliError("unknown argument: \{args[i]}")
    }
    i += 2
  }
  let request = match input {
    Some(path) => @fs.read_file_to_bytes(path)
    None => @stdio.read_stdin()
  }
  // Generate and validate every output before creating or replacing any file.
  let files = @codegen.generate(request)
  for file in files {
    guard safe_output_path(file.path) else {
      raise CliError("unsafe generated path: \{file.path}")
    }
  }
  ensure_dir(output)
  for file in files {
    let parts = file.path.split("/").to_array()
    let parents = parts[:parts.length() - 1].to_owned().join("/")
    if parents != "" {
      ensure_dir(output + "/" + parents)
    }
    @fs.write_string_to_file(output + "/" + file.path, file.content)
  }
  let package_path = output + "/moon.pkg"
  if !@fs.path_exists(package_path) {
    @fs.write_string_to_file(
      package_path, "import {\n  \"Ridge-Lab/capnp\",\n}\n",
    )
  }
}
