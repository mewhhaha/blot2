#include "array-prefix.h"
struct IncompleteFixture {};
struct Predicate {
    Ast ast;
    StableTypeGraph stabletypes;
    StableCanContainGraph stablecontainment;
    StableReachesGraph stablereaches;
    using TypePairCache = flat_map<pair<TypeExpr *,TypeExpr *>,bool>;
    TypePairCache cancontain, reachesthrough;
    int typesbuilding = 0;
    StableQueryProfile arrayprofile { "array.elements" };
    ArrayGateProfile arraygateprofile;
    uint64_t size_reads = 0;
    vector<TypeExpr *> field_reads;
    Predicate() {
        ast.inttypes[IS_I64] = ast.NewType(TY_INT, Line{});
        ast.inttypes[IS_I64]->intstorage = IS_I64;
    }
    uint64_t reach_walks = 0;
    function<void(TypeExpr *)> lazy;
    int64_t ArraySize(TypeArray *a) {
        ++size_reads;
        if (a->size < 0 && a->sizeexpr) throw IncompleteFixture{};
        return a->size;
    }
    template<class F> bool AnyField(TypeExpr *t, F f) {
        auto fields = [&](const vector<TypeExpr *> &types) {
            for (auto type : types) if (type && f(type)) return true;
            return false;
        };
        field_reads.push_back(t);
        auto nominal = t;
        if (t->kind == TY_VARIANT) nominal=t->var->adt;
        if (lazy) lazy(nominal);
        if (nominal->kind == TY_STRUCT) {
            auto i=nominal->struc->inst;
            if (!i || !i->validated || i->failed) throw IncompleteFixture{};
            return fields(i->ftypes);
        }
        if (nominal->kind == TY_ENUM) {
            auto i=nominal->enu->inst;
            if (!i || !i->validated || i->failed) throw IncompleteFixture{};
            if (t->kind == TY_VARIANT) return fields(i->vftypes.at(i->en->VariantIndex(t->var->variant)));
            for (auto &types:i->vftypes) if(fields(types)) return true;
        }
        return false;
    }
    template<class F> void EachField(TypeExpr *t,F f) {
        AnyField(t,[&](TypeExpr *ft){f(ft);return false;});
    }
    unordered_map<const void *,vector<TypeExpr *>> arrayelements;
    uint64_t array_walks=0;
#include "array-methods.h"
};

