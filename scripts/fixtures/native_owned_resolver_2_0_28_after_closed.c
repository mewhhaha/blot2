// Reviewed Bend 2.0.28 raw-C cases after the guarded closed-kernel transform.
// Non-compilable string fixture for the downstream owned-resolver transform.
#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }
#define NAT_IMM ((1ull << 48) - 1)
#define CID_NONE 8
#define CID_SOME 9
#define CID_UNIT 12
#define CID_NIL 13
#define CID_CON 14
#define CID_MODEL_UNITTY 104
#define CID_MODEL_U32TY 105
#define CID_MODEL_BOOLTY 106
#define CID_MODEL_APPLIEDTY 107
#define CID_MODEL_FUNCTIONTY 108
#define CID_MODEL_PARAMETERTY 109
#define CID_MODEL_VARIABLETY 110
#define CID_MODEL_NEVERTY 111
#define CID_MODEL_F32TY 112
#define CID_MODEL_PROVIDERTY 113
#define CID_MODEL_STATEPROVIDERTY 114
#define CID_MODEL_EFFECTDESCRIPTORTY 115
#define CID_MODEL_EFFECTSETTY 116
#define CID_MODEL_PRODUCTTY 117
#define CID_MODEL_ARRAYTY 118
#define CID_MODEL_FREETY 119
#define CID_MODEL_EFFECTROW 256
#define CID_TYPES_SUBSTITUTIONS 562
#define CID_NAT_INDEX_EMPTY 618
#define CID_NAT_INDEX_LEAF 619
#define CID_NAT_INDEX_BRANCH 620
#define CID_TYPES_VERSION 621
#define FID_TYPES_APPEND_SUBSTITUTION 469
#define FID_TYPES_APPEND_SUBSTITUTION_K825 470
#define FID_TYPES_APPEND_SUBSTITUTION_K826 471
#define FID_TYPES_APPEND_SUBSTITUTION_K827 472
#define FID_TYPES_APPEND_SUBSTITUTION_K828 473
#define FID_NAT_INDEX_GET 3114
#define FID_TYPES_FLAT_STEP 4414
#define FID_NAT_INDEX_SET 5233
#define FID_NAT_INDEX_FIND 5234
#define FID_NAT_INDEX_FIND_C7098 5235
#define FID_NAT_INDEX_FIND_K7103 5240
#define FID_TYPES_RESOLVE_WORK 7021
#define FID_TYPES_RESOLVE_WORK_K9082 7022
#define FID_CLO_APPLY 13479
#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)
#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))
INLINE u64 term_aux(Term t) {
  return (t >> 40) & 0xFFFF;
}
INLINE bool term_rfc(Term t) {
  return (t & RFC_BIT) != 0;
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
INLINE bool term_triv(Term t) {
  return term_tag(t) <= TAG_PAK || t == TERM_HOLE || term_loc(t) < HEAP_OFF;
}
INLINE Term rfc_seal(Env e, Term t) {
  if (term_tag(t) != TAG_CTR || term_rfc(t)) {
    return t;
  }
  return rfc_wrap(e, t, 1);
}
OUTLINE Term rfc_wrap(Env e, Term t, u32 cnt) {
  if (term_tag(t) == TAG_CLO || term_tag(t) == TAG_TSK) {
    err_post(e.mem, ERR_RFCS);
    return t;
  }
  Loc r = heap_alloc(e, 0);
  e.mem[r] = ((u64)term_loc(t) << 24) | cnt;
  return (t & ~LOC_MASK) | RFC_BIT | r;
}
INLINE Term term_keep(Env e, Term t) {
  if (term_rfc(t)) {
    rfc_bump(e, term_loc(t), 1);
    return t;
  }
  if (term_triv(t)) {
    return t;
  }
  return rfc_wrap(e, t, 2);
}
INLINE Loc heap_alloc(Env e, Cls cls) {
  Loc h = ALC_AT(e, cls);
  if (h) {
    ALC_AT(e, cls)   = e.mem[h];
    ALC_LEN(e, cls) -= 1ull << cls;
    return h;
  }
  return heap_alloc_miss(e, cls);
}
INLINE Nat nat_chk(Env e, Nat n) {
  if (n > NAT_IMM) {
    err_post(e.mem, ERR_NATS);
    return NAT_IMM;
  }
  return n;
}
static inline bool compact_closed_work(Env e, u32 tag, Term work, Term fuel) { return true; }
INLINE Term spin_0(Env e, THR Term* o) { return 0; }
#if !DEVICE
  WL_CASE(FID_TYPES_APPEND_SUBSTITUTION)
  {
    Term _substitutions_0 = r0;
    Term _substitutions_1 = r1;
    Term _substitutions_2 = r2;
    Term _substitutions_3 = r3;
    u32 _substitution_0 = r4;
    Term _substitution_1 = r5;
    Term _substitution_2 = r6;
    u32 _substitution_3 = r7;
    Term _substitution_4 = r8;
    WL_OPEN
    if (_substitution_0 == 0) {
      _substitutions_1 = term_keep(e, _substitutions_1);
      if (seq) {
        WL_ROOM(7);
        STK(0) = _substitutions_0;
        STK(1) = _substitutions_1;
        STK(2) = _substitutions_2;
        STK(3) = _substitutions_3;
        STK(4) = _substitution_1;
        STK(5) = _substitution_2;
        STK(6) = FID_TYPES_APPEND_SUBSTITUTION_K825;
        WL_PUSHN(7);
      } else {
        u64 _t_0 = task_node(e, FID_TYPES_APPEND_SUBSTITUTION_K825, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _substitutions_0;
        e.mem[_t_0 + 1] = _substitutions_1;
        e.mem[_t_0 + 2] = _substitutions_2;
        e.mem[_t_0 + 3] = _substitutions_3;
        e.mem[_t_0 + 4] = _substitution_1;
        e.mem[_t_0 + 5] = _substitution_2;
        WL_CONT = term_tsk(FID_TYPES_APPEND_SUBSTITUTION_K825, _t_0);
        WL_IDX = 6;
      }
      if (!DEVICE && !seq && fid_nofk(FID_NAT_INDEX_GET)) {
        u64 _t_1 = task_node(e, FID_NAT_INDEX_GET, WL_CONT, WL_IDX, 0);
        e.mem[_t_1 + 0] = _substitutions_1;
        e.mem[_t_1 + 1] = _substitution_1;
        e.mem[_t_1 + 2] = term_pak(CID_NIL, 0);
        return term_tsk(FID_NAT_INDEX_GET, _t_1);
      }
      r0 = _substitutions_1;
      r1 = _substitution_1;
      r2 = term_pak(CID_NIL, 0);
      WL_JMP(FID_NAT_INDEX_GET);
    } else {
      _substitutions_2 = term_keep(e, _substitutions_2);
      if (seq) {
        WL_ROOM(9);
        STK(0) = _substitutions_0;
        STK(1) = _substitutions_1;
        STK(2) = _substitutions_2;
        STK(3) = _substitutions_3;
        STK(4) = _substitution_1;
        STK(5) = _substitution_2;
        STK(6) = _substitution_3;
        STK(7) = _substitution_4;
        STK(8) = FID_TYPES_APPEND_SUBSTITUTION_K827;
        WL_PUSHN(9);
      } else {
        u64 _t_4 = task_node(e, FID_TYPES_APPEND_SUBSTITUTION_K827, WL_CONT, WL_IDX, 1);
        e.mem[_t_4 + 0] = _substitutions_0;
        e.mem[_t_4 + 1] = _substitutions_1;
        e.mem[_t_4 + 2] = _substitutions_2;
        e.mem[_t_4 + 3] = _substitutions_3;
        e.mem[_t_4 + 4] = _substitution_1;
        e.mem[_t_4 + 5] = _substitution_2;
        e.mem[_t_4 + 6] = _substitution_3;
        e.mem[_t_4 + 7] = _substitution_4;
        WL_CONT = term_tsk(FID_TYPES_APPEND_SUBSTITUTION_K827, _t_4);
        WL_IDX = 8;
      }
      if (!DEVICE && !seq && fid_nofk(FID_NAT_INDEX_GET)) {
        u64 _t_5 = task_node(e, FID_NAT_INDEX_GET, WL_CONT, WL_IDX, 0);
        e.mem[_t_5 + 0] = _substitutions_2;
        e.mem[_t_5 + 1] = _substitution_1;
        e.mem[_t_5 + 2] = term_pak(CID_NIL, 0);
        return term_tsk(FID_NAT_INDEX_GET, _t_5);
      }
      r0 = _substitutions_2;
      r1 = _substitution_1;
      r2 = term_pak(CID_NIL, 0);
      WL_JMP(FID_NAT_INDEX_GET);
    }
  }}
#endif
#if !DEVICE
  WL_CASE(FID_TYPES_APPEND_SUBSTITUTION_K825)
  {
    WL_POPN(6);
    Term _substitutions_4 = STK(0);
    Term _substitutions_5 = STK(1);
    Term _substitutions_6 = STK(2);
    Term _substitutions_7 = STK(3);
    Term _substitution_5 = STK(4);
    Term _substitution_6 = STK(5);
    Term _versions_0 = r0;
    WL_OPEN
    _substitution_6 = term_keep(e, _substitution_6);
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _substitutions_7);
    e.mem[_nd_0 + 1] = rfc_seal(e, _substitution_6);
    u64 _nd_1 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_1 + 0] = rfc_seal(e, term_ctr(CID_TYPES_VERSION, _nd_0));
    e.mem[_nd_1 + 1] = rfc_seal(e, _versions_0);
    if (seq) {
      WL_ROOM(6);
      STK(0) = _substitutions_4;
      STK(1) = _substitutions_6;
      STK(2) = _substitutions_7;
      STK(3) = _substitution_5;
      STK(4) = _substitution_6;
      STK(5) = FID_TYPES_APPEND_SUBSTITUTION_K826;
      WL_PUSHN(6);
    } else {
      u64 _t_2 = task_node(e, FID_TYPES_APPEND_SUBSTITUTION_K826, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _substitutions_4;
      e.mem[_t_2 + 1] = _substitutions_6;
      e.mem[_t_2 + 2] = _substitutions_7;
      e.mem[_t_2 + 3] = _substitution_5;
      e.mem[_t_2 + 4] = _substitution_6;
      WL_CONT = term_tsk(FID_TYPES_APPEND_SUBSTITUTION_K826, _t_2);
      WL_IDX = 5;
    }
    if (!DEVICE && !seq && fid_nofk(FID_NAT_INDEX_SET)) {
      u64 _t_3 = task_node(e, FID_NAT_INDEX_SET, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _substitutions_5;
      e.mem[_t_3 + 1] = _substitution_5;
      e.mem[_t_3 + 2] = term_ctr(CID_CON, _nd_1);
      return term_tsk(FID_NAT_INDEX_SET, _t_3);
    }
    r0 = _substitutions_5;
    r1 = _substitution_5;
    r2 = term_ctr(CID_CON, _nd_1);
    WL_JMP(FID_NAT_INDEX_SET);
  }}
