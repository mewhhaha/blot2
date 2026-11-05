// Owned recipes describe formal slots and paths; live authority stays local.
namespace blot_check_capability_contracts;
import .logical_scratch_budget;
import support.error;
import support.option;
import support.structural;
import support.pooled_buffer;
import support.blake3;
type Error = blot_error::Error;
type Id = u32;
enum Tag { empty, unknown, parameter, authority, captures, product, record, wrapped, join, project, elements, argument, callable }
enum Projection { index, field, payload }
struct Term { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 }
struct Limits { nodes: i64 = 4096, words: i64 = 65536, visits: i64 = 65536, depth: i64 = 128 }
struct View { nodes: const Term[:], words: const u32[:] }
fn children(self: View, node: Term) -> const u32[:] { return self.words[node.a..node.a + node.b]; }
fn parameterMask(self: View, root: Id) -> u16, Error {
    if root >= self.nodes.len || self.nodes.len > 4096 { return 0, Error.invalid_capability_contract; } var masks: u16[4096] = [0; 4096]; var remaining: i64 = 65536;
    for node, index in self.nodes { if remaining == 0 { return 0, Error.capability_analysis_limit; } remaining -= 1;
        match node.tag {
            Tag.parameter => { if node.a >= 16 { return 0, Error.invalid_capability_contract; } masks[index] = (1 as u16) << node.a; },
            Tag.argument => {},
            Tag.callable => { if node.b >= index || node.c >= index { return 0, Error.invalid_capability_contract; } masks[index] = masks[node.b]; },
            Tag.wrapped, Tag.project, Tag.elements => { if node.a >= index { return 0, Error.invalid_capability_contract; } masks[index] = masks[node.a]; },
            Tag.captures, Tag.product, Tag.join, Tag.record => {
                if node.a > self.words.len || node.b > self.words.len - node.a { return 0, Error.invalid_capability_contract; }
                for child, position in self.children(node) { if node.tag == Tag.record && position % 2 == 0 { continue; } if remaining == 0 { return 0, Error.capability_analysis_limit; } remaining -= 1; if child >= index { return 0, Error.invalid_capability_contract; } masks[index] |= masks[child]; }
            },
            Tag.unknown, Tag.authority => { return 0, Error.invalid_capability_contract; },
            Tag.empty => {},
        }
    } return masks[root], Error.none;
}
fn argumentMask(self: View, root: Id, remaining: i64&) -> u16, Error { return argumentMaskDepth(self, root, remaining, 0); }
recursive fn argumentMaskDepth(self: View, root: Id, remaining: i64&, depth: i64) -> u16, Error {
    if root >= self.nodes.len || depth >= 128 || remaining == 0 { return 0, Error.capability_analysis_limit; } remaining -= 1; let node = self.nodes[root];
    match node.tag {
        Tag.argument => { if node.a >= 16 { return 0, Error.invalid_capability_contract; } return (1 as u16) << node.a, Error.none; },
        Tag.parameter, Tag.authority, Tag.unknown => { return 0, Error.invalid_capability_contract; },
        Tag.empty => { return 0, Error.none; },
        Tag.callable => { return argumentMaskDepth(self, node.b, remaining, depth + 1); },
        Tag.wrapped, Tag.project, Tag.elements => { return argumentMaskDepth(self, node.a, remaining, depth + 1); },
        Tag.captures, Tag.product, Tag.join, Tag.record => { if node.a > self.words.len || node.b > self.words.len - node.a { return 0, Error.invalid_capability_contract; } var mask: u16 = 0;
            for child, index in self.children(node) { if node.tag == Tag.record && index % 2 == 0 { continue; } let result, error = argumentMaskDepth(self, child, remaining, depth + 1); if error != Error.none { return 0, error; } mask |= result; } return mask, Error.none;
        },
    }
}
fn containsParameter(self: View, root: Id, remaining: i64&) -> bool, Error { return parameterDepth(self, root, remaining, 0); }
recursive fn parameterDepth(self: View, root: Id, remaining: i64&, depth: i64) -> bool, Error {
    if root >= self.nodes.len || depth >= 128 || remaining == 0 { return false, Error.capability_analysis_limit; } remaining -= 1; let node = self.nodes[root];
    match node.tag {
        Tag.parameter, Tag.argument => { return true, Error.none; },
        Tag.callable => { return parameterDepth(self, node.b, remaining, depth + 1); },
        Tag.wrapped, Tag.project, Tag.elements => { return parameterDepth(self, node.a, remaining, depth + 1); },
        Tag.captures, Tag.product, Tag.join, Tag.record => { if node.a > self.words.len || node.b > self.words.len - node.a { return false, Error.invalid_capability_contract; }
            for child, index in self.children(node) { if node.tag == Tag.record && index % 2 == 0 { continue; } let found, error = parameterDepth(self, child, remaining, depth + 1); if error != Error.none || found { return found, error; } } return false, Error.none;
        },
        _ => { return false, Error.none; },
    }
}
fn validate(self: View, root: Id, arity: u32, portable: bool) -> Error {
    if self.nodes.len == 0 || self.nodes.len > 4096 || self.words.len > 65536 || root >= self.nodes.len || arity > 16 || self.nodes[0] != Term { Tag.empty } { return Error.invalid_capability_contract; }
    var visits: i64 = 0; var depths: u8[4096] = [0; 4096]; var roles: u8[65536] = [0; 65536];
    for node, index in self.nodes { visits += 1; if visits > 65536 { return Error.capability_analysis_limit; }
        match node.tag {
            Tag.empty, Tag.unknown => { if node.a != 0 || node.b != 0 || node.c != 0 { return Error.invalid_capability_contract; } },
            Tag.parameter, Tag.argument => { if node.a >= 16 || node.b != 0 || node.c != 0 { return Error.invalid_capability_contract; } },
            Tag.callable => { if node.a == 0 || node.a > 16 || node.b >= index || node.c >= index { return Error.invalid_capability_contract; } },
            Tag.authority => { if portable || node.b == 0 || node.c != 0 { return Error.invalid_capability_contract; } },
            Tag.wrapped, Tag.elements => { if node.a >= index || node.b != 0 || node.c != 0 { return Error.invalid_capability_contract; } },
            Tag.project => { if node.a >= index || node.c > projectionCode(Projection.payload) || (node.c == projectionCode(Projection.payload) && node.b != 0) { return Error.invalid_capability_contract; } },
            Tag.captures, Tag.product, Tag.join, Tag.record => {
                if node.a > self.words.len || node.b > self.words.len - node.a || node.c != 0 { return Error.invalid_capability_contract; } let children = self.children(node);
                if node.tag == Tag.record { if children.len % 2 != 0 { return Error.invalid_capability_contract; } for field in 0..children.len / 2 { if children[field * 2] == 0 || children[field * 2 + 1] >= index { return Error.invalid_capability_contract; }
                        for prior in 0..field { visits += 1; if visits > 65536 { return Error.capability_analysis_limit; } if children[prior * 2] == children[field * 2] { return Error.invalid_capability_contract; } }
                    }
                } else { for child in children { if child >= index { return Error.invalid_capability_contract; } } }
            },
        }
        var height: u16 = 0; if node.tag == Tag.callable { height = max(depths[node.b], depths[node.c]) as u16 + 1; }
        if node.tag == Tag.wrapped || node.tag == Tag.project || node.tag == Tag.elements { height = depths[node.a] as u16 + 1; }
        if node.tag == Tag.captures || node.tag == Tag.product || node.tag == Tag.record || node.tag == Tag.join { for child, offset in self.children(node) { var role: u8 = 2; if node.tag == Tag.record && offset % 2 == 0 { role = 1; }
                let slot = node.a + offset; if roles[slot] != 0 && roles[slot] != role { return Error.invalid_capability_contract; } roles[slot] = role; if role == 2 { height = max(height, depths[child] as u16 + 1); }
        } }
        if height >= 128 { return Error.capability_analysis_limit; } depths[index] = height as u8;
    }
    var reached: bool[4096][17] = [[false; 4096]; 17]; var remaining = 65536 - visits; return boundScopes(self, root, arity, 0, reached, remaining, 0);
}
recursive fn boundScopes(self: View, root: Id, arity: u32, callable_arity: u32, reached: bool[4096][17]&, remaining: i64&, depth: i64) -> Error {
    if depth >= 128 || remaining == 0 { return Error.capability_analysis_limit; } remaining -= 1; if reached[callable_arity][root] { return Error.none; } reached[callable_arity][root] = true; let node = self.nodes[root];
    match node.tag {
        Tag.parameter => { if callable_arity != 0 || node.a >= arity { return Error.invalid_capability_contract; } },
        Tag.argument => { if callable_arity == 0 || node.a >= callable_arity { return Error.invalid_capability_contract; } },
        Tag.authority => { if callable_arity != 0 { return Error.invalid_capability_contract; } },
        Tag.callable => { let error = boundScopes(self, node.b, arity, callable_arity, reached, remaining, depth + 1); if error != Error.none { return error; } return boundScopes(self, node.c, arity, node.a, reached, remaining, depth + 1); },
        Tag.wrapped, Tag.project, Tag.elements => { return boundScopes(self, node.a, arity, callable_arity, reached, remaining, depth + 1); },
        Tag.captures, Tag.product, Tag.record, Tag.join => { for child, index in self.children(node) { if node.tag == Tag.record && index % 2 == 0 { continue; } let error = boundScopes(self, child, arity, callable_arity, reached, remaining, depth + 1); if error != Error.none { return error; } } },
        Tag.empty, Tag.unknown => {},
    } return Error.none;
}
struct Recipe { arity: u32, root: Id, nodes: const Term[:], words: const u32[:] }
struct Owned { arity: u32, root: Id, nodes: const Term[:] = [], words: const u32[:] = [] }
fn view(self: Recipe) -> View { return View { self.nodes, self.words }; }
fn view(self: Owned) -> View { return View { self.nodes, self.words }; }
fn clone(self: Owned, nodes: Term[>..]&, words: u32[>..]&) -> Owned, Error { let first = nodes.len; let second = words.len; nodes += self.nodes; words += self.words; return Owned { self.arity, self.root, nodes[first..], words[second..] }, Error.none; }
fn deinit(self: Owned&) { self.nodes = []; self.words = []; }
struct Mark { nodes: i64, words: i64, visits: i64 }
struct Store {
 nodes: TermBuffer& = inactive_terms, words: WordBuffer& = inactive_words, limits: Limits = Limits {}, visits: i64 = 0,
    budget: blot_check_logical_scratch_budget::Budget? = null,
    node_allocation: blot_check_logical_scratch_budget::ArrayBlock = blot_check_logical_scratch_budget::ArrayBlock {element_size:16,alignment:4},
    word_allocation: blot_check_logical_scratch_budget::ArrayBlock = blot_check_logical_scratch_budget::ArrayBlock {element_size:4,alignment:4}, lease:u32=0,generation:u64=0 }

