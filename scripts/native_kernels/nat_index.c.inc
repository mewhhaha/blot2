#if !DEVICE
  WL_CASE(FID_NAT_INDEX_FIND)
  {
    Term index = r0;
    Nat key = r1;
    u32 wpoll = 0;
    WL_OPEN
    for (;;) {
      if (err_spun(e.mem, &wpoll)) return 0;
      u32 kind = term_aux(index);
      if (kind == CID_NAT_INDEX_EMPTY) {
        r0 = 0;
        r1 = 0;
        WL_RETN(2);
      }
      if (kind == CID_NAT_INDEX_LEAF) {
        Term fields[2];
        Loc span = ctr_take(e, index, 2, fields);
        Term value = fields[1];
        if (fields[0] == key) {
          r0 = 1;
          r1 = value;
        } else {
          term_sink(e, value);
          r0 = 0;
          r1 = 0;
        }
        spare_free(e, cls_fit(2), span);
        WL_RETN(2);
      }
      Term fields[4];
      Loc span = ctr_take(e, index, 4, fields);
      Nat sample = fields[0];
      Nat mask = fields[1];
      Term low = fields[2];
      Term high = fields[3];
      // Bend Nat.div(x, 0) is 0, so an explicit zero-mask Branch follows low.
      if (mask && (key / mask) / 2 != (sample / mask) / 2) {
        term_sink(e, low);
        term_sink(e, high);
        spare_free(e, cls_fit(4), span);
        r0 = 0;
        r1 = 0;
        WL_RETN(2);
      }
      u32 upper = mask ? (u32)((key / mask) & 1) : 0;
      index = upper ? high : low;
      term_sink(e, upper ? low : high);
      spare_free(e, cls_fit(4), span);
    }
  }}
#endif
