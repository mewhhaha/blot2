// Independent source programs, not fixed-output snapshots of the new compiler.
// reference_test.mjs runs this accepted corpus against the Bend implementation.
export const accepted = [
  {name:'scalar constants', source:`entry const a = 0\nentry const b = 0xffffffff\nentry const c = 4_096\nentry const yes = True\nentry const no = False\nentry const unit = ()\nentry const f = 1.25\n`, read:{a:0,b:4294967295,c:4096,yes:true,no:false,unit:null,f:1.25}},
  {name:'precedence',source:`entry const answer = fn () => 2 + 3 * (4 - 1)\n`,calls:[['answer',null,11]]},
  {name:'wrapping',source:`entry const a = 0xffffffff + 1\nentry const b = 0 - 1\nentry const c = 0xffffffff * 0xffffffff\nentry const multiply = fn (x: U32) => x * 0xffffffff\n`,read:{a:0,b:4294967295,c:1},calls:[['multiply',4294967295,1]]},
  {name:'unsigned ordering',source:`entry const lt = fn x => x < 0xffffffff\nentry const le = fn x => x <= 1\nentry const gt = fn x => x > 0\nentry const ge = fn x => x >= 0xffffffff\nentry const eq = fn x => x == 42\nentry const ne = fn x => x != 42\n`,calls:[['lt',2147483648,true],['le',2,false],['gt',4294967295,true],['ge',4294967295,true],['eq',42,true],['ne',42,false]]},
  {name:'forward dependencies',source:`entry const answer = fn () => add_two seed\nconst seed = forty + 0\nconst add_two = fn x => x + 2\nconst forty = 40\n`,calls:[['answer',null,42]],exports:['answer']},
  {name:'scalar annotation',source:`entry const f: U32 -> U32 = fn x -> U32 => x + 1\nentry const answer: U32 = 42\n`,read:{answer:42},calls:[['f',41,42]]},
  {name:'recursion',source:`entry const factorial = fn (n: U32) -> U32 => do:\n  if n <= 1:\n    return 1\n  return n * factorial (n - 1)\nentry const six = factorial 3\n`,read:{six:6},calls:[['factorial',0,1],['factorial',6,720]]},
  {name:'mutual recursion',source:`entry const even = fn (n: U32) -> Bool => do:\n  if n == 0:\n    return True\n  return odd (n - 1)\nconst odd = fn (n: U32) -> Bool => do:\n  if n == 0:\n    return False\n  return even (n - 1)\n`,calls:[['even',10,true],['even',11,false]]},
  {name:'unit block',source:`entry const answer = fn () => do:\n  42\n`,calls:[['answer',null,null]]},
  {name:'lexical shadowing',source:`entry const answer = fn () => do:\n  let x = 7\n  if True:\n    let x = 99\n    x\n  return x\n`,calls:[['answer',null,7]]},
  {name:'rebinding and self',source:`entry const answer = fn (x: U32) => do:\n  x := self + x\n  x := self + 2\n  return x\n`,calls:[['answer',20,42]]},
  {name:'rebinding type change',source:`entry const answer = fn () => do:\n  let x = 1\n  x := True\n  return x\n`,calls:[['answer',null,true]]},
  {name:'nested return boundary',source:`entry const answer = fn () => do:\n  let x = do:\n    return 40\n  return x + 2\n`,calls:[['answer',null,42]]},
  {name:'if else',source:`entry const choose = fn (flag: Bool) => do:\n  if flag:\n    return 7\n  else:\n    return 9\n`,calls:[['choose',true,7],['choose',false,9]]},
  {name:'nested if return',source:`entry const choose = fn (flag: Bool) => do:\n  if flag:\n    if True:\n      return 42\n  return 0\n`,calls:[['choose',true,42],['choose',false,0]]},
  {name:'block fallthrough',source:`entry const answer = fn (flag: Bool) => do:\n  if flag:\n    return ()\n`,calls:[['answer',true,null],['answer',false,null]]},
  {name:'constant blocks',source:`entry const answer = do:\n  let x = 20\n  x := self * 2\n  return x + 2\n`,read:{answer:42}},
  {name:'F32 arithmetic',source:`entry const arithmetic = fn (x: F32) => (x + 1.0) * 2.0 / 4.0 - 0.25\nentry const round = 16777216.0 + 1.0\nentry const negate = fn x => -x\n`,read:{round:16777216},calls:[['arithmetic',2,1.25],['negate',2,-2],['negate',0,-0]]},
  {name:'F32 intrinsics',source:`entry const square_root = fn x => @f32.sqrt x\nentry const absolute = fn x => @f32.abs x\nentry const floor = fn x => @f32.floor x\nentry const ceil = fn x => @f32.ceil x\nentry const trunc = fn x => @f32.trunc x\nentry const negative_zero = @f32.neg 0.0\n`,read:{negative_zero:-0},calls:[['square_root',9,3],['absolute',-2,2],['floor',-2.2,-3],['ceil',-2.2,-2],['trunc',-2.2,-2]]},
  {name:'F32 exceptional',source:`entry const infinity = 1.0 / 0.0\nentry const nan = 0.0 / 0.0\nentry const eq = fn x => x == (0.0 / 0.0)\nentry const ne = fn x => x != (0.0 / 0.0)\n`,read:{infinity:Infinity,nan:NaN},calls:[['eq',NaN,false],['ne',NaN,true]]},
  {name:'F32 conversions',source:`entry const to_u32 = fn x => @f32.to_u32 x\nentry const to_f32 = fn x => @u32.to_f32 x\nentry const big = @u32.to_f32 0xffffffff\nentry const neg = @f32.to_u32 (-2.5)\nentry const nan = @f32.to_u32 (0.0 / 0.0)\n`,read:{big:4294967296,neg:0,nan:0},calls:[['to_u32',-1,0],['to_u32',NaN,0],['to_u32',Infinity,4294967295],['to_u32',3.9,3],['to_f32',4294967295,4294967296]]},
  {name:'explicit intrinsics',source:`entry const add = fn x => @u32.add x 2\nentry const sum = @u32.add 40 2\nentry const product = @f32.mul 2.0 3.0\n`,read:{sum:42,product:6},calls:[['add',40,42]]},
  {name:'multiline application',source:`entry const answer = fn () => (\n  @u32.add\n    40\n    2\n)\n`,calls:[['answer',null,42]]},
  {name:'comments and CRLF',source:'// comment\r\nentry const answer = fn () => do:\r\n  // indented\r\n\r\n  return 42 // end\r\n',calls:[['answer',null,42]]},
  {name:'dead const evaluation',source:`const loop = fn (n: U32) -> U32 => loop n\nconst unused = loop 0\nentry const answer = 42\n`,read:{answer:42},exports:['answer']},
  {name:'entry let function',source:`entry let answer = fn () => 42\n`,calls:[['answer',null,42]]},
  {name:'range carried state',source:`entry const sum = fn (end: U32) => do:
  let total = 0
  for index in 0..end:
    total := self + index
  return total
`,calls:[['sum',0,0],['sum',5,10],['sum',100,4950]]},
  {name:'discarded range',source:`entry const answer = fn () => do:
  let x = 0
  for 0..5:
    x := self + 1
  return x
`,calls:[['answer',null,5]]},
  {name:'explicit range binder',source:`entry const answer = fn () => do:
  let x = 0
  for let i in 2..5:
    x := self + i
  return x
`,calls:[['answer',null,9]]},
  {name:'reverse range',source:`entry const answer = fn () => do:
  let x = 7
  for i in 5..2:
    x := self + i
  return x
`,calls:[['answer',null,7]]},
  {name:'nested carried loops',source:`entry const answer = fn () => do:
  let total = 0
  for i in 0..3:
    for j in 0..4:
      total := self + i * j
  return total
`,calls:[['answer',null,18]]},
  {name:'loop if shadow',source:`entry const answer = fn () => do:
  let total = 1
  for 0..3:
    if True:
      total := self + 100
    total := self + 1
  return total
`,calls:[['answer',null,4]]},
  {name:'loop inner do shadow',source:`entry const answer = fn () => do:
  let total = 1
  for 0..3:
    let ignored = do:
      total := self + 100
      return total
    total := self + 1
  return total
`,calls:[['answer',null,4]]},
  {name:'return from loop',source:`entry const answer = fn () => do:
  for i in 0..10:
    if i == 4:
      return 42
  return 0
`,calls:[['answer',null,42]]},
  {name:'forever return',source:`entry const answer = fn () => do:
  let x = 0
  for ever:
    x := self + 1
    if x == 5:
      return x
`,calls:[['answer',null,5]]},
  {name:'const range and forever',source:`entry const sum = do:
  let x = 0
  for i in 0..5:
    x := self + i
  return x
entry const stop = do:
  let x = 0
  for ever:
    x := self + 1
    if x == 5:
      return x
`,read:{sum:10,stop:5}},
  {name:'polymorphic scalar identity',source:`const identity = fn value => value
entry const integer = identity 42
entry const floating = identity 1.25
entry const boolean = identity True
entry const unit = identity ()
entry const uint = fn (value: U32) => identity value
entry const float = fn (value: F32) => identity value
entry const bool = fn (value: Bool) => identity value
entry const nothing = fn () => identity ()
`,read:{integer:42,floating:1.25,boolean:true,unit:null},calls:[['uint',4294967295,4294967295],['float',-0,-0],['bool',false,false],['nothing',null,null]]},
  {name:'polymorphic forward composition',source:`entry const integer = outer 42
entry const floating = outer 1.5
entry const boolean = outer False
const outer = fn value => inner value
const inner = fn value => identity value
const identity = fn value => value
`,read:{integer:42,floating:1.5,boolean:false}},
  {name:'polymorphic numeric helpers',source:`const twice = fn value => value + value
const square = fn value => value * value
const compose = fn value => square (twice value)
entry const integer = compose 3
entry const floating = compose 1.5
entry const uint = fn (value: U32) => twice value
entry const float = fn (value: F32) => twice value
`,read:{integer:36,floating:9},calls:[['uint',4294967295,4294967294],['float',1.25,2.5]]},
  {name:'polymorphic comparison',source:`const equal_self = fn value => value == value
entry const integer = equal_self 42
entry const floating = equal_self 1.25
entry const nan = equal_self (0.0 / 0.0)
`,read:{integer:true,floating:true,nan:false}},
  {name:'polymorphic scalar recursion',source:`const recurse = fn value => do:
  if True:
    return value
  return recurse value
entry const integer = recurse 42
entry const floating = recurse 1.25
entry const boolean = recurse True
entry const unit = recurse ()
`,read:{integer:42,floating:1.25,boolean:true,unit:null}},
  {name:'polymorphic mutual recursion',source:`const first = fn value => second value
const second = fn value => do:
  if True:
    return value
  return first value
entry const integer = first 42
entry const floating = first 1.25
entry const boolean = first True
entry const unit = first ()
`,read:{integer:42,floating:1.25,boolean:true,unit:null}},
  {name:'polymorphic recursive numeric constraint',source:`const first = fn value => second value
const second = fn value => do:
  if True:
    return value + value
  return first value
entry const integer = first 21
entry const floating = first 1.25
`,read:{integer:42,floating:2.5}},
  {name:'polymorphic block locals',source:`const identity = fn value => do:
  let copy = value
  copy := self
  let nested = do:
    return copy
  return nested
entry const integer = identity 42
entry const floating = identity 1.25
entry const boolean = identity True
`,read:{integer:42,floating:1.25,boolean:true}},
  {name:'polymorphic loop carried values',source:`const repeat = fn value => do:
  let result = value
  for 0..3:
    result := self
  return result
entry const integer = repeat 42
entry const floating = repeat 1.25
entry const boolean = repeat False
`,read:{integer:42,floating:1.25,boolean:false}},
  {name:'polymorphic unused parameter',source:`const ignore = fn value => 42
entry const integer = ignore 1
entry const floating = ignore 1.25
entry const boolean = ignore False
entry const unit = ignore ()
`,read:{integer:42,floating:42,boolean:42,unit:42}},
  {name:'polymorphic global constant capture',source:`const answer = 42
const read = fn ignored => answer
entry const integer = read 1
entry const floating = read 1.25
entry const boolean = read False
`,read:{integer:42,floating:42,boolean:42}},
  {name:'dependency respects lexical shadowing',source:`const identity = fn value => do:
  let caller = value
  return caller
const caller = fn () => identity True
entry const integer = identity 42
entry const floating = identity 1.25
entry const boolean = caller ()
`,read:{integer:42,floating:1.25,boolean:true}},
  {name:'dependency respects let initializer',source:`const identity = fn value => value
const wrapper = fn value => do:
  let identity = identity value
  return identity
entry const integer = wrapper 42
entry const floating = wrapper 1.25
`,read:{integer:42,floating:1.25}},
  {name:'dead deferred numeric obligation',source:`const unused = fn x => True + False
entry const answer = 42
`,read:{answer:42},exports:['answer']},
  {name:'dead generic numeric helper',source:`const unused = fn value => value + value
entry const answer = 42
`,read:{answer:42},exports:['answer']},
  {name:'multiple result specializations',source:`const bottom = fn value => bottom value
entry const uint = fn () => do:
  if False:
    return bottom ()
  return 42
entry const float = fn () => do:
  if False:
    return bottom ()
  return 1.25
`,calls:[['uint',null,42],['float',null,1.25]]},
];

