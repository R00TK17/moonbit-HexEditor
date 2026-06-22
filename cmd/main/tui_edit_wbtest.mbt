// Internal tests for tui_edit.mbt — undo/redo system, all 5 UndoOp kinds

///|
/// Test: undo_op constructor
test "undo_op constructor" {
  let op = undo_op(0, 10, b'\xFF')
  assert_eq(op.kind, 0)
  assert_eq(op.offset, 10)
  assert_eq(op.old_byte, b'\xFF')
  assert_eq(op.count, 1)
}

test "undo_op insert kind" {
  let op = undo_op(1, 5, b'\x00')
  assert_eq(op.kind, 1)
  assert_eq(op.offset, 5)
}

///|
/// Test: pop_last
test "pop_last empty" {
  let stack : Array[UndoOp] = []
  let (new_stack, item) = pop_last(stack)
  assert_eq(new_stack.length(), 0)
  assert_true(item is None)
}

test "pop_last single" {
  let op = undo_op(0, 0, b'\xAA')
  let stack = [op]
  let (new_stack, item) = pop_last(stack)
  assert_eq(new_stack.length(), 0)
  assert_true(item is Some(_))
  assert_eq(item.unwrap().old_byte, b'\xAA')
}

test "pop_last multiple" {
  let op1 = undo_op(0, 0, b'\x01')
  let op2 = undo_op(1, 5, b'\x02')
  let stack = [op1, op2]
  let (new_stack, item) = pop_last(stack)
  assert_eq(new_stack.length(), 1)
  assert_eq(item.unwrap().offset, 5)
  assert_eq(new_stack[0].offset, 0)
}

///|
/// Test: depth_suffix
test "depth_suffix none" {
  assert_eq(depth_suffix(0, 0), "")
}

test "depth_suffix undo only" {
  let s = depth_suffix(3, 0)
  assert_true(s.contains("undo:3"))
  assert_true(s.contains("redo:0"))
}

test "depth_suffix both" {
  let s = depth_suffix(5, 2)
  assert_true(s.contains("undo:5"))
  assert_true(s.contains("redo:2"))
}

// ====== Undo tests — Kind 0 (Modify) ======

test "apply_undo kind 0 modify" {
  // buf = [0x00, 0x01, 0x02], modify buf[1] = 0xFF
  let buf = @lib.HexBuffer::from_bytes(b"\x00\x01\x02")
  let op = undo_op(0, 1, b'\x01') // old_byte = 0x01
  // First, simulate the edit: set byte to something new
  buf.set_byte(1, b'\xFF') |> ignore
  assert_eq(buf.byte_at(1), b'\xFF')
  // Now undo: should restore 0x01
  let redo_op = apply_undo(buf, op)
  assert_eq(buf.byte_at(1), b'\x01')
  // Redo op should be kind 0 with the modified value
  assert_eq(redo_op.kind, 0)
  assert_eq(redo_op.offset, 1)
  assert_eq(redo_op.old_byte, b'\xFF')
}

// ====== Undo tests — Kind 1 (Insert) ======

test "apply_undo kind 1 insert" {
  // buf = [0x01, 0x03], inserted 0x02 at position 1
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x02\x03")
  let op = undo_op(1, 1, b'\x00') // kind 1 at position 1
  let redo_op = apply_undo(buf, op)
  // After undo: should have deleted the inserted byte
  assert_eq(buf.length(), 2)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x03')
  // Redo should be kind 2 (delete)
  assert_eq(redo_op.kind, 2)
}

// ====== Undo tests — Kind 2 (Delete) ======

test "apply_undo kind 2 delete" {
  // buf = [0x01, 0x03], deleted 0x02 at position 1
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x03")
  let op = undo_op(2, 1, b'\x02') // kind 2, re-insert 0x02
  let redo_op = apply_undo(buf, op)
  // After undo: should have re-inserted the byte
  assert_eq(buf.length(), 3)
  assert_eq(buf.byte_at(1), b'\x02')
  // Redo should be kind 1 (insert)
  assert_eq(redo_op.kind, 1)
}

// ====== Undo tests — Kind 3 (Paste Overwrite) ======

test "apply_undo kind 3 paste overwrite" {
  // buf = [0x01, 0x02, 0x03], paste overwrite at pos 0 with [0xAA, 0xBB]
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x02\x03")
  let original = [b'\x01', b'\x02']
  let op : UndoOp = { kind: 3, offset: 0, old_byte: b'\x00', old_bytes: original, count: 2 }
  // Simulate paste: overwrite
  buf.set_byte(0, b'\xAA') |> ignore
  buf.set_byte(1, b'\xBB') |> ignore
  assert_eq(buf.byte_at(0), b'\xAA')
  assert_eq(buf.byte_at(1), b'\xBB')
  // Undo: restore original bytes
  let redo_op = apply_undo(buf, op)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x02')
  // Redo should be kind 3 with pasted bytes saved
  assert_eq(redo_op.kind, 3)
  // Check that pasted bytes were saved as old_bytes in redo op
  assert_eq(redo_op.old_bytes.length(), 2)
  assert_eq(redo_op.old_bytes[0], b'\xAA')
  assert_eq(redo_op.old_bytes[1], b'\xBB')
}

// ====== Undo tests — Kind 4 (Paste Insert) ======

test "apply_undo kind 4 paste insert" {
  // buf = [0x01, 0x04], paste insert [0x02, 0x03] at position 1
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x02\x03\x04")
  let op : UndoOp = { kind: 4, offset: 1, old_byte: b'\x00', old_bytes: [], count: 2 }
  let redo_op = apply_undo(buf, op)
  // After undo: should have deleted the 2 inserted bytes
  assert_eq(buf.length(), 2)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x04')
  // Redo should be kind 4 with inserted bytes saved
  assert_eq(redo_op.kind, 4)
}