#endif
#if !DEVICE
  WL_CASE(FID_TYPES_APPEND_SUBSTITUTION_K827)
  {
    WL_POPN(8);
    Term _substitutions_11 = STK(0);
    Term _substitutions_12 = STK(1);
    Term _substitutions_13 = STK(2);
    Term _substitutions_14 = STK(3);
    Term _substitution_9 = STK(4);
    Term _substitution_10 = STK(5);
    u32 _substitution_11 = STK(6);
    Term _substitution_12 = STK(7);
    Term _versions_1 = r0;
    WL_OPEN
    _substitution_10 = term_keep(e, _substitution_10);
    u64 _nd_4 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_4 + 0] = rfc_seal(e, _substitution_10);
    e.mem[_nd_4 + 1] = rfc_seal(e, _substitution_11);
    e.mem[_nd_4 + 2] = rfc_seal(e, _substitution_12);
    u64 _nd_5 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_5 + 0] = rfc_seal(e, _substitutions_14);
    e.mem[_nd_5 + 1] = rfc_seal(e, term_ctr(CID_MODEL_EFFECTROW, _nd_4));
    u64 _nd_6 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_6 + 0] = rfc_seal(e, term_ctr(CID_TYPES_VERSION, _nd_5));
    e.mem[_nd_6 + 1] = rfc_seal(e, _versions_1);
    if (seq) {
      WL_ROOM(8);
      STK(0) = _substitutions_11;
      STK(1) = _substitutions_12;
      STK(2) = _substitutions_14;
      STK(3) = _substitution_9;
      STK(4) = _substitution_10;
      STK(5) = _substitution_11;
      STK(6) = _substitution_12;
      STK(7) = FID_TYPES_APPEND_SUBSTITUTION_K828;
      WL_PUSHN(8);
    } else {
      u64 _t_6 = task_node(e, FID_TYPES_APPEND_SUBSTITUTION_K828, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _substitutions_11;
      e.mem[_t_6 + 1] = _substitutions_12;
      e.mem[_t_6 + 2] = _substitutions_14;
      e.mem[_t_6 + 3] = _substitution_9;
      e.mem[_t_6 + 4] = _substitution_10;
      e.mem[_t_6 + 5] = _substitution_11;
      e.mem[_t_6 + 6] = _substitution_12;
      WL_CONT = term_tsk(FID_TYPES_APPEND_SUBSTITUTION_K828, _t_6);
      WL_IDX = 7;
    }
    if (!DEVICE && !seq && fid_nofk(FID_NAT_INDEX_SET)) {
      u64 _t_7 = task_node(e, FID_NAT_INDEX_SET, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = _substitutions_13;
      e.mem[_t_7 + 1] = _substitution_9;
      e.mem[_t_7 + 2] = term_ctr(CID_CON, _nd_6);
      return term_tsk(FID_NAT_INDEX_SET, _t_7);
    }
    r0 = _substitutions_13;
    r1 = _substitution_9;
    r2 = term_ctr(CID_CON, _nd_6);
    WL_JMP(FID_NAT_INDEX_SET);
  }}
