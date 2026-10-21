///|
priv struct CopyBudget {
  mut words : Int
}

///|
fn copy_charge(budget : CopyBudget, words : Int) -> Unit raise CapnpError {
  if words < 0 || words > budget.words {
    raise Limit("deep-copy traversal limit exceeded")
  }
  budget.words -= words
}

///|
fn copy_limits(max_depth : Int, max_words : Int) -> CopyBudget raise CapnpError {
  // Bound recursive call-stack use even if a source reader permits deeper input.
  if max_depth < 0 || max_depth > 256 || max_words < 0 {
    raise Limit("copy limits require depth 0..256 and nonnegative words")
  }
  { words: max_words, }
}

///|
fn copy_transaction(
  target : PointerBuilder,
  action : () -> Unit raise CapnpError,
) -> Unit raise CapnpError {
  let mark = target.owner.arena.length()
  let mut old = 0UL
  for i in 0..<8 {
    old = old | (target.owner.arena[target.slot + i].to_uint64() << (8 * i))
  }
  errdefer {
    target.owner.arena.truncate(mark)
    b_write(target.owner, target.slot, old, 8)
  }
  action()
}

///|
fn copy_struct_contents(
  target : StructBuilder,
  source : StructReader,
  depth : Int,
  budget : CopyBudget,
) -> Unit raise CapnpError {
  let start = source.state.offsets[source.segment] + source.start
  for i in 0..<source.data_bytes {
    target.owner.arena[target.data_start + i] = source.state.bytes[start + i]
  }
  for i in 0..<source.pointer_count {
    copy_pointer(target.get_pointer(i), source.get_pointer(i), depth, budget)
  }
}

///|
fn copy_struct(
  target : PointerBuilder,
  source : StructReader,
  depth : Int,
  budget : CopyBudget,
) -> Unit raise CapnpError {
  if depth <= 0 {
    raise Limit("deep-copy nesting limit exceeded")
  }
  let data_words = (source.data_bytes + 7) / 8
  copy_charge(budget, Int::max(1, data_words + source.pointer_count))
  let result = target.init_struct(data_words, source.pointer_count)
  copy_struct_contents(result, source, depth - 1, budget)
}

///|
fn copy_list(
  target : PointerBuilder,
  source : ListReader,
  depth : Int,
  budget : CopyBudget,
) -> Unit raise CapnpError {
  if depth <= 0 {
    raise Limit("deep-copy nesting limit exceeded")
  }
  if source.code == 7 {
    let stride = source.data_words + source.pointer_count
    let words = if stride == 0 {
      source.count + 1
    } else {
      source.count * stride + 1
    }
    copy_charge(budget, words)
    let result = target.init_struct_list(
      source.count,
      source.data_words,
      source.pointer_count,
    )
    if stride != 0 {
      for i in 0..<source.count {
        copy_struct_contents(
          result.struct_at(i),
          source.get_struct(i),
          depth - 1,
          budget,
        )
      }
    }
  } else {
    let bytes = if source.code == 1 {
      (source.count + 7) / 8
    } else {
      source.count * source.stride
    }
    copy_charge(
      budget,
      if source.code == 0 {
        source.count
      } else {
        (bytes + 7) / 8
      },
    )
    let result = target.init_list(source.code, source.count)
    if source.code == 6 {
      for i in 0..<source.count {
        copy_pointer(
          result.get_pointer(i),
          source.get_pointer(i),
          depth - 1,
          budget,
        )
      }
    } else {
      let start = source.state.offsets[source.segment] + source.start
      for i in 0..<bytes {
        result.owner.arena[result.start + i] = source.state.bytes[start + i]
      }
    }
  }
}

///|
fn copy_pointer(
  target : PointerBuilder,
  source : PointerReader,
  depth : Int,
  budget : CopyBudget,
) -> Unit raise CapnpError {
  if source.is_null() {
    target.clear()
    return
  }
  if depth <= 0 {
    raise Limit("deep-copy nesting limit exceeded")
  }
  match source.kind() {
    Null => target.clear()
    Struct => copy_struct(target, source.as_struct(), depth, budget)
    List => copy_list(target, source.as_list(), depth, budget)
    Capability =>
      raise Unsupported(
        "deep-copying capabilities requires capability-table remapping",
      )
  }
}

///|
/// Deep-copy an opaque pointer, preserving unknown fields and wire list widths.
/// On CapnpError the destination slot and new arena allocations are rolled back.
/// Source traversal budget is consumed even when copying fails. Aliases become
/// independent copies; cycles stop at the reader or copy traversal/depth limit.
/// Capabilities are rejected because no capability-table remapping is available.
pub fn PointerBuilder::set(
  self : PointerBuilder,
  source : PointerReader,
  max_depth? : Int = 64,
  max_words? : Int = 8388608,
) -> Unit raise CapnpError {
  let budget = copy_limits(max_depth, max_words)
  copy_transaction(self, () => copy_pointer(self, source, max_depth, budget))
}

///|
/// Copy an opaque struct including every on-wire data word and pointer slot.
pub fn PointerBuilder::set_struct(
  self : PointerBuilder,
  source : StructReader,
  max_depth? : Int = 64,
  max_words? : Int = 8388608,
) -> Unit raise CapnpError {
  let budget = copy_limits(max_depth, max_words)
  copy_transaction(self, () => copy_struct(self, source, max_depth, budget))
}

///|
/// Copy an opaque list, retaining its element width and composite struct size.
pub fn PointerBuilder::set_list(
  self : PointerBuilder,
  source : ListReader,
  max_depth? : Int = 64,
  max_words? : Int = 8388608,
) -> Unit raise CapnpError {
  let budget = copy_limits(max_depth, max_words)
  copy_transaction(self, () => copy_list(self, source, max_depth, budget))
}
