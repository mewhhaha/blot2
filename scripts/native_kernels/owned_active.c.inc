
#define OWNED_NODE_LIMIT 256
#define OWNED_CHILD_LIMIT 16
typedef struct {
  unsigned kind; // 0 borrowed, 1 array, 2 function, 3 state, 4 applied, 5 product
  bool changed;
  Term original;
  Term fields[5];
  unsigned child[OWNED_CHILD_LIMIT];
  unsigned count;
} OwnedTypeNode;

typedef struct {
  OwnedTypeNode nodes[OWNED_NODE_LIMIT];
  unsigned used;
} OwnedTypePlan;

static inline bool owned_can_keep(Term value) {
  return term_triv(value) || term_rfc(value);
}

// Borrowed Patricia lookup, preserving the generated NatIndex's key path.
static bool owned_versions(Env e, Term index, Term key,
                           Term *versions, bool *found) {
  if (key > (1ull << 48)) return false;
  for (unsigned depth = 0; depth < 64; ++depth) {
    u64 cid = term_aux(index);
    if (cid == CID_NAT_INDEX_EMPTY) { *found = false; return true; }
    if (cid == CID_NAT_INDEX_LEAF) {
      Loc at = term_peek(e, index);
      Term stored = e.mem[at];
      if (stored > (1ull << 48)) return false;
      *found = stored == key;
      if (*found) *versions = e.mem[at + 1];
      return true;
    }
    if (cid != CID_NAT_INDEX_BRANCH) return false;
    Loc at = term_peek(e, index);
    Term sample = e.mem[at], mask = e.mem[at + 1];
    if (sample > (1ull << 48) || mask == 0 || mask > (1ull << 48) ||
        (mask & (mask - 1)) != 0) return false;
    if (key / (2 * mask) != sample / (2 * mask)) {
      *found = false;
      return true;
    }
    index = e.mem[at + ((key / mask) & 1 ? 3 : 2)];
  }
  return false;
}

// Version lists are newest first. The last eligible entry is the earliest
// chronological replacement in the requested cursor suffix.
static bool owned_version(Env e, Term versions, Term cursor, Term count,
                          Term *position, Term *replacement, bool *found) {
  *found = false;
  for (unsigned step = 0; step < 256; ++step) {
    if (term_aux(versions) == CID_NIL) return true;
    if (term_aux(versions) != CID_CON) return false;
    Loc at = term_peek(e, versions);
    Term entry = e.mem[at];
    if (term_aux(entry) != CID_TYPES_VERSION) return false;
    Loc value_at = term_peek(e, entry);
    Term current = e.mem[value_at];
    if (current >= count) return false;
    if (current >= cursor) {
      *found = true;
      *position = current;
      *replacement = e.mem[value_at + 1];
    }
    versions = e.mem[at + 1];
  }
  return false;
}

static bool owned_type(Env e, Term ty, Term index, Term count,
                       Term fuel, Term cursor, Term links, bool exhausted,
                       unsigned depth, OwnedTypePlan *plan, unsigned *out);

static bool owned_many(Env e, Term list, Term index, Term count,
                       Term fuel, Term cursor, Term links, bool exhausted,
                       unsigned depth, OwnedTypePlan *plan,
                       OwnedTypeNode *parent) {
  for (;;) {
    if (exhausted) return false; // A substituted exhausted subtree is borrowed whole.
    if (fuel == 0 || depth > 64) return false;
    if (term_aux(list) == CID_NIL) return true;
    if (term_aux(list) != CID_CON || parent->count == OWNED_CHILD_LIMIT)
      return false;
    Loc at = term_peek(e, list);
    unsigned child = 0;
    if (!owned_type(e, e.mem[at], index, count, fuel - 1, cursor,
                    links, false, depth + 1, plan, &child)) return false;
    parent->child[parent->count++] = child;
    parent->changed |= plan->nodes[child].changed;
    list = e.mem[at + 1];
    fuel--;
    depth++;
  }
}

static bool owned_leaf(OwnedTypePlan *plan, Term ty, unsigned *out) {
  if (plan->used == OWNED_NODE_LIMIT) return false;
  unsigned id = plan->used++;
  plan->nodes[id] = (OwnedTypeNode){ .kind = 0, .changed = false,
                                     .original = ty, .count = 0 };
  *out = id;
  return true;
}

