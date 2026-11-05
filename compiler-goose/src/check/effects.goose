// Flat rows and chronological substitutions. Graph IDs retain Zig ordinals.
namespace blot_check_effects;
import support.structural;
import std;
import dictionary;
import support.error;
import support.option;

type Id = u32;
type Label = u32;
type Cursor = u32;
type Error = blot_error::Error;
let formal_key_bit: u32 = 0x80000000;
let none: u32 = 0xffffffff;
struct List { start: u32 = 0, len: u32 = 0 }
enum Tail { closed, variable { value: u32 }, parameter { value: u32 }, formal { value: u32 } }
struct Row { labels: List = List {}, tail: Tail = Tail.closed, cursor: Cursor = 0 }
struct Variable { first: u32 = none, last: u32 = none }
struct Version {
    variable: u32, replacement: Id, position: Cursor, previous: u32,
    next: u32 = none, birth: u32 = none, shortcut: u32 = none,
    shortcut_birth: u32 = none,
}
struct Mark { rows: i64, labels: i64, variables: i64, versions: i64, next_position: Cursor }
struct Extraction { remaining: Id, expanded: blot_support::Option<u32> = blot_support::Option<u32> { false, 0 } }
struct ExtractionView {
    remaining: Row,
    expanded: blot_support::Option<u32> = blot_support::Option<u32> { false, 0 },
    saved: blot_support::Option<Id> = blot_support::Option<Id> { false, 0 },
}
struct Options { resolution_cache: bool = true }
// All table owners live in the compilation/session driver.
struct Store {lease:u32=0,owner_generation:u64=0,
rows:Table_rows&=inactive_rows,
labels:Table_labels&=inactive_labels,
variables:Table_variables&=inactive_variables,
versions:Table_versions&=inactive_versions,
resolved:Map_resolved&=inactive_resolved,
physical_epoch:(u64)&=inactive_scalars.physical_epoch,
mutation_epoch:(u64)&=inactive_scalars.mutation_epoch,
resolved_physical:(u64)&=inactive_scalars.resolved_physical,
resolved_high_water:(u32)&=inactive_scalars.resolved_high_water,
use_resolution_cache:(bool)&=inactive_scalars.use_resolution_cache,
next_position:(Cursor)&=inactive_scalars.next_position,
}



