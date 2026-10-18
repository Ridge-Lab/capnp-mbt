///|
fn main raise {
  let args = @stdio.args()
  guard args.length() == 3 else {
    println("Usage: telemetry produce BATCH.bin | verify REPORT.bin")
    @stdio.exit(2)
    return
  }
  match args[1] {
    "produce" => {
      @fs.write_bytes_to_file(args[2], @sample.make_batch())
      println("Wrote job 9007199254740993: 6 typed samples")
    }
    "verify" => {
      @sample.verify_report(@fs.read_file_to_bytes(args[2]))
      println(
        "Verified independent report: accepted=4 rejected=2 mean=21 min=19.5 max=23",
      )
    }
    _ => {
      println("Unknown action: \{args[1]}")
      @stdio.exit(2)
    }
  }
}