fn mark(self: const Store&) -> Mark { return Mark { self.nodes.len, self.words.len, self.visits }; }
fn rollback(self: Store&, checkpoint: Mark) { self.nodes.resize(checkpoint.nodes); self.words.resize(checkpoint.words); self.visits = checkpoint.visits; }
fn deinit(self: Store&) { if self.lease==0 {return;}assert(valid(self));self.nodes.deinit();self.words.deinit();let index=self.lease-1;store_states[index].live=false;store_states.free(index);self=Store{}; }
fn view(self: const Store&) -> View { return View { self.nodes.items[:], self.words.items[:] }; }
fn visit(self: Store&, depth: i64) -> Error { if depth >= self.limits.depth || self.visits >= self.limits.visits { return Error.capability_analysis_limit; } self.visits += 1; return Error.none; }
fn append(self: Store&, term: Term) -> Id, Error {
    let before = mark(self); if self.nodes.len == 0 { let error = ensureNodes(self,1); if error != Error.none { return 0,error; } self.nodes.push(Term { Tag.empty }); } for known, index in self.nodes.items { if known == term { return index as u32, Error.none; } }
    if self.nodes.len >= self.limits.nodes { rollback(self, before); return 0, Error.capability_analysis_limit; } let id = self.nodes.len as u32; let error = ensureNodes(self,self.nodes.len+1); if error != Error.none { rollback(self,before); return 0,error; } self.nodes.push(term); return id, Error.none;
}
fn aggregate(self: Store&, tag: Tag, children: const u32[:]) -> Id, Error {
    let before = mark(self); if tag != Tag.product && tag != Tag.record && tag != Tag.captures && tag != Tag.join { return 0, Error.invalid_capability_contract; }
    var room: i64 = 0; if self.words.len < self.limits.words { room = self.limits.words - self.words.len; } if children.len > room { return 0, Error.capability_analysis_limit; }
    for node, index in self.nodes.items { if node.tag == tag && node.b == children.len && self.view().children(node) == children { return index as u32, Error.none; } }
    let start = self.words.len as u32; let growth = ensureWords(self,self.words.len+children.len); if growth != Error.none { return 0,growth; } self.words.append(children); let id, error = append(self, Term { tag, start, children.len as u32 }); if error != Error.none { rollback(self, before); } return id, error;
}
fn project(self: Store&, base: Id, selector: u32, kind: Projection) -> Id, Error { let before = mark(self); let id, error = projectDepth(self, base, selector, kind, 0); if error != Error.none { rollback(self, before); } return id, error; }
recursive fn projectDepth(self: Store&, base: Id, selector: u32, kind: Projection, depth: i64) -> Id, Error {
    let error = visit(self, depth); if error != Error.none { return 0, error; } if base >= self.nodes.len { return 0, Error.invalid_capability_contract; } let term = self.nodes.items[base];
    if term.tag == Tag.empty || term.tag == Tag.unknown { return base, Error.none; }
    if term.tag == Tag.join { var projected: Id[4096]; if term.b > projected.len { return 0, Error.capability_analysis_limit; } for index in 0..term.b { let id, error = projectDepth(self, self.words.items[term.a + index], selector, kind, depth + 1); if error != Error.none { return 0, error; } projected[index] = id; } return aggregate(self, Tag.join, projected[..term.b]); }
    if kind == Projection.payload && term.tag == Tag.wrapped { return term.a, Error.none; }
    if kind == Projection.index && term.tag == Tag.product { if selector >= term.b { return 0, Error.invalid_capability_contract; } return self.words.items[term.a + selector], Error.none; }
    if kind == Projection.field && term.tag == Tag.record { for field in 0..term.b / 2 { if self.words.items[term.a + field * 2] == selector { return self.words.items[term.a + field * 2 + 1], Error.none; } } return 0, Error.invalid_capability_contract; }
    return append(self, Term { Tag.project, base, selector, projectionCode(kind) });
}
fn elements(self: Store&, base: Id) -> Id, Error { let before = mark(self); let id, error = elementsDepth(self, base, 0); if error != Error.none { rollback(self, before); } return id, error; }
recursive fn elementsDepth(self: Store&, base: Id, depth: i64) -> Id, Error {
    let error = visit(self, depth); if error != Error.none { return 0, error; } if base >= self.nodes.len { return 0, Error.invalid_capability_contract; } let term = self.nodes.items[base]; if term.tag == Tag.empty || term.tag == Tag.unknown { return base, Error.none; }
    if term.tag == Tag.product || term.tag == Tag.join { var children: Id[4096]; if term.b > children.len { return 0, Error.capability_analysis_limit; } for index in 0..term.b { let child = self.words.items[term.a + index]; children[index] = child; if term.tag == Tag.join { let id, error = elementsDepth(self, child, depth + 1); if error != Error.none { return 0, error; } children[index] = id; } } return aggregate(self, Tag.join, children[..term.b]); }
    return append(self, Term { Tag.elements, base });
}
fn own(self: const Store&, arity: u32, root: Id, nodes: Term[>..]&, words: u32[>..]&) -> Owned, Error { let error = self.view().validate(root, arity, true); if error != Error.none { return default<Owned>(), error; } return clone(Owned { arity, root, self.nodes.items[:], self.words.items[:] }, nodes, words); }
fn instantiate<H>(self: Store&, header: H, arguments: const Id[:]) -> Id, Error { let before = mark(self); let id, error = instantiateBody(self, header, arguments); if error != Error.none { rollback(self, before); } return id, error; }
fn instantiateBody<H>(self: Store&, header: H, arguments: const Id[:]) -> Id, Error {
    let error = header.view().validate(header.root, header.arity, true); if error != Error.none { return 0, error; } if arguments.len != header.arity { return 0, Error.invalid_capability_contract; }
    if self.nodes.len == 0 { let id, error = append(self, Term { Tag.empty }); if error != Error.none { return 0, error; } }
    for argument in arguments { if argument >= self.nodes.len { return 0, Error.invalid_capability_contract; } }
    var needed: bool[4096] = [false; 4096]; needed[header.root] = true; var reverse = header.nodes.len;
    while reverse != 0 { reverse -= 1; if !needed[reverse] { continue; } let term = header.nodes[reverse];
        if term.tag == Tag.callable { needed[term.b] = true; needed[term.c] = true; }
        if term.tag == Tag.wrapped || term.tag == Tag.project || term.tag == Tag.elements { needed[term.a] = true; }
        else if term.tag == Tag.captures || term.tag == Tag.product || term.tag == Tag.record || term.tag == Tag.join { for child, index in header.view().children(term) { if term.tag == Tag.record && index % 2 == 0 { continue; } needed[child] = true; } }
    }
    var map: Id[4096]; map[0] = 0; for index in 1..header.nodes.len { if !needed[index] { continue; } let error = visit(self, 0); if error != Error.none { return 0, error; } let id, error = copy(self, header.view(), header.nodes[index], map, arguments); if error != Error.none { return 0, error; } map[index] = id; }
    return map[header.root], Error.none;
}
struct Frame { node: Id, next: u32 = 0 }
fn instantiateCanonical<H>(self: Store&, header: H, arguments: const Id[:]) -> Id, Error { let before = mark(self); let id, error = canonicalBody(self, header, arguments); if error != Error.none { rollback(self, before); } return id, error; }
fn canonicalBody<H>(self: Store&, header: H, arguments: const Id[:]) -> Id, Error {
    let source = header.view(); let error = source.validate(header.root, header.arity, true); if error != Error.none { return 0, error; } if arguments.len != header.arity { return 0, Error.invalid_capability_contract; }
    if self.nodes.len == 0 { let id, error = append(self, Term { Tag.empty }); if error != Error.none { return 0, error; } } for argument in arguments { if argument >= self.nodes.len { return 0, Error.invalid_capability_contract; } }
    var map: Id[4096] = [0xffffffff; 4096]; map[0] = 0; var stack: Frame[130]; var depth: i64 = 1; stack[0] = Frame { header.root };
    while depth != 0 { let top: Frame& = stack[depth - 1]; if map[top.node] != 0xffffffff { depth -= 1; continue; } let term = source.nodes[top.node]; var pending: Id = 0xffffffff;
        match term.tag {
            Tag.callable => { while top.next < 2 { var child = term.c; if top.next == 0 { child = term.b; } top.next += 1; if map[child] == 0xffffffff { pending = child; break; } } },
            Tag.wrapped, Tag.project, Tag.elements => { if top.next == 0 { top.next = 1; if map[term.a] == 0xffffffff { pending = term.a; } } },
            Tag.captures, Tag.product, Tag.record, Tag.join => { let children = source.children(term); while top.next < children.len { let position = top.next; top.next += 1; if term.tag == Tag.record && position % 2 == 0 { continue; } if map[children[position]] == 0xffffffff { pending = children[position]; break; } } },
            _ => {},
        }
        if pending != 0xffffffff { if depth == stack.len { return 0, Error.capability_analysis_limit; } stack[depth] = Frame { pending }; depth += 1; continue; }
        let error = visit(self, 0); if error != Error.none { return 0, error; } let id, error = copy(self, source, term, map, arguments); if error != Error.none { return 0, error; } map[top.node] = id; depth -= 1;
    } return map[header.root], Error.none;
}
fn copy(self: Store&, source: View, term: Term, map: const Id[4096]&, arguments: const Id[:]) -> Id, Error {
    match term.tag {
        Tag.empty => { return 0, Error.none; },
        Tag.unknown, Tag.argument => { return append(self, term); },
        Tag.parameter => { return arguments[term.a], Error.none; },
        Tag.callable => { return append(self, Term { Tag.callable, term.a, map[term.b], map[term.c] }); },
        Tag.authority => { return 0, Error.invalid_capability_contract; },
        Tag.wrapped => { return append(self, Term { Tag.wrapped, map[term.a] }); },
        Tag.elements => { return elements(self, map[term.a]); },
        Tag.project => { let kind, error = projectionFromCode(term.c); if error != Error.none { return 0, error; } return project(self, map[term.a], term.b, kind); },
        Tag.captures, Tag.product, Tag.record, Tag.join => { let children = source.children(term); var mapped: u32[4096]; if children.len > mapped.len { return 0, Error.capability_analysis_limit; }
            for child, index in children { if term.tag == Tag.record && index % 2 == 0 { mapped[index] = child; } else { mapped[index] = map[child]; } } return aggregate(self, term.tag, mapped[..children.len]);
        },
    }
}
fn callable(self: Store&, header: Recipe, captures: Id) -> Id, Error { let before = mark(self); let id, error = callableBody(self, header, captures); if error != Error.none { rollback(self, before); } return id, error; }
fn callableBody(self: Store&, header: Recipe, captures: Id) -> Id, Error {
    if self.nodes.len == 0 { let id, error = append(self, Term { Tag.empty }); if error != Error.none { return 0, error; } } if header.arity == 0 || header.arity > 16 || captures >= self.nodes.len { return 0, Error.invalid_capability_contract; }
    var arguments: Id[16]; for index in 0..header.arity { let id, error = append(self, Term { Tag.argument, index as u32 }); if error != Error.none { return 0, error; } arguments[index] = id; }
    let result, error = instantiate(self, header, arguments[..header.arity]); if error != Error.none { return 0, error; } return append(self, Term { Tag.callable, header.arity, captures, result });
}
recursive fn callableArity(self: const Store&, root: Id, arity: i64, remaining: i64&, depth: i64) -> bool, Error {
    if root >= self.nodes.len || depth >= 128 || remaining == 0 { return false, Error.capability_analysis_limit; } remaining -= 1; let node = self.nodes.items[root];
    if node.tag == Tag.callable { return node.a == arity && node.a != 0 && node.a <= 16 && node.b < root && node.c < root, Error.none; }
    if node.tag != Tag.join || node.b == 0 { return false, Error.none; } if node.a > self.words.len || node.b > self.words.len - node.a { return false, Error.invalid_capability_contract; }
    for child in self.view().children(node) { if child >= root { return false, Error.invalid_capability_contract; } let valid, error = callableArity(self, child, arity, remaining, depth + 1); if error != Error.none || !valid { return valid, error; } } return true, Error.none;
}
fn invoke(self: Store&, root: Id, arguments: const Id[:]) -> Id, Error { let before = mark(self); let id, error = invokeDepth(self, root, arguments, 0); if error != Error.none { rollback(self, before); } return id, error; }
recursive fn invokeDepth(self: Store&, root: Id, arguments: const Id[:], depth: i64) -> Id, Error {
    let error = visit(self, depth); if error != Error.none { return 0, error; } if root >= self.nodes.len || arguments.len == 0 || arguments.len > 16 { return 0, Error.invalid_capability_contract; } let callable = self.nodes.items[root];
    if callable.tag == Tag.join { if callable.b == 0 || callable.b > 4096 || callable.a > self.words.len || callable.b > self.words.len - callable.a { return 0, Error.invalid_capability_contract; } var results: Id[4096];
        for index in 0..callable.b { let child = self.words.items[callable.a + index]; if child >= root { return 0, Error.invalid_capability_contract; } let id, error = invokeDepth(self, child, arguments, depth + 1); if error != Error.none { return 0, error; } results[index] = id; } return aggregate(self, Tag.join, results[..callable.b]);
    }
    if callable.tag != Tag.callable || callable.a != arguments.len || callable.b >= root || callable.c >= root { return 0, Error.invalid_capability_contract; } for argument in arguments { if argument >= self.nodes.len { return 0, Error.invalid_capability_contract; } }
    let count = self.nodes.len; if count > 4096 { return 0, Error.capability_analysis_limit; } var needed: bool[4096] = [false; 4096]; needed[callable.c] = true; var reverse = count;
    while reverse != 0 { reverse -= 1; let error = visit(self, depth); if error != Error.none { return 0, error; } if !needed[reverse] { continue; } let node = self.nodes.items[reverse];
        match node.tag {
            Tag.callable => { if node.a == 0 || node.a > 16 || node.b >= reverse || node.c >= reverse { return 0, Error.invalid_capability_contract; } needed[node.b] = true; },
            Tag.wrapped, Tag.project, Tag.elements => { if node.a >= reverse { return 0, Error.invalid_capability_contract; } needed[node.a] = true; },
            Tag.captures, Tag.product, Tag.record, Tag.join => {
                if node.a > self.words.len || node.b > self.words.len - node.a || (node.tag == Tag.record && node.b % 2 != 0) { return 0, Error.invalid_capability_contract; }
                for child, index in self.view().children(node) { let error = visit(self, depth); if error != Error.none { return 0, error; } if node.tag == Tag.record && index % 2 == 0 { continue; } if child >= reverse { return 0, Error.invalid_capability_contract; } needed[child] = true; }
            },
            _ => {},
        }
    }
    var map: Id[4096]; map[0] = 0;
    for index in 1..count { let error = visit(self, depth); if error != Error.none { return 0, error; } if !needed[index] { continue; } let node = self.nodes.items[index]; var result: Id = 0;
        match node.tag {
            Tag.empty, Tag.unknown => { result = index as u32; },
            Tag.argument => { if node.a >= arguments.len { return 0, Error.invalid_capability_contract; } result = arguments[node.a]; },
            Tag.parameter, Tag.authority => { return 0, Error.invalid_capability_contract; },
            Tag.callable => { let id, error = append(self, Term { Tag.callable, node.a, map[node.b], node.c }); if error != Error.none { return 0, error; } result = id; },
            _ => { let id, error = copy(self, self.view(), node, map, arguments); if error != Error.none { return 0, error; } result = id; },
        } map[index] = result;
    }
    if callable.b == 0 { return map[callable.c], Error.none; } let children: Id[2] = [map[callable.c], callable.b]; return aggregate(self, Tag.join, children);
}
struct Binding { binding: u32, root: Id }
struct Collection { nodes: const Term[:] = [], words: const u32[:] = [], bindings: const Binding[:] = [] }
fn header(self: Collection, binding: u32, arity: u32) -> blot_support::Option<Recipe> { for entry in self.bindings { if entry.binding == binding { return blot_support::some(Recipe { arity, entry.root, self.nodes, self.words }); } } return blot_support::none<Recipe>(); }
struct CollectionTables { nodes: Term[>..]&, words: u32[>..]&, bindings: Binding[>..]& }
fn select(self: Collection, bindings, keep: const bool[:], has_keep: bool, destination: CollectionTables) -> Collection, Error {let initialized,error=initPooled();if error!=Error.none {return Collection{},error;}var store=initialized;var roots:Binding[>..<]=[];let result,failure=selectValues(self,bindings,keep,has_keep,destination,store,roots);store.deinit();return result,failure;}
fn selectValues(self:Collection,bindings,keep:const bool[:],has_keep:bool,destination:CollectionTables,store:Store&,roots:Binding[>..<]&)->Collection,Error {for entry in self.bindings {if entry.binding>=bindings.len {return Collection{},Error.invalid_capability_contract;}let binding=bindings[entry.binding];if binding.kind!=blot_check_check::Kind.global || !binding.capability_parameters.present() {continue;}if has_keep && !keep[entry.binding] {continue;}let found=header(self,entry.binding,binding.capability_parameters.arity());if !found.present {return Collection{},Error.invalid_capability_contract;}let recipe=found.value;var arguments:u32[16]=[0;16];for index in 0..recipe.arity {let id,error=append(store,Term{Tag.parameter,index as u32});if error!=Error.none {return Collection{},error;}arguments[index]=id;}let root,error=instantiateCanonical(store,recipe,arguments[..recipe.arity]);if error!=Error.none {return Collection{},error;}roots.push(Binding{entry.binding,root});}if roots.len==0 {return Collection{},Error.none;}return clone(Collection{store.nodes.items[:],store.words.items[:],roots[:]},destination);}

