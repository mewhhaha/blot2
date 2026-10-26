import os;
import frame_arena;
fn main(){assert(write_file("frame-arena.wasm",frame_arena::emit(-1)));assert(write_file("frame-trap.wasm",frame_arena::emit(0)));print("private frame-arena wasm emitted");}
