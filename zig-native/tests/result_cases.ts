export const resultCases = [
  {
    name: "expected_nominal",
    source: `type Box is data = #Box {value:U32}
const Box.from = fn value => #Box {value: @u32.add value 1}
const from = fn value => @type.result "from" value
entry const answer = fn () => do:
  let box:Box = from 41
  return box.value
`,
    expected: { "answer": 42 },
  },
  {
    name: "distinct_destinations",
    source: `type Integer is data = #Integer U32
type Float is data = #Float F32
const Integer.convert = fn value => #Integer (@u32.add value 1)
const Float.convert = fn value => #Float (@u32.to_f32 value)
const convert = fn value => @type.result "convert" value
const alias = convert
entry const integer = fn () => do:
  let #Integer value:Integer = alias 41
  return value
entry const floating = fn () => do:
  let #Float value:Float = alias 42
  return value
`,
    expected: { "integer": 42, "floating": 42 },
  },
  {
    name: "generic_destination",
    source: `type Box value is data = #Box value
const Box.from = fn value => #Box value
const from = fn value => @type.result "from" value
entry const integer = fn () => do:
  let #Box value:Box U32 = from 42
  return value
entry const floating = fn () => do:
  let #Box value:Box F32 = from 1.25
  return value
`,
    expected: { "integer": 42, "floating": 1.25 },
  },
  {
    name: "input_owner_not_selected",
    source: `type Source is data = #Source U32
type Target is data = #Target U32
const Source.from = fn value => @panic "input owner was selected"
const Target.from = fn (source:Source) => do:
  let #Source value=source
  return #Target (@u32.add value 1)
entry const answer = fn () => do:
  let #Target value:Target = @type.result "from" (#Source 41)
  return value
`,
    expected: { "answer": 42 },
  },
  {
    name: "unused_missing",
    source: `type Missing is data = #Missing U32
const unused = fn (value:U32) -> Missing => @type.result "from" value
entry const answer = 42
`,
    expected: { "answer": 42 },
  },
  {
    name: "selected_input_mismatch",
    source: `type Target is data = #Target U32
const Target.from = fn (value:F32) => #Target 42
entry const answer:Target = @type.result "from" 1
`,
    error: "type_mismatch",
  },
  {
    name: "selected_result_mismatch",
    source: `type Target is data = #Target U32
const Target.from = fn value => 42
entry const answer:Target = @type.result "from" 1
`,
    error: "type_mismatch",
  },
  {
    name: "ambiguous_destination",
    source: `const from = fn value => @type.result "from" value
entry const answer = from 42
`,
    error: "ambiguous_associated",
  },
  {
    name: "partial_primitive",
    source: `const from = @type.result "from"
entry const answer = 42
`,
    error: "call_arity",
  },
  {
    name: "nonliteral_member",
    source: `const name = 42
entry const answer = @type.result name 42
`,
    error: "literal_required",
  },
] as const;
