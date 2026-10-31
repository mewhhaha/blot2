export const loopCases = [
  {
    name: "continue_range_collection_and_pattern_guard",
    expected: { range: 18, collection: 8, nested: 6, guarded: 7, folded: 18 },
    source: `
type Maybe a is data = $Some a | $None
entry const range = func () => return do:
  let total = 0
  for index in 0..6:
    total := @u32.add self 1
    if @u32.lt index 3:
      continue
    total := @u32.add self index
  break total
entry const collection = func () => return do:
  let total = 0
  for value in #[1, 2, 3, 4]:
    if @u32.eq value 2:
      continue
    total := @u32.add self value
  break total
entry const nested = func () => return do:
  let total = 0
  for outer in 0..3:
    for inner in 0..3:
      if @u32.eq inner 1:
        continue
      total := @u32.add self 1
  break total
entry const guarded = func () => return do:
  let total = 0
  for candidate in #[$None, $Some 2, $Some 5]:
    let $Some value = candidate else:
      continue
    total := @u32.add self value
  break total
entry const folded = range ()
`,
  },
  {
    name: "continue_forever_and_simultaneous_carries",
    expected: { forever: 7, swap: 21, shadow: 99, snapshot: 3, row: 6 },
    source: `
entry const forever = func () => return do:
  let total = 0
  for ever:
    total := @u32.add self 1
    if @u32.lt total 7:
      continue
    break
  break total
entry const swap = func () => return do:
  let first = 1
  let second = 2
  for 0..3:
    let before = first
    first := second
    second := before
    continue
  break @u32.add (@u32.mul first 10) second
entry const shadow = func () => return do:
  let total = 0
  for 0..1:
    total := @u32.add self 1
    let total = 99
    continue
  break total
entry const snapshot = func () => return do:
  let values = #[1, 2]
  let total = 0
  for value in values:
    values := #[99]
    total := @u32.add self value
    continue
  break total
entry const row = func () => return do:
  let total = 0
  for (left, right) in #[(1, 2), (3, 4)]:
    if @u32.eq left 3:
      continue
    total := @u32.add self (@u32.add left right)
  break @u32.add total 3
`,
  },
  {
    name: "range_carry",
    expected: { folded: 45, run: 45, reversed: 42, maximum: 1 },
    arguments: { run: 10 },
    source: `
const sum = func limit => return do:
  let total = 0
  for index in 0..limit:
    total := @u32.add self index
  break total
entry const folded = sum 10
entry const run = func (limit: U32) => return sum limit
entry const reversed = func () => return do:
  let total = 42
  for index in 9..2:
    total := @u32.add self index
  break total
entry const maximum = func () => return do:
  let total = 0
  for index in 4294967294..4294967295:
    total := @u32.add self 1
  break total
`,
  },
  {
    name: "ordinary_use_forever",
    expected: { run: 13 },
    source: `
const identity = func value => return value
entry const run = func () => return do:
  let total = 0
  for 0..5:
    total := @u32.add self 1
  for let value in #[2, 3]:
    use next <- identity (@u32.add total value)
    total := next
  for ever:
    total := @u32.add self 1
    if @u32.eq total 13:
      break total
`,
  },
  {
    name: "nested_scopes",
    expected: { nested: 138, shadowed: 42, shadow_after: 3, nested_do: 6 },
    source: `
entry const nested = func () => return do:
  let total = 0
  for row in 0..3:
    for column in 0..4:
      total := @u32.add self (@u32.add (@u32.mul row 10) column)
  break total
entry const shadowed = func () => return do:
  let total = 42
  for index in #[1, 2]:
    let total = index
    total := @u32.add self 1
  break total
entry const shadow_after = func () => return do:
  let total = 0
  for index in 0..3:
    total := @u32.add self 1
    let total = 99
    total := @u32.add self 1
  break total
entry const nested_do = func () => return do:
  let total = 0
  for index in 0..3:
    let amount = do:
      break @u32.add index 1
    total := @u32.add self amount
  break total
`,
  },
  {
    name: "array_pattern_return",
    expected: { folded: 42, run: 12, empty: 0, product: 42 },
    source: `
const first = func values => return do:
  for value in values:
    if @u32.lt 10 value:
      break value
  break 0
entry const folded = first #[1, 42, 99]
entry const run = func () => return first #[2, 12, 42]
entry const empty = func () => return first #[]
entry const product = func () => return do:
  let total = 0
  for (left, right) in #[(10, 1), (30, 1)]:
    total := @u32.add self (@u32.add left right)
  break total
`,
  },
  {
    name: "break_current_state",
    expected: { before: 1, after: 1, nested: 3, crossing_do: 42 },
    source: `
entry const before = func () => return do:
  let total = 0
  for index in 0..10:
    if @u32.eq index 2:
      break
    total := @u32.add self index
  break total
entry const after = func () => return do:
  let total = 0
  for ever:
    total := @u32.add self 1
    break
  break total
entry const nested = func () => return do:
  let total = 0
  for outer in 0..3:
    for inner in 0..10:
      total := @u32.add self 1
      break
  break total
entry const crossing_do = func () => return do:
  let total = 42
  for ever:
    let ignored = do:
      break
    total := 99
  break total
`,
  },
  {
    name: "captured_iteration",
    expected: { run: 12 },
    source: `
entry const run = func () => return do:
  let callbacks = @array.fill 3 (func () => return 0)
  for index in 0..3:
    callbacks := @array.set self index (func () => return index)
  break @u32.add (@u32.mul ((@array.get callbacks 0) ()) 100) (@u32.add (@u32.mul ((@array.get callbacks 1) ()) 10) ((@array.get callbacks 2) ()))
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
entry const swap = func () => return do:
  let first = 1
  let second = 2
  for 0..3:
    let before = first
    first := second
    second := before
  break @u32.add (@u32.mul first 10) second
entry const branch = func () => return do:
  let total = 0
  for index in 0..4:
    if @u32.lt index 2:
      total := @u32.add self 1
    else:
      total := @u32.add self 10
  break total
entry const shadow_break = func () => return do:
  let total = 0
  for ever:
    total := @u32.add self 1
    let total = 99
    break
  break total
entry const snapshot = func () => return do:
  let values = #[1, 2]
  let total = 0
  for value in values:
    values := #[99]
    total := @u32.add self value
  break total
entry const floating = func () => return do:
  let total = 0.0
  for value in #[1.0, 1.5, 2.0]:
    total := @f32.add self value
  break total
`,
  },
  {
    name: "conditional_successor_shadow",
    expected: { run: 3 },
    source: `
entry const run = func () => return do:
  let total = 0
  for index in 0..3:
    if true:
      total := @u32.add self 1
      let total = 99
      use total
  break total
`,
  },
  {
    name: "unreachable_after_break",
    error: "unreachable_statement",
    source:
      "entry const run = func () => return do:\n  for ever:\n    break\n    use ()\n  break 0\n",
  },
  {
    name: "break_outside",
    error: "break_scope",
    source: "entry const run = func () => return do:\n  break\n",
  },
  {
    name: "continue_outside",
    error: "continue_scope",
    source: "entry const run = func () => return do:\n  continue\n",
  },
  {
    name: "continue_lambda_boundary",
    error: "continue_scope",
    source:
      "entry const run = func () => return do:\n  for ever:\n    let closure = func () => return do:\n      continue\n    break\n  break 0\n",
  },
  {
    name: "unreachable_after_continue",
    error: "unreachable_statement",
    source:
      "entry const run = func () => return do:\n  for ever:\n    continue\n    use ()\n",
  },
  {
    name: "break_lambda_boundary",
    error: "break_scope",
    source:
      "entry const run = func () => return do:\n  for ever:\n    let closure = func () => return do:\n      break\n    break 42\n",
  },
  {
    name: "loop_local_escape",
    error: "unknown_value",
    source:
      "entry const run = func () => return do:\n  for index in 0..3:\n    use ()\n  break index\n",
  },
  {
    name: "loop_carry_type_change",
    error: "type_mismatch",
    source:
      "entry const run = func () => return do:\n  let total = 0\n  for index in 0..3:\n    total := true\n  break total\n",
  },
  {
    name: "range_f32",
    error: "type_mismatch",
    source:
      "entry const run = func () => return do:\n  for index in 0.0..3:\n    use ()\n  break 0\n",
  },
  {
    name: "array_scalar",
    error: "missing_member",
    source:
      "entry const run = func () => return do:\n  for value in 3:\n    use ()\n  break 0\n",
  },
  {
    name: "array_refutable",
    error: "non_exhaustive_match",
    source:
      "type Maybe a is data = $Some a | $None\nentry const run = func () => return do:\n  for $Some value in #[$Some 42, $None]:\n    use value\n  break 0\n",
  },
] as const;