static bool owned_type(Env e, Term ty, Term index, Term count,
                       Term fuel, Term cursor, Term links, bool exhausted,
                       unsigned depth, OwnedTypePlan *plan, unsigned *out) {
  if (depth > 64) return false;
  if (exhausted) return owned_leaf(plan, ty, out);
  if (fuel == 0 || fuel > 65536) return false;
  u64 cid = term_aux(ty);
  if (cid == CID_MODEL_VARIABLETY) {
    if (links == 0) return false; // Preserve the generated internal diagnostic.
    Loc at = term_peek(e, ty);
    Term key = e.mem[at], versions = 0, position = 0, replacement = 0;
    bool has_key = false, has_version = false;
    if (!owned_versions(e, index, key, &versions, &has_key)) return false;
    if (has_key && !owned_version(e, versions, cursor, count,
                                  &position, &replacement, &has_version)) return false;
    if (!has_version) return owned_leaf(plan, ty, out);
    if (position + 1 > count) return false;
    if (!owned_type(e, replacement, index, count, fuel, position + 1,
                    links - 1, position + 1 >= count, depth + 1,
                    plan, out)) return false;
    // A replacement may itself be a borrowed leaf. It is a change relative
    // to the original variable even if its interior needed no further work.
    // If an unchanged composite replacement was planned, borrow it whole:
    // its interior fields were not individually certified for acquisition.
    // Already planned descendants are all unchanged and freeze to no terms.
    if (!plan->nodes[*out].changed) {
      if (!owned_can_keep(plan->nodes[*out].original)) return false;
      plan->nodes[*out].kind = 0;
      plan->nodes[*out].count = 0;
    }
    plan->nodes[*out].changed = true;
    return true;
  }
  if (!owned_leaf(plan, ty, out)) return false;
  OwnedTypeNode *node = &plan->nodes[*out];
  Loc at;
  unsigned child;
  if (cid == CID_MODEL_ARRAYTY) {
    at = term_peek(e, ty);
    node->kind = 1;
    if (!owned_type(e, e.mem[at], index, count, fuel - 1, cursor, links,
                    false, depth + 1, plan, &child)) return false;
    node->child[0] = child;
    node->changed = plan->nodes[child].changed;
    return !node->changed || plan->nodes[child].changed ||
           owned_can_keep(plan->nodes[child].original);
  }
  if (cid == CID_MODEL_FUNCTIONTY) {
    at = term_peek(e, ty);
    if (e.mem[at + 3] == 1) return false; // Scoped row substitution stays in Bend.
    node->kind = 2;
    node->fields[2] = e.mem[at + 2];
    node->fields[3] = e.mem[at + 3];
    node->fields[4] = e.mem[at + 4];
    if (!owned_type(e, e.mem[at], index, count, fuel - 1, cursor, links,
                    false, depth + 1, plan, &child)) return false;
    node->child[0] = child;
    if (!owned_type(e, e.mem[at + 1], index, count, fuel - 1, cursor,
                    links, false, depth + 1, plan, &child)) return false;
    node->child[1] = child;
    node->changed = plan->nodes[node->child[0]].changed ||
                    plan->nodes[node->child[1]].changed;
    return !node->changed ||
           (owned_can_keep(node->fields[2]) &&
            owned_can_keep(node->fields[4]) &&
            (plan->nodes[node->child[0]].changed ||
             owned_can_keep(plan->nodes[node->child[0]].original)) &&
            (plan->nodes[node->child[1]].changed ||
             owned_can_keep(plan->nodes[node->child[1]].original)));
  }
  if (cid == CID_MODEL_STATEPROVIDERTY) {
    at = term_peek(e, ty);
    node->kind = 3;
    for (unsigned i = 0; i < 4; ++i) node->fields[i] = e.mem[at + i];
    if (!owned_type(e, e.mem[at + 4], index, count, fuel - 1, cursor,
                    links, false, depth + 1, plan, &child)) return false;
    node->child[0] = child;
    node->changed = plan->nodes[child].changed;
    if (!node->changed) return true;
    if (!plan->nodes[child].changed &&
        !owned_can_keep(plan->nodes[child].original)) return false;
    for (unsigned i = 0; i < 4; ++i)
      if (!owned_can_keep(node->fields[i])) return false;
    return true;
  }
  if (cid == CID_MODEL_APPLIEDTY || cid == CID_MODEL_PRODUCTTY) {
    at = term_peek(e, ty);
    node->kind = cid == CID_MODEL_APPLIEDTY ? 4 : 5;
    Term list = e.mem[at + (node->kind == 4 ? 2 : 0)];
    if (node->kind == 4) {
      node->fields[0] = e.mem[at];
      node->fields[1] = e.mem[at + 1];
    }
    if (!owned_many(e, list, index, count, fuel - 1, cursor, links,
                    false, depth + 1, plan, node)) return false;
    if (!node->changed) return true;
    if (node->kind == 4 && (!owned_can_keep(node->fields[0]) ||
                            !owned_can_keep(node->fields[1]))) return false;
    for (unsigned i = 0; i < node->count; ++i) {
      OwnedTypeNode *c = &plan->nodes[node->child[i]];
      if (!c->changed && !owned_can_keep(c->original)) return false;
    }
    return true;
  }
  if (cid == CID_MODEL_PROVIDERTY) {
    at = term_peek(e, ty);
    return e.mem[at + 3] != 1; // No value child; closed/parameter row is inert.
  }
  // Remaining type constructors have no substitutable fields.
  return cid == CID_MODEL_UNITTY || cid == CID_MODEL_U32TY ||
         cid == CID_MODEL_BOOLTY || cid == CID_MODEL_PARAMETERTY ||
         cid == CID_MODEL_NEVERTY || cid == CID_MODEL_F32TY ||
         cid == CID_MODEL_EFFECTDESCRIPTORTY || cid == CID_MODEL_EFFECTSETTY ||
         cid == CID_MODEL_FREETY;
}

