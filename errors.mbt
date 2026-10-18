///|
pub(all) suberror CapnpError {
  InvalidMessage(String)
  Bounds(String)
  Limit(String)
  TypeMismatch(String)
  Unsupported(String)
} derive(Debug)

///|
pub extend CapnpError with @moonbitlang/core/debug.Debug::{to_repr}