fn validate(self: Collection, binding_count: i64, symbol_count: i64) -> Error {
    if self.bindings.len == 0 { if self.nodes.len != 0 || self.words.len != 0 { return Error.invalid_capability_contract; } return Error.none; }
    let error = validate(View { self.nodes, self.words }, 0, 16, true); if error != Error.none { return error; } var previous: u32 = 0; var has_previous = false;
    for entry in self.bindings { if entry.binding == 0 || entry.binding >= binding_count || (has_previous && entry.binding <= previous) || entry.root >= self.nodes.len { return Error.invalid_capability_contract; } previous = entry.binding; has_previous = true; }
    for node in self.nodes {
        if node.tag == Tag.record { for field in 0..node.b / 2 { if self.words[node.a + field * 2] >= symbol_count { return Error.invalid_capability_contract; } } }
        if node.tag == Tag.project && node.c == projectionCode(Projection.field) && (node.b == 0 || node.b >= symbol_count) { return Error.invalid_capability_contract; }
    } return Error.none;
}
fn clone(self: Collection, destination: CollectionTables) -> Collection, Error {
    let nodes = destination.nodes.len; let words = destination.words.len; let bindings = destination.bindings.len; destination.nodes += self.nodes; destination.words += self.words; destination.bindings += self.bindings;
    return Collection { destination.nodes[nodes..], destination.words[words..], destination.bindings[bindings..] }, Error.none;
}
fn deinit(self: Collection&) { self = Collection {}; }
fn equivalent(left: View, left_root: Id, right: View, right_root: Id) -> bool, Error { var remaining: i64 = 65536; return equivalentDepth(left, left_root, right, right_root, remaining, 0); }
recursive fn equivalentDepth(left: View, left_root: Id, right: View, right_root: Id, remaining: i64&, depth: i64) -> bool, Error {
    if depth >= 128 || remaining == 0 { return false, Error.capability_analysis_limit; } remaining -= 1; if left_root >= left.nodes.len || right_root >= right.nodes.len { return false, Error.invalid_capability_contract; } let a = left.nodes[left_root]; let b = right.nodes[right_root]; if a.tag != b.tag { return false, Error.none; }
    match a.tag {
        Tag.empty, Tag.unknown => { return true, Error.none; },
        Tag.parameter, Tag.argument, Tag.authority => { return a.a == b.a && a.b == b.b && a.c == b.c, Error.none; },
        Tag.callable => { if a.a != b.a { return false, Error.none; } let equal, error = equivalentDepth(left, a.b, right, b.b, remaining, depth + 1); if error != Error.none || !equal { return equal, error; } return equivalentDepth(left, a.c, right, b.c, remaining, depth + 1); },
        Tag.wrapped, Tag.elements => { return equivalentDepth(left, a.a, right, b.a, remaining, depth + 1); },
        Tag.project => { if a.b != b.b || a.c != b.c { return false, Error.none; } return equivalentDepth(left, a.a, right, b.a, remaining, depth + 1); },
        Tag.captures, Tag.product, Tag.join, Tag.record => { if a.b != b.b { return false, Error.none; } let before = left.children(a); let after = right.children(b);
            for first, index in before { let second = after[index]; if a.tag == Tag.record && index % 2 == 0 { if first != second { return false, Error.none; } continue; } let equal, error = equivalentDepth(left, first, right, second, remaining, depth + 1); if error != Error.none || !equal { return equal, error; } } return true, Error.none;
        },
    }
}
fn digest(recipe: Recipe, pool: const blot_parse_symbols::Pool&) -> blot_support::Option<u8[32]> {
    if recipe.view().validate(recipe.root, recipe.arity, true) != Error.none { return blot_support::none<u8[32]>(); }
    var hash = blot_support_blake3::init(); word(hash, 0x43565001); word(hash, recipe.arity); var remaining: i64 = 65536;
    if !digestTerm(recipe.view(), recipe.root, pool, hash, remaining, 0) { return blot_support::none<u8[32]>(); } return blot_support::some(hash.final());
}
fn word(hash: blot_support_blake3::State&, value: u32) { var bytes: u8[4]; for index in 0..4 { bytes[index] = (value >> (index * 8)) as! u8; } hash.update(bytes); }
fn fieldDigest(hash: blot_support_blake3::State&, pool: const blot_parse_symbols::Pool&, symbol: u32) -> bool { if symbol == 0 || symbol > pool.entries.len { return false; } let text = pool.get(symbol); word(hash, text.len as u32); hash.update(text); return true; }
recursive fn digestTerm(view: View, root: Id, pool: const blot_parse_symbols::Pool&, hash: blot_support_blake3::State&, remaining: i64&, depth: i64) -> bool {
    if depth >= 128 || remaining == 0 { return false; } remaining -= 1; let term = view.nodes[root]; word(hash, tagCode(term.tag));
    match term.tag {
        Tag.empty, Tag.unknown => {},
        Tag.authority => { return false; },
        Tag.parameter, Tag.argument => { word(hash, term.a); },
        Tag.callable => { word(hash, term.a); return digestTerm(view, term.b, pool, hash, remaining, depth + 1) && digestTerm(view, term.c, pool, hash, remaining, depth + 1); },
        Tag.wrapped, Tag.elements => { return digestTerm(view, term.a, pool, hash, remaining, depth + 1); },
        Tag.project => { word(hash, term.c); if term.c == projectionCode(Projection.field) { if !fieldDigest(hash, pool, term.b) { return false; } } else { word(hash, term.b); } return digestTerm(view, term.a, pool, hash, remaining, depth + 1); },
        Tag.captures, Tag.product, Tag.record, Tag.join => { word(hash, term.b); for child, index in view.children(term) { if term.tag == Tag.record && index % 2 == 0 { if !fieldDigest(hash, pool, child) { return false; } } else if !digestTerm(view, child, pool, hash, remaining, depth + 1) { return false; } } },
    } return true;
}

