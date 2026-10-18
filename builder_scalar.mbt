///|
/// Set a bit in the data section, XOR'd with its schema default.
pub fn StructBuilder::set_bool(
  self : StructBuilder,
  bit_offset : Int,
  value : Bool,
  default? : Bool = false,
) -> Unit raise CapnpError {
  if bit_offset < 0 {
    raise Bounds("negative bit offset")
  }
  let pos = b_data(self, bit_offset / 8, 1)
  let mask : Byte = 1 << (bit_offset % 8)
  self.owner.arena[pos] = if value != default {
    self.owner.arena[pos] | mask
  } else {
    self.owner.arena[pos] & mask.lnot()
  }
}

///|
pub fn StructBuilder::set_uint8(
  self : StructBuilder,
  byte_offset : Int,
  value : Byte,
  default? : Byte = 0,
) -> Unit raise CapnpError {
  b_write(
    self.owner,
    b_data(self, byte_offset, 1),
    (value ^ default).to_uint64(),
    1,
  )
}

///|
pub fn StructBuilder::set_uint16(
  self : StructBuilder,
  byte_offset : Int,
  value : UInt,
  default? : UInt = 0,
) -> Unit raise CapnpError {
  if value > 65535U || default > 65535U {
    raise Bounds("uint16 value or default exceeds 65535")
  }
  b_write(
    self.owner,
    b_data(self, byte_offset, 2),
    UInt64::extend_uint(value ^ default),
    2,
  )
}

///|
pub fn StructBuilder::set_uint32(
  self : StructBuilder,
  byte_offset : Int,
  value : UInt,
  default? : UInt = 0,
) -> Unit raise CapnpError {
  b_write(
    self.owner,
    b_data(self, byte_offset, 4),
    UInt64::extend_uint(value ^ default),
    4,
  )
}

///|
pub fn StructBuilder::set_uint64(
  self : StructBuilder,
  byte_offset : Int,
  value : UInt64,
  default? : UInt64 = 0,
) -> Unit raise CapnpError {
  b_write(self.owner, b_data(self, byte_offset, 8), value ^ default, 8)
}

///|
pub fn StructBuilder::set_int8(
  self : StructBuilder,
  byte_offset : Int,
  value : Int,
  default? : Int = 0,
) -> Unit raise CapnpError {
  if value < -128 || value > 127 || default < -128 || default > 127 {
    raise Bounds("int8 value or default outside -128..127")
  }
  b_write(
    self.owner,
    b_data(self, byte_offset, 1),
    ((value ^ default) & 255).to_uint64(),
    1,
  )
}

///|
pub fn StructBuilder::set_int16(
  self : StructBuilder,
  byte_offset : Int,
  value : Int,
  default? : Int = 0,
) -> Unit raise CapnpError {
  if value < -32768 || value > 32767 || default < -32768 || default > 32767 {
    raise Bounds("int16 value or default outside -32768..32767")
  }
  b_write(
    self.owner,
    b_data(self, byte_offset, 2),
    ((value ^ default) & 65535).to_uint64(),
    2,
  )
}

///|
pub fn StructBuilder::set_int32(
  self : StructBuilder,
  byte_offset : Int,
  value : Int,
  default? : Int = 0,
) -> Unit raise CapnpError {
  b_write(
    self.owner,
    b_data(self, byte_offset, 4),
    UInt64::extend_uint((value ^ default).reinterpret_as_uint()),
    4,
  )
}

///|
pub fn StructBuilder::set_int64(
  self : StructBuilder,
  byte_offset : Int,
  value : Int64,
  default? : Int64 = 0,
) -> Unit raise CapnpError {
  b_write(
    self.owner,
    b_data(self, byte_offset, 8),
    (value ^ default).reinterpret_as_uint64(),
    8,
  )
}

///|
pub fn StructBuilder::set_float32(
  self : StructBuilder,
  byte_offset : Int,
  value : Float,
  default? : Float = 0.0,
) -> Unit raise CapnpError {
  self.set_uint32(
    byte_offset,
    value.reinterpret_as_uint(),
    default=default.reinterpret_as_uint(),
  )
}

///|
pub fn StructBuilder::set_float64(
  self : StructBuilder,
  byte_offset : Int,
  value : Double,
  default? : Double = 0.0,
) -> Unit raise CapnpError {
  self.set_uint64(
    byte_offset,
    value.reinterpret_as_uint64(),
    default=default.reinterpret_as_uint64(),
  )
}
