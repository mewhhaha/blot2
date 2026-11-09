/* Query methods/AST are extracted by the runner; lazy field and ArraySize leaves
 * reuse the existing array_gate.cpp Predicate. Assertions stay on in both runs. */
#undef NDEBUG
#include <cassert>
static void parity(Predicate &old, Predicate &q, TypeExpr *t, TypeExpr *of) {
    assert(old.BaselineReaches(t, of) == q.ReachesThroughRefs(t, of));
    vector<TypeExpr *> a, b;
    old.ReachedThroughRefs(t, a); q.ReachedThroughRefs(t, b);
    assert(q.TypeArgsEq(a, b));
}
int main() {
    law("cyclic full ordered closure and Boolean parity", [] {
        Arena a; auto i = a.Int(); auto b = a.Type(TY_BOOL);
        auto x = a.Struct(), y = a.Struct();
        x->struc->inst->ftypes = {a.Ref(y), a.Ref(i)};
        y->struc->inst->ftypes = {a.Ref(x), a.Slice(b)};
        Predicate old, q;
        parity(old, q, x, i); parity(old, q, x, b); parity(old, q, x, a.Type(TY_FLT));
        vector<TypeExpr *> raw; q.ReachedThroughRefs(x, raw);
        assert(q.TypeArgsEq(raw, q.referenceclosures.entries.at(x->struc->inst)));
        assert(raw == vector<TypeExpr *>({i, y, b, x}));
    });
    law("same validated instance shares outer const and plain clones", [] {
        Arena a; auto i = a.Int(), b = a.Type(TY_BOOL); auto x = a.Struct({a.Ref(i)});
        auto c = a.Type(TY_STRUCT); c->struc = x->struc; c->cq = true;
        Predicate old, q; q.referenceclosures.profile.enabled = true;
        parity(old, q, x, i); parity(old, q, c, b);
        assert(q.referenceclosures.entries.size() == 1 && q.referenceclosures.profile.hits == 1);
    });
    law("generic instances retain separate field closures", [] {
        Arena a; auto i = a.Int(), b = a.Type(TY_BOOL);
        auto x = a.Struct({a.Ref(i)}), y = a.Struct({a.Ref(b)});
        args(x, {i}); args(y, {b}); y->struc->st = x->struc->st;
        Predicate old, q; parity(old, q, x, i); parity(old, q, y, i);
        assert(q.referenceclosures.entries.size() == 2);
        assert(q.referenceclosures.entries.at(x->struc->inst) == vector<TypeExpr *>({i}));
        assert(q.referenceclosures.entries.at(y->struc->inst) == vector<TypeExpr *>({b}));
    });
    law("struct ref slice relative pool optional and qualifier roots differ", [] {
        Arena a; auto i = a.Int(); auto s = a.Struct({i}); auto r = a.Ref(s);
        auto slice = a.Slice(s), relative = a.Ref(s), optional = a.Ref(s), qualified = a.Ref(s);
        VarDef pool{}; relative->ref->pool = &pool; relative->ref->poolname = "p";
        relative->ref->lenstorage = IS_U32; optional->ref->optional = true; qualified->cq = true;
        Predicate old, q;
        for (auto t : {s, r, slice, relative, optional, qualified}) parity(old, q, t, i);
        assert(!q.ReachesThroughRefs(s, i) && q.ReachesThroughRefs(r, i));
        assert(!q.ReachesThroughRefs(relative, i) && q.ReachesThroughRefs(slice, i));
        assert(q.referenceclosures.entries.size() == 6);
        auto cs = a.Type(TY_STRUCT); cs->struc = s->struc; cs->cq = true;
        auto cr = a.Ref(cs); parity(old, q, cr, i);
        assert(q.referenceclosures.entries.count(cr));
    });
    law("cold incomplete grow fixed index and pool graphs retain original path", [] {
        Arena a; auto i = a.Int(); auto unfinished = a.Struct({a.Ref(i)}, false);
        auto grow = a.Array(a.Type(TY_VOID), A_GROW, 0);
        auto fixed = a.Array(a.Ref(i), A_FIXED, -1);
        auto pending_pool = a.Ref(i); pending_pool->ref->poolname = "missing";
        auto index = a.Int(); index->ix = a.Detail<TypeIndex>(); index->ix->name = "pending";
        for (auto t : {unfinished, grow, fixed, pending_pool, a.Ref(index)}) {
            Predicate old, q; bool failed_old = false, failed_q = false;
            try { old.BaselineReaches(t, i); } catch (const IncompleteFixture &) { failed_old = true; }
            try { q.ReachesThroughRefs(t, i); } catch (const IncompleteFixture &) { failed_q = true; }
            assert(failed_old == failed_q && q.referenceclosures.entries.empty() && q.reachesthrough.size() == 0);
        }
        auto root = a.Struct({a.Ref(i)}); Predicate q; q.typesbuilding = 1;
        assert(q.ReachesThroughRefs(root, i) && q.referenceclosures.entries.empty());
        q.typesbuilding = 0; assert(q.ReachesThroughRefs(root, i) && q.referenceclosures.entries.size() == 1);
    });
    law("unknown target identity never seeds a closure", [] {
        Arena a; auto i = a.Int(); auto root = a.Struct({a.Ref(i)});
        auto pending = a.Ref(i); pending->ref->poolname = "missing";
        Predicate old, q; parity(old, q, root, pending);
        assert(q.referenceclosures.entries.empty() && q.reachesthrough.size() == 0);
    });
    law("failed traversal publishes no partial closure", [] {
        Arena a; auto i = a.Int(); auto bad = a.Struct(); auto root = a.Struct({a.Ref(i), bad});
        Predicate q; q.lazy = [&](TypeExpr *t) { if (t == bad) throw IncompleteFixture{}; };
        bool failed = false; try { q.ReachesThroughRefs(root, i); } catch (const IncompleteFixture &) { failed = true; }
        assert(failed && q.referenceclosures.entries.empty() && q.reachesthrough.size() == 0);
        q.lazy = {}; assert(q.ReachesThroughRefs(root, i) && q.referenceclosures.entries.size() == 1);
    });
    law("entry and retained-capacity caps always preserve answers", [] {
        Arena a; auto i = a.Int(), b = a.Type(TY_BOOL); auto x = a.Struct({a.Ref(i)}), y = a.Struct({a.Ref(b)});
        for (int mode = 0; mode < 2; ++mode) {
            Predicate old, q;
            if (mode == 0) q.referenceclosures.max_entries = 1;
            else q.referenceclosures.max_pointers = 0;
            for (auto t : {x, y}) for (auto of : {i, b}) parity(old, q, t, of);
            assert(q.referenceclosures.entries.size() <= q.referenceclosures.max_entries);
            assert(q.referenceclosures.pointers <= q.referenceclosures.max_pointers);
        }
    });
    law("fresh empty Boolean cache leaves prefilled append semantics untouched", [] {
        Arena a; auto i = a.Int(), b = a.Type(TY_BOOL); auto root = a.Struct({a.Ref(i)});
        Predicate q; assert(q.ReachesThroughRefs(root, i));
        vector<TypeExpr *> out{b}; q.ReachedThroughRefs(root, out);
        assert(out == vector<TypeExpr *>({b, i}));
        assert(q.referenceclosures.entries.at(root->struc->inst) == vector<TypeExpr *>({i}));
    });
    law("sampled trace uses bounded shallow nominal identity", [] {
        Arena a; auto t = a.Struct({a.Int()}); t->struc->st->qname = "probe::Engine";
        Predicate q; q.trace.enabled = true;
        CheckerTraceRoot root(q.trace, "probe", "trace-root");
        CheckerTraceBody body(q.trace, "trace-body", t);
        for (unsigned n = 0; n < (1U << 20); ++n) q.TraceEngine(CheckerEngine::TypeEq, t);
        assert(q.trace.calls[(size_t)CheckerEngine::TypeEq] == (1U << 20));
    });
    std::cout << "{\"laws\":" << passed << ",\"ordered_reference_closure_parity\":true}\n";
}
