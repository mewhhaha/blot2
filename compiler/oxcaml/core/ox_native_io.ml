(* Native semantic port of compiler/native_io.bend.

   Source SHA-256: f607001bd2b41d31a0314affbb058701f5633c1a4f04a570165ba4a070382fca

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

type t_Frame =
  | Frame of bytes * int32
