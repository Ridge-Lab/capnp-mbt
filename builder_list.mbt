///|
pub fn ListBuilder::length(self : ListBuilder) -> Int32 {
  self.count
}

///|
pub fn ListBuilder::element_size(self : ListBuilder) -> Int32 {
  self.size_code
}

///|
fn b_list_index(
  handle : ListBuilder,
  index : Int32,
  expected : Int32,
) -> Unit raise CapnpError {
  if index < 0 || index >= handle.count {
    raise Bounds("list index out of bounds")
  }
  if handle.size_code != expected {
    raise TypeMismatch("list setter does not match element size")
  }
}

///|
fn b_list_slot(handle : ListBuilder, index : Int32) -> Int32 raise CapnpError {
  b_list_index(handle, index, 6)
  handle.start + index * 8
}

///|
pub fn ListBuilder::set_void(
  self : ListBuilder,
  index : Int32,
) -> Unit raise CapnpError {
  b_list_index(self, index, 0)
}

///|
pub fn ListBuilder::set_bool(
  self : ListBuilder,
  index : Int32,
  value : Bool,
) -> Unit raise CapnpError {
  b_list_index(self, index, 1)
  let pos = self.start + index / 8
  let mask : Byte = 1 << (index % 8)
  self.owner.arena[pos] = if value {
    self.owner.arena[pos] | mask
  } else {
    self.owner.arena[pos] & mask.lnot()
  }
}

///|
pub fn ListBuilder::set_uint8(
  self : ListBuilder,
  index : Int32,
  value : Byte,
) -> Unit raise CapnpError {
  b_list_index(self, index, 2)
  self.owner.arena[self.start + index] = value
}

///|
pub fn ListBuilder::set_uint16(
  self : ListBuilder,
  index : Int32,
  value : UInt32,
) -> Unit raise CapnpError {
  b_list_index(self, index, 3)
  if value > 65535U {
    raise Bounds("uint16 list value exceeds 65535")
  }
  b_write(self.owner, self.start + index * 2, UInt64::extend_uint(value), 2)
}

///|
pub fn ListBuilder::set_uint32(
  self : ListBuilder,
  index : Int32,
  value : UInt32,
) -> Unit raise CapnpError {
  b_list_index(self, index, 4)
  b_write(self.owner, self.start + index * 4, UInt64::extend_uint(value), 4)
}

///|
pub fn ListBuilder::set_uint64(
  self : ListBuilder,
  index : Int32,
  value : UInt64,
) -> Unit raise CapnpError {
  b_list_index(self, index, 5)
  b_write(self.owner, self.start + index * 8, value, 8)
}

///|
pub fn ListBuilder::set_int8(
  self : ListBuilder,
  index : Int32,
  value : Int32,
) -> Unit raise CapnpError {
  if value < -128 || value > 127 {
    raise Bounds("int8 list value outside -128..127")
  }
  self.set_uint8(index, (value & 255).to_byte())
}

///|
pub fn ListBuilder::set_int16(
  self : ListBuilder,
  index : Int32,
  value : Int32,
) -> Unit raise CapnpError {
  if value < -32768 || value > 32767 {
    raise Bounds("int16 list value outside -32768..32767")
  }
  self.set_uint16(index, (value & 65535).reinterpret_as_uint())
}

///|
pub fn ListBuilder::set_int32(
  self : ListBuilder,
  index : Int32,
  value : Int32,
) -> Unit raise CapnpError {
  self.set_uint32(index, value.reinterpret_as_uint())
}

///|
pub fn ListBuilder::set_int64(
  self : ListBuilder,
  index : Int32,
  value : Int64,
) -> Unit raise CapnpError {
  self.set_uint64(index, value.reinterpret_as_uint64())
}

///|
pub fn ListBuilder::set_float32(
  self : ListBuilder,
  index : Int32,
  value : Float,
) -> Unit raise CapnpError {
  self.set_uint32(index, value.reinterpret_as_uint())
}

///|
pub fn ListBuilder::set_float64(
  self : ListBuilder,
  index : Int32,
  value : Double,
) -> Unit raise CapnpError {
  self.set_uint64(index, value.reinterpret_as_uint64())
}

///|
pub fn ListBuilder::clear_pointer(
  self : ListBuilder,
  index : Int32,
) -> Unit raise CapnpError {
  b_write(self.owner, b_list_slot(self, index), 0, 8)
}

///|
pub fn ListBuilder::set_text(
  self : ListBuilder,
  index : Int32,
  value : String,
) -> Unit raise CapnpError {
  b_blob(self.owner, b_list_slot(self, index), @utf8.encode(value), true)
}

///|
pub fn ListBuilder::set_data(
  self : ListBuilder,
  index : Int32,
  value : Bytes,
) -> Unit raise CapnpError {
  b_blob(self.owner, b_list_slot(self, index), value, false)
}

///|
pub fn ListBuilder::init_struct(
  self : ListBuilder,
  index : Int32,
  data_words : Int32,
  pointer_count : Int32,
) -> StructBuilder raise CapnpError {
  b_init_struct(self.owner, b_list_slot(self, index), data_words, pointer_count)
}

///|
pub fn ListBuilder::init_list(
  self : ListBuilder,
  index : Int32,
  element_size : Int32,
  length : Int32,
) -> ListBuilder raise CapnpError {
  b_init_list(self.owner, b_list_slot(self, index), element_size, length)
}

///|
pub fn ListBuilder::init_struct_list(
  self : ListBuilder,
  index : Int32,
  length : Int32,
  data_words : Int32,
  pointer_count : Int32,
) -> ListBuilder raise CapnpError {
  b_init_struct_list(
    self.owner,
    b_list_slot(self, index),
    length,
    data_words,
    pointer_count,
  )
}

///|
/// Return the existing element of an inline composite list without allocation.
pub fn ListBuilder::struct_at(
  self : ListBuilder,
  index : Int32,
) -> StructBuilder raise CapnpError {
  b_list_index(self, index, 7)
  {
    owner: self.owner,
    data_start: self.start + index * (self.data_words + self.pointer_count) * 8,
    data_words: self.data_words,
    pointer_count: self.pointer_count,
  }
}
