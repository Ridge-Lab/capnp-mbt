@0xe5845191dfb4ea36;

struct Foo { value @0 :UInt32; }
enum FooReader { first @0; second @1; }
enum Iter { once @0; many @1; }
enum ArrayView { borrowed @0; owned @1; }
enum Ref { read @0; write @1; }

struct ListOwner { children @0 :List(UInt32); }
struct ListOwnerChildrenList { value @0 :Text; }

struct Box(T) { value @0 :T; }
struct BoxAsText { value @0 :UInt32; }

const values :List(UInt32) = [3, 4];
struct ValuesConstantList { value @0 :Text; }

struct A { struct B { value @0 :UInt32; } }
struct AB { value @0 :Text; }

struct Uses {
  foo @0 :Foo;
  status @1 :FooReader;
  list @2 :ListOwner;
  listNamed @3 :ListOwnerChildrenList;
  bound @4 :Box(Text);
  boundNamed @5 :BoxAsText;
  constantNamed @6 :ValuesConstantList;
  nested @7 :A.B;
  nestedNamed @8 :AB;
  root @9 :List(UInt32);
  rootField @10 :List(UInt32);
  rootFieldF10 @11 :List(UInt32);
}
