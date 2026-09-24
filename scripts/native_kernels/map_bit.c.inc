#if !DEVICE
  WL_CASE(FID_MAP_BIT)
  {
    // key is owned throughout; cursor only borrows its immutable suffixes.
    Term key = r0;
    u64 character_index = r1 / 33ull;
    u64 bit_offset = r1 % 33ull;
    Term cursor = key;
    u32 bit = 0;
    u32 wpoll = 0;
    WL_OPEN
    for (;;) {
      if (err_spun(e.mem, &wpoll)) return 0;
      if (term_aux(cursor) == CID_SNIL) break;
      Loc loc = term_peek(e, cursor);
      if (character_index == 0) {
        u32 character = (u32)e.mem[loc];
        bit = bit_offset == 0 ? 1u :
          (character >> (32u - (u32)bit_offset)) & 1u;
        break;
      }
      cursor = e.mem[loc + 1];
      character_index -= 1;
    }
    r0 = key;
    r1 = bit;
    WL_RETN(2);
  }}
#endif
