///|
pub fn ListReader::length(self : ListReader) -> Int32 {
  self.count
}

///|
/// Return the wire element-size code, 0 through 7.
pub fn ListReader::element_size(self : ListReader) -> Int32 {
  self.code
}

///|
fn ListReader::read_list_index(
  self : ListReader,
  index : Int32,
) -> Unit raise CapnpError {
  if index < 0 || index >= self.count {
    raise Bounds("list index out of bounds")
  }
}

///|
fn ListReader::read_list_bits(
  self : ListReader,
  index : Int32,
  code : Int32,
  width : Int32,
) -> UInt64 raise CapnpError {
  ListReader::read_list_index(self, index)
  if self.code == 7 {
    if self.data_words == 0 {
      raise TypeMismatch("expected a data field in an evolved struct list")
    }
    return StructReader::read_struct_bits(self.get_struct(index), 0, width)
  }
  if self.code != code {
    raise TypeMismatch("list element size does not match scalar type")
  }
  let start = self.state.offsets[self.segment] + self.start + index * width
  for i in 0..<width; bits = 0UL {
    continue bits | (self.state.bytes[start + i].to_uint64() << (i * 8))
  } nobreak {
    bits
  }
}

///|
pub fn ListReader::get_bool(
  self : ListReader,
  index : Int32,
) -> Bool raise CapnpError {
  ListReader::read_list_index(self, index)
  if self.code != 1 {
    raise TypeMismatch("expected bit list")
  }
  let start = self.state.offsets[self.segment] + self.start
  (self.state.bytes[start + index / 8].to_int() & (1 << (index % 8))) != 0
}

///|
pub fn ListReader::get_uint8(
  self : ListReader,
  index : Int32,
) -> Byte raise CapnpError {
  ListReader::read_list_bits(self, index, 2, 1).to_byte()
}

///|
pub fn ListReader::get_uint16(
  self : ListReader,
  index : Int32,
) -> UInt32 raise CapnpError {
  ListReader::read_list_bits(self, index, 3, 2).to_uint()
}

///|
pub fn ListReader::get_uint32(
  self : ListReader,
  index : Int32,
) -> UInt32 raise CapnpError {
  ListReader::read_list_bits(self, index, 4, 4).to_uint()
}

///|
pub fn ListReader::get_uint64(
  self : ListReader,
  index : Int32,
) -> UInt64 raise CapnpError {
  ListReader::read_list_bits(self, index, 5, 8)
}

///|
pub fn ListReader::get_int8(
  self : ListReader,
  index : Int32,
) -> Int32 raise CapnpError {
  let value = ListReader::read_list_bits(self, index, 2, 1).to_int()
  if value >= 128 {
    value - 256
  } else {
    value
  }
}

///|
pub fn ListReader::get_int16(
  self : ListReader,
  index : Int32,
) -> Int32 raise CapnpError {
  let value = ListReader::read_list_bits(self, index, 3, 2).to_int()
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
pub fn ListReader::get_int32(
  self : ListReader,
  index : Int32,
) -> Int32 raise CapnpError {
  ListReader::read_list_bits(self, index, 4, 4).to_uint().reinterpret_as_int()
}

///|
pub fn ListReader::get_int64(
  self : ListReader,
  index : Int32,
) -> Int64 raise CapnpError {
  ListReader::read_list_bits(self, index, 5, 8).reinterpret_as_int64()
}

///|
pub fn ListReader::get_float32(
  self : ListReader,
  index : Int32,
) -> Float raise CapnpError {
  Float::reinterpret_from_uint(
    ListReader::read_list_bits(self, index, 4, 4).to_uint(),
  )
}

///|
pub fn ListReader::get_float64(
  self : ListReader,
  index : Int32,
) -> Double raise CapnpError {
  ListReader::read_list_bits(self, index, 5, 8).reinterpret_as_double()
}

///|
/// Read an inline struct, or view a primitive/pointer element as an evolved struct.
/// Bit lists cannot be upgraded to struct lists under the Cap'n Proto specification.
pub fn ListReader::get_struct(
  self : ListReader,
  index : Int32,
) -> StructReader raise CapnpError {
  ListReader::read_list_index(self, index)
  if self.code == 1 {
    raise TypeMismatch("bit lists cannot be upgraded to struct lists")
  }
  let start = self.start + index * self.stride
  if self.code == 7 {
    return {
      state: self.state,
      segment: self.segment,
      start,
      data_bytes: self.data_words * 8,
      pointer_start: start / 8 + self.data_words,
      pointer_count: self.pointer_count,
      depth: self.depth,
    }
  }
  {
    state: self.state,
    segment: self.segment,
    start,
    data_bytes: if self.code == 6 {
      0
    } else {
      self.stride
    },
    pointer_start: start / 8,
    pointer_count: if self.code == 6 {
      1
    } else {
      0
    },
    depth: self.depth,
  }
}

///|
pub fn ListReader::get_pointer(
  self : ListReader,
  index : Int32,
) -> PointerReader raise CapnpError {
  ListReader::read_list_index(self, index)
  if self.code == 7 {
    if self.pointer_count == 0 {
      raise TypeMismatch("expected a pointer field in an evolved struct list")
    }
    return self.get_struct(index).get_pointer(0)
  }
  if self.code != 6 {
    raise TypeMismatch("expected pointer list")
  }
  {
    state: self.state,
    segment: self.segment,
    word: self.start / 8 + index,
    depth: self.depth,
  }
}

///|
pub fn ListReader::get_list(
  self : ListReader,
  index : Int32,
) -> ListReader raise CapnpError {
  self.get_pointer(index).as_list()
}

///|
pub fn ListReader::get_text(
  self : ListReader,
  index : Int32,
) -> String raise CapnpError {
  self.get_pointer(index).as_text()
}

///|
pub fn ListReader::get_data(
  self : ListReader,
  index : Int32,
) -> Bytes raise CapnpError {
  self.get_pointer(index).as_data()
}
