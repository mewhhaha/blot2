
#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <functional>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>
using namespace std;
struct TypeExpr;struct StructInst;struct EnumInst;
struct SStruct{int id;};struct SEnum{int id;};struct SVariant{int id;};
struct VarDef{int id;};struct Node{int id;int64_t value;};
struct Line {
    int line = 0;
    int fileidx = 0;
    int col = 0;
};
enum TypeKind {
    TY_INT,         // A sized integer type; intstorage picks the width (§3.1, §3.6).
    TY_FLT,         // A sized float type; fltstorage picks f32/f64.
    TY_BOOL,
    TY_STRUCT,      // A nominal struct, with any generic type arguments.
    TY_ENUM,        // A nominal ADT; fixed-mode use, or variable-mode T.. (varmode flag, §3.5).
    TY_GENERIC,     // A generic type parameter name (typecheck validates scope).
    TY_UNRESOLVED,  // Parse-time only: a name + args; none survive resolution.
    TY_FN,          // Static function value type; bare `fn` has has_sig false.
    TY_ARRAY,       // The array family minus slices; akind picks the flavor.
    TY_SLICE,       // T[:] — a reference + count; kin of TY_REF, not TY_ARRAY.
    TY_REF,         // T& / T&<w> / T&<w in pool> (relative offset) / optional T?.
    TY_VARIANT,     // T.Name — variant type of an ADT.
    TY_VOID,        // Typecheck-created: the "type" of statements and valueless blocks.
};
enum ArrayKind {
    A_FIXED,       // T[k]           sizeexpr = k, a constant expression
    A_VAR,         // T[] / T[u8]    lenstorage = length field storage, -1 = default
    A_LIMITED,     // T[..k] / T[..] sizeexpr = capacity, null = construction-time
    A_GROW,        // T[>..]
    A_GROWSHRINK,  // T[>..<]
};
enum IntStorage { IS_I8, IS_I16, IS_I32, IS_I64, IS_U8, IS_U16, IS_U32, IS_U64, IS_VARINT };
enum FltStorage { FS_F32, FS_F64 };
struct TypeDetail { virtual ~TypeDetail() {} };
struct TypeStruct : TypeDetail {     // TY_STRUCT
    SStruct *st = nullptr;
    vector<TypeExpr *> args;         // Generic type arguments, possibly empty.
    StructInst *inst = nullptr;      // Instantiation cache (typecheck; concrete args only).
};
struct TypeEnum : TypeDetail {       // TY_ENUM
    SEnum *en = nullptr;
    vector<TypeExpr *> args;
    bool varmode = false;            // T.. — variable-mode use (§3.5).
    EnumInst *inst = nullptr;        // Instantiation cache (typecheck; concrete args only).
};
struct TypeName : TypeDetail {       // TY_UNRESOLVED and TY_GENERIC
    int expansionbinding = 0;       // Lexical const-for binding, never a name lookup.
    string_view expansionerror;     // Invalid substitution, diagnosed only when instantiated.
    string_view name;                // As written: `Name`, `ns::Name` or `::Name`.
    string_view ns;                  // Where an unqualified name resolves first: the
                                     // namespace of the declaration it was written in
                                     // (docs/design/namespaces.md).
    vector<TypeExpr *> args;         // Args on a TY_GENERIC are an error (typecheck).
    bool varmode = false;            // T.. as written; resolution moves it to TypeEnum.
    // A TY_GENERIC an exemplar binds a type parameter to (TypeCheck::
    // CheckExemplar): a concrete type equal only to itself, by this detail,
    // which its `const` copies share.
    bool opaque = false;
};
struct TypeFn : TypeDetail {         // TY_FN
    vector<TypeExpr *> args;         // Parameter types.
    vector<TypeExpr *> rets;
    bool has_sig = false;            // Bare `fn` vs full signature.
};
struct TypeArray : TypeDetail {      // TY_ARRAY
    TypeExpr *sub = nullptr;         // Element type.
    ArrayKind akind = A_FIXED;
    Node *sizeexpr = nullptr;        // A_FIXED size / A_LIMITED capacity (const expr; null for `[..]`).
    int lenstorage = -1;             // A_VAR length field IntStorage; -1 = default (u32).
    int64_t size = -1;               // Evaluated sizeexpr (typecheck); -1 = not yet / none.
};
struct TypeRef : TypeDetail {        // TY_REF
    TypeExpr *sub = nullptr;         // Pointee.
    int lenstorage = -1;             // Relative offset IntStorage; -1 = plain address.
    bool optional = false;           // T? — nullable (`T&?` and `T?` are the same type).
    // `T&<u32 in pool>`: the offset is measured from the named global pool's
    // base instead of from the field itself (§3.9). The name is what the
    // parser saw; typecheck resolves it once, and the pool is part of the
    // type's identity from then on.
    string_view poolname;
    string_view poolns;              // The namespace poolname resolves in (as TypeName::ns).
    VarDef *pool = nullptr;
};
struct TypeVariant : TypeDetail {    // TY_VARIANT
    TypeExpr *adt = nullptr;         // The ADT type this is a variant of.
    string_view name;                // Stable through resolution and substitution.
    SVariant *variant = nullptr;     // Resolved declaration; null until its ADT is known.
};
struct TypeIndex : TypeDetail {
    string_view name;
    string_view ns;                  // The namespace name resolves in (as TypeName::ns).
    VarDef *arr = nullptr;
    bool upto = false;
};
struct TypeExpr {
    TypeKind kind;
    Line line;
    // `const T` (§9.5): a value whose contents are read-only, or, on a
    // reference or slice, one whose pointee or elements are. Part of the
    // type's identity (TypeEq); a C type does not carry it.
    bool cq = false;
    // A use of a type alias (resolve.h): a copy of the alias's type, whose
    // sizes name what they name where the alias is declared, at top level,
    // whatever scope the use is in (TypeCheck::ConstNamesIn).
    bool aliasuse = false;
    // On a TY_INT: an index or bound type (TypeIndex). Outside the union,
    // since intstorage is the member a TY_INT uses.
    TypeIndex *ix = nullptr;
    union {                          // Active member selected by kind:
        IntStorage intstorage;       //   TY_INT
        FltStorage fltstorage;       //   TY_FLT
        TypeExpr *sub;               //   TY_SLICE (element type)
        TypeStruct *struc;           //   TY_STRUCT
        TypeEnum *enu;               //   TY_ENUM
        TypeName *named;             //   TY_UNRESOLVED, TY_GENERIC
        TypeFn *fn;                  //   TY_FN
        TypeArray *arr;              //   TY_ARRAY
        TypeRef *ref;                //   TY_REF
        TypeVariant *var;            //   TY_VARIANT
    };                               // (TY_BOOL uses none.)