fn tagCode(value: Tag) -> u32 {
    match value {
        Tag.empty => { return 0; },
        Tag.unknown => { return 1; },
        Tag.parameter => { return 2; },
        Tag.authority => { return 3; },
        Tag.captures => { return 4; },
        Tag.product => { return 5; },
        Tag.record => { return 6; },
        Tag.wrapped => { return 7; },
        Tag.join => { return 8; },
        Tag.project => { return 9; },
        Tag.elements => { return 10; },
        Tag.argument => { return 11; },
        Tag.callable => { return 12; },
    }
}
fn tagFromCode(code: u32) -> Tag, blot_error::Error {
    match code {
        0 => { return Tag.empty, blot_error::Error.none; },
        1 => { return Tag.unknown, blot_error::Error.none; },
        2 => { return Tag.parameter, blot_error::Error.none; },
        3 => { return Tag.authority, blot_error::Error.none; },
        4 => { return Tag.captures, blot_error::Error.none; },
        5 => { return Tag.product, blot_error::Error.none; },
        6 => { return Tag.record, blot_error::Error.none; },
        7 => { return Tag.wrapped, blot_error::Error.none; },
        8 => { return Tag.join, blot_error::Error.none; },
        9 => { return Tag.project, blot_error::Error.none; },
        10 => { return Tag.elements, blot_error::Error.none; },
        11 => { return Tag.argument, blot_error::Error.none; },
        12 => { return Tag.callable, blot_error::Error.none; },
        _ => { return Tag.empty, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_contracts::Tag, right: blot_check_capability_contracts::Tag) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_capability_contracts::Tag) { blot_structural::hash(sink, blot_check_capability_contracts::tagCode(value) as! u8); }
fn projectionCode(value: Projection) -> u32 {
    match value {
        Projection.index => { return 0; },
        Projection.field => { return 1; },
        Projection.payload => { return 2; },
    }
}
fn projectionFromCode(code: u32) -> Projection, blot_error::Error {
    match code {
        0 => { return Projection.index, blot_error::Error.none; },
        1 => { return Projection.field, blot_error::Error.none; },
        2 => { return Projection.payload, blot_error::Error.none; },
        _ => { return Projection.index, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_contracts::Projection, right: blot_check_capability_contracts::Projection) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_capability_contracts::Projection) { blot_structural::hash(sink, blot_check_capability_contracts::projectionCode(value) as! u8); }





fn ensureNodes(self:Store&,minimum:i64)->Error {let active=activate(self);if active!=Error.none {return active;}let budget .= self.budget;if budget {let error=blot_check_logical_scratch_budget::ensure(budget,self.node_allocation,minimum);if error!=Error.none {return error;}}return self.nodes.ensure(minimum);}
fn ensureWords(self:Store&,minimum:i64)->Error {let active=activate(self);if active!=Error.none {return active;}let budget .= self.budget;if budget {let error=blot_check_logical_scratch_budget::ensure(budget,self.word_allocation,minimum);if error!=Error.none {return error;}}return self.words.ensure(minimum);}

struct TermBuffer {storage:Term[:]=[],items:Term[:]=[],len:i64=0}
struct WordBuffer {storage:u32[:]=[],items:u32[:]=[],len:i64=0}
reusable[] var term_runs:Term[>..];
reusable[] var word_runs:u32[>..];
var inactive_terms=TermBuffer{};
var inactive_words=WordBuffer{};
struct StoreState {terms:TermBuffer=TermBuffer{},words:WordBuffer=WordBuffer{},generation:u64=0,live:bool=false}
reusable[] var store_states:StoreState[>..];
var store_generation:u64=1;
fn ensure(self:TermBuffer&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,term_runs);}
fn ensure(self:WordBuffer&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,word_runs);}
fn push(self:TermBuffer&,term:Term) {assert(self.len<self.storage.len);self.storage[self.len]=term;self.len+=1;self.items=self.storage[..self.len];}
fn append(self:WordBuffer&,values:const u32[:]) {assert(values.len<=self.storage.len-self.len);for value,index in values {self.storage[self.len+index]=value;}self.len+=values.len;self.items=self.storage[..self.len];}
fn resize(self:TermBuffer&,length:i64) {assert(length>=0 && length<=self.len);self.items=self.storage[..length];self.len=length;}
fn resize(self:WordBuffer&,length:i64) {assert(length>=0 && length<=self.len);self.items=self.storage[..length];self.len=length;}
fn clear(self:TermBuffer&) {self.items=self.storage[..0];self.len=0;}
fn clear(self:WordBuffer&) {self.items=self.storage[..0];self.len=0;}
fn deinit(self:TermBuffer&) {blot_support_pooled_buffer::deinit(self,term_runs);self.len=0;}
fn deinit(self:WordBuffer&) {blot_support_pooled_buffer::deinit(self,word_runs);self.len=0;}
fn valid(self:const Store&)->bool {return self.lease!=0 && self.lease-1<store_states.len && store_states[self.lease-1].live && store_states[self.lease-1].generation==self.generation;}
fn activate(self:Store&)->Error {if self.lease!=0 {assert(valid(self));return Error.none;}if store_generation==0xffffffffffffffff || store_states.len>=0xffffffff {return Error.out_of_memory;}let generation=store_generation;store_generation+=1;let index=store_states.alloc_index(StoreState{generation:generation,live:true});self.nodes .= store_states[index].terms;self.words .= store_states[index].words;self.lease=(index+1) as u32;self.generation=generation;return Error.none;}
fn initPooled()->Store,Error {var result=Store{};let error=activate(result);return result,error;}
fn init()->Store,Error {return initPooled();}
fn withStore<C,F>(context:C&)->Error {let initialized,error=initPooled();if error!=Error.none {return error;}var store=initialized;let result=F(context,store);store.deinit();return result;}
fn withStoreValue<C,F,R>(context:C&)->R,Error {let initialized,error=initPooled();if error!=Error.none {return default<R>(),error;}var store=initialized;let result,failure=F(context,store);store.deinit();return result,failure;}
