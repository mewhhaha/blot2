// Extracted from reviewed Bend 2.0.28 native-main C emission. Contract fixture.

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

INLINE Term spin_15(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 _v_16 = 0;
  u32 _a_2 = r0;
  u32 _b_2 = r1;
  WL_SPIN
    _v_16 = U32_BIN(_a_2, ==, _b_2);
  break;
  }
  o[0] = _v_16;
  return 1;
}

INLINE Term spin_14(Env e, THR Term* o, Term r0, Term r1, u32 r2) {
  u32 wpoll = 0;
  u32 _v_13 = 0;
  Term _left_1 = r0;
  Term _right_1 = r1;
  u32 _same_0 = r2;
  WL_SPIN
    if (term_aux(_left_1) == CID_SNIL) {
      if (term_aux(_right_1) == CID_SNIL) {
        if (_same_0 == 0) {
          _v_13 = 0;
        } else {
          _v_13 = 1;
        }
      } else {
        term_sink(e, _right_1);
        if (_same_0 == 0) {
          _v_13 = 0;
        } else {
          _v_13 = 0;
        }
      }
    } else {
      Term _fb_1[2];
      u64 _sp_1 = ctr_take(e, _left_1, 2, _fb_1);
      u32 _f_3 = _fb_1[0];
      Term _f_4 = _fb_1[1];
      if (term_aux(_right_1) == CID_SCON) {
        Term _fb_2[2];
        u64 _sp_2 = ctr_take(e, _right_1, 2, _fb_2);
        u32 _f_5 = _fb_2[0];
        Term _f_6 = _fb_2[1];
        if (_same_0 == 0) {
          term_sink(e, _f_4);
          term_sink(e, _f_6);
          _v_13 = 0;
          spare_free(e, cls_fit(2), _sp_2);
          spare_free(e, cls_fit(2), _sp_1);
        } else {
          u32 _v_14 = 0;
          u32 _v_15 = 0;
          Term _o_1[1];
          if (spin_15(e, _o_1, _f_3, _f_5) == 0) {
            return 0;
          }
          _v_15 = _o_1[0];
          _v_14 = _v_15;
          spare_free(e, cls_fit(2), _sp_2);
          spare_free(e, cls_fit(2), _sp_1);
          r0 = _f_4;
          r1 = _f_6;
          r2 = _v_14;
          _left_1 = r0;
          _right_1 = r1;
          _same_0 = r2;
          WL_AGAIN(spin_14);
        }
      } else {
        term_sink(e, _f_4);
        term_sink(e, _right_1);
        if (_same_0 == 0) {
          _v_13 = 0;
          spare_free(e, cls_fit(2), _sp_1);
        } else {
          _v_13 = 0;
          spare_free(e, cls_fit(2), _sp_1);
        }
      }
    }
  break;
  }
  o[0] = _v_13;
  return 1;
}

INLINE Term spin_13(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  u32 _v_11 = 0;
  Term _left_0 = r0;
  Term _right_0 = r1;
  WL_SPIN
    u32 _v_12 = 0;
    Term _o_2[1];
    if (spin_14(e, _o_2, _left_0, _right_0, 1) == 0) {
      return 0;
    }
    _v_12 = _o_2[0];
    _v_11 = _v_12;
  break;
  }
  o[0] = _v_11;
  return 1;
}

// Work
