(* Best-effort launch policy only. Failure to raise priority never prevents a
   build; --inherit-priority does not change any launcher-provided setting. *)
external configure : bool -> unit = "caml_blot_configure" [@@noalloc]
