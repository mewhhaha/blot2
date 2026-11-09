struct Arena {
    vector<unique_ptr<TypeExpr>> types;
    vector<unique_ptr<TypeDetail>> details;
    vector<unique_ptr<StructInst>> structs;
    vector<unique_ptr<EnumInst>> enums;
    vector<unique_ptr<SStruct>> struct_declarations;
    vector<unique_ptr<SEnum>> enum_declarations;
    template<class T> T *Detail() { auto p = make_unique<T>(); auto out = p.get(); details.push_back(std::move(p)); return out; }
    TypeExpr *Type(TypeKind k) { auto p = make_unique<TypeExpr>(k, Line{}); auto out = p.get(); types.push_back(std::move(p)); return out; }
    TypeExpr *Int(IntStorage storage = IS_I64) { auto t = Type(TY_INT); t->intstorage = storage; return t; }
    TypeExpr *Struct(vector<TypeExpr *> fields = {}, bool ready = true) {
        auto t = Type(TY_STRUCT); t->struc = Detail<TypeStruct>();
        auto declaration = make_unique<SStruct>(); t->struc->st = declaration.get();
        struct_declarations.push_back(std::move(declaration));
        auto i = make_unique<StructInst>(); i->validated = ready; i->ftypes = std::move(fields);
        t->struc->inst = i.get(); structs.push_back(std::move(i)); return t;
    }
    TypeExpr *Enum(vector<vector<TypeExpr *>> fields = {}, bool ready = true) {
        auto t = Type(TY_ENUM); t->enu = Detail<TypeEnum>();
        auto declaration = make_unique<SEnum>(); t->enu->en = declaration.get();
        enum_declarations.push_back(std::move(declaration));
        auto i = make_unique<EnumInst>(); i->validated = ready; i->vftypes = std::move(fields);
        t->enu->inst = i.get(); enums.push_back(std::move(i)); return t;
    }
    TypeExpr *Ref(TypeExpr *sub) { auto t = Type(TY_REF); t->ref = Detail<TypeRef>(); t->ref->sub = sub; return t; }
    TypeExpr *Slice(TypeExpr *sub) { auto t = Type(TY_SLICE); t->sub = sub; return t; }
    TypeExpr *Array(TypeExpr *sub, ArrayKind kind = A_FIXED, int size = 2) {
        auto t = Type(TY_ARRAY); t->arr = Detail<TypeArray>(); t->arr->sub = sub; t->arr->akind = kind; t->arr->size = size; return t;
    }
};

static bool IdentityEq(TypeExpr *a, TypeExpr *b) {
    if (a == b) return true;
    if (a->kind != b->kind || a->cq != b->cq) return false;
    auto args = [](const vector<TypeExpr *> &xs, const vector<TypeExpr *> &ys) {
        if (xs.size() != ys.size()) return false;
        for (size_t i=0;i<xs.size();i++) if (!IdentityEq(xs[i],ys[i])) return false;
        return true;
    };
    switch (a->kind) {
        case TY_INT: return a->intstorage == b->intstorage && a->ix == b->ix;
        case TY_BOOL: case TY_VOID: case TY_FN: return true;
        case TY_STRUCT: return a->struc == b->struc || (a->struc->inst == b->struc->inst && args(a->struc->args,b->struc->args));
        case TY_ENUM: return a->enu == b->enu || (a->enu->inst == b->enu->inst && a->enu->varmode == b->enu->varmode && args(a->enu->args,b->enu->args));
        case TY_ARRAY: return a->arr->akind == b->arr->akind && a->arr->size == b->arr->size && IdentityEq(a->arr->sub,b->arr->sub);
        case TY_SLICE: return IdentityEq(a->sub,b->sub);
        case TY_REF: return a->ref->optional == b->ref->optional && a->ref->lenstorage == b->ref->lenstorage && a->ref->pool == b->ref->pool && IdentityEq(a->ref->sub,b->ref->sub);
        case TY_VARIANT: return a->var->variant == b->var->variant && IdentityEq(a->var->adt,b->var->adt);
        default: return false;
    }
}
template<class Gate> struct QueryModel {
    StableTypeGraph full;
    Gate scoped;
    bool candidate;
    map<pair<TypeExpr *,TypeExpr *>, bool> answers;
    size_t walks = 0;
    explicit QueryModel(bool c):candidate(c){}
    bool Walk(TypeExpr *t, TypeExpr *of) {
        walks++;
        if (IdentityEq(t,of)) return true;
        // LoadedTypeEq's top-const and relative-reference transformations.
        TypeExpr loaded = *t; TypeRef ref;
        if (IsVarintT(t)) { loaded.intstorage=IS_I64; loaded.ix=nullptr; }
        else if (t->cq && !IsRefOrSlice(t)) loaded.cq=false;
        else if (IsRelRef(t)) {ref.sub=t->ref->sub;ref.optional=t->ref->optional;loaded.ref=&ref;}
        if (IdentityEq(&loaded,of)) return true;
        if (t->kind == TY_ARRAY) return Contains(t->arr->sub,of);
        if (t->kind == TY_STRUCT && t->struc->inst) {
            for(auto field:t->struc->inst->ftypes) if(field && Contains(field,of)) return true;
        }
        if (t->kind == TY_ENUM && t->enu->inst) {
            for(auto &fields:t->enu->inst->vftypes) for(auto field:fields) if(field && Contains(field,of)) return true;
        }
        return false;
    }
    bool Contains(TypeExpr *t, TypeExpr *of, bool building=false) {
        if (!t) return false;
        if (t->kind != TY_STRUCT && t->kind != TY_ENUM && t->kind != TY_VARIANT && t->kind != TY_ARRAY) return Walk(t,of);
        auto key=pair{t,of}; auto found=answers.find(key); if(found!=answers.end())return found->second;
        bool ready=false;
        if (!building) {
            if (candidate) ready=scoped.Ready(t) && scoped.Identity(of);
            else ready=full.Ready(t) && full.Ready(of);
        }
        auto answer=Walk(t,of); if(ready)answers[key]=answer; return answer;
    }
};

