// Height ceilings memoize fully known physical layouts and semantic rows.
namespace blot_reuse_artifact_import;
import reuse.artifact_import;
import backend.layout;
import check.effect_evidence;
import support.error;
import support.option;
import support.pooled_buffer;
type KnowledgeKind = u8;
let knowledge_layout: KnowledgeKind = 0;
let knowledge_row: KnowledgeKind = 1;
struct KnowledgeFrame { kind: KnowledgeKind, id: u32, next: u32 = 0, argument: u32 = 0, ceiling: i16 = 127 }
struct KnowledgeChild { kind: KnowledgeKind, id: u32 }
struct ByteBuffer { storage: u8[:] = default<u8[:]>(), items: u8[:] = default<u8[:]>() }
struct FrameBuffer { storage: KnowledgeFrame[:] = default<KnowledgeFrame[:]>(), items: KnowledgeFrame[:] = default<KnowledgeFrame[:]>() }
reusable[] var knowledge_bytes: u8[>..] = [];
reusable[] var knowledge_frames: KnowledgeFrame[>..] = [];
fn resize(self_: ByteBuffer&, length: i64) -> Error { let old = self_.items.len; let error = blot_support_pooled_buffer::ensure(self_, length, knowledge_bytes); if error != blot_error::Error.none { return error; } for index in old..length { self_.storage[index] = 0; } self_.items = self_.storage[..length]; return blot_error::Error.none; }
fn clear(self_: ByteBuffer&) { self_.items = self_.storage[..0]; }
fn deinit(self_: ByteBuffer&) { blot_support_pooled_buffer::deinit(self_, knowledge_bytes); }
fn push(self_: FrameBuffer&, value: KnowledgeFrame) -> Error { return blot_support_pooled_buffer::push(self_, value, knowledge_frames); }
fn clear(self_: FrameBuffer&) { self_.items = self_.storage[..0]; }
fn deinit(self_: FrameBuffer&) { blot_support_pooled_buffer::deinit(self_, knowledge_frames); }
struct Knowledge { store: const blot_backend_layout::Store? = null, layouts: ByteBuffer = ByteBuffer {..}, rows: ByteBuffer = ByteBuffer {..}, frames: FrameBuffer = FrameBuffer {..} }
fn deinit(self_: Knowledge&) { self_.layouts.deinit(); self_.rows.deinit(); self_.frames.deinit(); self_.store .= null; }
fn table(self_: Knowledge&, kind: KnowledgeKind) -> ByteBuffer& { if kind == knowledge_layout { return self_.layouts; } return self_.rows; }
fn absent(store: const blot_backend_layout::Store&, kind: KnowledgeKind, id: u32) -> blot_support::Option<i16> {
    if kind == knowledge_layout { if id == 0 || id >= store.nodes.len { return blot_support::some(-1 as i16); } }
    else if id == blot_backend_layout::unknown_row || id >= blot_check_effect_evidence::view(store.effects).rows.len { return blot_support::some(-1 as i16); }
    return blot_support::none<i16>();
}
fn knownLayout(self_: Knowledge&, store: const blot_backend_layout::Store&, id: u32) -> bool, Error { let value, error = self_.ceiling(store, knowledge_layout, id); return value >= 0, error; }
fn knownRow(self_: Knowledge&, store: const blot_backend_layout::Store&, id: u32) -> bool, Error { let value, error = self_.ceiling(store, knowledge_row, id); return value >= 0, error; }
fn ceiling(self_: Knowledge&, store: const blot_backend_layout::Store&, kind: KnowledgeKind, id: u32) -> i16, Error {
    if self_.store .!= store { self_.layouts.clear(); self_.rows.clear(); self_.store .= store; }
    let missing = absent(store, kind, id); if missing.present { return missing.value, blot_error::Error.none; }
    let first = self_.layouts.resize(store.nodes.len); if first != blot_error::Error.none { return -1, first; } let second = self_.rows.resize(blot_check_effect_evidence::view(store.effects).rows.len); if second != blot_error::Error.none { return -1, second; }
    if self_.table(kind).items[id] >= 2 { return self_.table(kind).items[id] as i16 - 3, blot_error::Error.none; } assert(self_.frames.items.len == 0);
    let appended = self_.frames.push(KnowledgeFrame { kind, id , ..}); if appended != blot_error::Error.none { return -1, appended; } self_.table(kind).items[id] = 1;
    let error = self_.completeCeilings(store);
    if error != blot_error::Error.none { for frame in self_.frames.items { self_.table(frame.kind).items[frame.id] = 0; } self_.frames.clear(); return -1, error; }
    return self_.table(kind).items[id] as i16 - 3, blot_error::Error.none;
}
fn completeCeilings(self_: Knowledge&, store: const blot_backend_layout::Store&) -> Error {
    while self_.frames.items.len != 0 {
        let last = self_.frames.items.len - 1; let frame: KnowledgeFrame& = self_.frames.items[last]; let child = nextChild(store, frame);
        if !child.present {
            let value = max(frame.ceiling, -1 as i16); let done = frame; self_.frames.items = self_.frames.storage[..last]; self_.table(done.kind).items[done.id] = (value + 3) as u8;
            if last != 0 { self_.frames.items[last - 1].ceiling = min(self_.frames.items[last - 1].ceiling, value - 1); } continue;
        }
        var known = absent(store, child.value.kind, child.value.id);
        if !known.present { let stored = self_.table(child.value.kind).items[child.value.id]; if stored == 1 { known = blot_support::some(-1 as i16); } else if stored != 0 { known = blot_support::some(stored as i16 - 3); } }
        if known.present { frame.ceiling = min(frame.ceiling, known.value - 1); continue; }
        let error = self_.frames.push(KnowledgeFrame { child.value.kind, child.value.id , ..}); if error != blot_error::Error.none { return error; } self_.table(child.value.kind).items[child.value.id] = 1;
    } return blot_error::Error.none;
}
fn nextChild(store: const blot_backend_layout::Store&, frame: KnowledgeFrame&) -> blot_support::Option<KnowledgeChild> {
    let no = blot_support::none<KnowledgeChild>();
    if frame.kind == knowledge_row {
        let view = store.effects.view(); let labels = view.rowLabels(frame.id);
        while frame.next < labels.len { let arguments = view.operationArguments(labels[frame.next]); if frame.argument < arguments.len { frame.argument++; return blot_support::some(KnowledgeChild { knowledge_layout, arguments[frame.argument - 1] , ..}); } frame.next++; frame.argument = 0; } return no;
    }
    let n = store.node(frame.id); let index = frame.next; frame.next++;
    match n.tag {
        invalid, erased => { frame.ceiling = -1; return no; },
        function => { if index == 0 { return blot_support::some(KnowledgeChild { knowledge_row, n.c , ..}); } if index == 1 { return blot_support::some(KnowledgeChild { knowledge_layout, n.a , ..}); } if index == 2 { return blot_support::some(KnowledgeChild { knowledge_layout, n.b , ..}); } },
        provider => { if index == 0 { return blot_support::some(KnowledgeChild { knowledge_row, n.c , ..}); } if index == 1 { return blot_support::some(KnowledgeChild { knowledge_layout, n.a , ..}); } },
        array, list, cursor, resolver => { if index == 0 { return blot_support::some(KnowledgeChild { knowledge_layout, n.a , ..}); } },
        state_provider => { if index == 0 { return blot_support::some(KnowledgeChild { knowledge_layout, n.a , ..}); } if index == 1 { return blot_support::some(KnowledgeChild { knowledge_layout, n.b , ..}); } if index == 2 { return blot_support::some(KnowledgeChild { knowledge_layout, n.c , ..}); } },
        product, nominal => { let items = store.children(frame.id); if index < items.len { return blot_support::some(KnowledgeChild { knowledge_layout, items[index] , ..}); } },
        record => { let items = store.children(frame.id); let at = index as i64 * 2 + 1; if at < items.len { return blot_support::some(KnowledgeChild { knowledge_layout, items[at] , ..}); } },
        _ => {},
    } return no;
}
