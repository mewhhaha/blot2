
// Read-only, bounded certificate that a type is unchanged by every history.
static bool compact_closed_type(Env e, Term ty, Term fuel, unsigned depth,
                                unsigned *steps);
static bool compact_closed_many(Env e, Term values, Term fuel, unsigned depth,
                                unsigned *steps) {
  if (fuel == 0 || depth > 128 || ++*steps > 512) return false;
  if (term_aux(values) == CID_NIL) return true;
  if (term_aux(values) != CID_CON) return false;
  Loc at = term_peek(e, values);
  return compact_closed_type(e, e.mem[at], fuel - 1, depth + 1, steps) &&
         compact_closed_many(e, e.mem[at + 1], fuel - 1, depth + 1, steps);
}

static bool compact_closed_type(Env e, Term ty, Term fuel, unsigned depth,
                                unsigned *steps) {
  if (fuel == 0 || depth > 128 || ++*steps > 512) return false;
  u64 cid = term_aux(ty);
  if (cid == CID_MODEL_VARIABLETY) return false;
  if (cid == CID_MODEL_FUNCTIONTY) {
    Loc at = term_peek(e, ty);
    return e.mem[at + 3] != 1 &&
           compact_closed_type(e, e.mem[at], fuel - 1, depth + 1, steps) &&
           compact_closed_type(e, e.mem[at + 1], fuel - 1, depth + 1, steps);
  }
  if (cid == CID_MODEL_STATEPROVIDERTY) {
    Loc at = term_peek(e, ty);
    return compact_closed_type(e, e.mem[at + 4], fuel - 1, depth + 1, steps);
  }
  if (cid == CID_MODEL_PROVIDERTY) {
    Loc at = term_peek(e, ty);
    return e.mem[at + 3] != 1;
  }
  if (cid == CID_MODEL_APPLIEDTY) {
    Loc at = term_peek(e, ty);
    return compact_closed_many(e, e.mem[at + 2], fuel - 1, depth + 1, steps);
  }
  if (cid == CID_MODEL_PRODUCTTY) {
    Loc at = term_peek(e, ty);
    return compact_closed_many(e, e.mem[at], fuel - 1, depth + 1, steps);
  }
  if (cid == CID_MODEL_ARRAYTY) {
    Loc at = term_peek(e, ty);
    return compact_closed_type(e, e.mem[at], fuel - 1, depth + 1, steps);
  }
  return true;
}

static inline bool compact_closed_work(Env e, u32 tag, Term work, Term fuel) {
  if (fuel == 0 || fuel > 65536) return false;
  unsigned steps = 0;
  if (tag == 0) return compact_closed_type(e, work, fuel, 0, &steps);
  if (tag == 1) return compact_closed_many(e, work, fuel, 0, &steps);
  return false;
}

static inline Term compact_closed_result(Env e, u32 tag, Term work) {
  if (tag == 1) return work; // Transfer ownership of the original list.
  Loc at = heap_alloc(e, cls_fit(2));
  e.mem[at] = rfc_seal(e, work); // Transfer ownership of the type.
  e.mem[at + 1] = rfc_seal(e, term_pak(CID_NIL, 0));
  return term_ctr(CID_CON, at);
}