    TypeExpr(TypeKind _kind, Line _line) : kind(_kind), line(_line) { named = nullptr; }
    // Stops descending once s reaches `limit`: text past it is unspecified,
    // and the caller cuts s back to the limit.
    void Dump(string &s, size_t limit = string::npos) const;
};
inline bool IsRefOrSlice(const TypeExpr *t) { return t->kind == TY_REF || t->kind == TY_SLICE; }
inline bool IsRelRef(const TypeExpr *t) { return t->kind == TY_REF && t->ref->lenstorage >= 0; }

struct StructInst{bool validated=false,failed=false;};struct EnumInst{bool validated=false,failed=false;};
struct Ast {
 vector<unique_ptr<TypeExpr>> all;
 vector<unique_ptr<TypeDetail>> details;
 array<TypeExpr*,IS_VARINT+1> inttypes{};
 TypeExpr *NewType(TypeKind k,Line l={}){auto p=make_unique<TypeExpr>(k,l);auto v=p.get();all.push_back(move(p));return v;}
 template<class T>T *NewDetail(){auto p=make_unique<T>();auto v=p.get();details.push_back(move(p));return v;}
 int Id(TypeExpr *p)const{for(size_t i=0;i<all.size();i++)if(all[i].get()==p)return int(i);return -1;}
    TypeExpr *ConstOf(TypeExpr *t) {
        if (t->cq) return t;
        auto n = NewType(t->kind, t->line);
        *n = *t;
        n->cq = true;
        return n;
    }
    TypeExpr *PlainOf(TypeExpr *t) {
        if (!t->cq || t->kind == TY_REF || t->kind == TY_SLICE) return t;
        auto n = NewType(t->kind, t->line);
        *n = *t;
        n->cq = false;
        return n;
    }
    TypeExpr *RefTo(TypeExpr *sub, Line line, bool optional = false) {
        auto t = NewType(TY_REF, line);
        t->ref = NewDetail<TypeRef>();
        t->ref->sub = sub;
        t->ref->optional = optional;
        return t;
    }