#endif
#if !DEVICE
  WL_CASE(FID_NAT_INDEX_FIND)
  {
    Term _index_0 = r0;
    Term _key_0 = r1;
    WL_OPEN
    if (term_aux(_index_0) == CID_NAT_INDEX_EMPTY) {
      r0 = 0;
      r1 = 0;
      WL_RETN(2);
    } else if (term_aux(_index_0) == CID_NAT_INDEX_LEAF) {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _index_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      u32 _v_0 = 0;
      u32 _v_1 = 0;
      Term _o_0[1];
      if (spin_6(e, _o_0, _f_0, _key_0) == 0) {
        return 0;
      }
      _v_1 = _o_0[0];
      _v_0 = _v_1;
      u64 _nd_0 = heap_alloc(e, cls_fit(1));
      e.mem[_nd_0 + 0] = rfc_seal(e, _f_1);
      Term _v_2 = 0;
      Term _o_1[1];
      if (spin_59(e, _o_1, _v_0, term_ctr(CID_SOME, _nd_0), term_pak(CID_NONE, 0)) == 0) {
        return 0;
      }
      _v_2 = _o_1[0];
      spare_free(e, cls_fit(2), _sp_0);
      u32 _o_2 = 0;
      Term _o_3 = 0;
      if (term_aux(_v_2) == CID_NONE) {
        _o_2 = 0;
      } else {
        _o_2 = 1;
        Term _fb_1[1];
        u64 _sp_1 = ctr_take(e, _v_2, 1, _fb_1);
        Term _f_2 = _fb_1[0];
        spare_free(e, cls_fit(1), _sp_1);
        _o_3 = _f_2;
      }
      r0 = _o_2;
      r1 = _o_3;
      WL_RETN(2);
    } else {
      Term _fb_2[4];
      u64 _sp_2 = ctr_take(e, _index_0, 4, _fb_2);
      Term _f_3 = _fb_2[0];
      Term _f_4 = _fb_2[1];
      Term _f_5 = _fb_2[2];
      Term _f_6 = _fb_2[3];
      u32 _v_3 = 0;
      u32 _v_4 = 0;
      Term _o_4[1];
      if (spin_643(e, _o_4, _key_0, _f_3, _f_4) == 0) {
        return 0;
      }
      _v_4 = _o_4[0];
      _v_3 = _v_4;
      u64 _nd_1 = heap_alloc(e, cls_fit(4));
      e.mem[_nd_1 + 0] = _f_4;
      e.mem[_nd_1 + 1] = _f_5;
      e.mem[_nd_1 + 2] = _f_6;
      e.mem[_nd_1 + 3] = _key_0;
      if (_v_3 == 1) {
        Term _found_0 = term_clo(FID_NAT_INDEX_FIND_C7098, _nd_1);
        spare_free(e, cls_fit(4), _sp_2);
        if (seq) {
          WL_ROOM(1);
          STK(0) = FID_NAT_INDEX_FIND_K7103;
          WL_PUSHN(1);
        } else {
          u64 _t_6 = task_node(e, FID_NAT_INDEX_FIND_K7103, WL_CONT, WL_IDX, 1);
          WL_CONT = term_tsk(FID_NAT_INDEX_FIND_K7103, _t_6);
          WL_IDX = 0;
        }
        if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
          u64 _t_7 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
          e.mem[_t_7 + 0] = _found_0;
          e.mem[_t_7 + 1] = term_pak(CID_UNIT, 0);
          return term_tsk(FID_CLO_APPLY, _t_7);
        }
        r0 = _found_0;
        r1 = term_pak(CID_UNIT, 0);
        WL_JMP(FID_CLO_APPLY);
      } else {
        Term _found_1 = term_clo(FID_NAT_INDEX_FIND_C7098, _nd_1);
        term_sink(e, _found_1);
        spare_free(e, cls_fit(4), _sp_2);
        r0 = 0;
        r1 = 0;
        WL_RETN(2);
      }
    }
  }}
