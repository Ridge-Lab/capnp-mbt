///|
pub suberror Error {
  InvalidMessage(String)
  Bounds(String)
  Limit(String)
  TypeMismatch(String)
  Unsupported(String)
} derive(Debug)