 Ast(){for(int i=0;i<=IS_VARINT;i++){inttypes[i]=NewType(TY_INT);inttypes[i]->intstorage=IntStorage(i);}}
};
struct Engine {
 Ast ast;
 vector<unique_ptr<SStruct>> structs;vector<unique_ptr<SEnum>> enums;vector<unique_ptr<SVariant>> variants;
 vector<unique_ptr<Node>> nodes;vector<unique_ptr<StructInst>> si;vector<unique_ptr<EnumInst>> ei;
 unordered_map<const TypeDetail*,vector<TypeExpr*>> fields;
 unordered_map<const TypeDetail*,int> lazy_errors;
 function<void(TypeExpr*)> mutate;
 vector<string> trace;
 uint64_t eq_calls=0,visits=0,size_calls=0;
 bool record=true;
 void log(string x){if(record)trace.push_back(move(x));}
 TypeExpr *num(){return ast.inttypes[IS_U32];}
 SStruct *decl(){auto p=make_unique<SStruct>();p->id=int(structs.size());auto d=p.get();structs.push_back(move(p));return d;}
 TypeExpr *str(SStruct*d,vector<TypeExpr*>args={}){auto t=ast.NewType(TY_STRUCT);t->struc=ast.NewDetail<TypeStruct>();t->struc->st=d;t->struc->args=move(args);return t;}
 TypeExpr *enm(SEnum*d,bool mode,vector<TypeExpr*>args={}){auto t=ast.NewType(TY_ENUM);t->enu=ast.NewDetail<TypeEnum>();t->enu->en=d;t->enu->args=move(args);t->enu->varmode=mode;return t;}
 TypeExpr *arrayof(TypeExpr*x,ArrayKind k,int64_t n=-1,bool pending=false){auto t=ast.NewType(TY_ARRAY);t->arr=ast.NewDetail<TypeArray>();t->arr->sub=x;t->arr->akind=k;t->arr->size=n;if(pending){auto p=make_unique<Node>();p->id=int(nodes.size());p->value=n;t->arr->size=-1;t->arr->sizeexpr=p.get();nodes.push_back(move(p));}return t;}
 TypeExpr *slice(TypeExpr*x){auto t=ast.NewType(TY_SLICE);t->sub=x;return t;}
 TypeExpr *generic(string_view name,bool opaque){auto t=ast.NewType(TY_GENERIC);t->named=ast.NewDetail<TypeName>();t->named->name=name;t->named->opaque=opaque;return t;}
 int64_t ArraySize(TypeArray *a){size_calls++;log("size:"+to_string(a->sizeexpr?a->sizeexpr->id:-1)+":"+to_string(a->size));if(a->size<0&&a->sizeexpr){if(a->sizeexpr->value<0)throw runtime_error("bad-size:"+to_string(a->sizeexpr->id));a->size=a->sizeexpr->value;}return a->size;}
 template<class F>void EachField(TypeExpr*t,F f){
  log("fields:"+to_string(ast.Id(t)));if(mutate)mutate(t);
  const TypeDetail *d=nullptr;
  if(t->kind==TY_STRUCT){d=t->struc;if(!t->struc->inst){log("build-struct:"+to_string(t->struc->st->id));auto x=make_unique<StructInst>();t->struc->inst=x.get();si.push_back(move(x));}if(lazy_errors[d])throw runtime_error("lazy:"+to_string(lazy_errors[d]));t->struc->inst->validated=true;}
  else if(t->kind==TY_ENUM){d=t->enu;if(!t->enu->inst){log("build-enum:"+to_string(t->enu->en->id));auto x=make_unique<EnumInst>();t->enu->inst=x.get();ei.push_back(move(x));}if(lazy_errors[d])throw runtime_error("lazy:"+to_string(lazy_errors[d]));t->enu->inst->validated=true;}
  else if(t->kind==TY_VARIANT){d=t->var;}
  if(d)for(auto x:fields[d])f(x);
 }
    static bool SameIndex(const TypeExpr *a, const TypeExpr *b) {
        if (!a->ix || !b->ix) return !a->ix && !b->ix;
        return a->ix->arr == b->ix->arr && a->ix->upto == b->ix->upto;
    }
    bool TypeEq(TypeExpr *a, TypeExpr *b) {
        eq_calls++;
        if (record && a->kind == b->kind) {
            bool same_bucket = true;
            if (a->kind == TY_STRUCT) same_bucket = a->struc->st == b->struc->st;
            if (a->kind == TY_ENUM) same_bucket = a->enu->en == b->enu->en;
            if (same_bucket) log("eq:" + to_string(ast.Id(a)) + ":" + to_string(ast.Id(b)));
        }
        if (a == b) return true;
        if (a->kind != b->kind || a->cq != b->cq) return false;
        switch (a->kind) {
            case TY_INT:  return a->intstorage == b->intstorage && SameIndex(a, b);
            case TY_FLT:  return a->fltstorage == b->fltstorage;
            case TY_BOOL: case TY_VOID: case TY_FN: return true;
            case TY_STRUCT: {
                if (a->struc->st != b->struc->st) return false;
                return TypeArgsEq(a->struc->args, b->struc->args);
            }
            case TY_ENUM: {
                if (a->enu->en != b->enu->en || a->enu->varmode != b->enu->varmode) return false;
                return TypeArgsEq(a->enu->args, b->enu->args);
            }
            case TY_ARRAY: {
                auto &x = *a->arr, &y = *b->arr;
                if (x.akind != y.akind || !TypeEq(x.sub, y.sub)) return false;
                switch (x.akind) {
                    case A_FIXED:   return ArraySize(a->arr) == ArraySize(b->arr);
                    case A_VAR: {
                        auto ls = [](int s) { return s < 0 ? IS_U32 : (IntStorage)s; };
                        return ls(x.lenstorage) == ls(y.lenstorage);
                    }
                    case A_LIMITED: {
                        auto xs = x.sizeexpr ? ArraySize(a->arr) : -1;
                        auto ys = y.sizeexpr ? ArraySize(b->arr) : -1;
                        return xs == ys;
                    }
                    default: return true;
                }
            }
            case TY_SLICE: return TypeEq(a->sub, b->sub);
            case TY_REF:
                // The pool is part of a relative reference's identity: offsets
                // measured from different bases are different encodings (§3.9).
                return TypeEq(a->ref->sub, b->ref->sub) && a->ref->optional == b->ref->optional &&
                       a->ref->lenstorage == b->ref->lenstorage && a->ref->pool == b->ref->pool;
            case TY_VARIANT:
                return a->var->variant == b->var->variant && TypeEq(a->var->adt, b->var->adt);
            case TY_GENERIC:
                if (a->named->opaque || b->named->opaque) return a->named == b->named;
                return a->named->name == b->named->name;
            default: assert(false); return false;
        }
    }
    bool TypeArgsEq(vector<TypeExpr *> &a, vector<TypeExpr *> &b) {
        if (a.size() != b.size()) return false;
        for (size_t i = 0; i < a.size(); i++) if (!TypeEq(a[i], b[i])) return false;
        return true;
    }
TypeExpr *LoadType(TypeExpr *t) {
    if (t->kind == TY_INT && t->intstorage == IS_VARINT) return ast.inttypes[IS_I64];
    // A const value loads as a copy, which is plain; a const reference or
    // slice loads as itself, its qualifier being about the pointee.
    if (t->cq && !IsRefOrSlice(t)) return ast.PlainOf(t);
    if (IsRelRef(t)) {
        auto r = ast.RefTo(t->ref->sub, t->line, t->ref->optional);
        r->cq = t->cq;
        return r;
    }
    return t;
}
    struct ArrayReachVisited {
        array<vector<TypeExpr *>, TY_VOID + 1> kinds;
        unordered_map<const void *, vector<TypeExpr *>> nominals;

