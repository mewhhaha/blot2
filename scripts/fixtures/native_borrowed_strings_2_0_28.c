// Bend 2.0.28 Map.bit/String.cmp cases and helpers from reviewed raw C in the
// older minimal fixture shell; intentionally not compilable.
#define DEVICE  0
typedef uint64_t u64;
typedef u64 Loc;
typedef u64 Term;
#define RFC_CNT  ((1u << 24) - 1)
#define a32_load(p)         __atomic_load_n(p, __ATOMIC_RELAXED)
#define a32_load_acq(p)     __atomic_load_n(p, __ATOMIC_ACQUIRE)
#define a32_acq(p)          ((void)a32_load_acq(p))
#define a32_at(H, word) ((DEV u32*)&(H)[word])
#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)

typedef uint32_t u32;

#define NAT_IMM ((1ull << 48) - 1)

#define LOC_MASK ((1ull << 40) - 1)

#define RFC_BIT  (1ull << 63)

#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))

#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }
#define WL_OPEN    { WL_BANK u32 rn;

#define CID_SNIL 1

#define CID_SCON 2

#define CID_CHR 18

#define FID_MAP_BIT_GO 7572
#define FID_MAP_BIT_GO_K5788 4441

#define FID_MAP_BIT 9623

#define FID_STRING_CMP 8484
#define FID_STRING_CMP_K7685 6189

#define FID_MAP_BIT_GO_K9775 7573
#define FID_STRING_CMP_K10892 8485
INLINE u64 term_aux(Term t) {
  return (t >> 40) & 0xFFFF;
}

INLINE bool term_rfc(Term t) {
  return (t & RFC_BIT) != 0;
}