#endif
#if !DEVICE
  WL_CASE(FID_TYPES_RESOLVE_WORK)
  {
    Term _substitutions_0 = r0;
    Term _substitutions_1 = r1;
    Term _substitutions_2 = r2;
    Term _substitutions_3 = r3;
    Term _fuel_0 = r4;
    u32 _work_0 = r5;
    Term _work_1 = r6;
    WL_OPEN

    if (err_seen(e.mem)) return 0;
    if (_substitutions_3 != 0 && compact_closed_work(e, _work_0, _work_1, _fuel_0)) {
      Term compact_result = compact_closed_result(e, _work_0, _work_1);
      term_sink(e, _substitutions_0);
      term_sink(e, _substitutions_1);
      term_sink(e, _substitutions_2);
      r0 = 1;
      r1 = compact_result;
      r2 = 0;
      r3 = 0;
      WL_RETN(4);
    }
    Term _v_0 = 0;
    _substitutions_0 = term_keep(e, _substitutions_0);
    _substitutions_1 = term_keep(e, _substitutions_1);
    _substitutions_2 = term_keep(e, _substitutions_2);
    Term _v_1 = 0;
    Term _o_0[1];
    if (spin_55(e, _o_0, _substitutions_0, _substitutions_1, _substitutions_2, _substitutions_3) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    u32 _v_2 = 0;
    u32 _v_3 = 0;
    Term _o_1[1];
    if (spin_6(e, _o_1, _v_0, 0) == 0) {
      return 0;
    }
    _v_3 = _o_1[0];
    _v_2 = _v_3;
    _work_1 = term_keep(e, _work_1);
    _substitutions_0 = term_keep(e, _substitutions_0);
    _substitutions_1 = term_keep(e, _substitutions_1);
    _substitutions_2 = term_keep(e, _substitutions_2);
    if (seq) {
      WL_ROOM(8);
      STK(0) = _substitutions_0;
      STK(1) = _substitutions_1;
      STK(2) = _substitutions_2;
      STK(3) = _substitutions_3;
      STK(4) = _fuel_0;
      STK(5) = _work_0;
      STK(6) = _work_1;
      STK(7) = FID_TYPES_RESOLVE_WORK_K9082;
      WL_PUSHN(8);
    } else {
      u64 _t_0 = task_node(e, FID_TYPES_RESOLVE_WORK_K9082, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _substitutions_0;
      e.mem[_t_0 + 1] = _substitutions_1;
      e.mem[_t_0 + 2] = _substitutions_2;
      e.mem[_t_0 + 3] = _substitutions_3;
      e.mem[_t_0 + 4] = _fuel_0;
      e.mem[_t_0 + 5] = _work_0;
      e.mem[_t_0 + 6] = _work_1;
      WL_CONT = term_tsk(FID_TYPES_RESOLVE_WORK_K9082, _t_0);
      WL_IDX = 7;
    }
    if (!DEVICE && !seq && fid_nofk(FID_TYPES_FLAT_STEP)) {
      u64 _t_1 = task_node(e, FID_TYPES_FLAT_STEP, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = 1048576ull;
      e.mem[_t_1 + 1] = _substitutions_0;
      e.mem[_t_1 + 2] = _substitutions_1;
      e.mem[_t_1 + 3] = _substitutions_2;
      e.mem[_t_1 + 4] = _substitutions_3;
      e.mem[_t_1 + 5] = 0;
      e.mem[_t_1 + 6] = _fuel_0;
      e.mem[_t_1 + 7] = _v_0;
      e.mem[_t_1 + 8] = _v_2;
      e.mem[_t_1 + 9] = 0;
      e.mem[_t_1 + 10] = _work_0;
      e.mem[_t_1 + 11] = _work_1;
      e.mem[_t_1 + 12] = term_pak(CID_NIL, 0);
      e.mem[_t_1 + 13] = term_pak(CID_NIL, 0);
      return term_tsk(FID_TYPES_FLAT_STEP, _t_1);
    }
    r0 = 1048576ull;
    r1 = _substitutions_0;
    r2 = _substitutions_1;
    r3 = _substitutions_2;
    r4 = _substitutions_3;
    r5 = 0;
    r6 = _fuel_0;
    r7 = _v_0;
    r8 = _v_2;
    r9 = 0;
    r10 = _work_0;
    r11 = _work_1;
    r12 = term_pak(CID_NIL, 0);
    r13 = term_pak(CID_NIL, 0);
    WL_JMP(FID_TYPES_FLAT_STEP);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TYPES_RESOLVE_WORK_K_REVIEW_END)
  { WL_OPEN WL_RETN(0); }
