const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const Case = struct { name: []const u8, source: []const u8, code: ?check.Code };
const cases = [_]Case{
    .{ .name = "let-binding-before-return", .source = "entry const answer: Unit -> U32 = fn () => do:\n  let stop = @panic \"stop\"\n  return 42\n", .code = null },
    .{ .name = "let-binding-final", .source = "entry const answer: Unit -> U32 = fn () => do:\n  let stop = @panic \"stop\"\n", .code = null },
    .{ .name = "product-binding", .source = "entry const answer: Unit -> U32 = fn () => do:\n  let (left,right) = @panic \"stop\"\n  return 42\n", .code = null },
    .{ .name = "wildcard-binding", .source = "entry const answer: Unit -> U32 = fn () => do:\n  let _ = @panic \"stop\"\n  return 42\n", .code = null },
    .{ .name = "guard-bound-panic", .source = "data Maybe a = #Some a | #None\nentry const answer = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let stop = @panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "guard-wildcard-panic", .source = "data Maybe a = #Some a | #None\nentry const answer = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let _ = @panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "guard-product-panic", .source = "data Maybe a = #Some a | #None\nentry const answer = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let (left,right) = @panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "guard-aggregate-panic", .source = "data Maybe a = #Some a | #None\nentry const answer = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let stop = (@panic \"stop\",0)\n  return value\n", .code = null },
    .{ .name = "if-bound-panic", .source = "entry const answer = fn (flag:Bool) => do:\n  if flag:\n    let stop = @panic \"stop\"\n  else:\n    return 42\n", .code = null },
    .{ .name = "if-both-bound-panic", .source = "entry const answer: Bool -> U32 = fn flag => do:\n  if flag:\n    let stop = @panic \"stop\"\n  else:\n    let stop = @panic \"stop\"\n", .code = null },
    .{ .name = "panic-condition", .source = "entry const answer: Unit -> U32 = fn () => if @panic \"stop\" then 41 else 42\n", .code = null },
    .{ .name = "panic-scrutinee", .source = "entry const answer: Unit -> U32 = fn () => case @panic \"stop\" of\n  true => 41\n  false => 42\n", .code = null },
    .{ .name = "partial-diverging-binding", .source = "entry const answer = fn (flag:Bool) => do:\n  let value = if flag then 42 else @panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "partial-diverging-pattern", .source = "data Maybe a = #Some a | #None\nentry const answer = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else @panic \"stop\" else:\n    return 0\n  return value\n", .code = null },
    .{ .name = "return-bound-panic", .source = "entry const answer: Unit -> U32 = fn () => do:\n  let stop = @panic \"stop\"\n  return stop\n", .code = null },
    .{ .name = "panic-update", .source = "entry const answer = fn (flag:Bool) => do:\n  let value = 42\n  if flag:\n    value := @panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "guard-product-first", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=(@panic \"stop\",0)\n  return value\n", .code = null },
    .{ .name = "guard-product-last", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=(0,@panic \"stop\")\n  return value\n", .code = null },
    .{ .name = "guard-product-nested", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=(0,(@panic \"stop\",1))\n  return value\n", .code = null },
    .{ .name = "guard-array-first", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=#[@panic \"stop\",0]\n  return value\n", .code = null },
    .{ .name = "guard-array-last", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=#[0,@panic \"stop\"]\n  return value\n", .code = null },
    .{ .name = "guard-constructor-product", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=(#Some (@panic \"stop\"),0)\n  return value\n", .code = null },
    .{ .name = "guard-bad-product-later", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=(@panic \"stop\",@u32.add #True 1)\n  return value\n", .code = .type_mismatch },
    .{ .name = "guard-bad-array-later", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=#[@panic \"stop\",1,1.5]\n  return value\n", .code = .type_mismatch },
    .{ .name = "return-aggregate-first", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"stop\",0)\n  return 42\n", .code = null },
    .{ .name = "return-aggregate-last", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=(0,@panic \"stop\")\n  return 42\n", .code = null },
    .{ .name = "return-aggregate-array", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=#[0,@panic \"stop\"]\n  return 42\n", .code = null },
    .{ .name = "rebind-else", .source = "entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=1\n  else:\n    value:=@panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "rebind-both", .source = "entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=@panic \"stop\"\n  else:\n    value:=@panic \"stop\"\n  return 42\n", .code = null },
    .{ .name = "rebind-type-change", .source = "entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=@panic \"stop\"\n  else:\n    value:=1.5\n  return value\n", .code = null },
    .{ .name = "rebind-type-change-no-panic", .source = "entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=1.5\n  return value\n", .code = .type_mismatch },
    .{ .name = "rebind-later-invalid", .source = "entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=@panic \"stop\"\n    let bad=@u32.add #True 1\n  return value\n", .code = .type_mismatch },
    .{ .name = "rebind-suffix-change", .source = "entry const answer=fn(flag:Bool)=>do:\n  let value=42\n  if flag:\n    value:=@panic \"stop\"\n    value:=1.5\n  return value\n", .code = null },
    .{ .name = "monad-aggregate", .source = "type Box value is data=#Box value\nconst Box.pure=fn value=>#Box value\nconst Box.bind=fn candidate=>fn next=>case candidate of\n  #Box value=>next value\nconst run=fn(flag:Bool)=>do (@do.monad Box):\n  let stop=(@panic \"stop\",0)\n  return 42\nentry const answer=fn(flag:Bool)=>case run flag of\n  #Box value=>value\n", .code = null },
    .{ .name = "monad-rebind", .source = "type Box value is data=#Box value\nconst Box.pure=fn value=>#Box value\nconst Box.bind=fn candidate=>fn next=>case candidate of\n  #Box value=>next value\nconst run=fn(flag:Bool)=>do (@do.monad Box):\n  let value=42\n  if flag:\n    value:=@panic \"stop\"\n  return value\nentry const answer=fn(flag:Bool)=>case run flag of\n  #Box value=>value\n", .code = null },
    .{ .name = "monad-partial", .source = "type Box value is data=#Box value\nconst Box.pure=fn value=>#Box value\nconst Box.bind=fn candidate=>fn next=>case candidate of\n  #Box value=>next value\nconst run=fn(flag:Bool)=>do (@do.monad Box):\n  let stop=if flag then (@panic \"stop\",0) else (1,2)\n  return 42\nentry const answer=fn(flag:Bool)=>case run flag of\n  #Box value=>value\n", .code = null },
    .{ .name = "aggregate-prefix-later-type-error", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"stop\",0)\n  let bad=@u32.add #True 1\n  return 42\n", .code = .type_mismatch },
    .{ .name = "qualified-extra-after-bottom", .source = "const helper:Unit->U32 where { associated \"missing\" U32 U32 U32 }=fn()=>42\nentry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"stop\",0)\n  return helper ()\n", .code = null },
    .{ .name = "aggregate-impure-later", .source = "type Read is effect=Unit->U32\nentry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"stop\",Read ())\n  return 42\n", .code = .let_effect },
    .{ .name = "call-strict-ignore", .source = "const ignore=fn value=>42\nentry const answer:Unit->U32=fn()=>do:\n  let stop=ignore (@panic \"stop\")\n  return 42\n", .code = null },
    .{ .name = "call-strict-primitive", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=@u32.add (@panic \"stop\") 1\n  return 42\n", .code = null },
    .{ .name = "call-callee-panic", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"stop\") 1\n  return 42\n", .code = null },
    .{ .name = "call-constructor-panic", .source = "data Box=#Box U32\nentry const answer:Unit->U32=fn()=>do:\n  let stop=#Box (@panic \"stop\")\n  return 42\n", .code = null },
    .{ .name = "call-record-panic", .source = "data Box=#Box {value:U32}\nentry const answer:Unit->U32=fn()=>do:\n  let stop=#Box {value:@panic \"stop\"}\n  return 42\n", .code = null },
    .{ .name = "call-fill-zero", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=@array.fill 0 (@panic \"stop\")\n  return 42\n", .code = null },
    .{ .name = "call-generate-zero-body", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=@array.generate 0 (fn(index:U32)->U32=>@panic \"stop\")\n  return 42\n", .code = null },
    .{ .name = "call-generate-zero-callee", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=@array.generate 0 (@panic \"stop\")\n  return 42\n", .code = null },
    .{ .name = "call-generate-count", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=@array.generate (@panic \"stop\") (fn(index:U32)->U32=>index)\n  return 42\n", .code = null },
    .{ .name = "call-scalar-later-invalid", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=@u32.add (@panic \"stop\") #True\n  return 42\n", .code = .type_mismatch },
    .{ .name = "guard-call-strict-ignore", .source = "data Maybe a=#Some a|#None\nconst ignore=fn value=>42\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=ignore (@panic \"stop\")\n  return value\n", .code = null },
    .{ .name = "guard-call-strict-primitive", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=@u32.add (@panic \"stop\") 1\n  return value\n", .code = null },
    .{ .name = "guard-call-callee-panic", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=(@panic \"stop\") 1\n  return value\n", .code = null },
    .{ .name = "guard-call-constructor-panic", .source = "data Maybe a=#Some a|#None\ndata Box=#Box U32\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=#Box (@panic \"stop\")\n  return value\n", .code = null },
    .{ .name = "guard-call-record-panic", .source = "data Maybe a=#Some a|#None\ndata Box=#Box {value:U32}\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=#Box {value:@panic \"stop\"}\n  return value\n", .code = null },
    .{ .name = "guard-call-fill-zero", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=@array.fill 0 (@panic \"stop\")\n  return value\n", .code = null },
    .{ .name = "guard-call-generate-zero-body", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=@array.generate 0 (fn(index:U32)->U32=>@panic \"stop\")\n  return value\n", .code = .guard_fallthrough },
    .{ .name = "guard-call-generate-one-body", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=@array.generate 1 (fn(index:U32)->U32=>@panic \"stop\")\n  return value\n", .code = .guard_fallthrough },
    .{ .name = "guard-call-generate-zero-callee", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=@array.generate 0 (@panic \"stop\")\n  return value\n", .code = null },
    .{ .name = "guard-call-generate-count", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=@array.generate (@panic \"stop\") (fn(index:U32)->U32=>index)\n  return value\n", .code = null },
    .{ .name = "guard-call-demand-ignore", .source = "data Maybe a=#Some a|#None\nconst ignore=fn ~(value:U32)=>42\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=ignore (@panic \"stop\")\n  return value\n", .code = .guard_fallthrough },
    .{ .name = "guard-call-demand-force", .source = "data Maybe a=#Some a|#None\nconst force=fn ~(value:U32)=>@force value\nentry const answer=fn(flag:Bool)=>do:\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=force (@panic \"stop\")\n  return value\n", .code = .guard_fallthrough },
    .{ .name = "bound-panic-closure-is-value", .source = "entry const answer=fn()=>do:\n  let stop=fn()->U32=>@panic \"stop\"\n  return 42\n", .code = null },
    .{ .name = "provider-aggregate", .source = "effect Read:Unit->U32\nconst provider=@effect.provider Read (fn()=>42)\nentry const answer:Bool->U32=fn flag=>do provider:\n  let stop=(@panic \"stop\",0)\n  return 42\n", .code = null },
    .{ .name = "provider-rebind", .source = "effect Read:Unit->U32\nconst provider=@effect.provider Read (fn()=>42)\nentry const answer:Bool->U32=fn flag=>do provider:\n  let value=42\n  if flag:\n    value:=@panic \"stop\"\n  return value\n", .code = null },
    .{ .name = "callee-panic-later-type-error", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"first\") (@u32.add #True 1)\n  return 42\n", .code = .type_mismatch },
    .{ .name = "call-after-panic-body", .source = "const stop=fn value=>@panic \"first-body\"\nentry const answer:U32=stop 1 (@panic \"later-arg\")\n", .code = null },
    .{ .name = "explicit-annotation-after-bottom", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=(@panic \"stop\",0)\n  let bad:U32=#True\n  return 42\n", .code = .type_mismatch },
    .{ .name = "runtime-never-named", .source = "const stop=fn value=>@panic \"first-body\"\nentry const answer:Unit->U32=fn()=>do:\n  let value=stop 1 (@panic \"later-arg\")\n  return 42\n", .code = null },
    .{ .name = "runtime-never-alias", .source = "const stop=fn value=>@panic \"first-body\"\nconst alias=stop\nentry const answer:Unit->U32=fn()=>do:\n  let value=alias 1 (@panic \"later-arg\")\n  return 42\n", .code = null },
    .{ .name = "runtime-never-local", .source = "entry const answer:Unit->U32=fn()=>do:\n  let stop=fn value=>@panic \"first-body\"\n  let value=stop 1 (@panic \"later-arg\")\n  return 42\n", .code = null },
    .{ .name = "alias-after-panic-body", .source = "const stop=fn value=>@panic \"first-body\"\nconst alias=stop\nentry const answer:U32=alias 1 (@panic \"later-arg\")\n", .code = null },
    .{ .name = "bad-callee-before-bottom-arg", .source = "entry const answer:Unit->U32=fn()=>do:\n  let value=42 (@panic \"later\")\n  return 42\n", .code = .type_mismatch },
    .{ .name = "known-scalar-callback-result-is-not-callable", .source = "entry const answer=fn(callback:U32->U32)=>callback 1 (@panic \"later\")\n", .code = .type_mismatch },
    .{ .name = "strict-local-argument-bottom", .source = "data Maybe a=#Some a|#None\nentry const answer=fn(flag:Bool)=>do:\n  let ignore=fn value=>42\n  let #Some value=if flag then #Some 42 else #None else:\n    let stop=ignore (@panic \"stop\")\n  return value\n", .code = null },
    .{ .name = "never-constructor-scrutinee", .source = "data Box=#Box U32\nentry const answer:Unit->U32=fn()=>case @panic \"scrutinee\" of\n  #Box value=>value\n", .code = null },
    .{ .name = "never-constructor-scrutinee-invalid-arm", .source = "data Box=#Box U32\nentry const answer:Unit->U32=fn()=>case @panic \"scrutinee\" of\n  #Box value=>@u32.add #True 1\n", .code = .type_mismatch },
    .{ .name = "never-multi-scrutinee-invalid-later", .source = "entry const answer:Unit->U32=fn()=>case @panic \"scrutinee\", @u32.add #True 1 of\n  _,_=>42\n", .code = .type_mismatch },
    .{ .name = "never-bool-scrutinee-refutable", .source = "entry const answer:Unit->U32=fn()=>case @panic \"scrutinee\" of\n  #True=>42\n", .code = null },
    .{ .name = "fullgate-runtime-panic-original", .source = "const identity = fn value => value\nentry const answer = fn (value: U32) => do:\n  let ignored = (identity, (fn input => @panic \"runtime operand\") value, @u32.div 1 0)\n  return 0\n", .code = null },
    .{ .name = "fullgate-runtime-panic-annotated", .source = "const identity = fn value => value\nentry const answer = fn (value: U32) -> U32 => do:\n  let ignored = (identity, (fn input => @panic \"runtime operand\") value, @u32.div 1 0)\n  return 0\n", .code = null },
    .{ .name = "fullgate-root-bottom", .source = "data Maybe a = #Some a | #None\nentry const answer = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let stop = @panic \"bound\"\n  return value\nentry const guard_wild = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let _ = @panic \"wildcard\"\n  return value\nentry const guard_tuple = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42 else #None else:\n    let (left,right) = @panic \"tuple\"\n  return value\nentry const guard_float = fn (flag:Bool) => do:\n  let #Some value = if flag then #Some 42.5 else #None else:\n    let (left,right) = @panic \"float tuple\"\n  return value\nentry const tuple_panic: Unit -> U32 = fn () => do:\n  let (left,right) = @panic \"never destructure\"\n  return 42\nentry const tuple_float: Unit -> F32 = fn () => do:\n  let (left,right) = @panic \"never destructure float\"\n  return 42.5\nentry const partial_value = fn (flag:Bool) => do:\n  let value = if flag then 42 else @panic \"initializer\"\n  return value\nentry const folded = guard_tuple (@u32.eq 1 1)\nentry const observed = fn (host: Unit -> U32 ! {Foreign}) => do:\n  use flag <- host ()\n  let #Some value = if @u32.eq flag 0 then #None else #Some 42 else:\n    host ()\n    let (left,right) = @panic \"after host\"\n  return value\n", .code = null },
    .{ .name = "fullgate-request-f32", .source = "type Float is effect = { ask: F32 -> F32 }\nconst helper = fn value => @f32.add (Float.ask value) (@panic \"cancelled F32 operand suffix ran\")\nconst checked = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Float.ask value =>\n        return @f32.to_u32 value\n      complete value =>\n        return @panic \"cancelled F32 helper completed\"\nentry const answer = fn (value: F32) => checked (@computation (fn () => helper value))\nentry const folded = answer 42.5\n", .code = null },
    .{ .name = "generic-bottom-u32", .source = "const stop=fn()=>@panic \"generic-body\"\nentry const answer:Unit->U32=fn()=>stop ()\n", .code = null },
    .{ .name = "generic-bottom-f32", .source = "const stop=fn()=>@panic \"generic-body\"\nentry const answer:Unit->F32=fn()=>stop ()\n", .code = null },
    .{ .name = "generic-bottom-unit", .source = "const stop=fn()=>@panic \"generic-body\"\nentry const answer:Unit->Unit=fn()=>stop ()\n", .code = null },
    .{ .name = "generic-bottom-array-u32", .source = "const stop=fn()=>@panic \"generic-body\"\nentry const answer:Unit->Array U32=fn()=>stop ()\n", .code = null },
    .{ .name = "generic-bottom-array-f32", .source = "const stop=fn()=>@panic \"generic-body\"\nentry const answer:Unit->Array F32=fn()=>stop ()\n", .code = null },
    .{ .name = "generic-bottom-nominal", .source = "const stop=fn()=>@panic \"generic-body\"\ndata Box=#Box U32\nentry const answer:Unit->U32=fn()=>case stop () of\n  #Box value=>value\n", .code = null },
    .{ .name = "generic-bottom-curried", .source = "const stop=fn value=>fn next=>@panic \"generic-body\"\nentry const answer:Unit->F32=fn()=>stop 1 2\n", .code = null },
    .{ .name = "generic-bottom-captured", .source = "const factory=fn value=>fn()=>do:\n  let captured=value\n  @panic \"generic-body\"\nconst stop=factory 41\nentry const answer:Unit->F32=fn()=>stop ()\n", .code = null },
    .{ .name = "generic-bottom-higher-order", .source = "const stop=fn()=>@panic \"generic-body\"\nconst invoke=fn callback=>callback ()\nentry const answer:Unit->F32=fn()=>invoke stop\n", .code = null },
    .{ .name = "generic-bottom-demanded", .source = "const stop=fn ~(value:U32)=>@panic \"generic-body\"\nentry const answer:Unit->F32=fn()=>stop 1\n", .code = null },
    .{ .name = "generic-bottom-distinct-uses", .source = "const stop=fn()=>@panic \"generic-body\"\nentry const answer:Bool->F32=fn flag=>if flag then stop () else 1.5\nentry const integer:Unit->U32=fn()=>stop ()\nentry const array:Unit->Array U32=fn()=>stop ()\n", .code = null },
    .{ .name = "explicit-bottom-f32", .source = "const stop:Unit->F32=fn()=>@panic \"typed-body\"\nentry const answer:Unit->F32=fn()=>stop ()\n", .code = null },
    .{ .name = "never-callee-keeps-later-arg", .source = "entry const answer:Unit->U32=fn()=>do:\n  let value=(@panic \"first-body\") (@panic \"later-arg\")\n  return 42\n", .code = null },
};
fn checking(allocator: std.mem.Allocator, case: Case) !void {
    var tokens = try lexer.lex(allocator, case.source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, case.source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const nodes = try allocator.dupe(ast.Node, tree.nodes.items);
    defer allocator.free(nodes);
    const spans = try allocator.dupe(ast.Span, tree.spans.items);
    defer allocator.free(spans);
    const extra = try allocator.dupe(u32, tree.extra.items);
    defer allocator.free(extra);
    var checked = try check.check(allocator, &tree, &names);
    defer checked.deinit(allocator);
    if (case.code) |expected| {
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(expected, checked.diagnostics[0].code);
    } else {
        if (checked.diagnostics.len != 0) std.debug.print("{s}: {s}\n", .{ case.name, @tagName(checked.diagnostics[0].code) });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    }
    try std.testing.expectEqualSlices(ast.Node, nodes, tree.nodes.items);
    try std.testing.expectEqualSlices(ast.Span, spans, tree.spans.items);
    try std.testing.expectEqualSlices(u32, extra, tree.extra.items);
}
fn named(name: []const u8) Case {
    for (cases) |case| if (std.mem.eql(u8, case.name, name)) return case;
    unreachable;
}
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn publication(allocator: std.mem.Allocator, source: []const u8) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    var found = false;
    var later = false;
    for (module.nodes) |node| {
        if (node.tag == .apply) {
            const callee = module.types.node(module.typeOf(node.a));
            try std.testing.expect(callee.tag == .function or callee.tag == .never);
            if (callee.tag == .never) try std.testing.expectEqual(T.never, node.ty);
            found = true;
        }
        if (node.tag == .panic and std.mem.eql(u8, module.names[node.a..][0..node.b], "later-arg")) later = true;
    }
    try std.testing.expect(found and later);
}
fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var emitted = try backend.compile(allocator, &.{module.*}, 1);
    defer emitted.deinit(allocator);
    if (emitted.diagnostic) |d| std.debug.print("emit {s}\n", .{@tagName(d.code)});
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), emitted.diagnostic);
    try std.testing.expect(emitted.bytes.len > 8);
}
test "eager bottom flow keeps every later type effect annotation and qualified requirement" {
    for (cases) |case| try checking(a, case);
    for ([_][]const u8{ "guard-product-first", "guard-array-last", "rebind-type-change", "monad-rebind", "provider-rebind", "call-scalar-later-invalid", "aggregate-prefix-later-type-error", "explicit-annotation-after-bottom", "guard-call-demand-ignore", "guard-call-generate-zero-body" }) |name|
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, checking, .{named(name)});
}
test "Never applications retain owned arguments and exact result types through every failed Core publication" {
    for ([_][]const u8{ "call-after-panic-body", "alias-after-panic-body", "runtime-never-local", "never-callee-keeps-later-arg" }) |name| {
        const source = named(name).source;
        try publication(a, source);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, publication, .{source});
    }
}
test "bottom aggregate and callee emission preserve frozen Core after frontend teardown and failed allocations" {
    for ([_][]const u8{ "guard-product-first", "guard-array-last", "runtime-never-local", "call-callee-panic", "never-constructor-scrutinee", "generic-bottom-f32", "generic-bottom-array-f32", "generic-bottom-nominal", "generic-bottom-captured" }) |name| {
        var module = try lower(a, named(name).source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const types = try a.dupe(T.Node, module.types.nodes);
        defer a.free(types);
        const extra = try a.dupe(T.Id, module.types.extra);
        defer a.free(extra);
        try emit(a, &module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
        try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
        try std.testing.expectEqualSlices(T.Node, types, module.types.nodes);
        try std.testing.expectEqualSlices(T.Id, extra, module.types.extra);
    }
}