// ====== Redo tests — roundtrip ======

test "undo_redo roundtrip kind 0 modify" {
  let buf = @lib.HexBuffer::from_bytes(b"\x00\x0A\xFF")
  // Simulate: modify buf[1] from 0x0A to 0x42
  buf.set_byte(1, b'\x42') |> ignore
  // Undo
  let undo_op = undo_op(0, 1, b'\x0A') // old_byte = 0x0A
  let redo_op = apply_undo(buf, undo_op)
  assert_eq(buf.byte_at(1), b'\x0A') // undone
  // Redo
  let _ = apply_redo(buf, redo_op)
  assert_eq(buf.byte_at(1), b'\x42') // redone
}

test "undo_redo roundtrip kind 1 insert" {
  // Simulate: insert 0x99 at position 1 into [0x01, 0x02, 0x03]
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x99\x02\x03")
  // The undo op records what was inserted (0x99) at position 1
  let op = undo_op(1, 1, b'\x99')
  // Undo: should delete the inserted byte
  let redo_op = apply_undo(buf, op)
  assert_eq(buf.length(), 3)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x02')
  assert_eq(buf.byte_at(2), b'\x03')
  // Redo: should re-insert 0x99 at position 1
  let _ = apply_redo(buf, redo_op)
  assert_eq(buf.length(), 4)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x99')
  assert_eq(buf.byte_at(2), b'\x02')
  assert_eq(buf.byte_at(3), b'\x03')
}

test "undo_redo roundtrip kind 2 delete" {
  // Simulate: delete byte at position 1 (was 0x02) from [0x01, 0x02, 0x03]
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x03")
  // The undo op records the deleted byte (0x02) at position 1
  let op = undo_op(2, 1, b'\x02')
  // Undo: should re-insert 0x02 at position 1
  let redo_op = apply_undo(buf, op)
  assert_eq(buf.length(), 3)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x02')
  assert_eq(buf.byte_at(2), b'\x03')
  // Redo: should delete byte at position 1 again
  let _ = apply_redo(buf, redo_op)
  assert_eq(buf.length(), 2)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x03')
}

test "undo_redo double modify roundtrip" {
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x02\x03")
  // Edit 1: buf[0] 0x01 → 0xFF
  buf.set_byte(0, b'\xFF') |> ignore
  let op1 = undo_op(0, 0, b'\x01')
  let redo1 = apply_undo(buf, op1)
  assert_eq(buf.byte_at(0), b'\x01')
  // Edit 2: buf[2] 0x03 → 0xEE
  buf.set_byte(2, b'\xEE') |> ignore
  let op2 = undo_op(0, 2, b'\x03')
  let redo2 = apply_undo(buf, op2)
  assert_eq(buf.byte_at(2), b'\x03')
  // Redo in reverse order (LIFO)
  let _ = apply_redo(buf, redo2)
  assert_eq(buf.byte_at(2), b'\xEE')
  let _ = apply_redo(buf, redo1)
  assert_eq(buf.byte_at(0), b'\xFF')
}

// ====== Revert all edits ======

test "revert_all_edits simple" {
  let buf = @lib.HexBuffer::from_bytes(b"\x0A\x0B\x0C")
  buf.set_byte(0, b'\xFF') |> ignore
  buf.set_byte(1, b'\xEE') |> ignore
  let stack = [undo_op(0, 0, b'\x0A'), undo_op(0, 1, b'\x0B')]
  revert_all_edits(buf, stack)
  assert_eq(buf.byte_at(0), b'\x0A')
  assert_eq(buf.byte_at(1), b'\x0B')
}

test "revert_all_edits mix insert delete modify" {
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x04")
  // Simulate: modify buf[0] 0x01→0xFF, insert 0x02 at pos 1, insert 0x03 at pos 2, delete original 0x04
  buf.set_byte(0, b'\xFF') |> ignore       // modify
  buf.insert_byte(1, b'\x02') |> ignore     // insert
  buf.insert_byte(2, b'\x03') |> ignore     // insert
  // Now buf = [0xFF, 0x02, 0x03, 0x04], but 0x04 was originally at pos 1
  let stack = [
    undo_op(0, 0, b'\x01'),    // undo modify
    undo_op(1, 1, b'\x00'),    // undo insert at 1
    undo_op(1, 2, b'\x00'),    // undo insert at 2
  ]
  revert_all_edits(buf, stack)
  // Should be back to original
  assert_eq(buf.length(), 2)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x04')
}

// ====== Kind 2 (delete) redo ======

test "apply_redo kind 1 delete" {
  // After undo of a delete at position 1, redo_stack has kind 1 with old_byte = deleted byte
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x02\x03")
  let op : UndoOp = { kind: 1, offset: 1, old_byte: b'\x02', old_bytes: [], count: 1 }
  let undo_op = apply_redo(buf, op)
  // Redo should delete byte at position 1 again
  assert_eq(buf.length(), 2)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x03')
  assert_eq(undo_op.kind, 2)
}

test "apply_redo kind 2 insert" {
  // After undo of an insert at position 1, redo_stack has kind 2 with old_byte = inserted byte
  let buf = @lib.HexBuffer::from_bytes(b"\x01\x03")
  let op : UndoOp = { kind: 2, offset: 1, old_byte: b'\x02', old_bytes: [], count: 1 }
  let undo_op = apply_redo(buf, op)
  // Redo should re-insert the byte
  assert_eq(buf.length(), 3)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x02')
  assert_eq(buf.byte_at(2), b'\x03')
  assert_eq(undo_op.kind, 1)
}
