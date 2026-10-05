export const updateCases = [
  {
    name: "scalar_array_aliases",
    expected: { folded: 41, run: 41 },
    arguments: { run: 1 },
    source: `
const update = fn index => do:
  let values = #[10, 20, 30]
  let before = values
  values[index] := @u32.add self 1
  return @u32.add (@array.get before index) (@array.get values index)
entry const folded = update 1
entry const run = fn (index: U32) -> U32 => update index
`,
  },
  {
    name: "mixed_nominal_array_fields",
    expected: { run: 42 },
    source: `
type Point is data = #Point { x: U32, y: U32 }
type Bucket is data = #Bucket { points: Array Point }
entry const run = fn () -> U32 => do:
  let bucket = #Bucket { points: #[#Point { y: 1, x: 10 }, #Point { y: 2, x: 20 }] }
  let before = bucket
  bucket.points[1].x := @u32.add self 2
  return @u32.add before.points[1].x bucket.points[1].x
`,
  },
  {
    name: "nested_array_indexes",
    expected: { run: 45 },
    source: `
entry const run = fn () -> U32 => do:
  let values = #[#[1, 2], #[3, 4]]
  let before = values
  values[1][0] := @u32.add self 39
  return @u32.add before[1][0] values[1][0]
`,
  },
  {
    name: "selector_self_root_rhs_self_leaf",
    expected: { run: 42 },
    source: `
entry const run = fn () -> U32 => do:
  let values = #[1, 41]
  values[@u32.sub (@array.length self) 1] := @u32.add self 1
  return values[1]
`,
  },
  {
    name: "generic_update_u32_f32",
    expected: { integer: 42, floating: 4.5 },
    source: `
const replace = fn values => fn index => fn value => do:
  values[index] := value
  return values
entry const integer = fn () -> U32 => (replace #[1, 2] 1 42)[1]
entry const floating = fn () -> F32 => (replace #[1.0, 2.0] 0 4.5)[0]
`,
  },
  {
    name: "nested_update_rhs_catalog_identity",
    expected: { folded: 42, run: 42 },
    source: `
const changed = fn () -> U32 => do:
  let values = #[1]
  values[0] := do:
    let other = #[40]
    other[0] := @u32.add self 2
    return other[0]
  return values[0]
entry const folded = changed ()
entry const run = fn () -> U32 => changed ()
`,
  },
  {
    name: "old_leaf_before_rhs_panic",
    error: "array_bounds",
    source: `
entry const answer: U32 = do:
  let values = #[1]
  values[2] := @panic "rhs must not execute"
  return 0
`,
  },
  {
    name: "outer_index_before_inner_index",
    error: "array_bounds",
    source: `
entry const answer: U32 = do:
  let values = #[#[1]]
  values[2][@panic "inner index must not execute"] := 0
  return 0
`,
  },
  {
    name: "valid_index_rhs_panic",
    error: "const_panic",
    source: `
entry const answer: U32 = do:
  let values = #[1]
  values[0] := @panic "rhs executes after selecting leaf"
  return 0
`,
  },
] as const;
