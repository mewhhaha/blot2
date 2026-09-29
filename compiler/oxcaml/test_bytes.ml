let expect name actual expected =
  if actual <> expected then failwith ("encoding mismatch: " ^ name)

let () =
  expect "unsigned zero" (Wasm_bytes.encode Wasm_bytes.u32 0l) "\000";
  expect "unsigned 127" (Wasm_bytes.encode Wasm_bytes.u32 127l) "\127";
  expect "unsigned 128" (Wasm_bytes.encode Wasm_bytes.u32 128l) "\128\001";
  expect "unsigned max" (Wasm_bytes.encode Wasm_bytes.u32 (-1l)) "\255\255\255\255\015";
  expect "signed -1" (Wasm_bytes.encode Wasm_bytes.i32 (-1l)) "\127";
  expect "signed 64" (Wasm_bytes.encode Wasm_bytes.i32 64l) "\192\000";
  expect "signed -65" (Wasm_bytes.encode Wasm_bytes.i32 (-65l)) "\191\127";
  expect "signed min" (Wasm_bytes.encode Wasm_bytes.i32 Int32.min_int) "\128\128\128\128\120";
  expect "signed max" (Wasm_bytes.encode Wasm_bytes.i32 Int32.max_int) "\255\255\255\255\007";
  expect "UTF-8 length" (Wasm_bytes.encode Wasm_bytes.string "\195\165") "\002\195\165";
  print_endline "10 Wasm byte-encoding checks passed"
