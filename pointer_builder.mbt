///|
/// The wire kind of an opaque pointer. Text and Data are both List pointers.
pub(all) enum PointerKind {
  Null
  Struct
  List
  Capability
} derive(Eq, Debug)

///|
pub extend PointerKind with @debug.Debug::{to_repr}

///|
pub extend PointerKind with Eq::{equal, not_equal}

///|
/// Inspect the pointer tag, resolving and validating far landing pads.
/// The pointed-to object is validated by as_struct/as_list or deep copying.
pub fn PointerReader::kind(
  self : PointerReader,
) -> PointerKind raise CapnpError {
  if self.is_null() {
    return Null
  }
  let (_, _, tag) = self.read_resolve()
  match tag.to_uint() & 3 {
    0 => Struct
    1 => List
    3 => {
      if tag.to_uint() != 3U {
        raise InvalidMessage("reserved other-pointer encoding")
      }
      Capability
    }
    _ => raise InvalidMessage("unresolved far pointer")
  }
}

///|
/// An opaque capability-table index, without a capability table or RPC behavior.
/// Copying an index preserves its bits, not the remote object it might identify.
pub fn PointerReader::capability_index(
  self : PointerReader,
) -> UInt raise CapnpError {
  if self.is_null() {
    raise TypeMismatch("expected capability pointer")
  }
  let (_, _, tag) = self.read_resolve()
  if tag.to_uint() != 3U {
    raise TypeMismatch("expected capability pointer")
  }
  (tag >> 32).to_uint()
}

///|
/// A mutable pointer slot in a bounded builder arena.
pub struct PointerBuilder {
  priv owner : Builder
  priv slot : Int
}

///|
pub fn Builder::root_pointer(self : Builder) -> PointerBuilder {
  { owner: self, slot: 0, }
}

///|
pub fn StructBuilder::get_pointer(
  self : StructBuilder,
  slot : Int,
) -> PointerBuilder raise CapnpError {
  { owner: self.owner, slot: b_pointer(self, slot), }
}

///|
pub fn ListBuilder::get_pointer(
  self : ListBuilder,
  index : Int,
) -> PointerBuilder raise CapnpError {
  { owner: self.owner, slot: b_list_slot(self, index), }
}

///|
pub fn PointerBuilder::is_null(self : PointerBuilder) -> Bool {
  for i in 0..<8 {
    if self.owner.arena[self.slot + i] != 0 {
      return false
    }
  }
  true
}

///|
pub fn PointerBuilder::clear(self : PointerBuilder) -> Unit {
  b_write(self.owner, self.slot, 0UL, 8)
}

///|
pub fn PointerBuilder::init_struct(
  self : PointerBuilder,
  data_words : Int,
  pointer_count : Int,
) -> StructBuilder raise CapnpError {
  b_init_struct(self.owner, self.slot, data_words, pointer_count)
}

///|
pub fn PointerBuilder::init_list(
  self : PointerBuilder,
  element_size : Int,
  length : Int,
) -> ListBuilder raise CapnpError {
  b_init_list(self.owner, self.slot, element_size, length)
}

///|
pub fn PointerBuilder::init_struct_list(
  self : PointerBuilder,
  length : Int,
  data_words : Int,
  pointer_count : Int,
) -> ListBuilder raise CapnpError {
  b_init_struct_list(self.owner, self.slot, length, data_words, pointer_count)
}

///|
pub fn PointerBuilder::set_text(
  self : PointerBuilder,
  value : String,
) -> Unit raise CapnpError {
  b_blob(self.owner, self.slot, @utf8.encode(value), true)
}

///|
pub fn PointerBuilder::set_data(
  self : PointerBuilder,
  value : Bytes,
) -> Unit raise CapnpError {
  b_blob(self.owner, self.slot, value, false)
}

///|
/// Store only the opaque table index. No RPC table is created or transferred.
pub fn PointerBuilder::set_capability_index(
  self : PointerBuilder,
  index : UInt,
) -> Unit {
  b_write(self.owner, self.slot, 3UL | (index.to_uint64() << 32), 8)
}
