#if !DEVICE
  WL_CASE(FID_INDEX_FIND_WORK)
  {
    Term index = r0;
    Term name = r1;
    Term remaining_root = r2;
    Term suffix = remaining_root;
    Nat cursor = r3;
    u32 wpoll = 0;
    WL_OPEN
    for (;;) {
      if (err_spun(e.mem, &wpoll)) {
        return 0;
      }
      u32 kind = term_aux(index);
      if (kind == CID_MTIP) {
        term_sink(e, name);
        term_sink(e, remaining_root);
        r0 = 0;
        r1 = 0;
        WL_RETN(2);
      }
      if (kind == CID_MLEAF) {
        Term fields[2];
        Loc span = ctr_take(e, index, 2, fields);
        Term key = fields[0];
        Term value = fields[1];
        term_sink(e, remaining_root);
        Term result[1];
        if (spin_3(e, result, key, name) == 0) {
          return 0;
        }
        spare_free(e, cls_fit(2), span);
        if (result[0]) {
          r0 = 1;
          r1 = value;
        } else {
          term_sink(e, value);
          r0 = 0;
          r1 = 0;
        }
        WL_RETN(2);
      }
      Term fields[3];
      Loc span = ctr_take(e, index, 3, fields);
      Nat position = fields[0];
      Term left = fields[1];
      Term right = fields[2];
      Nat character = position / 33;
      Nat skip = character < cursor ? 0 : character - cursor;
      while (skip && term_aux(suffix) == CID_SCON) {
        if (err_spun(e.mem, &wpoll)) {
          return 0;
        }
        suffix = e.mem[term_peek(e, suffix) + 1];
        --skip;
      }
      u32 high = 0;
      if (term_aux(suffix) == CID_SCON) {
        u32 offset = (u32)(position % 33);
        if (offset == 0) {
          high = 1;
        } else {
          u32 head = (u32)e.mem[term_peek(e, suffix)];
          high = (head >> (32 - offset)) & 1;
        }
      }
      index = high ? right : left;
      term_sink(e, high ? left : right);
      spare_free(e, cls_fit(3), span);
      cursor = character;
    }
  }}
#endif
