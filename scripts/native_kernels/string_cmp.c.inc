#if !DEVICE
  WL_CASE(FID_STRING_CMP)
  {
    // Both original roots remain owned and are returned unchanged.
    Term root_a = r0, root_b = r1;
    Term a = root_a, b = root_b;
    u32 ordering = 1, cmp_poll = 0;
    WL_OPEN
    for (;;) {
      if (err_spun(e.mem, &cmp_poll)) return 0;
      if (a == b) break;
      if (term_aux(a) == CID_SNIL) {
        ordering = term_aux(b) == CID_SNIL ? 1 : 0;
        break;
      }
      if (term_aux(b) == CID_SNIL) { ordering = 2; break; }
      Loc ax = term_peek(e, a), bx = term_peek(e, b);
      u32 ac = (u32)e.mem[ax], bc = (u32)e.mem[bx];
      if (ac != bc) { ordering = ac < bc ? 0 : 2; break; }
      a = e.mem[ax + 1]; b = e.mem[bx + 1];
    }
    r0 = root_a; r1 = root_b; r2 = ordering;
    WL_RETN(3);
  }}
#endif
