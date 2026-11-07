// Flat rows and chronological substitutions. Graph IDs retain Zig ordinals.
namespace blot_check_effects;
import support.error;
import support.option;
import support.pooled_buffer;
import support.structural_adapters;

import support.structural;
import std;
import dictionary;

type Id = u32;
type Label = u32;
type Cursor = u32;
type Error = blot_error::Error;
let formal_key_bit: u32 = 0x80000000;
let none: u32 = 0xffffffff;
struct List { start: u32 = 0, len: u32 = 0 }
enum Tail { closed, variable { value: u32 }, parameter { value: u32 }, formal { value: u32 } }
fn isParameter(tail: Tail) -> bool { match tail { parameter => { return true; }, _ => { return false; }, } }
fn isVariable(tail: Tail) -> bool { match tail { variable => { return true; }, _ => { return false; }, } }
struct Row { labels: List = List {..}, tail: Tail = Tail.closed, cursor: Cursor = 0 }
struct Variable { first: u32 = none, last: u32 = none }
struct Version {
    variable: u32, replacement: Id, position: Cursor, previous: u32,
    next: u32 = none, birth: u32 = none, shortcut: u32 = none,
    shortcut_birth: u32 = none,
}
struct Mark { rows: i64, labels: i64, variables: i64, versions: i64, next_position: Cursor }
struct Extraction { remaining: Id, expanded: blot_support::Option<u32>   = blot_support::Option<u32> { false, 0 , ..} }
struct ExtractionView {
    remaining: Row,
    expanded: blot_support::Option<u32>   = blot_support::Option<u32> { false, 0 , ..},
    saved: blot_support::Option<Id>   = blot_support::Option<Id> { false, 0 , ..},
}
struct Options { resolution_cache: bool = true }
// All table owners live in the compilation/session driver.
struct Store {lease:u32=0,owner_generation:u64=0,
rows:Table_rows& =inactive_rows,
labels:Table_labels& =inactive_labels,
variables:Table_variables& =inactive_variables,
versions:Table_versions& =inactive_versions,
resolved:Map_resolved& =inactive_resolved,
physical_epoch:(u64)& =inactive_scalars.physical_epoch,
mutation_epoch:(u64)& =inactive_scalars.mutation_epoch,
resolved_physical:(u64)& =inactive_scalars.resolved_physical,
resolved_high_water:(u32)& =inactive_scalars.resolved_high_water,
use_resolution_cache:(bool)& =inactive_scalars.use_resolution_cache,
next_position:(Cursor)& =inactive_scalars.next_position,
}