        vector<TypeExpr *> &Bucket(TypeExpr *t) {
            if (t->kind == TY_STRUCT) return nominals[t->struc->st];
            if (t->kind == TY_ENUM) return nominals[t->enu->en];
            return kinds[(size_t)t->kind];
        }
    };
void walk_old(TypeExpr *t, vector<TypeExpr *> &out,
                                         vector<TypeExpr *> &open) {
        visits++;
    for (auto o : open)
        if (TypeEq(o, t)) return;
    open.push_back(t);
    if (t->kind == TY_REF) {
        walk_old(LoadType(t->ref->sub), out, open);
    } else if (t->kind == TY_SLICE) {
        walk_old(t->sub, out, open);
    } else if (t->kind == TY_ARRAY) {
        auto seen = false;
        for (auto e : out) seen = seen || TypeEq(e, t->arr->sub);
        if (!seen) out.push_back(t->arr->sub);
        walk_old(t->arr->sub, out, open);
    } else {
        EachField(t, [&](TypeExpr *ft) { walk_old(ft, out, open); });
    }
}
void walk_new(TypeExpr *t, vector<TypeExpr *> &out,
                                         ArrayReachVisited &open) {
        visits++;
    auto &bucket = open.Bucket(t);
    for (auto o : bucket)
        if (TypeEq(o, t)) return;
    bucket.push_back(t);
    if (t->kind == TY_REF) {
        walk_new(LoadType(t->ref->sub), out, open);
    } else if (t->kind == TY_SLICE) {
        walk_new(t->sub, out, open);
    } else if (t->kind == TY_ARRAY) {
        auto seen = false;
        for (auto e : out) seen = seen || TypeEq(e, t->arr->sub);
        if (!seen) out.push_back(t->arr->sub);
        walk_new(t->arr->sub, out, open);
    } else {
        EachField(t, [&](TypeExpr *ft) { walk_new(ft, out, open); });
    }
}

