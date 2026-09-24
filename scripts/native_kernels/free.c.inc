
// Borrowed type walk. No child is taken, kept, mutated, or cached.
typedef struct {
  Term items[32];
  unsigned size;
} CompactFree;

static inline bool compact_free_put(CompactFree *v, Term id) {
  if (id > UINT32_MAX) return false; // Keep Nat fields trivially immediate.
  for (unsigned i = 0; i < v->size; ++i) if (v->items[i] == id) return true;
  if (v->size == 32) return false;
  for (unsigned i = v->size; i > 0; --i) v->items[i] = v->items[i - 1];
  v->items[0] = id;
  ++v->size;
  return true;
}

static inline bool compact_free_union(CompactFree *left, CompactFree *right) {
  for (unsigned i = 0; i < left->size; ++i)
    if (!compact_free_put(right, left->items[i])) return false;
  return true;
}

static bool compact_free_type(Env e, Term ty, Term fuel, unsigned depth,
                              unsigned *steps, CompactFree *out);
static bool compact_free_many(Env e, Term values, Term fuel, unsigned depth,
                              unsigned *steps, CompactFree *out) {
  if (fuel == 0 || depth > 128 || ++*steps > 512) return false;
  if (term_aux(values) == CID_NIL) return true;
  if (term_aux(values) != CID_CON) return false;
  Loc at = term_peek(e, values);
  CompactFree head = { .size = 0 }, tail = { .size = 0 };
  if (!compact_free_type(e, e.mem[at], fuel - 1, depth + 1, steps, &head) ||
      !compact_free_many(e, e.mem[at + 1], fuel - 1, depth + 1, steps, &tail) ||
      !compact_free_union(&head, &tail)) return false;
  *out = tail;
  return true;
}

static bool compact_free_type(Env e, Term ty, Term fuel, unsigned depth,
                              unsigned *steps, CompactFree *out) {
  if (fuel == 0 || depth > 128 || ++*steps > 512) return false;
  u64 cid = term_aux(ty);
  if (cid == CID_MODEL_VARIABLETY) {
    Loc at = term_peek(e, ty);
    return compact_free_put(out, e.mem[at]);
  }
  if (cid == CID_MODEL_FUNCTIONTY) {
    Loc at = term_peek(e, ty);
    CompactFree parameter = { .size = 0 }, result = { .size = 0 };
    if (!compact_free_type(e, e.mem[at], fuel - 1, depth + 1, steps, &parameter) ||
        !compact_free_type(e, e.mem[at + 1], fuel - 1, depth + 1, steps, &result) ||
        !compact_free_union(&parameter, &result)) return false;
    if (e.mem[at + 3] == 1 &&
        !compact_free_put(&result, e.mem[at + 4])) return false;
    *out = result;
    return true;
  }
  if (cid == CID_MODEL_STATEPROVIDERTY) {
    Loc at = term_peek(e, ty);
    return compact_free_type(e, e.mem[at + 4], fuel - 1, depth + 1, steps, out);
  }
  if (cid == CID_MODEL_PROVIDERTY) {
    Loc at = term_peek(e, ty);
    return e.mem[at + 3] != 1 || compact_free_put(out, e.mem[at + 4]);
  }
  if (cid == CID_MODEL_APPLIEDTY) {
    Loc at = term_peek(e, ty);
    return compact_free_many(e, e.mem[at + 2], fuel - 1, depth + 1, steps, out);
  }
  if (cid == CID_MODEL_PRODUCTTY) {
    Loc at = term_peek(e, ty);
    return compact_free_many(e, e.mem[at], fuel - 1, depth + 1, steps, out);
  }
  if (cid == CID_MODEL_ARRAYTY) {
    Loc at = term_peek(e, ty);
    return compact_free_type(e, e.mem[at], fuel - 1, depth + 1, steps, out);
  }
  return true;
}

static inline bool compact_free_work(Env e, u32 work_tag, Term work,
                                     Term fuel, CompactFree *out) {
  if (fuel == 0 || fuel > 65536) return false;
  unsigned steps = 0;
  if (work_tag == 0)
    return compact_free_type(e, work, fuel, 0, &steps, out);
  if (work_tag == 1)
    return compact_free_many(e, work, fuel, 0, &steps, out);
  return false;
}

static inline Term compact_free_list(Env e, const CompactFree *out) {
  Term list = term_pak(CID_NIL, 0);
  for (unsigned i = out->size; i > 0; --i) {
    Loc at = heap_alloc(e, cls_fit(2));
    e.mem[at] = rfc_seal(e, out->items[i - 1]);
    e.mem[at + 1] = rfc_seal(e, list);
    list = term_ctr(CID_CON, at);
  }
  return list;
}
