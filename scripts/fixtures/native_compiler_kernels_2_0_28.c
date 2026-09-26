// Review candidate extracted from fresh bend 2.0.28 native_main C.
// Non-compilable string fixture; compare with raw C before adopting.
#define WL_OPEN    {
#define WL_OPEN    { WL_BANK u32 rn;
#define WL_SPIN     for (;;) { if (err_spun(e.mem, &wpoll)) { return 0; }
#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }
#define CID_SNIL 1
#define CID_SCON 2
#define CID_NONE 8
#define CID_SOME 9
#define CID_UNIT 12
#define CID_NIL 13
#define CID_CON 14
#define CID_MTIP 20
#define CID_MLEAF 21
#define CID_MNODE 22
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
#define FID_TYPES_FREE_WORK 4397
#define FID_TYPES_FREE_WORK_K6139 4398
#define FID_TYPES_FREE_WORK_K6145 4404
#define FID_TYPES_FLAT_STEP 4414
#define FID_TYPES_RESOLVE_WORK 7021
#define FID_TYPES_RESOLVE_WORK_K9082 7022
#define FID_INDEX_FIND_WORK 10535
#define FID_INDEX_FIND_WORK_C13319 10536
#define FID_INDEX_FIND_WORK_C13321 10538
#define FID_INDEX_FIND_WORK_K13323 10540
#define FID_INDEX_FIND_WORK_K13324 10541
#define FID_CLO_APPLY 13479
#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)
#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))
INLINE u64 term_aux(Term t) {
  return (t >> 40) & 0xFFFF;
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
INLINE Loc ctr_take(Env e, Term t, u32 n, THR Term* out) {
  Corpus H = e.mem;
  if (!term_rfc(t)) {
    for (u32 j = 0; j < n; j += 1) {
      out[j] = H[term_loc(t) + j];
    }
    return term_loc(t);
  }
  Loc r    = term_loc(t);
  u64 cell = rfc_view(e, r);
  Loc src  = cell >> 24;
  for (u32 j = 0; j < n; j += 1) {
    out[j] = H[src + j];
  }
  if ((cell & RFC_CNT) == 1) {
    heap_free(e, 0, r);
    return src;
  }
  span_fade(e, t, src, n);
  return 0;
}
OUTLINE void span_fade(Env e, Term t, Loc src, u32 n) {
  for (u32 j = 0; j < n; j += 1) {
    Term f = e.mem[src + j];
    if (term_rfc(f)) {
      rfc_bump(e, term_loc(f), 1);
    } else if (!term_triv(f)) {
      err_post(e.mem, ERR_RFCS);
    }
  }
  term_drop(e, t);
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
INLINE void spare_free(Env e, Cls cls, Loc loc) {
  if (loc >= HEAP_OFF) {
    heap_free(e, cls, loc);
  }
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
INLINE Term spin_0(Env e, THR Term* o) { return 0; }
#if !DEVICE
  WL_CASE(FID_TYPES_FREE_WORK)
  {
    Term _fuel_0 = r0;
    u32 _work_0 = r1;
    Term _work_1 = r2;
    WL_OPEN
    WL_SPIN
    if (_fuel_0 == 0) {
      term_sink(e, _work_1);
      r0 = 0;
      r1 = term_ctr(CID_SCON, STAT_OFF + 508);
      r2 = term_ctr(CID_SCON, STAT_OFF + 524);
      r3 = term_ctr(CID_SCON, STAT_OFF + 628);
      WL_RETN(4);
    } else {
      Term _rest_0 = (_fuel_0 - 1);
      if (_work_0 == 0) {
        if (term_aux(_work_1) == CID_MODEL_VARIABLETY) {
          Term _fb_0[1];
          u64 _sp_0 = ctr_take(e, _work_1, 1, _fb_0);
          Term _f_0 = _fb_0[0];
          u64 _nd_0 = heap_alloc(e, cls_fit(2));
          e.mem[_nd_0 + 0] = rfc_seal(e, _f_0);
          e.mem[_nd_0 + 1] = rfc_seal(e, term_pak(CID_NIL, 0));
          spare_free(e, cls_fit(1), _sp_0);
          r0 = 1;
          r1 = term_ctr(CID_CON, _nd_0);
          r2 = 0;
          r3 = 0;
          WL_RETN(4);
        } else if (term_aux(_work_1) == CID_MODEL_FUNCTIONTY) {
          Term _fb_1[5];
          u64 _sp_1 = ctr_take(e, _work_1, 5, _fb_1);
          Term _f_1 = _fb_1[0];
          Term _f_2 = _fb_1[1];
          Term _f_3 = _fb_1[2];
          u32 _f_4 = _fb_1[3];
          Term _f_5 = _fb_1[4];
          spare_free(e, cls_fit(5), _sp_1);
          if (seq) {
            WL_ROOM(6);
            STK(0) = _rest_0;
            STK(1) = _f_2;
            STK(2) = _f_3;
            STK(3) = _f_4;
            STK(4) = _f_5;
            STK(5) = FID_TYPES_FREE_WORK_K6139;
            WL_PUSHN(6);
          } else {
            u64 _t_0 = task_node(e, FID_TYPES_FREE_WORK_K6139, WL_CONT, WL_IDX, 1);
            e.mem[_t_0 + 0] = _rest_0;
            e.mem[_t_0 + 1] = _f_2;
            e.mem[_t_0 + 2] = _f_3;
            e.mem[_t_0 + 3] = _f_4;
            e.mem[_t_0 + 4] = _f_5;
            WL_CONT = term_tsk(FID_TYPES_FREE_WORK_K6139, _t_0);
            WL_IDX = 5;
          }
          r0 = _rest_0;
          r1 = 0;
          r2 = _f_1;
          _fuel_0 = r0;
          _work_0 = r1;
          _work_1 = r2;
          WL_AGAIN(FID_TYPES_FREE_WORK);
        } else if (term_aux(_work_1) == CID_MODEL_STATEPROVIDERTY) {
          Term _fb_3[5];
          u64 _sp_3 = ctr_take(e, _work_1, 5, _fb_3);
          Term _f_23 = _fb_3[0];
          Term _f_24 = _fb_3[1];
          Term _f_25 = _fb_3[2];
          Term _f_26 = _fb_3[3];
          Term _f_27 = _fb_3[4];
          term_sink(e, _f_23);
          term_sink(e, _f_24);
          term_sink(e, _f_25);
          term_sink(e, _f_26);
          spare_free(e, cls_fit(5), _sp_3);
          r0 = _rest_0;
          r1 = 0;
          r2 = _f_27;
          _fuel_0 = r0;
          _work_0 = r1;
          _work_1 = r2;
          WL_AGAIN(FID_TYPES_FREE_WORK);
        } else if (term_aux(_work_1) == CID_MODEL_PROVIDERTY) {
          Term _fb_4[5];
          u64 _sp_4 = ctr_take(e, _work_1, 5, _fb_4);
          Term _f_28 = _fb_4[0];
          Term _f_29 = _fb_4[1];
          Term _f_30 = _fb_4[2];
          u32 _f_31 = _fb_4[3];
          Term _f_32 = _fb_4[4];
          term_sink(e, _f_28);
          term_sink(e, _f_29);
          Term _v_8 = 0;
          Term _v_9 = 0;
          Term _o_12[1];
          if (spin_10(e, _o_12, _f_30, _f_31, _f_32) == 0) {
            return 0;
          }
          _v_9 = _o_12[0];
          _v_8 = _v_9;
          term_sink(e, _f_30);
          spare_free(e, cls_fit(5), _sp_4);
          r0 = 1;
          r1 = _v_8;
          r2 = 0;
          r3 = 0;
          WL_RETN(4);
        } else if (term_aux(_work_1) == CID_MODEL_APPLIEDTY) {
          Term _fb_5[3];
          u64 _sp_5 = ctr_take(e, _work_1, 3, _fb_5);
          Term _f_33 = _fb_5[0];
          Term _f_34 = _fb_5[1];
          Term _f_35 = _fb_5[2];
          term_sink(e, _f_33);
          term_sink(e, _f_34);
          spare_free(e, cls_fit(3), _sp_5);
          r0 = _rest_0;
          r1 = 1;
          r2 = _f_35;
          _fuel_0 = r0;
          _work_0 = r1;
          _work_1 = r2;
          WL_AGAIN(FID_TYPES_FREE_WORK);
        } else if (term_aux(_work_1) == CID_MODEL_PRODUCTTY) {
          Term _fb_6[1];
          u64 _sp_6 = ctr_take(e, _work_1, 1, _fb_6);
          Term _f_36 = _fb_6[0];
          spare_free(e, cls_fit(1), _sp_6);
          r0 = _rest_0;
          r1 = 1;
          r2 = _f_36;
          _fuel_0 = r0;
          _work_0 = r1;
          _work_1 = r2;
          WL_AGAIN(FID_TYPES_FREE_WORK);
        } else if (term_aux(_work_1) == CID_MODEL_ARRAYTY) {
          Term _fb_7[1];
          u64 _sp_7 = ctr_take(e, _work_1, 1, _fb_7);
          Term _f_37 = _fb_7[0];
          spare_free(e, cls_fit(1), _sp_7);
          r0 = _rest_0;
          r1 = 0;
          r2 = _f_37;
          _fuel_0 = r0;
          _work_0 = r1;
          _work_1 = r2;
          WL_AGAIN(FID_TYPES_FREE_WORK);
        } else {
          term_sink(e, _work_1);
          r0 = 1;
          r1 = term_pak(CID_NIL, 0);
          r2 = 0;
          r3 = 0;
          WL_RETN(4);
        }
      } else {
        if (term_aux(_work_1) == CID_NIL) {
          r0 = 1;
          r1 = term_pak(CID_NIL, 0);
          r2 = 0;
          r3 = 0;
          WL_RETN(4);
        } else {
          Term _fb_8[2];
          u64 _sp_8 = ctr_take(e, _work_1, 2, _fb_8);
          Term _f_38 = _fb_8[0];
          Term _f_39 = _fb_8[1];
          spare_free(e, cls_fit(2), _sp_8);
          if (seq) {
            WL_ROOM(3);
            STK(0) = _rest_0;
            STK(1) = _f_39;
            STK(2) = FID_TYPES_FREE_WORK_K6145;
            WL_PUSHN(3);
          } else {
            u64 _t_7 = task_node(e, FID_TYPES_FREE_WORK_K6145, WL_CONT, WL_IDX, 1);
            e.mem[_t_7 + 0] = _rest_0;
            e.mem[_t_7 + 1] = _f_39;
            WL_CONT = term_tsk(FID_TYPES_FREE_WORK_K6145, _t_7);
            WL_IDX = 2;
          }
          r0 = _rest_0;
          r1 = 0;
          r2 = _f_38;
          _fuel_0 = r0;
          _work_0 = r1;
          _work_1 = r2;
          WL_AGAIN(FID_TYPES_FREE_WORK);
        }
      }
    }
    WL_SPUN
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
  WL_CASE(FID_INDEX_FIND_WORK)
  {
    Term _index_0 = r0;
    Term _name_0 = r1;
    Term _remaining_0 = r2;
    Term _cursor_0 = r3;
    WL_OPEN
    if (term_aux(_index_0) == CID_MTIP) {
      term_sink(e, _name_0);
      term_sink(e, _remaining_0);
      r0 = 0;
      r1 = 0;
      WL_RETN(2);
    } else if (term_aux(_index_0) == CID_MLEAF) {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _index_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      term_sink(e, _remaining_0);
      u32 _v_0 = 0;
      u32 _v_1 = 0;
      Term _o_0[1];
      if (spin_13(e, _o_0, _f_0, _name_0) == 0) {
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
      Term _fb_2[3];
      u64 _sp_2 = ctr_take(e, _index_0, 3, _fb_2);
      Term _f_3 = _fb_2[0];
      Term _f_4 = _fb_2[1];
      Term _f_5 = _fb_2[2];
      Term _v_3 = 0;
      Term _v_4 = 0;
      Term _o_4[1];
      if (spin_121(e, _o_4, _f_3, 33ull) == 0) {
        return 0;
      }
      _v_4 = _o_4[0];
      _v_3 = _v_4;
      Term _v_5 = 0;
      Term _v_6 = 0;
      Term _o_5[1];
      if (spin_215(e, _o_5, _remaining_0, (_v_3 < _cursor_0 ? 0 : _v_3 - _cursor_0)) == 0) {
        return 0;
      }
      _v_6 = _o_5[0];
      _v_5 = _v_6;
      u32 _v_7 = 0;
      Term _v_8 = 0;
      Term _v_9 = 0;
      Term _o_6[1];
      if (spin_563(e, _o_6, _f_3, 33ull) == 0) {
        return 0;
      }
      _v_9 = _o_6[0];
      _v_8 = _v_9;
      u32 _v_10 = 0;
      Term _o_8[1];
      if (spin_1199(e, _o_8, _v_5, 0, _v_8) == 0) {
        return 0;
      }
      _v_10 = _o_8[0];
      _v_7 = _v_10;
      _name_0 = term_keep(e, _name_0);
      _v_5 = term_keep(e, _v_5);
      u64 _nd_1 = heap_alloc(e, cls_fit(4));
      e.mem[_nd_1 + 0] = _f_5;
      e.mem[_nd_1 + 1] = _name_0;
      e.mem[_nd_1 + 2] = _v_3;
      e.mem[_nd_1 + 3] = _v_5;
      u64 _nd_3 = heap_alloc(e, cls_fit(4));
      e.mem[_nd_3 + 0] = _f_4;
      e.mem[_nd_3 + 1] = _name_0;
      e.mem[_nd_3 + 2] = _v_3;
      e.mem[_nd_3 + 3] = _v_5;
      if (_v_7 == 1) {
        Term _right_0 = term_clo(FID_INDEX_FIND_WORK_C13319, _nd_1);
        Term _left_0 = term_clo(FID_INDEX_FIND_WORK_C13321, _nd_3);
        term_sink(e, _left_0);
        spare_free(e, cls_fit(3), _sp_2);
        if (seq) {
          WL_ROOM(1);
          STK(0) = FID_INDEX_FIND_WORK_K13323;
          WL_PUSHN(1);
        } else {
          u64 _t_4 = task_node(e, FID_INDEX_FIND_WORK_K13323, WL_CONT, WL_IDX, 1);
          WL_CONT = term_tsk(FID_INDEX_FIND_WORK_K13323, _t_4);
          WL_IDX = 0;
        }
        if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
          u64 _t_5 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
          e.mem[_t_5 + 0] = _right_0;
          e.mem[_t_5 + 1] = term_pak(CID_UNIT, 0);
          return term_tsk(FID_CLO_APPLY, _t_5);
        }
        r0 = _right_0;
        r1 = term_pak(CID_UNIT, 0);
        WL_JMP(FID_CLO_APPLY);
      } else {
        Term _right_1 = term_clo(FID_INDEX_FIND_WORK_C13319, _nd_1);
        term_sink(e, _right_1);
        Term _left_1 = term_clo(FID_INDEX_FIND_WORK_C13321, _nd_3);
        spare_free(e, cls_fit(3), _sp_2);
        if (seq) {
          WL_ROOM(1);
          STK(0) = FID_INDEX_FIND_WORK_K13324;
          WL_PUSHN(1);
        } else {
          u64 _t_6 = task_node(e, FID_INDEX_FIND_WORK_K13324, WL_CONT, WL_IDX, 1);
          WL_CONT = term_tsk(FID_INDEX_FIND_WORK_K13324, _t_6);
          WL_IDX = 0;
        }
        if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
          u64 _t_7 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
          e.mem[_t_7 + 0] = _left_1;
          e.mem[_t_7 + 1] = term_pak(CID_UNIT, 0);
          return term_tsk(FID_CLO_APPLY, _t_7);
        }
        r0 = _left_1;
        r1 = term_pak(CID_UNIT, 0);
        WL_JMP(FID_CLO_APPLY);
      }
    }
  }}
#endif
#if !DEVICE
  WL_CASE(FID_REVIEW_END)
  { WL_OPEN WL_RETN(0); }
