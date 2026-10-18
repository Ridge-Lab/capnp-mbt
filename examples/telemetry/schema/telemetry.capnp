@0xf107518019e20281;
using Q = import "quality.capnp";

# A batch job contract shared by the MoonBit client and the Python worker.
struct Sample {
  timestampNs @0 :UInt64;
  value @1 :Float64;
  quality @2 :Q.Quality;
}

struct Batch {
  jobId @0 :UInt64;
  source @1 :Text;
  samples @2 :List(Sample);
  unit @3 :Text = "celsius";
}

struct Report {
  jobId @0 :UInt64;
  source @1 :Text;
  total @2 :UInt32;
  accepted @3 :UInt32;
  rejected @4 :UInt32;
  union {
    empty @5 :Void;
    statistics :group {
      mean @6 :Float64;
      minimum @7 :Float64;
      maximum @8 :Float64;
    }
  }
}