fn node(self_: const Store&, id: Id) -> Row { return self_.rows.items[id]; }
fn list(self_: const Store&, span: List) -> const Label[:] {
    return self_.labels.items[span.start..span.start + span.len];
}
fn mark(self_: const Store&) -> Mark {
    return Mark { self_.rows.len, self_.labels.len, self_.variables.len, self_.versions.len, self_.next_position , ..};
}
fn tick(self_: Store&) { if self_.mutation_epoch != 0xffffffffffffffff { self_.mutation_epoch += 1; } }
fn rollback(self_: Store&, point: Mark) {
    if self_.physical_epoch != 0xffffffffffffffff { self_.physical_epoch += 1; }
    tick(self_);
    while self_.versions.len > point.versions {
        let write = self_.versions.pop();
        self_.variables.items[write.variable].last = write.previous;
        if write.previous == none { self_.variables.items[write.variable].first = none; }
        else { self_.versions.items[write.previous].next = none; }
    }
    self_.rows.pop_n(self_.rows.len - point.rows);
    self_.labels.pop_n(self_.labels.len - point.labels);
    self_.variables.pop_n(self_.variables.len - point.variables);
    self_.next_position = point.next_position;
}
fn add(self_: Store&, value: Row) -> Id, Error {
    if self_.rows.len == none { return 0, blot_error::Error.effect_limit; }
    let id = self_.rows.len as u32;
    self_.rows.push(value);if self_.rows.failure!=blot_error::Error.none {return 0,self_.rows.failure;}
    return id, blot_error::Error.none;
}
fn row(self_: Store&, labels: const Label[:], tail: Tail) -> Id, Error {
    if labels.len == 0 && tail == Tail.closed { return 0, blot_error::Error.none; }
    if labels.len > 0 {
        let start = self_.labels.index_of(labels[0]);
        if start >= 0 && labels.len <= self_.labels.len - start {
            return add(self_, Row { List { start as u32, labels.len as u32 }, tail , ..});
        }
    }
    if labels.len > none - self_.labels.len { return 0, blot_error::Error.effect_limit; }
    let start = self_.labels.len;
    self_.labels.append(labels);if self_.labels.failure!=blot_error::Error.none {return 0,self_.labels.failure;}
    let result, error = add(self_, Row { List { start as u32, labels.len as u32 }, tail , ..});
    if error != blot_error::Error.none { self_.labels.pop_n(self_.labels.len - start); }
    return result, error;
}
fn rowAt(self_: Store&, labels: const Label[:], tail: Tail, at: Cursor) -> Id, Error {
    let result, error = row(self_, labels, tail);
    if error != blot_error::Error.none { return 0, error; }
    if result != 0 { self_.rows.items[result].cursor = at; }
    return result, blot_error::Error.none;
}
fn cursor(self_: const Store&) -> Cursor { return self_.next_position; }
fn freeVariables(self_: Store&, root: Id) -> u32[>..], Error {
    let resolved, error = resolve(self_, root, 0);
    if error != blot_error::Error.none { return [], error; }
    var result: u32[>..] = [];
    match node(self_, resolved).tail {
        variable v => { result.push(v.value); },
        _ => {},
    }
    return result, blot_error::Error.none;
}
fn fresh(self_: Store&) -> Id, Error {
    if self_.variables.len >= formal_key_bit { return 0, blot_error::Error.effect_limit; }
    let index = self_.variables.len as u32;
    self_.variables.push(Variable {..});if self_.variables.failure!=blot_error::Error.none {return 0,self_.variables.failure;}
    let result, error = row(self_, [], Tail.variable { index , ..});
    if error != blot_error::Error.none { self_.variables.pop(); }
    return result, error;
}
fn appendVersion(self_: Store&, variable: u32, replacement_id: Id) -> Error {
    return appendVersionAt(self_, variable, replacement_id, self_.next_position);
}
fn appendVersionAt(self_: Store&, variable: u32, replacement_id: Id, position: Cursor) -> Error {
    assert(variable < self_.variables.len && replacement_id < self_.rows.len);
    assert(position >= self_.next_position);
    if position == none || self_.versions.len == none { return blot_error::Error.effect_limit; }
    let old = self_.variables.items[variable];
    let index = self_.versions.len as u32;
    var birth = none;
    if self_.physical_epoch < none { birth = self_.physical_epoch as u32; }
    self_.versions.push(Version { variable: variable, replacement: replacement_id, position: position, previous: old.last, birth: birth , ..});if self_.versions.failure!=blot_error::Error.none {return self_.versions.failure;}
    if old.last == none { self_.variables.items[variable].first = index; }
    else { self_.versions.items[old.last].next = index; }
    self_.variables.items[variable].last = index;
    self_.next_position = position + 1;
    tick(self_);
    return blot_error::Error.none;
}
fn replacementIndex(self_: const Store&, variable: u32, at: Cursor) -> u32, bool {
    var index = self_.variables.items[variable].first;
    if index == none { return 0, false; }
    if self_.versions.items[index].position >= at { return index, true; }
    if self_.versions.items[self_.variables.items[variable].last].position < at { return 0, false; }
    index = self_.versions.items[index].next;
    while index != none {
        let write = self_.versions.items[index];
        if write.position >= at { return index, true; }
        index = write.next;
    }
    return 0, false;
}
fn replacement(self_: const Store&, variable: u32, at: Cursor) -> Version, bool {
    let index, found = replacementIndex(self_, variable, at);
    if !found { return default<Version>(), false; }
    return self_.versions.items[index], true;
}
fn replacementAt(self_: const Store&, variable: u32, at: Cursor) -> Version, bool { return replacement(self_, variable, at); }
fn retainShortcut(self_: Store&, from: u32, to: u32) {
    assert(from < to);
    self_.versions.items[from].shortcut = to;
    self_.versions.items[from].shortcut_birth = self_.versions.items[to].birth;
}
fn shortcut(self_: Store&, first: u32) -> u32 {
    var current = first;
    loop {
        let link = self_.versions.items[current];
        if link.shortcut >= self_.versions.len || self_.versions.items[link.shortcut].birth != link.shortcut_birth { break; }
        assert(current < link.shortcut);
        current = link.shortcut;
    }
    if current != first { retainShortcut(self_, first, current); }
    return current;
}
fn resolve(self_: Store&, root: Id, at: Cursor) -> Id, Error {
    match node(self_, root).tail { variable => {}, _ => { return root, blot_error::Error.none; }, }
    if !self_.use_resolution_cache || at != 0 || root == 0 ||
       self_.physical_epoch >= none || self_.mutation_epoch >= none {
        return resolveUncached(self_, root, at);
    }
    if self_.resolved_physical != self_.physical_epoch {
        self_.resolved.clear(); self_.resolved_high_water = 0;
        self_.resolved_physical = self_.physical_epoch;
    }
    var previous = root;
    block {
        let entry = self_.resolved.get(root);
        if entry { previous = entry; }
    }
    if previous != root {
        match node(self_, previous).tail { variable => {}, _ => { return previous, blot_error::Error.none; }, }
    }
    let result, error = resolveUncached(self_, previous, at);
    if error != blot_error::Error.none { return 0, error; }
    if previous != root && result == previous { return result, blot_error::Error.none; }
    if result == root && root >= self_.resolved_high_water { return result, blot_error::Error.none; }
    self_.resolved.insert(root, result);if self_.resolved.failure!=blot_error::Error.none {return 0,self_.resolved.failure;}
    if root >= self_.resolved_high_water { self_.resolved_high_water = root + 1; }
    return result, blot_error::Error.none;
}
fn resolveUncached(self_: Store&, root: Id, at: Cursor) -> Id, Error {
    let original = node(self_, root);
    match original.tail { variable => {}, _ => { return root, blot_error::Error.none; }, }
    var position = max(at, original.cursor);
    var current = original;
    var labels: Label[>..] = [];
    var single = List {..};
    var fragments: i64 = 0;
    var changed = false;
    let cache_versions = self_.use_resolution_cache && self_.physical_epoch < none && self_.mutation_epoch < none;
    var prefix = none;
    loop {
        var variable: u32 = 0;
        match current.tail { variable v => { variable = v.value; }, _ => { break; }, }
        position = max(position, current.cursor);
        let first, found = replacementIndex(self_, variable, position);
        if !found { break; }
        if current.labels.len != 0 {
            prefix = none;
            if fragments == 0 { single = current.labels; }
            else {
                if fragments == 1 { labels.append(list(self_, single)); }
                labels.append(list(self_, current.labels));
            }
            fragments += 1;
        }
        var index = first;
        if cache_versions { index = shortcut(self_, first); }
        if cache_versions {
            if prefix != none { retainShortcut(self_, prefix, index); }
            else { prefix = first; }
        }
        let write = self_.versions.items[index];
        current = node(self_, write.replacement);
        position = write.position + 1;
        changed = true;
    }
    if !changed {
        if position == original.cursor { return root, blot_error::Error.none; }
        return add(self_, Row { original.labels, original.tail, position , ..});
    }
    if current.labels.len != 0 {
        if fragments == 0 { single = current.labels; }
        else {
            if fragments == 1 { labels.append(list(self_, single)); }
            labels.append(list(self_, current.labels));
        }
        fragments += 1;
    }
    if fragments <= 1 {
        if single.len == 0 && current.tail == Tail.closed { return 0, blot_error::Error.none; }
        return add(self_, Row { single, current.tail, position , ..});
    }
    let result, error = row(self_, labels, current.tail);
    if error != blot_error::Error.none { return 0, error; }
    if result != 0 { self_.rows.items[result].cursor = position; }
    return result, blot_error::Error.none;
}
fn bind(self_: Store&, variable: u32, replacement_id: Id) -> Error {
    let point = mark(self_);
    let resolved, error = resolve(self_, replacement_id, 0);
    if error != blot_error::Error.none { rollback(self_, point); return error; }
    match node(self_, resolved).tail {
        variable v => { if v.value == variable { rollback(self_, point); return blot_error::Error.infinite_effect; } },
        _ => {},
    }
    let written = appendVersion(self_, variable, resolved);
    if written != blot_error::Error.none { rollback(self_, point); }
    return written;
}
fn extractInner(self_: Store&, root: Id, label: Label) -> Extraction, Error {
    let view, error = extractView(self_, node(self_, root), label);
    if error != blot_error::Error.none { return default<Extraction>(), error; }
    var remaining: Id = 0;
    if view.saved.present { remaining = view.saved.value; }
    else if view.remaining.labels.len != 0 || view.remaining.tail != Tail.closed {
        let result, added = add(self_, view.remaining);
        if added != blot_error::Error.none { return default<Extraction>(), added; }
        remaining = result;
    }
    return Extraction { remaining, view.expanded , ..}, blot_error::Error.none;
}
fn extract(self_: Store&, root: Id, label: Label) -> Extraction, Error {
    let point = mark(self_);
    let resolved, error = resolve(self_, root, 0);
    if error != blot_error::Error.none { rollback(self_, point); return default<Extraction>(), error; }
    let result, extracted = extractInner(self_, resolved, label);
    if extracted != blot_error::Error.none { rollback(self_, point); }
    return result, extracted;
}
fn resolveView(self_: Store&, value: Row) -> Row, Error {
    var variable: u32 = 0;
    match value.tail { variable v => { variable = v.value; }, _ => { return value, blot_error::Error.none; }, }
    let write, found = replacement(self_, variable, value.cursor);
    if !found { return value, blot_error::Error.none; }
    let added, error = add(self_, value);
    if error != blot_error::Error.none { return default<Row>(), error; }
    let resolved, resolution = resolve(self_, added, 0);
    if resolution != blot_error::Error.none { return default<Row>(), resolution; }
    return node(self_, resolved), blot_error::Error.none;
}
fn extractView(self_: Store&, value: Row, label: Label) -> ExtractionView, Error {
    let labels = list(self_, value.labels);
    for candidate, index in labels {
        if candidate != label { continue; }
        if index == 0 || index + 1 == labels.len {
            var start = value.labels.start;
            if index == 0 { start += 1; }
            return ExtractionView { Row { List { start, value.labels.len - 1 }, value.tail } , ..}, blot_error::Error.none;
        }
        var remaining: Label[>..] = [];
        remaining.append(labels[..index]); remaining.append(labels[index + 1..]);
        let saved, error = row(self_, remaining, value.tail);
        if error != blot_error::Error.none { return default<ExtractionView>(), error; }
        return ExtractionView { remaining: node(self_, saved), saved: blot_support::Option<Id> { true, saved , ..} , ..}, blot_error::Error.none;
    }
    var variable: u32 = 0;
    match value.tail {
        variable v => { variable = v.value; },
        _ => { return default<ExtractionView>(), blot_error::Error.effect_mismatch; },
    }
    let tail, error = fresh(self_);
    if error != blot_error::Error.none { return default<ExtractionView>(), error; }
    let replacement_id, added = row(self_, [label], node(self_, tail).tail);
    if added != blot_error::Error.none { return default<ExtractionView>(), added; }
    let written = appendVersion(self_, variable, replacement_id);
    if written != blot_error::Error.none { return default<ExtractionView>(), written; }
    return ExtractionView { remaining: Row { value.labels, node(self_, tail).tail, value.cursor },
        expanded: blot_support::Option<u32> { true, variable , ..} , ..}, blot_error::Error.none;
}
fn unify(self_: Store&, left: Id, right: Id) -> Error {
    let point = mark(self_);
    let error = unifyInner(self_, left, right);
    if error != blot_error::Error.none { rollback(self_, point); }
    return error;
}
fn unifyInner(self_: Store&, left: Id, right: Id) -> Error {
    let first, first_error = resolve(self_, left, 0);
    if first_error != blot_error::Error.none { return first_error; }
    let second, second_error = resolve(self_, right, 0);
    if second_error != blot_error::Error.none { return second_error; }
    var a = node(self_, first); var b = node(self_, second);
    var work: i64 = 0;
    loop {
        if work == 65536 { return blot_error::Error.effect_limit; }
        work += 1;
        if a.labels.len == 0 && b.labels.len == 0 && a.tail == b.tail { return blot_error::Error.none; }
        if a.labels.len == 0 {
            match a.tail { variable v => {
                let added, error = add(self_, b); if error != blot_error::Error.none { return error; }
                return bind(self_, v.value, added);
            }, _ => {}, }
        }
        if b.labels.len == 0 {
            match b.tail { variable v => {
                let added, error = add(self_, a); if error != blot_error::Error.none { return error; }
                return bind(self_, v.value, added);
            }, _ => {}, }
        }
        if a.labels.len == 0 { return blot_error::Error.effect_mismatch; }
        let selected, error = extractView(self_, b, list(self_, a.labels)[0]);
        if error != blot_error::Error.none { return error; }
        if selected.expanded.present {
            match a.tail { variable v => {
                if v.value == selected.expanded.value { return blot_error::Error.infinite_effect; }
            }, _ => {}, }
        }
        let advanced, first_advance = resolveView(self_, Row { List { a.labels.start + 1, a.labels.len - 1 }, a.tail, a.cursor , ..});
        if first_advance != blot_error::Error.none { return first_advance; }
        a = advanced;
        let selected_row, second_advance = resolveView(self_, selected.remaining);
        if second_advance != blot_error::Error.none { return second_advance; }
        b = selected_row;
    }
}
fn substitute(self_: Store&, root: Id, variable: u32, replacement_id: Id) -> Id, Error {
    match node(self_, root).tail { variable v => {
        if v.value == variable { return replaceTail(self_, root, replacement_id); }
    }, _ => {}, }
    return root, blot_error::Error.none;
}
fn substituteParameter(self_: Store&, root: Id, parameter: u32, replacement_id: Id) -> Id, Error {
    match node(self_, root).tail { parameter v => {
        if v.value == parameter { return replaceTail(self_, root, replacement_id); }
    }, _ => {}, }
    return root, blot_error::Error.none;
}
fn substituteFormal(self_: Store&, root: Id, formal: u32, replacement_id: Id) -> Id, Error {
    match node(self_, root).tail { formal v => {
        if v.value == formal { return replaceTail(self_, root, replacement_id); }
    }, _ => {}, }
    return root, blot_error::Error.none;
}
fn replaceTail(self_: Store&, root: Id, replacement_id: Id) -> Id, Error {
    let original = node(self_, root); let replacement_ = node(self_, replacement_id);
    var labels: Label[>..] = [];
    labels.append(list(self_, original.labels)); labels.append(list(self_, replacement_.labels));
    let result, error = row(self_, labels, replacement_.tail);
    if error != blot_error::Error.none { return 0, error; }
    if result != 0 { self_.rows.items[result].cursor = max(original.cursor, replacement_.cursor); }
    return result, blot_error::Error.none;
}
fn operationSet(self_: const Store&, root: Id) -> Label[>..], Error {
    let value = node(self_, root);
    if value.tail != Tail.closed { return [], blot_error::Error.effect_mismatch; }
    var labels: Label[>..] = [];
    labels.append(list(self_, value.labels));
    sort(labels);
    var result: Label[>..] = [];
    for label in labels {
        if result.len != 0 && result[result.len - 1] == label { continue; }
        result.push(label);
    }
    return result, blot_error::Error.none;
}
fn tailCode(value: Tail) -> u32 { match value { closed => { return 0; }, variable => { return 1; }, parameter => { return 2; }, formal => { return 3; }, } }
fn tailFromCode(code: u32, value: u32) -> Tail, Error {
    match code { 0 => { return Tail.closed, blot_error::Error.none; }, 1 => { return Tail.variable { value , ..}, blot_error::Error.none; }, 2 => { return Tail.parameter { value , ..}, blot_error::Error.none; }, 3 => { return Tail.formal { value , ..}, blot_error::Error.none; }, _ => { return Tail.closed, blot_error::Error.invalid_artifact; }, }
}
fn blot_structural::equal(left: blot_check_effects::Tail, right: blot_check_effects::Tail) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_effects::Tail) {
    blot_structural::hash(sink, blot_check_effects::tailCode(value) as! u8);
    match value { closed => {}, variable v => { blot_structural::hash(sink, v.value); }, parameter v => { blot_structural::hash(sink, v.value); }, formal v => { blot_structural::hash(sink, v.value); }, }
}

