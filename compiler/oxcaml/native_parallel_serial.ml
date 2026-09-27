(* Stock OCaml portability build only. OxCaml/OCaml 5 select the domains backend. *)
let backend = "serial-portability"
let configure requested =
  if requested < 1 || requested > 64 then invalid_arg "worker count must be in [1,64]"
let shutdown () = ()
let worker_count () = 1
let two a b = let a = a () in let b = b () in a,b
let four a b c d = let a,b = two a b in let c,d = two c d in a,b,c,d
let eight a b c d e f g h =
  let a,b,c,d = four a b c d in let e,f,g,h = four e f g h in a,b,c,d,e,f,g,h
