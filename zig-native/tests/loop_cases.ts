export const loopCases = [
  {
    name: "range_carry",
    expected: { folded: 45, run: 45, reversed: 42, maximum: 1 },
    arguments: { run: 10 },
    source: `
const sum = fn limit => do:
  let total = 0
  for index in 0..limit:
    total := @u32.add self index
  return total
entry const folded = sum 10
entry const run = fn (limit: U32) => sum limit
entry const reversed = fn () => do:
  let total = 42
  for index in 9..2:
    total := @u32.add self index
  return total
entry const maximum = fn () => do:
  let total = 0
  for index in 4294967294..4294967295:
    total := @u32.add self 1
  return total
`,
  },
  {
    name: "ordinary_use_forever",
    expected: { run: 13 },
    source: `
const identity = fn value => value
entry const run = fn () => do:
  let total = 0
  for 0..5:
    total := @u32.add self 1
  for let value in #[2, 3]:
    use next <- identity (@u32.add total value)
    total := next
  for ever:
    total := @u32.add self 1
    if @u32.eq total 13:
      return total
`,
  },
  {
    name: "nested_scopes",
    expected: { nested: 138, shadowed: 42, shadow_after: 3, nested_do: 6 },
    source: `
entry const nested = fn () => do:
  let total = 0
  for row in 0..3:
    for column in 0..4:
      total := @u32.add self (@u32.add (@u32.mul row 10) column)
  return total
entry const shadowed = fn () => do:
  let total = 42
  for index in #[1, 2]:
    let total = index
    total := @u32.add self 1
  return total
entry const shadow_after = fn () => do:
  let total = 0
  for index in 0..3:
    total := @u32.add self 1
    let total = 99
    total := @u32.add self 1
  return total
entry const nested_do = fn () => do:
  let total = 0
  for index in 0..3:
    let amount = do:
      return @u32.add index 1
    total := @u32.add self amount
  return total
`,
  },
  {
    name: "array_pattern_return",
    expected: { folded: 42, run: 12, empty: 0, product: 42 },
    source: `
const first = fn values => do:
  for value in values:
    if @u32.lt 10 value:
      return value
  return 0
entry const folded = first #[1, 42, 99]
entry const run = fn () => first #[2, 12, 42]
entry const empty = fn () => first #[]
entry const product = fn () => do:
  let total = 0
  for (left, right) in #[(10, 1), (30, 1)]:
    total := @u32.add self (@u32.add left right)
  return total
`,
  },
  {
    name: "break_current_state",
    expected: { before: 1, after: 1, nested: 3, crossing_do: 42 },
    source: `
entry const before = fn () => do:
  let total = 0
  for index in 0..10:
    if @u32.eq index 2:
      break
    total := @u32.add self index
  return total
entry const after = fn () => do:
  let total = 0
  for ever:
    total := @u32.add self 1
    break
  return total
entry const nested = fn () => do:
  let total = 0
  for outer in 0..3:
    for inner in 0..10:
      total := @u32.add self 1
      break
  return total
entry const crossing_do = fn () => do:
  let total = 42
  for ever:
    let ignored = do:
      break
    total := 99
  return total
`,
  },
  {
    name: "captured_iteration",
    expected: { run: 12 },
    source: `
entry const run = fn () => do:
  let callbacks = @array.fill 3 (fn () => 0)
  for index in 0..3:
    callbacks := @array.set self index (fn () => index)
  return @u32.add (@u32.mul ((@array.get callbacks 0) ()) 100) (@u32.add (@u32.mul ((@array.get callbacks 1) ()) 10) ((@array.get callbacks 2) ()))
`,
  },
  {
    name: "simultaneous_carries_and_array_snapshot",
    expected: {
      swap: 21,
      branch: 22,
      shadow_break: 99,
      snapshot: 3,
      floating: 4.5,
    },
    source: `
entry const swap = fn () => do:
  let first = 1
  let second = 2
  for 0..3:
    let before = first
    first := second
    second := before
  return @u32.add (@u32.mul first 10) second
entry const branch = fn () => do:
  let total = 0
  for index in 0..4:
    if @u32.lt index 2:
      total := @u32.add self 1
    else:
      total := @u32.add self 10
  return total
entry const shadow_break = fn () => do:
  let total = 0
  for ever:
    total := @u32.add self 1
    let total = 99
    break
  return total
entry const snapshot = fn () => do:
  let values = #[1, 2]
  let total = 0
  for value in values:
    values := #[99]
    total := @u32.add self value
  return total
entry const floating = fn () => do:
  let total = 0.0
  for value in #[1.0, 1.5, 2.0]:
    total := @f32.add self value
  return total
`,
  },
  {
    name: "conditional_successor_shadow",
    expected: { run: 3 },
    source: `
entry const run = fn () => do:
  let total = 0
  for index in 0..3:
    if #True:
      total := @u32.add self 1
      let total = 99
      use total
  return total
`,
  },
  {
    name: "unreachable_after_break",
    error: "unreachable_statement",
    source:
      "entry const run = fn () => do:\n  for ever:\n    break\n    use ()\n  return 0\n",
  },
  {
    name: "break_outside",
    error: "break_scope",
    source: "entry const run = fn () => do:\n  break\n",
  },
  {
    name: "break_lambda_boundary",
    error: "break_scope",
    source:
      "entry const run = fn () => do:\n  for ever:\n    let closure = fn () => do:\n      break\n    return 42\n",
  },
  {
    name: "loop_local_escape",
    error: "unknown_value",
    source:
      "entry const run = fn () => do:\n  for index in 0..3:\n    use ()\n  return index\n",
  },
  {
    name: "loop_carry_type_change",
    error: "type_mismatch",
    source:
      "entry const run = fn () => do:\n  let total = 0\n  for index in 0..3:\n    total := #True\n  return total\n",
  },
  {
    name: "range_f32",
    error: "type_mismatch",
    source:
      "entry const run = fn () => do:\n  for index in 0.0..3:\n    use ()\n  return 0\n",
  },
  {
    name: "array_scalar",
    error: "missing_member",
    source:
      "entry const run = fn () => do:\n  for value in 3:\n    use ()\n  return 0\n",
  },
  {
    name: "array_refutable",
    error: "non_exhaustive_match",
    source:
      "type Maybe a is data = #Some a | #None\nentry const run = fn () => do:\n  for #Some value in #[#Some 42, #None]:\n    use value\n  return 0\n",
  },
] as const;
