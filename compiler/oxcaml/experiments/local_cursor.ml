type cursor = { mutable offset : int; global_ data : bytes }
let get (c @ local) = let i = c.offset in c.offset <- i + 1; Bytes.get c.data i
let[@zero_alloc strict] first data = let local_ c = { offset = 0; data } in get c [@nontail]
let () = assert (first (Bytes.of_string "x") = 'x'); print_endline "local cursor: strict zero-allocation check passed"
