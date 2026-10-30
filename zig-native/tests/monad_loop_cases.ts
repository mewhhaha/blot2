export const monadLoopCases = [
  {
    name: "continue_pattern_guard",
    source: `type Candidate is data = #Keep U32 | #Skip
const sequence = func () => return do (monad Maybe):
  let total = 0
  for candidate in #[#Skip, #Keep 2, #Keep 5]:
    let #Keep value = candidate else:
      continue
    use amount <- #Some value
    total := @u32.add self amount
  break total
entry const answer = func () => return Maybe.unwrap_or 0 (sequence ())
`,
    expected: { answer: 7 },
  },
  {
    name: "continue_carries_and_skips_effects",
    source: `const sequence = func () => return do (monad Maybe):
  let total = 0
  for index in 0..5:
    use value <- #Some 1
    total := @u32.add self value
    if @u32.lt index 3:
      continue
    total := @u32.add self index
  break total
entry const answer = func () => return Maybe.unwrap_or 0 (sequence ())
entry const folded = answer ()
`,
    expected: { answer: 12, folded: 12 },
  },
  {
    name: "nested_loop_break",
    source: `const sequence = func () => return do (monad Maybe):
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
entry const answer = func () => return Maybe.unwrap_or 0 (sequence ())
`,
    expected: {"answer": 42},
  },
  {
    name: "bounded_stack",
    source: `const range = func count => return do (monad Maybe):
  let total = 0
  for index in 0..count:
    use value <- #Some 1
    total := @u32.add self value
  break total
const forever = func count => return do (monad Maybe):
  let total = 0
  for ever:
    use value <- #Some 1
    total := @u32.add self value
    if @u32.eq total count:
      break $ #Some total
entry const answer = func () => return @u32.add (Maybe.unwrap_or 0 (range 100000)) (Maybe.unwrap_or 0 (forever 100000))
`,
    expected: {"answer": 200000},
  },
  {
    name: "missing_iterate",
    source: `type Box value is data = #Box value
const Box.pure = func value => return #Box value
const Box.bind = func candidate => return func next => return case candidate of
  #Box value => next value
const monad = func constructor => return @do.monad constructor
entry const answer = func () => return do:
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
    source: `const direct = func () => return do (monad Maybe):
  for outer in 0..2:
    for inner in 0..2:
      use value <- #Some 42
      break value
  break 0
const forwarded = func () => return do (monad Maybe):
  for outer in 0..2:
    for inner in 0..2:
      break $ #Some 42
  break 0
entry const answer = func () => return @u32.add (Maybe.unwrap_or 0 (direct ())) (Maybe.unwrap_or 0 (forwarded ()))
entry const folded = answer ()
`,
    expected: { answer: 84, folded: 84 },
  },
  {
    name: "array_original_handle",
    // The frozen compiler loses the generated cursor's product shape for an
    // Array carry. Native lowering retains that shape and the original array.
    reference_error: "unknown_product_shape",
    source: `const sequence = func () => return do (monad Maybe):
  let values: Array U32 = #[1,2,3]
  let total = 0
  for original in values:
    use value <- #Some original
    total := @u32.add self value
    values := @array.set self 0 9
  break @u32.add total (@array.get values 0)
entry const answer = func () => return Maybe.unwrap_or 0 (sequence ())
entry const folded = answer ()
`,
    expected: { answer: 15, folded: 15 },
  },
  {
    name: "array_product_pattern",
    source: `const sequence = func () => return do (monad Maybe):
  let total = 0
  for (left,right) in #[(20,22),(40,2)]:
    use value <- #Some (@u32.add left right)
    total := @u32.add self value
  break total
entry const answer = func () => return Maybe.unwrap_or 0 (sequence ())
`,
    expected: { answer: 84 },
  },
  {
    name: "break_visible_shadow",
    source: `const sequence = func () => return do (monad Maybe):
  let total = 0
  for index in 0..3:
    use value <- #Some 1
    total := @u32.add self value
    let total = 99
    break
  break total
entry const answer = func () => return Maybe.unwrap_or 0 (sequence ())
`,
    expected: { answer: 99 },
  },
] as const;
