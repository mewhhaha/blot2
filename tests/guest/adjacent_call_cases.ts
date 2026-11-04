export const cases = [
  {
    name: "returned_record",
    source:
      "type Box is data = $Box { value: U32 }\nconst make = func value => return $Box { value }\nentry const answer = func (value: U32) => return make(value).value\n",
    valid: true,
    calls: [["answer", 42, 42], ["answer", 1, 1]],
  },
  {
    name: "returned_array",
    source:
      "const make = func value => return #[value, @u32.add value 2]\nentry const answer = func (value: U32) => return make(value)[1]\n",
    valid: true,
    calls: [["answer", 40, 42]],
  },
  {
    name: "spaced_projection",
    source:
      "type Box is data = $Box { value: U32 }\nconst add = func value => return @u32.add value 2\nentry const answer = func () => return add ($Box { value: 40 }).value\n",
    valid: true,
    calls: [["answer", null, 42]],
  },
  {
    name: "spaced_index",
    source:
      "const add = func value => return @u32.add value 2\nentry const answer = func () => return add (#[40])[0]\n",
    valid: true,
    calls: [["answer", null, 42]],
  },
  {
    name: "curried_result",
    source:
      "type Box is data = $Box { value: U32 }\nconst factory = func () => return func value => return $Box { value: @u32.add value 2 }\nentry const answer = func () => return factory()(40).value\n",
    valid: true,
    calls: [["answer", null, 42]],
  },
  {
    name: "tuple_argument",
    source:
      "const add = func pair => return do:\n  let (left, right) = pair\n  break @u32.add left right\nentry const answer = add(20, 22)\n",
    valid: true,
    reads: [["answer", 42]],
  },
  {
    name: "intrinsic_curried",
    source: "entry const answer = @u32.add(20)(22)\n",
    valid: true,
    reads: [["answer", 42]],
  },
  {
    name: "record_function",
    source:
      "type Action is data = $Action { run: U32 -> U32 }\nentry const answer = func () => return do:\n  let action = $Action { run: func value => return @u32.add value 2 }\n  break action.run(40)\n",
    valid: true,
    calls: [["answer", null, 42]],
  },
  {
    name: "result_method",
    source:
      "type Box is data = $Box { value: U32 }\nconst Box.add = func receiver => return func amount => return $Box { value: @u32.add receiver.value amount }\nconst make = func value => return $Box { value }\nentry const answer = make(40).add(2).value\n",
    valid: true,
    reads: [["answer", 42]],
  },
  {
    name: "spaced_index_field",
    source:
      "type Box is data = $Box { value: U32 }\nconst add = func left => return func right => return @u32.add left right\nentry const answer = func () => return do:\n  let values = #[$Box { value: 40 }]\n  break add values[0].value 2\n",
    valid: true,
    calls: [["answer", null, 42]],
  },
  {
    name: "grouped_callee",
    source:
      "const add = func value => return @u32.add value 2\nentry const answer = (add)(40)\n",
    valid: true,
    reads: [["answer", 42]],
  },
  {
    name: "call_index_call",
    source:
      "const make = func () => return #[func value => return @u32.add value 2]\nentry const answer = func () => return make()[0](40)\n",
    valid: true,
    calls: [["answer", null, 42]],
  },
  {
    name: "argument_projection_chain",
    source:
      "type Box is data = $Box { value: U32 }\nconst make = func value => return $Box { value }\nentry const answer = make(($Box { value: 42 }).value).value\n",
    valid: true,
    reads: [["answer", 42]],
  },
  {
    name: "bad_tuple_arity",
    source:
      "const identity = func (value: U32) => return value\nentry const answer = identity(20, 22)\n",
    valid: false,
  },
  {
    name: "bad_extra_argument",
    source:
      "const identity = func (value: U32) => return value\nentry const answer = identity(42)(1)\n",
    valid: false,
  },
  {
    name: "bad_unit_argument",
    source:
      "type Box is data = $Box { value: U32 }\nconst make = func (value: U32) => return $Box { value }\nentry const answer = make().value\n",
    valid: false,
  },
  {
    name: "bad_scalar_call",
    source: "entry const answer = 42(1)\n",
    valid: false,
  },
  {
    name: "bad_spaced_member",
    source:
      "type Box is data = $Box { value: U32 }\nconst make = func (value: U32) => return $Box { value }\nentry const answer = make (42).value\n",
    valid: false,
  },
] as const;

export const foreignSource = `
type Box is data = $Box { values: Array U32 }
const Box.pick = func receiver => return func index => return receiver.values[index]
const make = func (probe: U32 -> U32 ! {Foreign}) => return do:
  use probe 1
  break $Box { values: #[40, 42] }
entry const run = func (probe: U32 -> U32 ! {Foreign}) => return make(probe).pick(probe(2) - 1)
`;

export const foreignArithmeticSource = foreignSource.replace(
  "make(probe).pick(probe(2) - 1)",
  "probe(5) - probe(3) + make(probe).pick(probe(2) - 1) - 2",
);