fn node(self: const Store&, id: Id) -> Row { return self.rows.items[id]; }
fn list(self: const Store&, span: List) -> const Label[:] {
    return self.labels.items[span.start..span.start + span.len];
}
fn mark(self: const Store&) -> Mark {
    return Mark { self.rows.len, self.labels.len, self.variables.len, self.versions.len, self.next_position };
}
fn tick(self: Store&) { if self.mutation_epoch != 0xffffffffffffffff { self.mutation_epoch += 1; } }
fn rollback(self: Store&, point: Mark) {
    if self.physical_epoch != 0xffffffffffffffff { self.physical_epoch += 1; }
    tick(self);
    while self.versions.len > point.versions {
        let write = self.versions.pop();
        self.variables.items[write.variable].last = write.previous;
        if write.previous == none { self.variables.items[write.variable].first = none; }
        else { self.versions.items[write.previous].next = none; }
    }
    self.rows.pop_n(self.rows.len - point.rows);
    self.labels.pop_n(self.labels.len - point.labels);
    self.variables.pop_n(self.variables.len - point.variables);
    self.next_position = point.next_position;
}
fn add(self: Store&, value: Row) -> Id, Error {
    if self.rows.len == none { return 0, Error.effect_limit; }
    let id = self.rows.len as u32;
    self.rows.push(value);if self.rows.failure!=Error.none {return 0,self.rows.failure;}
    return id, Error.none;
}
fn row(self: Store&, labels: const Label[:], tail: Tail) -> Id, Error {
    if labels.len == 0 && tail == Tail.closed { return 0, Error.none; }
    if labels.len > 0 {
        let start = self.labels.index_of(labels[0]);
        if start >= 0 && labels.len <= self.labels.len - start {
            return add(self, Row { List { start as u32, labels.len as u32 }, tail });
        }
    }
    if labels.len > none - self.labels.len { return 0, Error.effect_limit; }
    let start = self.labels.len;
    self.labels.append(labels);if self.labels.failure!=Error.none {return 0,self.labels.failure;}
    let result, error = add(self, Row { List { start as u32, labels.len as u32 }, tail });
    if error != Error.none { self.labels.pop_n(self.labels.len - start); }
    return result, error;
}
fn rowAt(self: Store&, labels: const Label[:], tail: Tail, at: Cursor) -> Id, Error {
    let result, error = row(self, labels, tail);
    if error != Error.none { return 0, error; }
    if result != 0 { self.rows.items[result].cursor = at; }
    return result, Error.none;
}
fn cursor(self: const Store&) -> Cursor { return self.next_position; }
fn freeVariables(self: Store&, root: Id) -> u32[>..], Error {
    let resolved, error = resolve(self, root, 0);
    if error != Error.none { return [], error; }
    var result: u32[>..] = [];
    match node(self, resolved).tail {
        variable v => { result.push(v.value); },
        _ => {},
    }
    return result, Error.none;
}
fn fresh(self: Store&) -> Id, Error {
    if self.variables.len >= formal_key_bit { return 0, Error.effect_limit; }
    let index = self.variables.len as u32;
    self.variables.push(Variable {});if self.variables.failure!=Error.none {return 0,self.variables.failure;}
    let result, error = row(self, [], Tail.variable { index });
    if error != Error.none { self.variables.pop(); }
    return result, error;
}
fn appendVersion(self: Store&, variable: u32, replacement_id: Id) -> Error {
    return appendVersionAt(self, variable, replacement_id, self.next_position);
}
fn appendVersionAt(self: Store&, variable: u32, replacement_id: Id, position: Cursor) -> Error {
    assert(variable < self.variables.len && replacement_id < self.rows.len);
    assert(position >= self.next_position);
    if position == none || self.versions.len == none { return Error.effect_limit; }
    let old = self.variables.items[variable];
    let index = self.versions.len as u32;
    var birth = none;
    if self.physical_epoch < none { birth = self.physical_epoch as u32; }
    self.versions.push(Version { variable, replacement_id, position, old.last, birth: birth });if self.versions.failure!=Error.none {return self.versions.failure;}
    if old.last == none { self.variables.items[variable].first = index; }
    else { self.versions.items[old.last].next = index; }
    self.variables.items[variable].last = index;
    self.next_position = position + 1;
    tick(self);
    return Error.none;
}
fn replacementIndex(self: const Store&, variable: u32, at: Cursor) -> u32, bool {
    var index = self.variables.items[variable].first;
    if index == none { return 0, false; }
    if self.versions.items[index].position >= at { return index, true; }
    if self.versions.items[self.variables.items[variable].last].position < at { return 0, false; }
    index = self.versions.items[index].next;
    while index != none {
        let write = self.versions.items[index];
        if write.position >= at { return index, true; }
        index = write.next;
    }
    return 0, false;
}
fn replacement(self: const Store&, variable: u32, at: Cursor) -> Version, bool {
    let index, found = replacementIndex(self, variable, at);
    if !found { return default<Version>(), false; }
    return self.versions.items[index], true;
}
fn replacementAt(self: const Store&, variable: u32, at: Cursor) -> Version, bool { return replacement(self, variable, at); }
fn retainShortcut(self: Store&, from: u32, to: u32) {
    assert(from < to);
    self.versions.items[from].shortcut = to;
    self.versions.items[from].shortcut_birth = self.versions.items[to].birth;
}
fn shortcut(self: Store&, first: u32) -> u32 {
    var current = first;
    loop {
        let link = self.versions.items[current];
        if link.shortcut >= self.versions.len || self.versions.items[link.shortcut].birth != link.shortcut_birth { break; }
        assert(current < link.shortcut);
        current = link.shortcut;
    }
    if current != first { retainShortcut(self, first, current); }
    return current;
}
fn resolve(self: Store&, root: Id, at: Cursor) -> Id, Error {
    match node(self, root).tail { variable => {}, _ => { return root, Error.none; }, }
    if !self.use_resolution_cache || at != 0 || root == 0 ||
       self.physical_epoch >= none || self.mutation_epoch >= none {
        return resolveUncached(self, root, at);
    }
    if self.resolved_physical != self.physical_epoch {
        self.resolved.clear(); self.resolved_high_water = 0;
        self.resolved_physical = self.physical_epoch;
    }
    var previous = root;
    block {
        let entry = self.resolved.get(root);
        if entry { previous = entry; }
    }
    if previous != root {
        match node(self, previous).tail { variable => {}, _ => { return previous, Error.none; }, }
    }
    let result, error = resolveUncached(self, previous, at);
    if error != Error.none { return 0, error; }
    if previous != root && result == previous { return result, Error.none; }
    if result == root && root >= self.resolved_high_water { return result, Error.none; }
    self.resolved.insert(root, result);if self.resolved.failure!=Error.none {return 0,self.resolved.failure;}
    if root >= self.resolved_high_water { self.resolved_high_water = root + 1; }
    return result, Error.none;
}
fn resolveUncached(self: Store&, root: Id, at: Cursor) -> Id, Error {
    let original = node(self, root);
    match original.tail { variable => {}, _ => { return root, Error.none; }, }
    var position = max(at, original.cursor);
    var current = original;
    var labels: Label[>..] = [];
    var single = List {};
    var fragments: i64 = 0;
    var changed = false;
    let cache_versions = self.use_resolution_cache && self.physical_epoch < none && self.mutation_epoch < none;
    var prefix = none;
    loop {
        var variable: u32 = 0;
        match current.tail { variable v => { variable = v.value; }, _ => { break; }, }
        position = max(position, current.cursor);
        let first, found = replacementIndex(self, variable, position);
        if !found { break; }
        if current.labels.len != 0 {
            prefix = none;
            if fragments == 0 { single = current.labels; }
            else {
                if fragments == 1 { labels.append(list(self, single)); }
                labels.append(list(self, current.labels));
            }
            fragments += 1;
        }
        var index = first;
        if cache_versions { index = shortcut(self, first); }
        if cache_versions {
            if prefix != none { retainShortcut(self, prefix, index); }
            else { prefix = first; }
        }
        let write = self.versions.items[index];
        current = node(self, write.replacement);
        position = write.position + 1;
        changed = true;
    }
    if !changed {
        if position == original.cursor { return root, Error.none; }
        return add(self, Row { original.labels, original.tail, position });
    }
    if current.labels.len != 0 {
        if fragments == 0 { single = current.labels; }
        else {
            if fragments == 1 { labels.append(list(self, single)); }
            labels.append(list(self, current.labels));
        }
        fragments += 1;
    }
    if fragments <= 1 {
        if single.len == 0 && current.tail == Tail.closed { return 0, Error.none; }
        return add(self, Row { single, current.tail, position });
    }
    let result, error = row(self, labels, current.tail);
    if error != Error.none { return 0, error; }
    if result != 0 { self.rows.items[result].cursor = position; }
    return result, Error.none;
}
fn bind(self: Store&, variable: u32, replacement_id: Id) -> Error {
    let point = mark(self);
    let resolved, error = resolve(self, replacement_id, 0);
    if error != Error.none { rollback(self, point); return error; }
    match node(self, resolved).tail {
        variable v => { if v.value == variable { rollback(self, point); return Error.infinite_effect; } },
        _ => {},
    }
    let written = appendVersion(self, variable, resolved);
    if written != Error.none { rollback(self, point); }
    return written;
}
fn extractInner(self: Store&, root: Id, label: Label) -> Extraction, Error {
    let view, error = extractView(self, node(self, root), label);
    if error != Error.none { return default<Extraction>(), error; }
    var remaining: Id = 0;
    if view.saved.present { remaining = view.saved.value; }
    else if view.remaining.labels.len != 0 || view.remaining.tail != Tail.closed {
        let result, added = add(self, view.remaining);
        if added != Error.none { return default<Extraction>(), added; }
        remaining = result;
    }
    return Extraction { remaining, view.expanded }, Error.none;
}
fn extract(self: Store&, root: Id, label: Label) -> Extraction, Error {
    let point = mark(self);
    let resolved, error = resolve(self, root, 0);
    if error != Error.none { rollback(self, point); return default<Extraction>(), error; }
    let result, extracted = extractInner(self, resolved, label);
    if extracted != Error.none { rollback(self, point); }
    return result, extracted;
}
fn resolveView(self: Store&, value: Row) -> Row, Error {
    var variable: u32 = 0;
    match value.tail { variable v => { variable = v.value; }, _ => { return value, Error.none; }, }
    let write, found = replacement(self, variable, value.cursor);
    if !found { return value, Error.none; }
    let added, error = add(self, value);
    if error != Error.none { return default<Row>(), error; }
    let resolved, resolution = resolve(self, added, 0);
    if resolution != Error.none { return default<Row>(), resolution; }
    return node(self, resolved), Error.none;
}
fn extractView(self: Store&, value: Row, label: Label) -> ExtractionView, Error {
    let labels = list(self, value.labels);
    for candidate, index in labels {
        if candidate != label { continue; }
        if index == 0 || index + 1 == labels.len {
            var start = value.labels.start;
            if index == 0 { start += 1; }
            return ExtractionView { Row { List { start, value.labels.len - 1 }, value.tail } }, Error.none;
        }
        var remaining: Label[>..] = [];
        remaining.append(labels[..index]); remaining.append(labels[index + 1..]);
        let saved, error = row(self, remaining, value.tail);
        if error != Error.none { return default<ExtractionView>(), error; }
        return ExtractionView { node(self, saved), saved: blot_support::Option<Id> { true, saved } }, Error.none;
    }
    var variable: u32 = 0;
    match value.tail {
        variable v => { variable = v.value; },
        _ => { return default<ExtractionView>(), Error.effect_mismatch; },
    }
    let tail, error = fresh(self);
    if error != Error.none { return default<ExtractionView>(), error; }
    let replacement_id, added = row(self, [label], node(self, tail).tail);
    if added != Error.none { return default<ExtractionView>(), added; }
    let written = appendVersion(self, variable, replacement_id);
    if written != Error.none { return default<ExtractionView>(), written; }
    return ExtractionView { Row { value.labels, node(self, tail).tail, value.cursor },
        expanded: blot_support::Option<u32> { true, variable } }, Error.none;
}
fn unify(self: Store&, left: Id, right: Id) -> Error {
    let point = mark(self);
    let error = unifyInner(self, left, right);
    if error != Error.none { rollback(self, point); }
    return error;
}
fn unifyInner(self: Store&, left: Id, right: Id) -> Error {
    let first, first_error = resolve(self, left, 0);
    if first_error != Error.none { return first_error; }
    let second, second_error = resolve(self, right, 0);
    if second_error != Error.none { return second_error; }
    var a = node(self, first); var b = node(self, second);
    var work: i64 = 0;
    loop {
        if work == 65536 { return Error.effect_limit; }
        work += 1;
        if a.labels.len == 0 && b.labels.len == 0 && a.tail == b.tail { return Error.none; }
        if a.labels.len == 0 {
            match a.tail { variable v => {
                let added, error = add(self, b); if error != Error.none { return error; }
                return bind(self, v.value, added);
            }, _ => {}, }
        }
        if b.labels.len == 0 {
            match b.tail { variable v => {
                let added, error = add(self, a); if error != Error.none { return error; }
                return bind(self, v.value, added);
            }, _ => {}, }
        }
        if a.labels.len == 0 { return Error.effect_mismatch; }
        let selected, error = extractView(self, b, list(self, a.labels)[0]);
        if error != Error.none { return error; }
        if selected.expanded.present {
            match a.tail { variable v => {
                if v.value == selected.expanded.value { return Error.infinite_effect; }
            }, _ => {}, }
        }
        let advanced, first_advance = resolveView(self, Row { List { a.labels.start + 1, a.labels.len - 1 }, a.tail, a.cursor });
        if first_advance != Error.none { return first_advance; }
        a = advanced;
        let selected_row, second_advance = resolveView(self, selected.remaining);
        if second_advance != Error.none { return second_advance; }
        b = selected_row;
    }
}
fn substitute(self: Store&, root: Id, variable: u32, replacement_id: Id) -> Id, Error {
    match node(self, root).tail { variable v => {
        if v.value == variable { return replaceTail(self, root, replacement_id); }
    }, _ => {}, }
    return root, Error.none;
}
fn substituteParameter(self: Store&, root: Id, parameter: u32, replacement_id: Id) -> Id, Error {
    match node(self, root).tail { parameter v => {
        if v.value == parameter { return replaceTail(self, root, replacement_id); }
    }, _ => {}, }
    return root, Error.none;
}
fn substituteFormal(self: Store&, root: Id, formal: u32, replacement_id: Id) -> Id, Error {
    match node(self, root).tail { formal v => {
        if v.value == formal { return replaceTail(self, root, replacement_id); }
    }, _ => {}, }
    return root, Error.none;
}
fn replaceTail(self: Store&, root: Id, replacement_id: Id) -> Id, Error {
    let original = node(self, root); let replacement_ = node(self, replacement_id);
    var labels: Label[>..] = [];
    labels.append(list(self, original.labels)); labels.append(list(self, replacement_.labels));
    let result, error = row(self, labels, replacement_.tail);
    if error != Error.none { return 0, error; }
    if result != 0 { self.rows.items[result].cursor = max(original.cursor, replacement_.cursor); }
    return result, Error.none;
}
fn operationSet(self: const Store&, root: Id) -> Label[>..], Error {
    let value = node(self, root);
    if value.tail != Tail.closed { return [], Error.effect_mismatch; }
    var labels: Label[>..] = [];
    labels.append(list(self, value.labels));
    sort(labels);
    var result: Label[>..] = [];
    for label in labels {
        if result.len != 0 && result[result.len - 1] == label { continue; }
        result.push(label);
    }
    return result, Error.none;
}
fn tailCode(value: Tail) -> u32 { match value { closed => { return 0; }, variable => { return 1; }, parameter => { return 2; }, formal => { return 3; }, } }
fn tailFromCode(code: u32, value: u32) -> Tail, Error {
    match code { 0 => { return Tail.closed, Error.none; }, 1 => { return Tail.variable { value }, Error.none; }, 2 => { return Tail.parameter { value }, Error.none; }, 3 => { return Tail.formal { value }, Error.none; }, _ => { return Tail.closed, Error.invalid_artifact; }, }
}
fn blot_structural::equal(left: blot_check_effects::Tail, right: blot_check_effects::Tail) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_effects::Tail) {
    blot_structural::hash(sink, blot_check_effects::tailCode(value) as! u8);
    match value { closed => {}, variable v => { blot_structural::hash(sink, v.value); }, parameter v => { blot_structural::hash(sink, v.value); }, formal v => { blot_structural::hash(sink, v.value); }, }
}