export const rejected = [
  ['concrete global constant capture','const shared = 42\nconst read = fn ignored => shared\nentry const integer: U32 = read True\nentry const floating: F32 = read 42\n','type_mismatch','type_mismatch'],
  // Constants with unresolved types are not generalized by this milestone.
  // The reference instead reaches const_budget on this divergent initializer;
  // this case is deliberately NOT a diagnostic-parity assertion.
  ['unresolved shared global type (unsupported)','const bottom = fn x => bottom x\nconst shared = bottom ()\nconst read = fn ignored => shared\nentry const integer: U32 = read True\nentry const floating: F32 = read 42\n','type_mismatch'],
  ['reachable concrete numeric obligation','const broken = fn x => True + False\nentry const answer = broken ()\n','unsupported_numeric_type','missing_associated'],
  ['generic Bool numeric obligation','const twice = fn x => x + x\nentry const answer = twice True\n','unsupported_numeric_type','missing_associated'],
  ['generic U32 division obligation','const divide = fn x => x / x\nentry const answer = divide 2\n','missing_implementation','missing_associated'],
  ['forward generic constraint','const outer = fn x => twice x\nconst twice = fn x => x + x\nentry const answer = outer True\n','unsupported_numeric_type','missing_associated'],
  ['recursive generic constraint','const f = fn x => g x\nconst g = fn x => do:\n  if True:\n    return x + x\n  return f x\nentry const answer = f True\n','unsupported_numeric_type','missing_associated'],
  ['monomorphic recursive input','const f = fn x => do:\n  f True\n  return f 1\nentry const answer = 42\n','type_mismatch','type_mismatch'],
  ['monomorphic recursive result','const f = fn x => do:\n  let a: U32 = f x\n  let b: F32 = f x\n  return x\nentry const answer = 42\n','type_mismatch','type_mismatch'],
  ['dead generic bad call','const identity = fn (x: U32) => x\nconst unused = fn x => identity True\nentry const answer = 42\n','type_mismatch','type_mismatch'],
  ['generic same variable conflict','const identity = fn x => x\nentry const answer: U32 = identity True\n','type_mismatch','type_mismatch'],

  ['U32 overflow','entry const answer = 4294967296\n','number: U32 overflow'],
  ['missing hex digits','entry const answer = 0x\n','number: missing'],
  ['numeric suffix','entry const answer = 1f\n','number: invalid'],
  ['missing exponent','entry const answer = 1e+\n','number: missing'],
  ['type mismatch','entry const answer = 1 + True\n','type_mismatch'],
  ['float mismatch','entry const answer = 1 + 1.0\n','type_mismatch'],
  ['annotation mismatch','entry const answer: Bool = 1\n','type_mismatch'],
  ['return mismatch','entry const answer = fn () -> Bool => 1\n','type_mismatch'],
  ['unit fallthrough','entry const answer = fn () -> U32 => do:\n  1\n','type_mismatch'],
  ['missing else','entry const answer = fn (x: Bool) => do:\n  if x:\n    return 1\n','type_mismatch'],
  ['bad predicate','entry const answer = fn () => do:\n  if 1:\n    return ()\n','type_mismatch'],
  ['unknown name','entry const answer = missing\n','unknown_name'],
  ['dead source error','const unused = missing\nentry const answer = 42\n','unknown_name'],
  ['duplicate declaration','const x = 1\nentry const x = 2\n','duplicate_name'],
  ['bad call','const x = 1\nentry const answer = x 2\n','not_callable'],
  ['bad argument','const f = fn (x: U32) => x\nentry const answer = f True\n','type_mismatch'],
  ['unbound rebind','entry const answer = fn () => do:\n  x := 42\n  return x\n','unknown_rebinding'],
  ['escaped binding','entry const answer = fn () => do:\n  if True:\n    let x = 1\n  return x\n','unknown_name'],
  ['unbound self','entry const answer = self\n','unknown_name'],
  ['comparison chain','entry const answer = 1 < 2 < 3\n','syntax: comparisons'],
  ['line boundary','entry const answer = fn () => do:\n  let x = 1 return x\n','syntax: expected a line'],
  ['declaration boundary','const x = 1 entry const y = 2\n','syntax: expected a line'],
  ['unclosed parenthesis','entry const answer = (1 + 2\n','syntax: unclosed'],
  ['mismatched indentation','entry const answer = fn () => do:\n  let x = 1\n return x\n','layout: inconsistent'],
  ['tab indentation','entry const answer = fn () => do:\n\treturn 1\n','layout: tabs'],
  ['const cycle','entry const answer: U32 = other\nconst other: U32 = answer\n','const_cycle'],
  ['bounded const recursion','const loop = fn (n: U32) -> U32 => loop n\nentry const answer = loop 0\n','const_depth'],
  ['integer division','entry const answer = 4 / 2\n','missing_implementation'],
  ['Bool arithmetic','entry const answer = True + False\n','unsupported_numeric_type'],
  ['nested closure','entry const answer = fn x => fn y => x\n','unsupported_closure'],
  ['function value','const identity = fn (x: U32) => x\nentry const answer = identity\n','unsupported_function_value'],
  ['higher order','entry const answer = fn transform => transform 42\n','unsupported_function_value'],
  ['unresolved generic','entry const answer = fn x => x\n','unsupported_polymorphism'],
  ['runtime scalar let','entry let answer = 42\n','unsupported_runtime_init'],
  ['unported arrays','entry const answer = [1, 2]\n','unsupported_syntax'],
  ['unported data','type Pair is data = Pair U32\n','syntax: expected'],
  ['unported effects','type Reader is effect = { ask: Unit -> U32 }\n','unsupported_syntax'],
  ['unported import','const lib = import "./lib.blot"\n','unsupported_syntax'],
  ['missing entry','// no exports\n','no_entry'],
  ['unreachable return mismatch','entry const answer = fn () => do:\n  return 1\n  return True\n','type_mismatch'],
  ['loop carried type mismatch','entry const answer = fn () => do:\n  let x = 0\n  for 0..2:\n    x := True\n  return x\n','type_mismatch'],
];

// The fourth field is a verified reference diagnostic, not an unsupported-feature claim.
export const referenceRejected = rejected.filter((item) => item[3]);
