export const monadCases = [
  {
    name: "phantom_input_instances",
    source: `type Option value is data = #Present value | #Absent
const Option.pure = fn value => #Present value
const Option.bind = fn candidate => fn next => case candidate of
  #Present value => next value
  #Absent => #Absent
const unwrap = fn candidate => case candidate of
  #Present value => value
  #Absent => 42
const sequence = fn candidate => do (@do.monad Option):
  use ignored <- candidate
  break 42
entry const empty = fn () => unwrap (sequence #Absent)
entry const integer = fn () => unwrap (sequence (#Present 99))
entry const floating = fn () => unwrap (sequence (#Present 1.25))
entry const folded = unwrap (sequence #Absent)
`,
    expected: { empty: 42, integer: 42, floating: 42, folded: 42 },
  },
  {
    name: "generic_alias",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const monad = fn constructor => @do.monad constructor
const identity = fn value => value
const resolver = identity (monad (identity Box))
const sequence = fn selected => fn candidate => do selected:
  use value <- candidate
  break @u32.add value 2
entry const answer = fn () => do:
  let #Box value = sequence resolver (#Box 40)
  break value
entry const folded = answer ()
`,
    expected: {"answer": 42, "folded": 42},
  },
  {
    name: "lift_forward_unit",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const monad = fn constructor => @do.monad constructor
const present = do (monad Box):
  break 40
const forwarded = do (monad Box):
  break $ #Box 2
const finished = do (monad Box):
  #Box 99
entry const answer = fn () => do:
  let #Box left = present
  let #Box right = forwarded
  let #Box () = finished
  break @u32.add left right
`,
    expected: {"answer": 42},
  },
  {
    name: "nested_return_scopes",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const monad = fn constructor => @do.monad constructor
const sequence = fn () => do (monad Box):
  let plain = do:
    use value <- #Box 40
    break value
  use value <- plain
  let extra = do (monad Box):
    break 2
  let #Box two = extra
  break @u32.add value two
entry const answer = fn () => do:
  let #Box value = sequence ()
  break value
`,
    expected: {"answer": 42},
  },
  {
    name: "continuation_multiplicity",
    source: `type Twice value is data = #Twice value
const Twice.pure = fn value => #Twice value
const Twice.bind = fn candidate => fn next => case candidate of
  #Twice value => do:
    let #Twice first = next value
    let #Twice second = next (@u32.add value 1)
    break #Twice (@u32.add first second)
const sequence = fn () => do (@do.monad Twice):
  let total = 0
  use value <- #Twice 20
  total := @u32.add self value
  break total
entry const answer = fn () => do:
  let #Twice value = sequence ()
  break value
`,
    expected: {"answer": 41},
  },
  {
    name: "selected_source_pure",
    source: `type Box value is data = #Box value
const Box.pure = fn (value:U32) => #Box (@u32.add value 2)
entry const answer = fn () => do:
  let #Box value = do (@do.monad Box):
    break 40
  break value
`,
    expected: {"answer": 42},
  },
  {
    name: "bind_failure",
    source: `type Option value is data = #Present value | #Absent
const Option.pure = fn value => #Present value
const Option.bind = fn candidate => fn next => case candidate of
  #Present value => next value
  #Absent => #Absent
const sequence = fn () => do (@do.monad Option):
  use value <- #Absent
  break @panic "continuation must not execute"
entry const answer = fn () => case sequence () of
  #Present value => value
  #Absent => 42
`,
    expected: {"answer": 42},
  },
  {
    name: "missing_pure",
    source: `type Box value is data = #Box value
entry const answer = do (@do.monad Box):
  break 42
`,
    error: "missing_member",
  },
  {
    name: "missing_bind",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
entry const answer = do (@do.monad Box):
  use value <- #Box 40
  break @u32.add value 2
`,
    error: "missing_member",
  },
  {
    name: "wrong_pure_owner",
    source: `type Box value is data = #Box value
const Box.pure = fn value => value
entry const answer = do (@do.monad Box):
  break 42
`,
    error: "type_mismatch",
  },
  {
    name: "invalid_constructor",
    source: `entry const answer = @do.monad 42
`,
    error: "type_constructor_required",
  },
  {
    name: "invalid_resolver",
    source: `entry const answer = do (42):
  break 42
`,
    error: "invalid_provider",
  },
  {
    name: "pure_ignores_mixed_returns",
    source: `type Box value is data = #Box value
const Box.pure = fn ignored => #Box 42
const sequence = fn enabled => do (@do.monad Box):
  if enabled:
    break #True
  break 40
entry const answer = fn () => do:
  let #Box first = sequence #True
  let #Box second = sequence #False
  break @u32.add first second
`,
    expected: { answer: 84 },
  },
  {
    name: "scalar_bind_input",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn (candidate:U32) => fn next => next candidate
const sequence = fn () => do (@do.monad Box):
  use value <- 40
  break @u32.add value 2
entry const answer = fn () => do:
  let #Box value = sequence ()
  break value
`,
    expected: { answer: 42 },
  },

  {
    name: "conditional_join",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const sequence=fn enabled=>do (@do.monad Box):
  let total=20
  if enabled:
    use value <- #Box 21
    total := @u32.add self value
  else:
    total := @u32.add self 22
  break total
entry const answer=fn()=>do:
  let #Box first=sequence #True
  let #Box second=sequence #False
  break @u32.add first second
`,
    expected: { answer: 83 },
  },
  {
    name: "conditional_failure",
    source: `type Option value is data = #Present value | #Absent
const Option.pure = fn value => #Present value
const Option.bind = fn candidate => fn next => case candidate of
  #Present value => next value
  #Absent => #Absent
const sequence=fn enabled=>do (@do.monad Option):
  if enabled:
    use #Absent
  break 42
entry const answer=fn()=>do:
  let #Absent=sequence #True else:
    break 0
  let #Present value=sequence #False else:
    break 0
  break value
`,
    expected: { answer: 42 },
  },
  {
    name: "guarded_forward",
    source: `type Option value is data = #Present value | #Absent
const Option.pure = fn value => #Present value
const Option.bind = fn candidate => fn next => case candidate of
  #Present value => next value
  #Absent => #Absent
const sequence=fn candidate=>do (@do.monad Option):
  let #Present value=candidate else:
    break $ #Absent
  break @u32.add value 2
entry const answer=fn()=>do:
  let #Absent=sequence #Absent else:
    break 0
  let #Present value=sequence (#Present 40) else:
    break 0
  break value
`,
    expected: { answer: 42 },
  },
  {
    name: "bind_transforms_suffix",
    source: `type Box value is data = #Box value
const Box.pure=fn value=>#Box value
const Box.bind=fn candidate=>fn next=>case candidate of
  #Box value=>do:
    let #Box result=next value
    break #Box (@u32.to_f32 result)
const sequence=fn()=>do (@do.monad Box):
  use value <- #Box 40
  break @u32.add value 2
entry const answer=fn()=>do:
  let #Box value=sequence ()
  break value
`,
    expected: { answer: 42 },
  },
  {
    name: "resolver_first_failure",
    source: `type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const create=fn()=>if #True then @panic "resolver executes first" else @do.monad Box
entry const answer:U32=do:
  let #Box value=do (create ()):
    break @panic "body executes second"
  break value
`,
    error: "const_panic",
  },
] as const;
