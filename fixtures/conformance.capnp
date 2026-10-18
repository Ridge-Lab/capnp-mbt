@0xdecaf00dbeef8018;

# Authored for this project. Oracle files are encoded by capnp 1.5.0.
enum Color {
  red @0;
  green @1;
  blue @2;
}

struct Child {
  id @0 :UInt64;
  name @1 :Text;
}

struct Fixture {
  boolean @0 :Bool = true;
  i8 @1 :Int8 = -12;
  i16 @2 :Int16 = -300;
  i32 @3 :Int32 = -70000;
  i64 @4 :Int64 = -9007199254740993;
  u8 @5 :UInt8 = 250;
  u16 @6 :UInt16 = 60000;
  u32 @7 :UInt32 = 4000000000;
  u64 @8 :UInt64 = 18446744073709551615;
  f32 @9 :Float32 = 1.5;
  f64 @10 :Float64 = -0.25;
  color @11 :Color = blue;
  text @12 :Text = "default text";
  data @13 :Data = 0x"0100ff";
  child @14 :Child;
  children @15 :List(Child);
  bools @16 :List(Bool);
  bytes @17 :List(UInt8);
  shorts @18 :List(Int16);
  ints @19 :List(Int32);
  longs @20 :List(Int64);
  floats @21 :List(Float32);
  doubles @22 :List(Float64);
  texts @23 :List(Text);
  blobs @24 :List(Data);
  nested @25 :List(List(UInt16));
  colors @26 :List(Color);
  union {
    none @27 :Void;
    message @28 :Text;
    code @29 :UInt32;
  }
  metadata :group {
    revision @30 :UInt32;
    author @31 :Text;
  }
}
