///|
fn StructReader::read_struct_bits(
  self : StructReader,
  offset : Int32,
  width : Int32,
) -> UInt64 raise CapnpError {
  if offset < 0 {
    raise Bounds("negative struct data offset")
  }
  if offset > self.data_bytes || width > self.data_bytes - offset {
    return 0
  }
  let start = self.state.offsets[self.segment] + self.start + offset
  for i in 0..<width; bits = 0UL {
    continue bits | (self.state.bytes[start + i].to_uint64() << (i * 8))
  } nobreak {
    bits
  }
}

///|
pub fn StructReader::get_bool(
  self : StructReader,
  bit_offset : Int32,
  default~ : Bool = false,
) -> Bool raise CapnpError {
  if bit_offset < 0 {
    raise Bounds("negative struct bit offset")
  }
  let value = StructReader::read_struct_bits(self, bit_offset / 8, 1)
  ((value & (1UL << (bit_offset % 8))) != 0) != default
}

///|
pub fn StructReader::get_uint8(
  self : StructReader,
  byte_offset : Int32,
  default~ : Byte = 0,
) -> Byte raise CapnpError {
  (StructReader::read_struct_bits(self, byte_offset, 1) ^ default.to_uint64()).to_byte()
}

///|
pub fn StructReader::get_uint16(
  self : StructReader,
  byte_offset : Int32,
  default~ : UInt32 = 0,
) -> UInt32 raise CapnpError {
  if default > 65535 {
    raise Bounds("UInt16 default exceeds 16 bits")
  }
  StructReader::read_struct_bits(self, byte_offset, 2).to_uint() ^ default
}

///|
pub fn StructReader::get_uint32(
  self : StructReader,
  byte_offset : Int32,
  default~ : UInt32 = 0,
) -> UInt32 raise CapnpError {
  StructReader::read_struct_bits(self, byte_offset, 4).to_uint() ^ default
}

///|
pub fn StructReader::get_uint64(
  self : StructReader,
  byte_offset : Int32,
  default~ : UInt64 = 0,
) -> UInt64 raise CapnpError {
  StructReader::read_struct_bits(self, byte_offset, 8) ^ default
}

///|
pub fn StructReader::get_int8(
  self : StructReader,
  byte_offset : Int32,
  default~ : Int32 = 0,
) -> Int32 raise CapnpError {
  if default < -128 || default > 127 {
    raise Bounds("Int8 default exceeds 8 bits")
  }
  let value = StructReader::read_struct_bits(self, byte_offset, 1).to_int() ^
    (default & 255)
  if value >= 128 {
    value - 256
  } else {
    value
  }
}

///|
pub fn StructReader::get_int16(
  self : StructReader,
  byte_offset : Int32,
  default~ : Int32 = 0,
) -> Int32 raise CapnpError {
  if default < -32768 || default > 32767 {
    raise Bounds("Int16 default exceeds 16 bits")
  }
  let value = StructReader::read_struct_bits(self, byte_offset, 2).to_int() ^
    (default & 65535)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
pub fn StructReader::get_int32(
  self : StructReader,
  byte_offset : Int32,
  default~ : Int32 = 0,
) -> Int32 raise CapnpError {
  StructReader::read_struct_bits(self, byte_offset, 4)
  .to_uint()
  .reinterpret_as_int() ^
  default
}

///|
pub fn StructReader::get_int64(
  self : StructReader,
  byte_offset : Int32,
  default~ : Int64 = 0,
) -> Int64 raise CapnpError {
  StructReader::read_struct_bits(self, byte_offset, 8).reinterpret_as_int64() ^
  default
}

///|
pub fn StructReader::get_float32(
  self : StructReader,
  byte_offset : Int32,
  default~ : Float = 0.0,
) -> Float raise CapnpError {
  Float::reinterpret_from_uint(
    StructReader::read_struct_bits(self, byte_offset, 4).to_uint() ^
    default.reinterpret_as_uint(),
  )
}

///|
pub fn StructReader::get_float64(
  self : StructReader,
  byte_offset : Int32,
  default~ : Double = 0.0,
) -> Double raise CapnpError {
  (StructReader::read_struct_bits(self, byte_offset, 8) ^
  default.reinterpret_as_uint64()).reinterpret_as_double()
}
