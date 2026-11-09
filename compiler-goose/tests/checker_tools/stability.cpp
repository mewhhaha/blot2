#include "probe-prefix.h"
struct Graph {
    Arena arena;
    vector<TypeExpr *> nodes, roots;
    TypeExpr *bad = nullptr;
    Graph(int size, int shape) {
        for (int i = 0; i < size; i++) nodes.push_back(arena.Struct());
        for (int i = 1; i < size; i++) {
            auto previous = nodes[i - 1];
            if (shape == 1) {
                nodes[i]->struc->args = { previous };
                nodes[i]->struc->st->generics.resize(1);
            } else {
                if (shape != 0) previous = arena.Ref(previous);
                nodes[i]->struc->inst->ftypes = { previous };
            }
        }
        if (shape == 3 || shape == 4) nodes[0]->struc->inst->ftypes.push_back(arena.Ref(nodes.back()));
        if (shape == 4 || shape == 5) {
            bad = arena.Type(TY_UNRESOLVED);
            nodes[0]->struc->inst->ftypes.push_back(bad);
        }
        roots.push_back(nodes.back());
        for (auto t : nodes) roots.push_back(t);
        roots.push_back(nodes.back());
    }
};
template<class Old, class New, class Call, class Cache> void compare(Graph &g, Call call, Cache cache) {
    Old old; New candidate;
    auto check = [&](TypeExpr *t) {
        auto before = cache(candidate);
        bool a = call(old, t), b = call(candidate, t);
        assert(a == b);
        if (!b) assert(before == cache(candidate));
        for (auto proved : cache(candidate)) {
            Old independent;
            if (g.nodes.size() > 64) {
                cache(independent) = cache(candidate);
                cache(independent).erase(proved);
            }
            assert(call(independent, proved));
        }
    };
    for (auto t : g.roots) check(t);
    if (g.bad) { g.bad->kind = TY_BOOL; for (auto t : g.roots) check(t); }
}
static void graph_laws() {
    for (int size : {1, 4, 16, 64, 256}) for (int shape = 0; shape < 6; shape++) {
        {
            Graph g(size, shape);
            compare<StableTypeGraph,CandidateStableTypeGraph>(g,
                [](auto &gate, TypeExpr *t) { return gate.Ready(t); },
                [](auto &gate) -> auto & { return gate.known; });
            passed++;
        }
        {
            Graph g(size, shape);
            compare<StableCanContainGraph,CandidateStableCanContainGraph>(g,
                [](auto &gate, TypeExpr *t) { return gate.Identity(t); },
                [](auto &gate) -> auto & { return gate.identities; });
            passed++;
        }
        {
            Graph g(size, shape);
            compare<StableCanContainGraph,CandidateStableCanContainGraph>(g,
                [](auto &gate, TypeExpr *t) { return gate.Ready(t); },
                [](auto &gate) -> auto & { return gate.known; });
            passed++;
        }
        {
            Graph g(size, shape);
            compare<StableReachesGraph,CandidateStableReachesGraph>(g,
                [](auto &gate, TypeExpr *t) {
                    if constexpr (std::is_same_v<std::remove_reference_t<decltype(gate)>, StableReachesGraph>) {
                        StableCanContainGraph identity; return gate.Ready(t, identity);
                    } else {
                        CandidateStableCanContainGraph identity; return gate.Ready(t, identity);
                    }
                },
                [](auto &gate) -> auto & { return gate.known; });
            passed++;
        }
    }
}
static void failure_laws() {
    law("full ancestor later failure publishes nothing", [] {
        Arena a; auto bad=a.Type(TY_UNRESOLVED); auto x=a.Struct(); auto y=a.Struct();
        x->struc->inst->ftypes={a.Ref(y),bad}; y->struc->inst->ftypes={a.Ref(x)};
        CandidateStableTypeGraph gate; assert(!gate.Ready(x)); assert(gate.known.empty());
        assert(!gate.Ready(y)); assert(gate.known.empty()); bad->kind=TY_BOOL;
        assert(gate.Ready(x) && gate.known.count(y) && gate.known.count(bad));
    });
    law("identity ancestor later failure publishes nothing", [] {
        Arena a; auto bad=a.Type(TY_UNRESOLVED); auto x=a.Struct(); auto y=a.Struct();
        x->struc->args={y,bad};x->struc->st->generics.resize(2);
        y->struc->args={x};y->struc->st->generics.resize(1);
        CandidateStableCanContainGraph gate; assert(!gate.Identity(x)); assert(gate.identities.empty());
        assert(!gate.Identity(y)); assert(gate.identities.empty()); bad->kind=TY_BOOL;
        assert(gate.Identity(x) && gate.identities.count(y) && gate.identities.count(bad));
    });
    law("containment ancestor later failure only publishes separate identity facts", [] {
        Arena a; auto bad=a.Type(TY_UNRESOLVED); auto x=a.Struct(); auto y=a.Struct();
        x->struc->inst->ftypes={y,bad};y->struc->inst->ftypes={x};
        CandidateStableCanContainGraph gate; assert(!gate.Ready(x));assert(gate.known.empty());
        assert(gate.identities.count(x) && gate.identities.count(y) && !gate.identities.count(bad));
        assert(!gate.Ready(y));assert(gate.known.empty());bad->kind=TY_BOOL;
        assert(gate.Ready(x) && gate.known.count(y) && gate.known.count(bad));
    });
    law("reference ancestor later failure publishes no reach proof", [] {
        Arena a;auto bad=a.Type(TY_UNRESOLVED);auto x=a.Struct();auto y=a.Struct();
        x->struc->inst->ftypes={a.Ref(y),bad};y->struc->inst->ftypes={a.Ref(x)};
        CandidateStableCanContainGraph identity;CandidateStableReachesGraph gate;
        assert(!gate.Ready(x,identity));assert(gate.known.empty());assert(identity.identities.count(y));
        assert(!gate.Ready(y,identity));assert(gate.known.empty());bad->kind=TY_BOOL;
        assert(gate.Ready(x,identity) && gate.known.count(y) && gate.known.count(bad));
    });
}
template<class Gate> static double time_graph(Graph &g, int repeats, int reuse) {
    auto start=chrono::steady_clock::now();
    for(int n=0;n<repeats;n++) {
        Gate q;
        assert(q.Ready(g.nodes.back()));
        if(reuse == 1)for(auto t:g.roots)assert(q.Ready(t));
        if(reuse == 2)for(auto it=g.nodes.rbegin();it!=g.nodes.rend();it++)assert(q.Ready(*it));
    }
    return chrono::duration<double,milli>(chrono::steady_clock::now()-start).count();
}
int main(int argc, char **) {
    if (argc > 1) {
        Arena a; auto t=a.Int(); CandidateStableTypeGraph q;
        assert(!q.Ready(nullptr)); assert(q.Ready(t));
        for (unsigned i=0;i<(1u<<20);i++) assert(q.Ready(t));
        assert(q.profile.enabled && q.profile.hits==(1u<<20) && q.profile.misses==2 && q.profile.rejected==1);
        puts("periodic counters exact"); return 0;
    }
    OriginalLaws<StableCanContainGraph>();OriginalLaws<CandidateStableCanContainGraph>();
    failure_laws();graph_laws();
    printf("{\"laws\":%d,\"gates\":4,\"fresh_member_audit_through\":64,\"large_member_local_discharge\":256}\n",passed);
    for(int size:{16,64,256})for(int shape:{0,1,2,3}) {
        Graph g(size,shape);
        for(int reuse:{0,1,2})for(int trial=0;trial<3;trial++) {
            int repeats=std::max(2,4096/size);
            double old,newtime;
            if(trial&1){newtime=time_graph<CandidateStableTypeGraph>(g,repeats,reuse);old=time_graph<StableTypeGraph>(g,repeats,reuse);}
            else{old=time_graph<StableTypeGraph>(g,repeats,reuse);newtime=time_graph<CandidateStableTypeGraph>(g,repeats,reuse);}
            printf("{\"size\":%d,\"shape\":%d,\"reuse\":%d,\"trial\":%d,\"repeats\":%d,\"baseline_ms\":%.6f,\"candidate_ms\":%.6f}\n",size,shape,reuse,trial,repeats,old,newtime);
        }
    }
}
