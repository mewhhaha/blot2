// Extracted from Bend 2.0.24 compiler native C emission. Contract fixture.

#define LOC_MASK ((1ull << 40) - 1)
#define RFC_BIT  (1ull << 63)
#define RFC_CNT  ((1u << 24) - 1)
#define HEAP_OFF (STAT_OFF + PAGE_UP(STAT_LEN))
#define CID_SNIL 1
#define CID_SCON 2

INLINE u64 term_tag(Term t) {
  return (t >> 56) & 0x7f;
}

INLINE bool term_rfc(Term t) {
  return (t & RFC_BIT) != 0;
}

INLINE u64 term_aux(Term t) {
  return (t >> 40) & 0xFFFF;
}

INLINE Loc term_loc(Term t) {
  return t & LOC_MASK;
}

INLINE bool term_triv(Term t) {
  return term_tag(t) <= TAG_PAK || t == TERM_HOLE || term_loc(t) < HEAP_OFF;
}

INLINE u64 rfc_view(Env e, Loc r) {
  DEV u32* w = a32_at(e.mem, r);
  u64 cell = ((u64)a32_load(w + 1) << 32) | a32_load(w);
  if ((cell & RFC_CNT) == 1) {
    a32_acq(w);
  }
  return cell;
}

INLINE Loc term_peek(Env e, Term t) {
  if (term_rfc(t)) {
    return rfc_view(e, term_loc(t)) >> 24;
  }
  return term_loc(t);
}

INLINE void term_sink(Env e, Term t) {
  if (!term_triv(t)) {
    term_drop(e, t);
  }
}

INLINE Term spin_4(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 v_8 = 0;
  u32 a_0 = r0;
  u32 b_0 = r1;
  WL_SPIN
    v_8 = U32_BIN(a_0, ==, b_0);
  break;
  }
  o[0] = v_8;
  return 1;
}

INLINE Term spin_3(Env e, THR Term* o, Term r0, Term r1, u32 r2) {
  u32 wpoll = 0;
  u32 v_5 = 0;
  Term left_6 = r0;
  Term right_6 = r1;
  u32 same_0 = r2;
  WL_SPIN
    if (term_aux(left_6) == CID_SNIL) {
      if (term_aux(right_6) == CID_SNIL) {
        if (same_0 == 0) {
          v_5 = 0;
        } else {
          v_5 = 1;
        }
      } else {
        term_sink(e, right_6);
        if (same_0 == 0) {
          v_5 = 0;
        } else {
          v_5 = 0;
        }
      }
    } else {
      Term fb_0[2];
      u64 sp_0 = ctr_take(e, left_6, 2, fb_0);
      u32 f_0 = fb_0[0];
      Term f_1 = fb_0[1];
      if (term_aux(right_6) == CID_SCON) {
        Term fb_1[2];
        u64 sp_1 = ctr_take(e, right_6, 2, fb_1);
        u32 f_2 = fb_1[0];
        Term f_3 = fb_1[1];
        if (same_0 == 0) {
          term_sink(e, f_1);
          term_sink(e, f_3);
          v_5 = 0;
          spare_free(e, cls_fit(2), sp_1);
          spare_free(e, cls_fit(2), sp_0);
        } else {
          u32 v_6 = 0;
          u32 v_7 = 0;
          Term o_0[1];
          if (spin_4(e, o_0, f_0, f_2) == 0) {
            return 0;
          }
          v_7 = o_0[0];
          v_6 = v_7;
          spare_free(e, cls_fit(2), sp_1);
          spare_free(e, cls_fit(2), sp_0);
          r0 = f_1;
          r1 = f_3;
          r2 = v_6;
          left_6 = r0;
          right_6 = r1;
          same_0 = r2;
          WL_AGAIN(spin_3);
        }
      } else {
        term_sink(e, f_1);
        term_sink(e, right_6);
        if (same_0 == 0) {
          v_5 = 0;
          spare_free(e, cls_fit(2), sp_0);
        } else {
          v_5 = 0;
          spare_free(e, cls_fit(2), sp_0);
        }
      }
    }
  break;
  }
  o[0] = v_5;
  return 1;
}

INLINE Term spin_2(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  u32 v_3 = 0;
  Term left_5 = r0;
  Term right_5 = r1;
  WL_SPIN
    u32 v_4 = 0;
    Term o_1[1];
    if (spin_3(e, o_1, left_5, right_5, 1) == 0) {
      return 0;
    }
    v_4 = o_1[0];
    v_3 = v_4;
  break;
  }
  o[0] = v_3;
  return 1;
}

// Work
