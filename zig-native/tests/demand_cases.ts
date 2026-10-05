export const demandCases = [
  {
    name: "lazy_skip",
    source: `const ignore=fn ~(value:U32)=>42
entry const answer=ignore (@panic "not forced")
`,
    expected: {"answer": 42},
  },
  {
    name: "aliases_and_callback",
    source: `const twice=fn ~(value:U32)=>@u32.add (@force value) (@force value)
const alias=twice
const call=fn (callback:~U32->U32)=>callback (@u32.add 20 1)
entry const folded=call alias
entry const run=fn(value:U32)=>alias value
`,
    expected: {"folded": 42, "run": 42},
    arguments: { run: 21 },
  },
  {
    name: "partial_application",
    source: `const first=fn ~(left:U32)=>fn ~(right:U32)=>@force left
const choose=first 42
entry const answer=choose (@panic "second never forced")
`,
    expected: {"answer": 42},
  },
  {
    name: "captured_versions",
    source: `const delay=fn ~value=>value
const capture=fn ~value=>fn ()=>@force value
entry const answer=fn ()=>do:
  let amount=20
  let pending=delay (@u32.add amount 1)
  let thunk=capture (@u32.add (@force pending) 21)
  amount:=99
  return @u32.add (thunk ()) (thunk ())
`,
    expected: {"answer": 84},
  },
  {
    name: "forward_existing",
    source: `const twice=fn ~(value:U32)=>@u32.add (@force value) (@force value)
const forward=fn ~(value:U32)=>twice (@force value)
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
    source: `const eager=fn(value:U32)=>value
const pass=fn(callback:~U32->U32)=>callback 42
entry const answer=pass eager
`,
    error: "type_mismatch",
  },
  {
    name: "unused_argument_type_error",
    source: `const ignore=fn ~(value:U32)=>42
entry const answer=ignore #True
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
    source: `const lazy=fn ~(value:U32)=>@force value
const call=fn callback=>callback 42
entry const answer=call lazy
`,
    error: "type_mismatch",
  },
  {
    name: "demand_reference_not_forward",
    source: `const lazy=fn ~(value:U32)=>@force value
const forward=fn ~(value:U32)=>lazy value
entry const answer=forward 42
`,
    error: "type_mismatch",
  },
  {
    name: "break_argument_scope",
    source: `const ignore=fn ~value=>42
entry const answer=fn()=>do:
  for index in 0..1:
    use ignore (do:
      break
    )
  return 42
`,
    error: "invalid_return",
  },

  {
    name: "both_demand_infix",
    source: `infixl 60 (+) = choose
const choose = fn ~(left:U32) => fn ~(right:U32) => @force left
entry const answer = 42 + (@panic "right never forced")
entry const run = fn (value:U32) => value + (@panic "runtime right never forced")
`,
    expected: {"answer": 42, "run": 42},
    arguments: {"run": 42},
    repetitions: 16,
  },
  {
    name: "global_array_memo",
    source: `const keep = fn ~value => fn () => @force value
const saved = keep #[40, 2]
const alias = saved
entry const read = fn () => do:
  let first = saved ()
  let second = alias ()
  return @u32.add first[0] second[1]
entry const changed = fn () => do:
  let first = saved ()
  first[0] := 0
  return @u32.add first[0] (alias ())[0]
entry const allocate = fn () => do:
  let values = @array.generate 128 (fn index => index)
  return values[42]
`,
    expected: {"read": 42, "changed": 40, "allocate": 42},
    repetitions: 16,
  },
] as const;
