@0x86a6dd47a8b565b6;
enum Status { unknown @0; ok @1; unknownValue1 @2; }
enum String { empty @0; filled @1; }
enum Error { invalid @0; valid @1; }
struct Names {
  status @0 :Status;
  string @1 :String;
}