 string run(TypeExpr*root,bool candidate){
  vector<TypeExpr*>out;string error;
  try{if(candidate){ArrayReachVisited seen;walk_new(root,out,seen);}else{vector<TypeExpr*>seen;walk_old(root,out,seen);}}
  catch(const runtime_error&e){error=e.what();}
  ostringstream o;o<<error<<'|';for(auto t:out)o<<ast.Id(t)<<',';o<<'|';for(auto &x:trace)o<<x<<';';
  for(auto &t:ast.all){o<<int(t->kind)<<':'<<t->cq;if(t->kind==TY_ARRAY)o<<':'<<t->arr->size<<':'<<ast.Id(t->arr->sub);if(t->kind==TY_ENUM)o<<':'<<t->enu->varmode;o<<',';}
  return o.str();
 }
 TypeExpr *graph(unsigned seed,int width=24,int repeats=3,bool homogeneous=false){
  auto root=str(decl());vector<TypeExpr*>children;
  if(homogeneous){for(int i=0;i<width;i++)children.push_back(arrayof(num(),A_FIXED,i+1));}
  else{
   for(int i=0;i<width;i++){
    auto t=str(decl(),{num()});fields[t->struc]={arrayof(num(),A_VAR)};children.push_back(t);
    if(i%4==0)children.push_back(ast.RefTo(ast.ConstOf(t),{}));
   }
  }
  auto initial=children;for(int j=1;j<repeats;j++)children.insert(children.end(),initial.begin(),initial.end());fields[root->struc]=children;
  if(width<100){
   auto d=decl();auto a=str(d,{num()});auto b=str(d,{ast.inttypes[IS_I64]});auto c=ast.ConstOf(a);
   fields[a->struc]={ast.RefTo(b,{})};fields[b->struc]={ast.RefTo(a,{}),arrayof(ast.inttypes[IS_U8],A_GROW)};
   fields[root->struc].insert(fields[root->struc].end(),{a,b,c,a});
   auto e=make_unique<SEnum>();e->id=int(enums.size());auto de=e.get();enums.push_back(move(e));
   auto fixed=enm(de,false,{num()});auto variable=enm(de,true,{num()});fields[fixed->enu]={arrayof(num(),A_FIXED,2)};fields[variable->enu]={arrayof(num(),A_FIXED,3)};
   fields[root->struc].insert(fields[root->struc].end(),{fixed,variable,fixed});
   auto u=generic("T",false);auto v=generic("T",false);auto op=generic("T",true);fields[root->struc].insert(fields[root->struc].end(),{u,v,op,ast.ConstOf(op)});
   auto rel=ast.RefTo(a,{});rel->ref->lenstorage=IS_U32;fields[root->struc].push_back(ast.RefTo(rel,{}));
   // Same nominal declaration forces full argument equality and array-size
   // trace/order; different cq must still suppress its argument comparison.
   auto sz1=arrayof(num(),A_FIXED,4,true);auto sz2=arrayof(num(),A_FIXED,seed%5==0?-7:4,true);
   auto sd=decl();auto n1=str(sd,{sz1});auto n2=str(sd,{sz2});fields[n1->struc]={};fields[n2->struc]={};fields[root->struc].insert(fields[root->struc].end(),{n1,ast.ConstOf(n2),n2});
   if(seed%5==1)lazy_errors[b->struc]=71;
   if(seed%5==2){auto target=arrayof(num(),A_LIMITED,3,true);fields[root->struc].push_back(target);fields[root->struc].push_back(arrayof(num(),A_LIMITED,3,true));}
   if(seed%5==3){bool *done=new bool(false);mutation_flag.reset(done);mutate=[this,b,fixed,sz1,done](TypeExpr*t){if(t==b&&!*done){*done=true;fixed->enu->varmode=true;sz1->arr->size=9;log("mutate-nonkey");}};}
  }
  return root;
 }
 unique_ptr<bool>mutation_flag;
};
int main(){
 size_t laws=0;uint64_t oldeq=0,neweq=0;vector<double>oldt,newt;
 for(unsigned seed=0;seed<100;seed++){
  Engine a,b;auto ar=a.graph(seed,8+seed%29,1+seed%4);auto br=b.graph(seed,8+seed%29,1+seed%4);
  assert(a.run(ar,false)==b.run(br,true));laws++;
  a.trace.clear();b.trace.clear();assert(a.run(ar,false)==b.run(br,true));laws++;
  // Nonkey mutation between invocations, each with its own fresh visited set.
  for(auto &t:a.ast.all)if(t->kind==TY_ARRAY){t->arr->size=12;t->arr->sub=a.ast.inttypes[IS_U8];}
  for(auto &t:b.ast.all)if(t->kind==TY_ARRAY){t->arr->size=12;t->arr->sub=b.ast.inttypes[IS_U8];}
  a.trace.clear();b.trace.clear();assert(a.run(ar,false)==b.run(br,true));laws++;
 }
 cout<<"laws "<<laws<<"\n";
 for(bool homogeneous:{false,true}){
  vector<double>ot,nt;uint64_t oc=0,nc=0;uint64_t ov=0,nv=0;
  for(int i=0;i<7;i++){
   Engine a,b;a.record=false;b.record=false;auto ar=a.graph(0,384,4,homogeneous);auto br=b.graph(0,384,4,homogeneous);
   string ao,bo;auto runa=[&]{auto t=chrono::steady_clock::now();ao=a.run(ar,false);ot.push_back(chrono::duration<double,milli>(chrono::steady_clock::now()-t).count());};
   auto runb=[&]{auto t=chrono::steady_clock::now();bo=b.run(br,true);nt.push_back(chrono::duration<double,milli>(chrono::steady_clock::now()-t).count());};
   if(i%2){runb();runa();}else{runa();runb();}assert(ao==bo);oc=a.eq_calls;nc=b.eq_calls;ov=a.visits;nv=b.visits;
  }
  sort(ot.begin(),ot.end());sort(nt.begin(),nt.end());cout<<(homogeneous?"onebucket":"heterogeneous")<<" eq "<<oc<<' '<<nc<<" visits "<<ov<<' '<<nv<<" median_ms "<<ot[3]<<' '<<nt[3]<<"\n";
 }
}
