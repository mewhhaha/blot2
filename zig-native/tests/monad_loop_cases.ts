export const monadLoopCases = [
  {
    name: "nested_loop_break",
    source: `const sequence = fn () => do (monad Maybe):
  let total = 0
  for outer in 0..3:
    for inner in 0..4:
      use value <- #Some 1
      total := @u32.add self value
      if @u32.eq inner 1:
        break
    total := @u32.add self 10
    if @u32.eq outer 1:
      break
  break @u32.add total 18
entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
`,
    expected: {"answer": 42},
  },
  {
    name: "bounded_stack",
    source: `const range = fn count => do (monad Maybe):
  let total = 0
  for index in 0..count:
    use value <- #Some 1
    total := @u32.add self value
  break total
const forever = fn count => do (monad Maybe):
  let total = 0
  for ever:
    use value <- #Some 1
    total := @u32.add self value
    if @u32.eq total count:
      break $ #Some total
entry const answer = fn () => @u32.add (Maybe.unwrap_or 0 (range 100000)) (Maybe.unwrap_or 0 (forever 100000))
`,
    expected: {"answer": 200000},
  },
  {
    name: "missing_iterate",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const monad = fn constructor => @do.monad constructor
entry const answer = fn () => do:
  let #Box value = do (monad Box):
    for index in 0..2:
      use #Box index
    break 42
  break value
`,
    error: "missing_member",
  },
  {
    name: "nested_return_layers",
    source: `const direct = fn () => do (monad Maybe):
  for outer in 0..2:
    for inner in 0..2:
      use value <- #Some 42
      break value
  break 0
const forwarded = fn () => do (monad Maybe):
  for outer in 0..2:
    for inner in 0..2:
      break $ #Some 42
  break 0
entry const answer = fn () => @u32.add (Maybe.unwrap_or 0 (direct ())) (Maybe.unwrap_or 0 (forwarded ()))
entry const folded = answer ()
`,
    expected: { answer: 84, folded: 84 },
  },
  {
    name: "array_original_handle",
    // The frozen compiler loses the generated cursor's product shape for an
    // Array carry. Native lowering retains that shape and the original array.
    reference_error: "unknown_product_shape",
    source: `const sequence = fn () => do (monad Maybe):
  let values: Array U32 = #[1,2,3]
  let total = 0
  for original in values:
    use value <- #Some original
    total := @u32.add self value
    values := @array.set self 0 9
  break @u32.add total (@array.get values 0)
entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
entry const folded = answer ()
`,
    expected: { answer: 15, folded: 15 },
  },
  {
    name: "array_product_pattern",
    source: `const sequence = fn () => do (monad Maybe):
  let total = 0
  for (left,right) in #[(20,22),(40,2)]:
    use value <- #Some (@u32.add left right)
    total := @u32.add self value
  break total
entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
`,
    expected: { answer: 84 },
  },
  {
    name: "break_visible_shadow",
    source: `const sequence = fn () => do (monad Maybe):
  let total = 0
  for index in 0..3:
    use value <- #Some 1
    total := @u32.add self value
    let total = 99
    break
  break total
entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
`,
    expected: { answer: 99 },
  },
] as const;