struct ScalarDefaults {
physical_epoch:u64=0,
mutation_epoch:u64=0,
resolved_physical:u64=0xffffffffffffffff,
resolved_high_water:u32=0,
use_resolution_cache:bool=true,
next_position:Cursor=0,
}
var inactive_scalars=ScalarDefaults{..};
struct OwnerState {generation:u64=0,live:bool=false,
rows:Table_rows=Table_rows{..},
labels:Table_labels=Table_labels{..},
variables:Table_variables=Table_variables{..},
versions:Table_versions=Table_versions{..},
resolved:Map_resolved=Map_resolved{..},
physical_epoch:u64=0,
mutation_epoch:u64=0,
resolved_physical:u64=0xffffffffffffffff,
resolved_high_water:u32=0,
use_resolution_cache:bool=true,
next_position:Cursor=0,
}
var inactive_rows=Table_rows{..};
var inactive_labels=Table_labels{..};
var inactive_variables=Table_variables{..};
var inactive_versions=Table_versions{..};
var inactive_resolved=Map_resolved{..};






reusable var owner_states:OwnerState[>..]=[];
var next_owner_generation:u64=1;

struct Table_rows {storage:Row[:]=default<Row[:]>(),items:Row[:]=default<Row[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_rows:Row[>..];
fn ensure(self_:Table_rows&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_rows);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_rows&,value:Row) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_rows);self_.len=self_.items.len;}
fn append(self_:Table_rows&,values:const Row[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_rows);self_.len=self_.items.len;}
fn resize(self_:Table_rows&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_rows&,length:i64,value:Row) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_rows&)->Row {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_rows&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_rows&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_rows&) {blot_support_pooled_buffer::deinit(self_,pool_Table_rows);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_rows&,value:const Row&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_rows&,values:const Row[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_labels {storage:Label[:]=default<Label[:]>(),items:Label[:]=default<Label[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_labels:Label[>..];
fn ensure(self_:Table_labels&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_labels);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_labels&,value:Label) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_labels);self_.len=self_.items.len;}
fn append(self_:Table_labels&,values:const Label[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_labels);self_.len=self_.items.len;}
fn resize(self_:Table_labels&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_labels&,length:i64,value:Label) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_labels&)->Label {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_labels&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_labels&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_labels&) {blot_support_pooled_buffer::deinit(self_,pool_Table_labels);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_labels&,value:const Label&)->i64 {for &item,index in self_.items {if item .== value {return index;}}return -1;}
fn restore(self_:Table_labels&,values:const Label[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_variables {storage:Variable[:]=default<Variable[:]>(),items:Variable[:]=default<Variable[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_variables:Variable[>..];
fn ensure(self_:Table_variables&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_variables);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_variables&,value:Variable) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_variables);self_.len=self_.items.len;}
fn append(self_:Table_variables&,values:const Variable[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_variables);self_.len=self_.items.len;}
fn resize(self_:Table_variables&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_variables&,length:i64,value:Variable) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_variables&)->Variable {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_variables&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_variables&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_variables&) {blot_support_pooled_buffer::deinit(self_,pool_Table_variables);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_variables&,value:const Variable&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_variables&,values:const Variable[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_versions {storage:Version[:]=default<Version[:]>(),items:Version[:]=default<Version[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_versions:Version[>..];
fn ensure(self_:Table_versions&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_versions);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_versions&,value:Version) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_versions);self_.len=self_.items.len;}
fn append(self_:Table_versions&,values:const Version[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_versions);self_.len=self_.items.len;}
fn resize(self_:Table_versions&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_versions&,length:i64,value:Version) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_versions&)->Version {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_versions&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_versions&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_versions&) {blot_support_pooled_buffer::deinit(self_,pool_Table_versions);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_versions&,value:const Version&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_versions&,values:const Version[:])->Error {self_.clear();self_.append(values);return self_.failure;}
struct Map_resolved { count: i64 = 0, failure:Error=blot_error::Error.none, slots: dictionary_slot<Id,Id>[:] = default<dictionary_slot<Id,Id>[:]>() }
fn probe(map: const Map_resolved&,key: Id) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_resolved&,key: Id) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_resolved&,key: Id) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<Id,Id>[:]) { if slots.len != 0 { pool_Map_resolved.free_slice(slots); } }
fn grow(map: Map_resolved&,capacity: i64) {
    if map.failure != blot_error::Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return; }
    let replacement = pool_Map_resolved.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_resolved&,key: Id,value: Id) -> bool {
    if map.failure != blot_error::Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != blot_error::Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<Id,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<Id,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_resolved&,key: Id) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_resolved&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_resolved&) { release(map.slots); map.slots=default<dictionary_slot<Id,Id>[:]>(); map.count = 0;map.failure=blot_error::Error.none; }