static bool owned_plan(Env e, Term work, Term index, Term count, Term fuel,
                       OwnedTypePlan *plan, unsigned *root) {
  plan->used = 0;
  if (count == 0 || count > 65536 || fuel == 0 || fuel > 65536) return false;
  return owned_type(e, work, index, count, fuel, 0, count, false, 0,
                    plan, root);
}

static inline Term owned_acquire(Env e, Term value) {
  return rfc_seal(e, term_keep(e, value));
}

static inline Term owned_child(Env e, OwnedTypePlan *plan,
                               Term *outputs, unsigned id) {
  return plan->nodes[id].changed ? rfc_seal(e, outputs[id]) :
                                   owned_acquire(e, outputs[id]);
}

static Term owned_freeze(Env e, OwnedTypePlan *plan, unsigned root) {
  Term outputs[OWNED_NODE_LIMIT];
  for (unsigned k = plan->used; k > 0; --k) {
    unsigned i = k - 1;
    OwnedTypeNode *node = &plan->nodes[i];
    if (!node->changed) { outputs[i] = node->original; continue; }
    if (node->kind == 0) {
      outputs[i] = owned_acquire(e, node->original);
      continue;
    }
    Loc at;
    if (node->kind == 1) {
      at = heap_alloc(e, cls_fit(1));
      e.mem[at] = owned_child(e, plan, outputs, node->child[0]);
      outputs[i] = term_ctr(CID_MODEL_ARRAYTY, at);
      continue;
    }
    if (node->kind == 2) {
      at = heap_alloc(e, cls_fit(5));
      e.mem[at] = owned_child(e, plan, outputs, node->child[0]);
      e.mem[at + 1] = owned_child(e, plan, outputs, node->child[1]);
      e.mem[at + 2] = owned_acquire(e, node->fields[2]);
      e.mem[at + 3] = node->fields[3];
      e.mem[at + 4] = owned_acquire(e, node->fields[4]);
      outputs[i] = term_ctr(CID_MODEL_FUNCTIONTY, at);
      continue;
    }
    if (node->kind == 3) {
      at = heap_alloc(e, cls_fit(5));
      for (unsigned f = 0; f < 4; ++f)
        e.mem[at + f] = owned_acquire(e, node->fields[f]);
      e.mem[at + 4] = owned_child(e, plan, outputs, node->child[0]);
      outputs[i] = term_ctr(CID_MODEL_STATEPROVIDERTY, at);
      continue;
    }
    Term list = term_pak(CID_NIL, 0);
    for (unsigned j = node->count; j > 0; --j) {
      at = heap_alloc(e, cls_fit(2));
      e.mem[at] = owned_child(e, plan, outputs, node->child[j - 1]);
      e.mem[at + 1] = rfc_seal(e, list);
      list = term_ctr(CID_CON, at);
    }
    if (node->kind == 5) {
      at = heap_alloc(e, cls_fit(1));
      e.mem[at] = rfc_seal(e, list);
      outputs[i] = term_ctr(CID_MODEL_PRODUCTTY, at);
    } else {
      at = heap_alloc(e, cls_fit(3));
      e.mem[at] = owned_acquire(e, node->fields[0]);
      e.mem[at + 1] = owned_acquire(e, node->fields[1]);
      e.mem[at + 2] = rfc_seal(e, list);
      outputs[i] = term_ctr(CID_MODEL_APPLIEDTY, at);
    }
  }
  return outputs[root];
}
