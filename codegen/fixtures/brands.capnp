@0xbfa27ea5c965c091;

struct Sample {
  id @0 :UInt64;
  name @1 :Text;
}

struct Box(T) {
  value @0 :T;
  values @1 :List(Box(T));
  next @2 :Box(T);
  details :group { extra @3 :T; }
}

struct Outer(T) {
  struct Inner(U) {
    left @0 :T;
    right @1 :U;
    same @2 :Inner(U);
    struct Deep(V, W) {
      first @0 :T;
      second @1 :U;
      third @2 :V;
      fourth @3 :W;
    }
  }
  child @0 :Inner(Data);
}

interface Service { ping @0 () -> (message :Text); }

struct Uses {
  textBox @0 :Box(Text);
  sampleBox @1 :Box(Sample);
  listBox @2 :Box(List(UInt32));
  nested @3 :Outer(Text).Inner(Data);
  unbound @4 :Box;
  pointer @5 :AnyPointer;
  structure @6 :AnyStruct;
  list @7 :AnyList;
  capability @8 :Service;
  deep @9 :Outer(Text).Inner(Data).Deep(Sample, List(UInt32));
}

enum Choice { no @0; yes @1; }
const flag :Bool = true;
const signed :Int64 = -9223372036854775808;
const unsigned :UInt64 = 18446744073709551615;
const text :Text = "literal";
const data :Data = 0x"00ff01";
const choice :Choice = yes;
const sample :Sample = (id = 123, name = "constant");
const list :List(UInt32) = [1, 4294967295];
const boxed :Box(Sample) = (value = (id = 456, name = "bound constant"));
const nestedList :List(List(Text)) = [["one"], [], ["two", "three"]];
const genericBoxes :List(Box(Text)) = [(value = "first"), (value = "second")];
const opaque :AnyPointer = .sample;
const opaqueStruct :AnyStruct = .sample;
const opaqueList :AnyList = .list;
const root :Text = "root constant";
const rootField :Text = "separate constant";

struct MethodNames {
  foo @0 :AnyList;
  fooStructs @1 :Sample;
}
