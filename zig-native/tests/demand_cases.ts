export const demandCases = [
  {
    name: "lazy_skip",
    source: `const ignore=func ~(value:U32)=> return 42
entry const answer=ignore (@panic "not forced")
`,
    expected: {"answer": 42},
  },
  {
    name: "aliases_and_callback",
    source: `const twice=func ~(value:U32)=> return @u32.add (@force value) (@force value)
const alias=twice
const call=func (callback:~U32->U32)=> return callback (@u32.add 20 1)
entry const folded=call alias
entry const run=func(value:U32)=> return alias value
`,
    expected: {"folded": 42, "run": 42},
    arguments: { run: 21 },
  },
  {
    name: "partial_application",
    source: `const first=func ~(left:U32)=> return func ~(right:U32)=> return @force left
const choose=first 42
entry const answer=choose (@panic "second never forced")
`,
    expected: {"answer": 42},
  },
  {
    name: "captured_versions",
    source: `const delay=func ~value=> return value
const capture=func ~value=> return func ()=> return @force value
entry const answer=func ()=> return do:
  let amount=20
  let pending=delay (@u32.add amount 1)
  let thunk=capture (@u32.add (@force pending) 21)
  amount:=99
  break @u32.add (thunk ()) (thunk ())
`,
    expected: {"answer": 84},
  },
  {
    name: "forward_existing",
    source: `const twice=func ~(value:U32)=> return @u32.add (@force value) (@force value)
const forward=func ~(value:U32)=> return twice (@force value)
entry const answer=forward 21
`,
    expected: {"answer": 42},
  },
  {
    name: "force_eager",
    source: `entry const answer=@force 42
`,
    error: "type_mismatch",
  },
  {
    name: "mode_mismatch",
    source: `const eager=func(value:U32)=> return value
const pass=func(callback:~U32->U32)=> return callback 42
entry const answer=pass eager
`,
    error: "type_mismatch",
  },
  {
    name: "unused_argument_type_error",
    source: `const ignore=func ~(value:U32)=> return 42
entry const answer=ignore true
`,
    error: "type_mismatch",
  },
  {
    name: "partial_force",
    source: `const force=@force
entry const answer=42
`,
    error: "call_arity",
  },
  {
    name: "unknown_callback_is_eager",
    source: `const lazy=func ~(value:U32)=> return @force value
const call=func callback=> return callback 42
entry const answer=call lazy
`,
    error: "type_mismatch",
  },
  {
    name: "demand_reference_not_forward",
    source: `const lazy=func ~(value:U32)=> return @force value
const forward=func ~(value:U32)=> return lazy value
entry const answer=forward 42
`,
    error: "type_mismatch",
  },
  {
    name: "break_argument_scope",
    source: `const ignore=func ~value=> return 42
entry const answer=func()=> return do:
  for index in 0..1:
    use ignore (do:
      break
    )
  break 42
`,
    error: "invalid_return",
  },

  {
    name: "both_demand_infix",
    source: `infixl 60 (+) = choose
const choose = func ~(left:U32) => return func ~(right:U32) => return @force left
entry const answer = 42 + (@panic "right never forced")
entry const run = func (value:U32) => return value + (@panic "runtime right never forced")
`,
    expected: {"answer": 42, "run": 42},
    arguments: {"run": 42},
    repetitions: 16,
  },
  {
    name: "global_array_memo",
    source: `const keep = func ~value => return func () => return @force value
const saved = keep #[40, 2]
const alias = saved
entry const read = func () => return do:
  let first = saved ()
  let second = alias ()
  break @u32.add first[0] second[1]
entry const changed = func () => return do:
  let first = saved ()
  first[0] := 0
  break @u32.add first[0] (alias ())[0]
entry const allocate = func () => return do:
  let values = @array.generate 128 (func index => return index)
  break values[42]
`,
    expected: {"read": 42, "changed": 40, "allocate": 42},
    repetitions: 16,
  },
] as const;
