///|
pub(all) suberror CapnpError {
  InvalidMessage(String)
  Bounds(String)
  Limit(String)
  TypeMismatch(String)
  Unsupported(String)
}

///|
pub impl @debug.Debug for CapnpError with fn to_repr(self) {
  let (name, message) = match self {
    InvalidMessage(s) => ("InvalidMessage", s)
    Bounds(s) => ("Bounds", s)
    Limit(s) => ("Limit", s)
    TypeMismatch(s) => ("TypeMismatch", s)
    Unsupported(s) => ("Unsupported", s)
  }
  @debug.Repr::ctor(name, [(None, @debug.Repr(message))])
}

///|
pub extend CapnpError with @moonbitlang/core/debug.Debug::{to_repr}