template<class Gate> void OriginalLaws() {
    using StableCanContainGraph = Gate;
    using Query = QueryModel<Gate>;
    law("null and primitive", []{StableCanContainGraph q;Arena a;assert(!q.Ready(nullptr));assert(q.Ready(a.Int()));});
    law("unvalidated nominal and lazy fields", []{StableCanContainGraph q;Arena a;auto s=a.Struct({},false);assert(!q.Ready(s));assert(q.known.empty());s->struc->inst->ftypes={a.Int()};s->struc->inst->validated=true;assert(q.Ready(s));});
    law("missing nominal instance", []{StableCanContainGraph q;Arena a;auto s=a.Struct();auto i=s->struc->inst;s->struc->inst=nullptr;assert(!q.Ready(s));s->struc->inst=i;assert(q.Ready(s));});
    law("failed nominal instance", []{StableCanContainGraph q;Arena a;auto s=a.Struct();s->struc->inst->failed=true;assert(!q.Ready(s));});
    law("generic identity and unfinished parameters", []{StableCanContainGraph q;Arena a;auto p=a.Type(TY_GENERIC);auto s=a.Struct();s->struc->args={p};s->struc->st->generics.resize(1);assert(!q.Identity(s));assert(q.identities.empty());p->kind=TY_INT;p->intstorage=IS_I64;assert(q.Identity(s));});
    law("function identity remains uncached", []{StableCanContainGraph q;Arena a;auto f=a.Type(TY_FN);assert(!q.Identity(f));assert(!q.Ready(a.Ref(f)));});
    law("fixed and expression array sizes", []{StableCanContainGraph q;Arena a;auto ar=a.Array(a.Int(),A_FIXED,-1);assert(!q.Ready(ar));ar->arr->size=0;assert(q.Ready(ar));auto cap=a.Array(a.Int(),A_LIMITED,-1);cap->arr->sizeexpr=reinterpret_cast<Node *>(cap);assert(!q.Ready(cap));cap->arr->size=3;assert(q.Ready(cap));});
    law("pending array element inference", []{StableCanContainGraph q;Arena a;auto ar=a.Array(a.Type(TY_VOID),A_GROW,0);assert(!q.Ready(ar));ar->arr->sub=a.Int();assert(q.Ready(ar));});
    law("unresolved relative pool identity", []{StableCanContainGraph q;Arena a;auto r=a.Ref(a.Int());r->ref->poolname="pool";assert(!q.Identity(r));VarDef owner{};r->ref->pool=&owner;assert(q.Identity(r));});
    law("unresolved index-array identity", []{StableCanContainGraph q;Arena a;auto t=a.Int(IS_U32);t->ix=a.Detail<TypeIndex>();assert(!q.Identity(t));VarDef owner{};t->ix->arr=&owner;assert(q.Identity(t));});
    law("reference and slice stop at nominal identity", []{StableCanContainGraph q;StableTypeGraph full;Arena a;auto referent=a.Struct({a.Type(TY_FN)});auto holder=a.Struct({a.Ref(referent),a.Slice(referent)});assert(!full.Ready(holder));assert(q.Ready(holder));assert(!q.Ready(referent));});
    law("enum payload closure and variant conservatism", []{StableCanContainGraph q;Arena a;auto pending=a.Type(TY_UNRESOLVED);auto e=a.Enum({{a.Int()},{pending}});auto v=a.Type(TY_VARIANT);v->var=a.Detail<TypeVariant>();v->var->adt=e;SVariant variant{};v->var->variant=&variant;assert(!q.Ready(e));assert(!q.Ready(v));pending->kind=TY_BOOL;assert(q.Ready(e));assert(q.Ready(v));});
    law("failed closure publishes no partial cycle", []{StableCanContainGraph q;Arena a;auto pending=a.Type(TY_UNRESOLVED);auto x=a.Struct();auto y=a.Struct({x,pending});x->struc->inst->ftypes={y};assert(!q.Ready(x));assert(q.known.empty());assert(!q.Ready(y));assert(q.known.empty());pending->kind=TY_BOOL;assert(q.Ready(x));});
    law("positive and negative cache parity", []{Arena a;auto i=a.Int();auto b=a.Type(TY_BOOL);auto s=a.Struct({i});Query old(false),q(true);for(int j=0;j<4;j++){assert(old.Contains(s,i)==q.Contains(s,i));assert(old.Contains(s,b)==q.Contains(s,b));}assert(q.answers.at({s,i}));assert(!q.answers.at({s,b}));});
    law("uncached negative before lazy completion", []{Arena a;auto i=a.Int();auto s=a.Struct({},false);Query q(true);assert(!q.Contains(s,i));assert(q.answers.count({s,i})==0);s->struc->inst->ftypes={i};s->struc->inst->validated=true;assert(q.Contains(s,i));assert(q.answers.at({s,i}));});
    law("type-building bypasses new cache", []{Arena a;auto i=a.Int();auto s=a.Struct({i});Query q(true);assert(q.Contains(s,i,true));assert(q.answers.count({s,i})==0);assert(q.Contains(s,i));assert(q.answers.at({s,i}));});
    law("const loaded value parity", []{Arena a;auto i=a.Int();auto ci=a.Int();ci->cq=true;auto s=a.Struct({ci});Query old(false),q(true);assert(old.Contains(s,i));assert(q.Contains(s,i));});
    law("referent field change cannot change by-value result", []{Arena a;auto i=a.Int();auto referent=a.Struct({a.Type(TY_FN)});auto r=a.Ref(referent);auto holder=a.Struct({r});Query q(true);assert(!q.Contains(holder,i));assert(q.Contains(holder,r));referent->struc->inst->ftypes.push_back(i);assert(!q.Contains(holder,i));assert(q.Contains(holder,r));});
    law("varint loaded identity parity", []{Arena a;auto plain=a.Int();auto packed=a.Int(IS_VARINT);auto s=a.Struct({packed});Query old(false),q(true);assert(old.Contains(s,plain));assert(q.Contains(s,plain));});
    law("relative reference loaded identity parity", []{Arena a;auto i=a.Int();auto absolute=a.Ref(i);auto relative=a.Ref(i);VarDef pool{};relative->ref->pool=&pool;relative->ref->poolname="pool";relative->ref->lenstorage=IS_U32;auto s=a.Struct({relative});Query old(false),q(true);assert(old.Contains(s,absolute));assert(q.Contains(s,absolute));});
    law("stable generic arguments retain distinct identities", []{Arena a;auto x=a.Struct();auto y=a.Struct();x->struc->args={a.Int()};y->struc->args={a.Type(TY_BOOL)};x->struc->st->generics.resize(1);y->struc->st->generics.resize(1);y->struc->inst=x->struc->inst;auto sx=a.Slice(x);auto sy=a.Slice(y);auto holder=a.Struct({sx});Query old(false),q(true);assert(!old.Contains(holder,sy));assert(!q.Contains(holder,sy));assert(q.Contains(holder,sx));});
}
