@0xc3898c394f2c8eb1;

# Project-authored compiler input exercising non-scalar defaults and groups.
struct Item {
  number @0 :Int32 = 7;
  name @1 :Text = "child default";
}

struct Defaults {
  item @0 :Item = (number = 12, name = "explicit");
  items @1 :List(Item) = [(number = 1), (number = 2)];
  numbers @2 :List(UInt16) = [1, 65535];
  nested @3 :List(List(Text)) = [["hello"], [], ["a", "b"]];
  nan @4 :Float32 = nan;
  infinity @5 :Float64 = inf;
  negativeZero @6 :Float64 = -0.0;
}

struct Switching {
  preserved @0 :Bool = true;
  union {
    none @1 :Void;
    configuration :group {
      enabled @2 :Bool;
      label @3 :Text;
    }
    code @4 :UInt64;
  }
  owner @5 :Text;
}

struct Outer {
  struct Inner { value @0 :UInt32; }
  inner @0 :Inner;
  matrix @1 :List(List(Inner));
}

struct OtherLists {
  nothing @0 :Void;
  empties @1 :List(Void);
  tiny @2 :List(Int8);
  words @3 :List(UInt32);
  big @4 :List(UInt64);
  root @5 :List(UInt16);
}