fn clone(map: const Map_resolved&) -> Map_resolved { var copy = Map_resolved {..}; if map.slots.len != 0 { let slots = pool_Map_resolved.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_resolved&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_resolved:dictionary_slot<Id,Id>[>..];
fn restore(map:Map_resolved&,slots:const dictionary_slot<Id,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}let run=pool_Map_resolved.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return blot_error::Error.none;}
fn valid(self_:const Store&)->bool {return self_.lease!=0 && self_.lease-1<owner_states.len && owner_states[self_.lease-1].live && owner_states[self_.lease-1].generation==self_.owner_generation;}
fn initPooled(options:Options=Options{..})->Store,Error {if next_owner_generation==0xffffffffffffffff || owner_states.len>=0xffffffff {return Store{..},blot_error::Error.out_of_memory;}let generation=next_owner_generation;next_owner_generation+=1;let index=owner_states.alloc_index(OwnerState{generation:generation,live:true, ..});let state:OwnerState& =owner_states[index];var self_=Store{lease:(index+1) as u32,owner_generation:generation,rows:state.rows,labels:state.labels,variables:state.variables,versions:state.versions,resolved:state.resolved,physical_epoch:state.physical_epoch,mutation_epoch:state.mutation_epoch,resolved_physical:state.resolved_physical,resolved_high_water:state.resolved_high_water,use_resolution_cache:state.use_resolution_cache,next_position:state.next_position, ..};self_.use_resolution_cache=options.resolution_cache;self_.rows.push(Row{..});if self_.rows.failure!=blot_error::Error.none {let error=self_.rows.failure;self_.deinit();return Store{..},error;}return self_,blot_error::Error.none;}
fn init()->Store,Error {return initPooled();}
fn initWithOptions(options:Options)->Store,Error {return initPooled(options);}
fn deinit(self_:Store&) {if self_.lease==0 {return;}assert(valid(self_));self_.rows.deinit();self_.labels.deinit();self_.variables.deinit();self_.versions.deinit();self_.resolved.deinit();let index=self_.lease-1;owner_states[index].live=false;owner_states.free(index);self_=Store{..};}
fn withStore<C,F>(context:C&)->Error {let initialized,error=initPooled();if error!=blot_error::Error.none {return error;}var store=initialized;let result=F(context,store);store.deinit();return result;}
fn withStoreValue<C,R,F>(context:C&)->R,Error {let initialized,error=initPooled();if error!=blot_error::Error.none {return default<R>(),error;}var store=initialized;let result,failure=F(context,store);store.deinit();return result,failure;}
