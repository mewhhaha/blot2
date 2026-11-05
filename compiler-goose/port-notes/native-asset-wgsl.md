# WGSL asset writing record

The full production first writing pass of backend/native_asset_wgsl.goose is
written. Native tests remain oracle requirements. No build, test, formatter,
compiler invocation, or static verification ran.

The reader includes UTF-8 validation, nested comments, token spans, attributes,
aliases and complete reflected declarations; it validates function signatures,
blocks, conditionals, for/while/loop/continuing/switch statements, assignments,
updates, return/discard/break/continue, diagnostics and const assertions without
retaining shader bodies. Pratt precedence preserves contiguous shift tokens
and template-angle disambiguation.

Constant folding retains scalar kinds, wrapping/signed bit behavior, vector and
matrix constructors, array captures, swizzles/indexing, recursive lane lifting,
reducers, casts and bitcasts, arithmetic/logical operations, every native builtin,
and the explicit unsupported-reflection diagnostics. Binary16 rounding is
implemented directly from binary64 with nearest-even handling of normals,
subnormals, overflow and signed zero. Float min/max preserve numerical operands
through NaNs. Scalar transcendental operations use Goose/libm primitives.

Pinned reflector behavior is intentional: hexadecimal floating tokens validate
but evaluate to zero, direct bitcasts are not exported until folded/cast, arrayLength
reports reflected bytes, unsigned extractBits declines, and cosh dispatches cos.
Decimal/hexadecimal parsing uses native_asset_numbers after the exact Zig0.17
separator checks; upper-case hexadecimal prefixes preserve the native float
parsing path. Source reads of Zig std parsing rules involved no Zig invocation.

Output preserves the first Parameters structure, at most four fields resolving
to f32 through bounded aliases, Blot identifier restrictions, insertion order and
replacement of duplicate constants, and the exact type/header/value spelling.
Source/issue messages own typed output runs; all intermediate aggregate runs
remain live until Reader disposal, matching the native arena lifetime.

APIs match native_asset_readers: Issue{start,end,code,message},
Result.source{bytes}/issue{value}, generate(bytes)->Result,Error, and deinit(Result&).
Limits remain16MiB input/output, depth128, one million structural visits and
tokens, and comment nesting128. No unknown expression, budget exhaustion, syntax
error, allocation error, or unsupported operation is admitted as generated success.
