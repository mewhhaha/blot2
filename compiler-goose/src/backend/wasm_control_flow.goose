namespace blot_backend_wasm_control_flow;
import std;
import .runtime_ir;

let absent: u32 = 4294967295;
struct Node { next: u32[2] = [absent, absent], first: u32 = absent }
struct Predecessor { from: u32, next: u32 }
struct Control { start: u32, alternate: u32 = absent }
struct Graph { nodes: Node[>..]&, predecessors: Predecessor[>..]&, valid: bool = true }
fn init(nodes: Node[>..]&, predecessors: Predecessor[>..]&, instructions: const blot_backend_runtime_ir::Instruction[:]) -> Graph {
    nodes.clear(); predecessors.clear();
    for index in 0..instructions.len + 1 { nodes.push(Node {}); }
    var graph = Graph { nodes: nodes, predecessors: predecessors };
    var ends: u32[>..] = []; var controls: Control[>..] = [];
    for index in 0..instructions.len { ends.push(absent); }
    for inst, index in instructions {
        let at = index as u32;
        if inst.op == blot_backend_runtime_ir::OP_block || inst.op == blot_backend_runtime_ir::OP_loop || inst.op == blot_backend_runtime_ir::OP_if_ { controls.push(Control { start: at }); }
        else if inst.op == blot_backend_runtime_ir::OP_else_ {
            if controls.len == 0 { graph.valid = false; return graph; }
            let top = controls.len - 1; let control = controls[top];
            if instructions[control.start].op != blot_backend_runtime_ir::OP_if_ || control.alternate != absent { graph.valid = false; return graph; }
            controls[top].alternate = at; nodes[control.start].next[1] = at + 1;
        } else if inst.op == blot_backend_runtime_ir::OP_end {
            if controls.len == 0 { graph.valid = false; return graph; }
            let control = controls.pop(); ends[control.start] = at;
            if control.alternate != absent { ends[control.alternate] = at; }
        }
    }
    if controls.len != 0 { graph.valid = false; return graph; }
    for inst, index in instructions {
        let at = index as u32; nodes[at].next[0] = at + 1;
        if inst.op == blot_backend_runtime_ir::OP_block || inst.op == blot_backend_runtime_ir::OP_loop || inst.op == blot_backend_runtime_ir::OP_if_ {
            controls.push(Control { start: at });
            if inst.op == blot_backend_runtime_ir::OP_if_ && nodes[at].next[1] == absent { nodes[at].next[1] = ends[at]; }
        } else if inst.op == blot_backend_runtime_ir::OP_else_ { nodes[at].next[0] = ends[at]; }
        else if inst.op == blot_backend_runtime_ir::OP_end { controls.pop(); }
        else if inst.op == blot_backend_runtime_ir::OP_br || inst.op == blot_backend_runtime_ir::OP_br_if {
            if inst.operand > controls.len { graph.valid = false; return graph; }
            var target = instructions.len as u32;
            if inst.operand != controls.len {
                let control = controls[controls.len - 1 - inst.operand];
                target = ends[control.start];
                if instructions[control.start].op == blot_backend_runtime_ir::OP_loop { target = control.start + 1; }
            }
            nodes[at].next[0] = target;
            if inst.op == blot_backend_runtime_ir::OP_br_if { nodes[at].next[1] = at + 1; }
        } else if inst.op == blot_backend_runtime_ir::OP_return_ || inst.op == blot_backend_runtime_ir::OP_unreachable_ { nodes[at].next[0] = instructions.len as u32; }
    }
    let node_count = nodes.len;
    for index in 0..node_count {
        let node = nodes[index];
        for next in node.next {
            if next == absent { continue; }
            predecessors.push(Predecessor { from: index as u32, next: nodes[next].first });
            nodes[next].first = (predecessors.len - 1) as u32;
        }
    }
    return graph;
}
fn markLive(graph: Graph&, marks: u32[:], stamp: u32, definition: u32, pending: u32[>..]&) {
    var cursor = 0;
    while cursor < pending.len {
        let at = pending[cursor]; cursor++;
        if at == definition { continue; }
        var edge = graph.nodes[at].first;
        while edge != absent {
            let previous = graph.predecessors[edge];
            if marks[previous.from] != stamp { marks[previous.from] = stamp; pending.push(previous.from); }
            edge = previous.next;
        }
    }
}