INLINE Loc term_loc(Term t) {
  return t & LOC_MASK;
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

INLINE Term spin_821(Env e, THR Term* o, u32 r0, Term r1) {
  u32 wpoll = 0;
  u32 _v_2 = 0;
  u32 _x_0 = r0;
  Term _k_0 = r1;
  WL_SPIN
    _v_2 = U32_BIN(U32_BIN((_k_0 >= 32 ? 0 : U32_BIN(_x_0, >>, _k_0)), &, 1ull), !=, 0ull);
  break;
  }

INLINE Term spin_903(Env e, THR Term* o, u32 r0, Term r1) {
  u32 wpoll = 0;
  u32 _v_4 = 0;
  u32 _v_5 = 0;
  u32 _c_0 = r0;
  Term _off_1 = r1;
  WL_SPIN
    if (_off_1 == 0) {
      _v_4 = _c_0;
      _v_5 = 1;
    } else {
      Term _b_0 = (_off_1 - 1);
      u32 _v_6 = 0;
      Term _a_0 = 31ull;
      u32 _v_7 = 0;
      Term _o_0[1];
      if (spin_821(e, _o_0, _c_0, (_a_0 < _b_0 ? 0 : _a_0 - _b_0)) == 0) {
        return 0;
      }
      _v_7 = _o_0[0];
      _v_6 = _v_7;
      _v_4 = _c_0;
      _v_5 = _v_6;
    }
  break;
  }

INLINE Term spin_995(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 _v_6 = 0;
  u32 _v_7 = 0;
  u32 _v_8 = 0;
  u32 _a_1 = r0;
  u32 _b_1 = r1;
  WL_SPIN
    _v_6 = _a_1;
    _v_7 = _b_1;
    _v_8 = (U32_BIN(_a_1, >, _b_1) + U32_BIN(_a_1, >=, _b_1));
  break;
  }

#if !DEVICE
  WL_CASE(FID_MAP_BIT_GO)
  {
    Term _key_0 = r0;
    Term _ci_0 = r1;
    Term _off_0 = r2;
    WL_OPEN
    WL_SPIN
    if (term_aux(_key_0) == CID_SNIL) {
      r0 = term_pak(CID_SNIL, 0);
      r1 = 0;
      WL_RETN(2);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _key_0, 2, _fb_0);
      u32 _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      if (_ci_0 == 0) {
        u32 _v_0 = 0;
        u32 _v_1 = 0;
        u32 _v_2 = 0;
        u32 _v_3 = 0;
        Term _o_1[2];
        if (spin_903(e, _o_1, _f_0, _off_0) == 0) {
          return 0;
        }
        _v_2 = _o_1[0];
        _v_3 = _o_1[1];
        _v_0 = _v_2;
        _v_1 = _v_3;
        Term _v_8 = 0;
        u32 _v_9 = 0;
        Term _o_2[2];
        if (spin_904(e, _o_2, _f_1, _v_0, _v_1) == 0) {
          return 0;
        }
        _v_8 = _o_2[0];
        _v_9 = _o_2[1];
        spare_free(e, cls_fit(2), _sp_0);
        r0 = _v_8;
        r1 = _v_9;
        WL_RETN(2);
      } else {
        Term _j_0 = (_ci_0 - 1);
        spare_free(e, cls_fit(2), _sp_0);
        if (seq) {
          WL_ROOM(2);
          STK(0) = _f_0;
          STK(1) = FID_MAP_BIT_GO_K9775;
          WL_PUSHN(2);
        } else {
          u64 _t_1 = task_node(e, FID_MAP_BIT_GO_K9775, WL_CONT, WL_IDX, 1);
          e.mem[_t_1 + 0] = _f_0;
          WL_CONT = term_tsk(FID_MAP_BIT_GO_K9775, _t_1);
          WL_IDX = 1;
        }
        r0 = _f_1;
        r1 = _j_0;
        r2 = _off_0;
        _key_0 = r0;
        _ci_0 = r1;
        _off_0 = r2;
        WL_AGAIN(FID_MAP_BIT_GO);
      }
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAP_BIT)
  {
    Term _key_0 = r0;
    Term _pos_0 = r1;
    WL_OPEN
    Term _a_0 = 33ull;
    Term _a_1 = (_a_0 == 0 ? 0 : _pos_0 / _a_0);
    Term _a_2 = (_a_0 == 0 ? _pos_0 : _pos_0 % _a_0);
    if (!DEVICE && !seq && fid_nofk(FID_MAP_BIT_GO)) {
      u64 _t_0 = task_node(e, FID_MAP_BIT_GO, WL_CONT, WL_IDX, 0);
      e.mem[_t_0 + 0] = _key_0;
      e.mem[_t_0 + 1] = _a_1;
      e.mem[_t_0 + 2] = _a_2;
      return term_tsk(FID_MAP_BIT_GO, _t_0);
    }
    r0 = _key_0;
    r1 = _a_1;
    r2 = _a_2;
    WL_JMP(FID_MAP_BIT_GO);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_CMP)
  {
    Term _a_0 = r0;
    Term _b_0 = r1;
    WL_OPEN
    WL_SPIN
    if (term_aux(_a_0) == CID_SNIL) {
      if (term_aux(_b_0) == CID_SNIL) {
        r0 = term_pak(CID_SNIL, 0);
        r1 = term_pak(CID_SNIL, 0);
        r2 = 1;
        WL_RETN(3);
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _b_0, 2, _fb_0);
        u32 _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        u64 _nd_0 = _sp_0 >= HEAP_OFF ? _sp_0 : heap_alloc(e, cls_fit(2));
        e.mem[_nd_0 + 0] = rfc_seal(e, _f_0);
        e.mem[_nd_0 + 1] = rfc_seal(e, _f_1);
        r0 = term_pak(CID_SNIL, 0);
        r1 = term_ctr(CID_SCON, _nd_0);
        r2 = 0;
        WL_RETN(3);
      }
    } else {
      Term _fb_1[2];
      u64 _sp_1 = ctr_take(e, _a_0, 2, _fb_1);
      u32 _f_2 = _fb_1[0];
      Term _f_3 = _fb_1[1];
      if (term_aux(_b_0) == CID_SNIL) {
        u64 _nd_1 = _sp_1 >= HEAP_OFF ? _sp_1 : heap_alloc(e, cls_fit(2));
        e.mem[_nd_1 + 0] = rfc_seal(e, _f_2);
        e.mem[_nd_1 + 1] = rfc_seal(e, _f_3);
        r0 = term_ctr(CID_SCON, _nd_1);
        r1 = term_pak(CID_SNIL, 0);
        r2 = 2;
        WL_RETN(3);
      } else {
        Term _fb_2[2];
        u64 _sp_2 = ctr_take(e, _b_0, 2, _fb_2);
        u32 _f_4 = _fb_2[0];
        Term _f_5 = _fb_2[1];
        u32 _v_0 = 0;
        u32 _v_1 = 0;
        u32 _v_2 = 0;
        u32 _v_3 = 0;
        u32 _v_4 = 0;
        u32 _v_5 = 0;
        Term _o_0[3];
        if (spin_995(e, _o_0, _f_2, _f_4) == 0) {
          return 0;
        }
        _v_3 = _o_0[0];
        _v_4 = _o_0[1];
        _v_5 = _o_0[2];
        _v_0 = _v_3;
        _v_1 = _v_4;
        _v_2 = _v_5;
        if (_v_2 == 0) {
          u64 _nd_2 = _sp_1 >= HEAP_OFF ? _sp_1 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_2 + 0] = rfc_seal(e, _v_0);
          e.mem[_nd_2 + 1] = rfc_seal(e, _f_3);
          u64 _nd_3 = _sp_2 >= HEAP_OFF ? _sp_2 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_3 + 0] = rfc_seal(e, _v_1);
          e.mem[_nd_3 + 1] = rfc_seal(e, _f_5);
          r0 = term_ctr(CID_SCON, _nd_2);
          r1 = term_ctr(CID_SCON, _nd_3);
          r2 = 0;
          WL_RETN(3);
        } else if (_v_2 == 1) {
          spare_free(e, cls_fit(2), _sp_2);
          spare_free(e, cls_fit(2), _sp_1);
          if (seq) {
            WL_ROOM(3);
            STK(0) = _v_0;
            STK(1) = _v_1;
            STK(2) = FID_STRING_CMP_K10892;
            WL_PUSHN(3);
          } else {
            u64 _t_0 = task_node(e, FID_STRING_CMP_K10892, WL_CONT, WL_IDX, 1);
            e.mem[_t_0 + 0] = _v_0;
            e.mem[_t_0 + 1] = _v_1;
            WL_CONT = term_tsk(FID_STRING_CMP_K10892, _t_0);
            WL_IDX = 2;
          }
          r0 = _f_3;
          r1 = _f_5;
          _a_0 = r0;
          _b_0 = r1;
          WL_AGAIN(FID_STRING_CMP);
        } else {
          u64 _nd_4 = _sp_1 >= HEAP_OFF ? _sp_1 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_4 + 0] = rfc_seal(e, _v_0);
          e.mem[_nd_4 + 1] = rfc_seal(e, _f_3);
          u64 _nd_5 = _sp_2 >= HEAP_OFF ? _sp_2 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_5 + 0] = rfc_seal(e, _v_1);
          e.mem[_nd_5 + 1] = rfc_seal(e, _f_5);
          r0 = term_ctr(CID_SCON, _nd_4);
          r1 = term_ctr(CID_SCON, _nd_5);
          r2 = 2;
          WL_RETN(3);
        }
      }
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAP_BIT_GO_K9775)
  {
    WL_POPN(1);
    u32 _f_2 = STK(0);
    Term _h_0 = r0;
    u32 _h_1 = r1;
    WL_OPEN
    Term _v_12 = 0;
    u32 _v_13 = 0;
    Term _o_3[2];
    if (spin_905(e, _o_3, _f_2, _h_0, _h_1) == 0) {
      return 0;
    }
    _v_12 = _o_3[0];
    _v_13 = _o_3[1];
    r0 = _v_12;
    r1 = _v_13;
    WL_RETN(2);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_CMP_K10892)
  {
    WL_POPN(2);
    u32 _v_9 = STK(0);
    u32 _v_10 = STK(1);
    Term _h_0 = r0;
    Term _h_1 = r1;
    u32 _h_2 = r2;
    WL_OPEN
    Term _v_11 = 0;
    Term _v_12 = 0;
    u32 _v_13 = 0;
    Term _o_1[3];
    if (spin_906(e, _o_1, _v_9, _v_10, _h_0, _h_1, _h_2) == 0) {
      return 0;
    }
    _v_11 = _o_1[0];
    _v_12 = _o_1[1];
    _v_13 = _o_1[2];
    r0 = _v_11;
    r1 = _v_12;
    r2 = _v_13;
    WL_RETN(3);
  }}
#endif

INLINE Term spin_904(Env e, THR Term* o, Term r0, u32 r1, u32 r2) {
  u32 wpoll = 0;
  Term _v_10 = 0;
  u32 _v_11 = 0;
  Term _t_0 = r0;
  u32 _r_0 = r1;
  u32 _r_1 = r2;
  WL_SPIN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _r_0);
    e.mem[_nd_0 + 1] = rfc_seal(e, _t_0);
    _v_10 = term_ctr(CID_SCON, _nd_0);
    _v_11 = _r_1;
  break;
  }