static void args(TypeExpr*t,vector<TypeExpr*>as){t->struc->args=as;t->struc->st->generics.resize(as.size());}
int main(){
 law("unused uninstantiated generic nominal argument, ordered and merged exact lists",[]{
  Arena a;auto i=a.Int();auto b=a.Type(TY_BOOL);auto leaf=a.Struct({i});auto arg=a.Struct({leaf});args(arg,{leaf});arg->struc->inst=nullptr;
  auto root=a.Struct({a.Array(i),a.Array(b),a.Array(i)});args(root,{arg});Predicate old,q;
  assert(!old.stabletypes.Ready(root));assert(q.stablereaches.Ready(root,q.stablecontainment));
  assert(old.field_reads.empty() && q.field_reads.empty() && !old.size_reads && !q.size_reads);
  q.arraygateprofile.enabled=true;
  for(int n=0;n<3;n++){vector<TypeExpr*>x,y;old.BaselineAppend(root,x);q.AppendArrayElemsReached(root,y);assert(old.TypeArgsEq(x,y));assert(x==vector<TypeExpr*>({i,b}));}
  assert(old.arrayelements.empty());assert(q.arrayelements.size()==1);assert(!arg->struc->inst);
  assert(find(old.field_reads.begin(),old.field_reads.end(),arg)==old.field_reads.end());
  assert(find(q.field_reads.begin(),q.field_reads.end(),arg)==q.field_reads.end());
  assert(q.arraygateprofile.checked==3 && q.arraygateprofile.full_rejected==3 && q.arraygateprofile.reach_accepted==3);

  vector<TypeExpr*>x{b},y{b};old.BaselineAppend(root,x);q.AppendArrayElemsReached(root,y);assert(old.TypeArgsEq(x,y));assert(x==vector<TypeExpr*>({b,i}));
  auto used=a.Struct({arg});Predicate blocked;assert(!blocked.stablereaches.Ready(used,blocked.stablecontainment));assert(blocked.stablereaches.known.empty());
 });
 law("unfinished actual instances and strict function generic pool array negatives",[]{
  Arena a;for(auto t:{a.Struct({},false),a.Enum({},false),a.Type(TY_FN),a.Type(TY_GENERIC),a.Array(a.Type(TY_VOID),A_GROW,0),a.Array(a.Int(),A_FIXED,-1)}){Predicate q;assert(!q.stablereaches.Ready(t,q.stablecontainment));assert(q.stablereaches.known.empty());}
  auto r=a.Ref(a.Int());r->ref->poolname="pool";Predicate q;assert(!q.stablereaches.Ready(r,q.stablecontainment));VarDef pool{};r->ref->pool=&pool;assert(q.stablereaches.Ready(r,q.stablecontainment));
  auto cap=a.Array(a.Int(),A_LIMITED,-1);cap->arr->sizeexpr=reinterpret_cast<Node*>(cap);Predicate p;assert(!p.stablereaches.Ready(cap,p.stablecontainment));cap->arr->size=3;assert(p.stablereaches.Ready(cap,p.stablecontainment));
 });
 law("failed struct enum and cycle publish no partial readiness",[]{
  Arena a;for(auto t:{a.Struct(),a.Enum()}){if(t->kind==TY_STRUCT)t->struc->inst->failed=true;else t->enu->inst->failed=true;Predicate q;assert(!q.stablereaches.Ready(t,q.stablecontainment));}
  auto pending=a.Type(TY_UNRESOLVED);auto x=a.Struct();auto y=a.Struct({x,pending});x->struc->inst->ftypes={y};Predicate q;assert(!q.stablereaches.Ready(x,q.stablecontainment));assert(q.stablereaches.known.empty());assert(!q.stablereaches.Ready(y,q.stablecontainment));pending->kind=TY_BOOL;assert(q.stablereaches.Ready(x,q.stablecontainment));
 });
 law("building guard and lazy actual field completion retain uncached first walk",[]{
  Arena a;auto root=a.Struct({a.Array(a.Int())});Predicate q;q.typesbuilding=1;vector<TypeExpr*>out;q.AppendArrayElemsReached(root,out);assert(q.arrayelements.empty());q.typesbuilding=0;q.AppendArrayElemsReached(root,out);assert(q.arrayelements.size()==1);
  auto missing=a.Struct({a.Array(a.Type(TY_BOOL))});auto inst=missing->struc->inst;missing->struc->inst=nullptr;Predicate p;p.lazy=[&](TypeExpr*t){if(t==missing)t->struc->inst=inst;};out.clear();p.AppendArrayElemsReached(missing,out);assert(p.arrayelements.empty());out.clear();p.AppendArrayElemsReached(missing,out);assert(p.arrayelements.size()==1);
 });
 law("references slices const and distinct nominal arguments preserve order",[]{
  Arena a;auto i=a.Int();auto ci=a.Int();ci->cq=true;auto x=a.Struct({a.Array(i)});args(x,{i});auto y=a.Struct({a.Array(ci)});args(y,{ci});y->struc->st=x->struc->st;
  auto root=a.Struct({a.Ref(x),a.Slice(y),a.Array(i)});Predicate old,q;for(int n=0;n<3;n++){vector<TypeExpr*>u,v;old.BaselineAppend(root,u);q.AppendArrayElemsReached(root,v);assert(old.TypeArgsEq(u,v));assert(u==vector<TypeExpr*>({i,ci}));}
 });
 law("pending array identity preserves the original first size failure",[]{
  Arena a;auto i=a.Int();auto pending=a.Array(i,A_FIXED,-1);pending->arr->sizeexpr=reinterpret_cast<Node *>(pending);
  auto first=a.Struct();auto second=a.Struct();args(first,{pending});args(second,{a.Array(i,A_FIXED,2)});second->struc->st=first->struc->st;
  auto root=a.Struct({first,second});Predicate old,q;
  assert(!old.stabletypes.Ready(root));assert(!q.stablereaches.Ready(root,q.stablecontainment));
  assert(old.size_reads==0 && q.size_reads==0 && old.field_reads.empty() && q.field_reads.empty());
  vector<TypeExpr*>x,y;bool badold=false,badnew=false;
  try{old.BaselineAppend(root,x);}catch(const IncompleteFixture &){badold=true;}
  try{q.AppendArrayElemsReached(root,y);}catch(const IncompleteFixture &){badnew=true;}
  assert(badold && badnew && old.arrayelements.empty() && q.arrayelements.empty());
  assert(old.size_reads==1 && q.size_reads==1 && old.field_reads==q.field_reads);
 });
 law("LoadType normalization keeps proven referents and primitive order",[]{
  Arena a;auto i=a.Int();auto ci=a.Int();ci->cq=true;auto packed=a.Int(IS_VARINT);auto target=a.Struct({a.Array(i),a.Array(ci),a.Array(packed)});
  auto relative=a.Ref(target);relative->ref->poolname="pool";VarDef pool{};relative->ref->pool=&pool;relative->ref->lenstorage=IS_U32;
  auto root=a.Struct({a.Ref(relative),a.Slice(target),a.Ref(packed),a.Ref(ci)});Predicate old,q;vector<TypeExpr*>x,y;
  old.BaselineAppend(root,x);q.AppendArrayElemsReached(root,y);assert(old.TypeArgsEq(x,y));
  assert(x==vector<TypeExpr*>({i,ci,packed}));
 });
 std::cout<<"{\"laws\":"<<passed<<",\"exact_array_query_parity\":true}"<<'\n';
}