import support.pooled_buffer;
struct ScalarDefaults {
physical_epoch:u64=0,
mutation_epoch:u64=0,
resolved_physical:u64=0xffffffffffffffff,
resolved_high_water:u32=0,
use_resolution_cache:bool=true,
next_position:Cursor=0,
}
var inactive_scalars=ScalarDefaults{};
struct OwnerState {generation:u64=0,live:bool=false,
rows:Table_rows=Table_rows{},
labels:Table_labels=Table_labels{},
variables:Table_variables=Table_variables{},
versions:Table_versions=Table_versions{},
resolved:Map_resolved=Map_resolved{},
physical_epoch:u64=0,
mutation_epoch:u64=0,
resolved_physical:u64=0xffffffffffffffff,
resolved_high_water:u32=0,
use_resolution_cache:bool=true,
next_position:Cursor=0,
}
var inactive_rows=Table_rows{};
var inactive_labels=Table_labels{};
var inactive_variables=Table_variables{};
var inactive_versions=Table_versions{};
var inactive_resolved=Map_resolved{};






reusable var owner_states:OwnerState[>..]=[];
var next_owner_generation:u64=1;

struct Table_rows {storage:Row[:]=[],items:Row[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_rows:Row[>..];
fn ensure(self:Table_rows&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_rows);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_rows&,value:Row) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_rows);self.len=self.items.len;}
fn append(self:Table_rows&,values:const Row[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_rows);self.len=self.items.len;}
fn resize(self:Table_rows&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_rows&,length:i64,value:Row) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_rows&)->Row {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_rows&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_rows&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_rows&) {blot_support_pooled_buffer::deinit(self,pool_Table_rows);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_rows&,value:const Row&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_rows&,values:const Row[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_labels {storage:Label[:]=[],items:Label[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_labels:Label[>..];
fn ensure(self:Table_labels&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_labels);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_labels&,value:Label) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_labels);self.len=self.items.len;}
fn append(self:Table_labels&,values:const Label[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_labels);self.len=self.items.len;}
fn resize(self:Table_labels&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_labels&,length:i64,value:Label) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_labels&)->Label {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_labels&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_labels&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_labels&) {blot_support_pooled_buffer::deinit(self,pool_Table_labels);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_labels&,value:const Label&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_labels&,values:const Label[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_variables {storage:Variable[:]=[],items:Variable[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_variables:Variable[>..];
fn ensure(self:Table_variables&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_variables);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_variables&,value:Variable) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_variables);self.len=self.items.len;}
fn append(self:Table_variables&,values:const Variable[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_variables);self.len=self.items.len;}
fn resize(self:Table_variables&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_variables&,length:i64,value:Variable) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_variables&)->Variable {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_variables&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_variables&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_variables&) {blot_support_pooled_buffer::deinit(self,pool_Table_variables);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_variables&,value:const Variable&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_variables&,values:const Variable[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_versions {storage:Version[:]=[],items:Version[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_versions:Version[>..];
fn ensure(self:Table_versions&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_versions);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_versions&,value:Version) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_versions);self.len=self.items.len;}
fn append(self:Table_versions&,values:const Version[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_versions);self.len=self.items.len;}
fn resize(self:Table_versions&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_versions&,length:i64,value:Version) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_versions&)->Version {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_versions&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_versions&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_versions&) {blot_support_pooled_buffer::deinit(self,pool_Table_versions);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_versions&,value:const Version&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_versions&,values:const Version[:])->Error {self.clear();self.append(values);return self.failure;}
struct Map_resolved { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<Id,Id>[:] = [] }
fn probe(map: const Map_resolved&,key: Id) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_resolved&,key: Id) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_resolved&,key: Id) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<Id,Id>[:]) { if slots.len != 0 { pool_Map_resolved.free_slice(slots); } }
fn grow(map: Map_resolved&,capacity: i64) {
    if map.failure != Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return; }
    let replacement = pool_Map_resolved.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_resolved&,key: Id,value: Id) -> bool {
    if map.failure != Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<Id,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<Id,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_resolved&,key: Id) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_resolved&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_resolved&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const Map_resolved&) -> Map_resolved { var copy = Map_resolved {}; if map.slots.len != 0 { let slots = pool_Map_resolved.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_resolved&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_resolved:dictionary_slot<Id,Id>[>..];
fn restore(map:Map_resolved&,slots:const dictionary_slot<Id,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_Map_resolved.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
fn valid(self:const Store&)->bool {return self.lease!=0 && self.lease-1<owner_states.len && owner_states[self.lease-1].live && owner_states[self.lease-1].generation==self.owner_generation;}
fn initPooled(options:Options=Options{})->Store,Error {if next_owner_generation==0xffffffffffffffff || owner_states.len>=0xffffffff {return Store{},Error.out_of_memory;}let generation=next_owner_generation;next_owner_generation+=1;let index=owner_states.alloc_index(OwnerState{generation:generation,live:true});let state:OwnerState&=owner_states[index];var self=Store{lease:(index+1) as u32,owner_generation:generation,rows:state.rows,labels:state.labels,variables:state.variables,versions:state.versions,resolved:state.resolved,physical_epoch:state.physical_epoch,mutation_epoch:state.mutation_epoch,resolved_physical:state.resolved_physical,resolved_high_water:state.resolved_high_water,use_resolution_cache:state.use_resolution_cache,next_position:state.next_position,};self.use_resolution_cache=options.resolution_cache;self.rows.push(Row{});if self.rows.failure!=Error.none {let error=self.rows.failure;self.deinit();return Store{},error;}return self,Error.none;}
fn init()->Store,Error {return initPooled();}
fn initWithOptions(options:Options)->Store,Error {return initPooled(options);}
fn deinit(self:Store&) {if self.lease==0 {return;}assert(valid(self));self.rows.deinit();self.labels.deinit();self.variables.deinit();self.versions.deinit();self.resolved.deinit();let index=self.lease-1;owner_states[index].live=false;owner_states.free(index);self=Store{};}
fn withStore<C,F>(context:C&)->Error {let initialized,error=initPooled();if error!=Error.none {return error;}var store=initialized;let result=F(context,store);store.deinit();return result;}
fn withStoreValue<C,F,R>(context:C&)->R,Error {let initialized,error=initPooled();if error!=Error.none {return default<R>(),error;}var store=initialized;let result,failure=F(context,store);store.deinit();return result,failure;}
