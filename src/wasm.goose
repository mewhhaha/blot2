// Wasm32 binary encoder and K1 fixed-pool helper lowering.
namespace wasm;
import std;
import .model;
import .runtime;
import .abi;
import .wasm_validate;

const I32: u8 = 0x7f;
const F32: u8 = 0x7d;
const VOID: u8 = 0x40;
struct Sig { start: u32 = 0, count: u32 = 0, result: u8 = 0 }
struct Func { type_id: u32 = 0, start: u32 = 0, length: u32 = 0, role: u32 = 0, source: u32 = 0, own_frame: u32 = 0, frame: u32 = 0, depth: u32 = 0, contract: u32 = 0, indirect: Span = Span { .. } }
struct Ex { start: u32 = 0, length: u32 = 0, kind: u8 = 0, index: u32 = 0 }
struct ModuleBuilder {
  types: Sig[>..]&, parameters: u8[>..]&,
  functions: Func[>..]&, bodies: u8[>..]&,
  exports: Ex[>..]&, names: u8[>..]&,
  table: u32[>..]&, data: u8[>..]&, indirect_contracts: u32[>..]&,
  map: runtime::MemoryMap, telemetry: bool = false,
}
fn with_module<F>(map: runtime::MemoryMap) {
  var types: Sig[>..] = []; var parameters: u8[>..] = [];
  var functions: Func[>..] = []; var bodies: u8[>..] = [];
  var exports: Ex[>..] = []; var names: u8[>..] = [];
  var table: u32[>..] = []; var data: u8[>..] = []; var indirect_contracts: u32[>..] = [];
  var m = ModuleBuilder {types, parameters, functions, bodies, exports, names, table, data, indirect_contracts, map};
  F(m);
}
struct Helpers { validate: u32 = 0, mark: u32 = 0, reserve: u32 = 0,
  place: u32 = 0, release: u32 = 0, reset: u32 = 0, seal: u32 = 0, open: u32 = 0 }

fn uleb(out: u8[>..]&, value: u32) {
  var n = value;
  while n >= 128 { out.push(((n & 127) | 128) as! u8); n >>= 7; }
  out.push(n as! u8);
}
fn sleb(out: u8[>..]&, value: i64) {
  var n = value;
  while true {
    let byte = (n & 127) as u8;
    n >>= 7;
    if (n == 0 && (byte & 64) == 0) || (n == -1 && (byte & 64) != 0) {
      out.push(byte); break;
    }
    out.push(byte | 128);
  }
}
fn name(out: u8[>..]&, bytes: const u8[:]) { uleb(out, bytes.len as u32); out.append(bytes); }
fn section(out: u8[>..]&, id: u8, body: const u8[:]) {
  out.push(id); uleb(out, body.len as u32); out.append(body);
}
fn signature(m: ModuleBuilder&, params: const u8[:], result: u8) -> u32 {
  for t, i in m.types {
    if t.result == result && m.parameters[t.start..t.start + t.count] == params { return i as u32; }
  }
  let id = m.types.len as u32;
  m.types.push(Sig {m.parameters.len as u32, params.len as u32, result});
  m.parameters.append(params);
  return id;
}
fn function(m: ModuleBuilder&, sig: u32, body: const u8[:]) -> u32 {
  let id = m.functions.len as u32;
  m.functions.push(Func {sig, m.bodies.len as u32, body.len as u32});
  m.bodies.append(body);
  return id;
}
fn export_function(m: ModuleBuilder&, label: const u8[:], index: u32) {
  m.exports.push(Ex {m.names.len as u32, label.len as u32, 0, index});
  m.names.append(label);
}
fn export_memory(m: ModuleBuilder&) {
  m.exports.push(Ex {m.names.len as u32, 6, 2, 0}); m.names.append("memory");
}
fn local_declarations(b: u8[>..]&, count: u32, ty: u8) {
  uleb(b, if count == 0 { 0 } else { 1 });
  if count != 0 { uleb(b, count); b.push(ty); }
}
fn op(b: u8[>..]&, code: u8) { b.push(code); }
fn get(b: u8[>..]&, n: u32) { op(b, 0x20); uleb(b, n); }
fn set(b: u8[>..]&, n: u32) { op(b, 0x21); uleb(b, n); }
fn tee(b: u8[>..]&, n: u32) { op(b, 0x22); uleb(b, n); }
fn constant(b: u8[>..]&, n: u32) { op(b, 0x41); sleb(b, n as! i32); }
fn call(b: u8[>..]&, n: u32) { op(b, 0x10); uleb(b, n); }
fn branch(b: u8[>..]&, n: u32) { op(b, 0x0c); uleb(b, n); }
fn branch_if(b: u8[>..]&, n: u32) { op(b, 0x0d); uleb(b, n); }
fn begin_block(b: u8[>..]&) { op(b, 0x02); op(b, VOID); }
fn begin_loop(b: u8[>..]&) { op(b, 0x03); op(b, VOID); }
fn when(b: u8[>..]&) { op(b, 0x04); op(b, VOID); }
fn otherwise(b: u8[>..]&) { op(b, 0x05); }
fn end(b: u8[>..]&) { op(b, 0x0b); }
fn load(b: u8[>..]&, offset: u32) { op(b, 0x28); uleb(b, 2); uleb(b, offset); }
fn store(b: u8[>..]&, offset: u32) { op(b, 0x36); uleb(b, 2); uleb(b, offset); }
fn read_local(b: u8[>..]&, local: u32, offset: u32) { get(b, local); load(b, offset); }
fn put_const(b: u8[>..]&, local: u32, offset: u32, value: u32) {
  get(b, local); constant(b, value); store(b, offset);
}
fn put_local(b: u8[>..]&, local: u32, offset: u32, value: u32) {
  get(b, local); get(b, value); store(b, offset);
}
fn add_const(b: u8[>..]&, local: u32, value: u32) { get(b, local); constant(b, value); op(b, 0x6a); }
fn increment(b: u8[>..]&, local: u32, value: u32) { add_const(b, local, value); set(b, local); }
fn trap_if(b: u8[>..]&) { when(b); op(b, 0x00); end(b); }
fn return_if(b: u8[>..]&) { when(b); op(b, 0x0f); end(b); }
fn entry_address(b: u8[>..]&, slot: u32, m: runtime::MemoryMap) {
  get(b, slot); constant(b, 1); op(b, 0x6b); constant(b, 5); op(b, 0x74);
  constant(b, m.owners); op(b, 0x6a);
}

// Instrumentation is emitted only by the explicit telemetry mode. It uses no
// calls, extra frame slots, source authority, or unbounded backing storage.
fn telemetry_address(m:ModuleBuilder&,id:u32)->u32 { m.map.control+16+id*8 }
fn telemetry_add_const(m:ModuleBuilder&,b:u8[>..]&,id:u32,amount:u32) {
  if !m.telemetry || amount==0 { return; } let address=telemetry_address(m,id);
  constant(b,address); constant(b,address); load(b,0); constant(b,amount); op(b,0x6a); store(b,0);
  constant(b,address); load(b,0); constant(b,amount); op(b,0x49); when(b);
  constant(b,address); constant(b,address); load(b,4); constant(b,1); op(b,0x6a); store(b,4); end(b);
}
fn telemetry_add_local(m:ModuleBuilder&,b:u8[>..]&,id:u32,local:u32,scale:u32) {
  if !m.telemetry || scale==0 { return; } let address=telemetry_address(m,id);
  constant(b,address); constant(b,address); load(b,0); get(b,local); constant(b,scale); op(b,0x6c); op(b,0x6a); store(b,0);
  constant(b,address); load(b,0); get(b,local); constant(b,scale); op(b,0x6c); op(b,0x49); when(b);
  constant(b,address); constant(b,address); load(b,4); constant(b,1); op(b,0x6a); store(b,4); end(b);
}
fn telemetry_high_local(m:ModuleBuilder&,b:u8[>..]&,id:u32,local:u32,add:u32) {
  if !m.telemetry { return; } let address=telemetry_address(m,id);
  add_const(b,local,add); constant(b,address); load(b,0); op(b,0x4b); when(b);
  constant(b,address); add_const(b,local,add); store(b,0); end(b);
}
fn telemetry_backing(m:ModuleBuilder&,b:u8[>..]&,local:u32,release:bool) {
  if !m.telemetry { return; } let live=telemetry_address(m,runtime::T_BACKING_LIVE); let high=telemetry_address(m,runtime::T_BACKING_HIGH);
  constant(b,live); constant(b,live); load(b,0); get(b,local); op(b,if release {0x6b} else {0x6a}); store(b,0);
  if !release { constant(b,live); load(b,0); constant(b,high); load(b,0); op(b,0x4b); when(b); constant(b,high); constant(b,live); load(b,0); store(b,0); end(b); }
}
fn emit_telemetry_reader(m:ModuleBuilder&) {
  if !m.telemetry { return; }
  let sig=signature(m,[I32],I32); var b:u8[>..]=[]; local_declarations(b,0,I32);
  get(b,0); constant(b,runtime::TELEMETRY_COUNT*2); op(b,0x49); op(b,0x04); op(b,I32);
  get(b,0); constant(b,2); op(b,0x74); constant(b,m.map.control+16); op(b,0x6a); load(b,0);
  otherwise(b); constant(b,0); end(b); end(b);
  let index=function(m,sig,b); m.functions[index].role=7; m.functions[index].depth=1;
  export_function(m,"blot.telemetry",index);
}

fn encode(m: ModuleBuilder&, out: u8[>..]&) {
  out.append([0 as u8, 97, 115, 109, 1, 0, 0, 0]);
  { var b: u8[>..] = []; uleb(b, m.types.len as u32);
    for t in m.types {
      op(b, 0x60); uleb(b, t.count); b.append(m.parameters[t.start..t.start + t.count]);
      uleb(b, if t.result == 0 { 0 } else { 1 }); if t.result != 0 { op(b, t.result); }
    } section(out, 1, b);
  }
  { var b: u8[>..] = []; uleb(b, m.functions.len as u32);
    for f in m.functions { uleb(b, f.type_id); } section(out, 3, b);
  }
  if m.table.len != 0 {
    var b: u8[>..] = []; uleb(b, 1); op(b, 0x70); op(b, 1);
    uleb(b, m.table.len as u32); uleb(b, m.table.len as u32); section(out, 4, b);
  }
  { var b: u8[>..] = []; uleb(b, 1); op(b, 1);
    uleb(b, m.map.pages); uleb(b, m.map.pages); section(out, 5, b);
  }
  { var b: u8[>..] = []; uleb(b, m.exports.len as u32);
    for e in m.exports { name(b, m.names[e.start..e.start + e.length]); op(b, e.kind); uleb(b, e.index); }
    section(out, 7, b);
  }
  if m.table.len != 0 {
    var b: u8[>..] = []; uleb(b, 1); op(b, 0); constant(b, 0); end(b);
    uleb(b, m.table.len as u32); for f in m.table { uleb(b, f); } section(out, 9, b);
  }
  { var b: u8[>..] = []; uleb(b, m.functions.len as u32);
    for f in m.functions { uleb(b, f.length); b.append(m.bodies[f.start..f.start + f.length]); }
    section(out, 10, b);
  }
  if m.data.len != 0 {
    var b: u8[>..] = []; uleb(b, 1); op(b, 0); constant(b, m.map.static_base); end(b);
    uleb(b, m.data.len as u32); b.append(m.data); section(out, 11, b);
  }
}

fn emit_validate(m: ModuleBuilder&) -> u32 {
  let sig = signature(m, [I32, I32, I32, I32], I32);
  var b: u8[>..] = []; local_declarations(b, 2, I32);
  get(b, 0); op(b, 0x45); get(b, 0); constant(b, m.map.owner_slots); op(b, 0x4b); op(b, 0x72); trap_if(b);
  entry_address(b, 0, m.map); set(b, 4);
  read_local(b, 4, 16); get(b, 1); op(b, 0x47); trap_if(b);
  read_local(b, 4, 20); tee(b, 5); get(b, 2); op(b, 0x47);
  get(b, 5); get(b, 3); op(b, 0x47); op(b, 0x71); trap_if(b);
  get(b, 4); end(b);
  return function(m, sig, b);
}
fn emit_mark(m: ModuleBuilder&) -> u32 {
  // (first granule, count, used); complete words are updated once.
  let sig = signature(m, [I32, I32, I32], 0);
  var b: u8[>..] = []; local_declarations(b, 5, I32);
  begin_block(b); begin_loop(b);
  get(b, 1); op(b, 0x45); branch_if(b, 1);
  get(b, 0); constant(b, 31); op(b, 0x71); set(b, 3); // bit
  constant(b, 32); get(b, 3); op(b, 0x6b); set(b, 4); // take
  get(b, 1); get(b, 4); op(b, 0x49); when(b); get(b, 1); set(b, 4); end(b);
  get(b, 4); constant(b, 32); op(b, 0x46); when(b);
  constant(b, 0xffffffff); set(b, 5);
  otherwise(b); constant(b, 1); get(b, 4); op(b, 0x74); constant(b, 1); op(b, 0x6b);
  get(b, 3); op(b, 0x74); set(b, 5); end(b);
  get(b, 0); constant(b, 5); op(b, 0x76); constant(b, 2); op(b, 0x74);
  constant(b, m.map.bitmap); op(b, 0x6a); tee(b, 6); load(b, 0); set(b, 7);
  get(b, 2); when(b); get(b, 6); get(b, 7); get(b, 5); op(b, 0x72); store(b, 0);
  otherwise(b); get(b, 6); get(b, 7); get(b, 5); constant(b, 0xffffffff); op(b, 0x73); op(b, 0x71); store(b, 0); end(b);
  get(b, 0); get(b, 4); op(b, 0x6a); set(b, 0);
  get(b, 1); get(b, 4); op(b, 0x6b); set(b, 1);
  branch(b, 0); end(b); end(b); end(b);
  return function(m, sig, b);
}
fn emit_reserve(m: ModuleBuilder&, h: Helpers) -> u32 {
  // (out: Result[(Owner,Space), ReserveError]*, bytes, owned)
  let sig = signature(m, [I32, I32, I32], 0);
  var b: u8[>..] = []; local_declarations(b, 10, I32);
  telemetry_add_const(m,b,runtime::T_RESERVE_ATTEMPTS,1);
  // 3=requested,4=rounded,5=slot,6=entry,7=needed,8=scan,9=run,10=first,11=generation,12=base
  for i in 5 { put_const(b, 0, i as u32 * 4, 0); } put_const(b, 0, 0, 1);
  get(b, 1); set(b, 3);
  get(b, 2); when(b);
  get(b, 1); constant(b, 0xfffffeff); op(b, 0x4b); when(b); telemetry_add_const(m,b,runtime::T_RESERVE_FAILURE,1); op(b,0x0f); end(b);
  add_const(b, 1, 256); set(b, 3); end(b);
  get(b, 3); constant(b, 0xfffff000); op(b, 0x4b); when(b); telemetry_add_const(m,b,runtime::T_RESERVE_FAILURE,1); op(b,0x0f); end(b);
  add_const(b, 3, 4095); constant(b, 0xfffff000); op(b, 0x71); set(b, 4);
  constant(b, 1); set(b, 5);
  begin_block(b); begin_loop(b);
  get(b, 5); constant(b, m.map.owner_slots); op(b, 0x4b); when(b);
  put_const(b, 0, 4, 1); telemetry_add_const(m,b,runtime::T_RESERVE_FAILURE,1); op(b, 0x0f); end(b);
  entry_address(b, 5, m.map); set(b, 6);
  read_local(b, 6, 20); op(b, 0x45);
  read_local(b, 6, 16); constant(b, 0xffffffff); op(b, 0x47); op(b, 0x71); branch_if(b, 1);
  increment(b, 5, 1); branch(b, 0); end(b); end(b);
  get(b, 4); constant(b, 12); op(b, 0x76); set(b, 7);
  get(b, 7); when(b);
  begin_block(b); begin_loop(b);
  get(b, 8); constant(b, m.map.granules); op(b, 0x4f); when(b);
  put_const(b, 0, 4, 2); telemetry_add_const(m,b,runtime::T_RESERVE_FAILURE,1); op(b, 0x0f); end(b);
  get(b, 8); constant(b, 3); op(b, 0x76); constant(b, m.map.bitmap); op(b, 0x6a);
  op(b, 0x2d); uleb(b, 0); uleb(b, 0);
  constant(b, 1); get(b, 8); constant(b, 7); op(b, 0x71); op(b, 0x74); op(b, 0x71);
  when(b); constant(b, 0); set(b, 9);
  otherwise(b);
  get(b, 9); op(b, 0x45); when(b); get(b, 8); set(b, 10); end(b);
  increment(b, 9, 1); get(b, 9); get(b, 7); op(b, 0x46); branch_if(b, 2);
  end(b); increment(b, 8, 1); branch(b, 0); end(b); end(b);
  get(b, 10); constant(b, 12); op(b, 0x74); constant(b, m.map.pool); op(b, 0x6a); set(b, 12);
  end(b);
  get(b, 10); get(b, 7); constant(b, 1); call(b, h.mark);
  read_local(b, 6, 16); constant(b, 1); op(b, 0x6a); set(b, 11);
  put_local(b, 6, 0, 12); put_local(b, 6, 4, 3); put_local(b, 6, 8, 4);
  get(b, 6); get(b, 2); constant(b, 8); op(b, 0x74); store(b, 12);
  put_local(b, 6, 16, 11);
  get(b, 6); constant(b, 4); constant(b, 1); get(b, 2); op(b, 0x1b); store(b, 20);
  put_const(b, 6, 24, 0); put_const(b, 6, 28, 0);
  put_local(b, 0, 4, 5); put_local(b, 0, 8, 11); put_local(b, 0, 12, 5); put_local(b, 0, 16, 11);
  telemetry_add_const(m,b,runtime::T_RESERVE_SUCCESS,1); telemetry_backing(m,b,4,false);
  put_const(b, 0, 0, 0); end(b);
  return function(m, sig, b);
}
fn emit_place(m: ModuleBuilder&, h: Helpers) -> u32 {
  // (out: Result[(Space,Dest),(Space,AllocError)]*, slot, gen, count, size, align)
  let sig = signature(m, [I32, I32, I32, I32, I32, I32], 0);
  var b: u8[>..] = []; local_declarations(b, 4, I32);
  // 6=entry,7=top,8=requested,9=data
  get(b, 1); get(b, 2); constant(b, 1); constant(b, 4); call(b, h.validate); set(b, 6);
  get(b, 4); op(b, 0x45); when(b); get(b, 5); constant(b, 1); op(b, 0x47); trap_if(b);
  otherwise(b); get(b, 5); constant(b, 4); op(b, 0x47); trap_if(b);
  get(b, 4); constant(b, 1); op(b, 0x47); when(b);
  get(b, 4); constant(b, 3); op(b, 0x71); trap_if(b); end(b); end(b);
  put_const(b, 0, 0, 1); put_local(b, 0, 4, 1); put_local(b, 0, 8, 2);
  put_const(b, 0, 12, 0); put_const(b, 0, 16, 0);
  get(b, 3); op(b, 0x45); when(b); put_const(b, 0, 0, 0); op(b, 0x0f); end(b);
  get(b, 4); when(b);
  get(b, 3); constant(b, 0xffffffff); get(b, 4); op(b, 0x6e); op(b, 0x4b); return_if(b);
  read_local(b, 6, 12); set(b, 7);
  get(b, 7); constant(b, 0xfffffffc); op(b, 0x4b); return_if(b);
  add_const(b, 7, 3); constant(b, 0xfffffffc); op(b, 0x71); set(b, 7);
  read_local(b, 6, 4); set(b, 8);
  get(b, 7); get(b, 8); op(b, 0x4b); when(b); put_const(b, 0, 12, 1); op(b, 0x0f); end(b);
  get(b, 3); get(b, 8); get(b, 7); op(b, 0x6b); get(b, 4); op(b, 0x6e); op(b, 0x4b);
  when(b); put_const(b, 0, 12, 1); op(b, 0x0f); end(b);
  get(b, 3); when(b); read_local(b, 6, 0); get(b, 7); op(b, 0x6a); set(b, 9); end(b);
  get(b, 6); get(b, 7); get(b, 3); get(b, 4); op(b, 0x6c); op(b, 0x6a); store(b, 12);
  end(b);
  put_local(b, 0, 12, 9); put_local(b, 0, 16, 3); put_const(b, 0, 0, 0); end(b);
  return function(m, sig, b);
}
fn emit_release(m: ModuleBuilder&, h: Helpers) -> u32 {
  let sig = signature(m, [I32, I32, I32], 0);
  var b: u8[>..] = []; local_declarations(b, 2, I32);
  get(b, 2); constant(b, 1); op(b, 0x47); get(b, 2); constant(b, 2); op(b, 0x47); op(b, 0x71);
  get(b, 2); constant(b, 4); op(b, 0x47); op(b, 0x71); trap_if(b);
  get(b, 0); get(b, 1); get(b, 2); get(b, 2); call(b, h.validate); set(b, 3);
  read_local(b, 3, 8); tee(b, 4); when(b);
  read_local(b, 3, 0); constant(b, m.map.pool); op(b, 0x6b); constant(b, 12); op(b, 0x76);
  get(b, 4); constant(b, 12); op(b, 0x76); constant(b, 0); call(b, h.mark); end(b);
  telemetry_add_const(m,b,runtime::T_RELEASES,1); telemetry_backing(m,b,4,true);
  for i in 8 { if i != 4 { put_const(b, 3, i as u32 * 4, 0); } }
  get(b, 1); constant(b, 0xffffffff); op(b, 0x46); when(b); put_const(b, 3, 20, 3); end(b);
  end(b); return function(m, sig, b);
}
fn emit_reset(m: ModuleBuilder&, h: Helpers) -> u32 {
  let sig = signature(m, [I32, I32], 0);
  var b: u8[>..] = []; local_declarations(b, 1, I32);
  get(b, 0); get(b, 1); constant(b, 1); constant(b, 1); call(b, h.validate); set(b, 2);
  telemetry_add_const(m,b,runtime::T_RESETS,1);
  put_const(b, 2, 12, 0); end(b); return function(m, sig, b);
}
fn emit_seal(m: ModuleBuilder&, h: Helpers) -> u32 {
  let sig = signature(m, [I32, I32, I32, I32, I32], 0);
  var b: u8[>..] = []; local_declarations(b, 3, I32);
  get(b, 0); get(b, 1); constant(b, 4); constant(b, 4); call(b, h.validate); set(b, 5);
  get(b, 4); constant(b, 64); op(b, 0x4b); trap_if(b);
  read_local(b, 5, 0); set(b, 6);
  begin_block(b); begin_loop(b); get(b, 7); constant(b, 64); op(b, 0x4f); branch_if(b, 1);
  get(b, 7); get(b, 4); op(b, 0x49); when(b);
  get(b, 6); get(b, 7); constant(b, 2); op(b, 0x74); op(b, 0x6a);
  get(b, 3); get(b, 7); constant(b, 2); op(b, 0x74); op(b, 0x6a); load(b, 0); store(b, 0);
  otherwise(b); get(b, 6); get(b, 7); constant(b, 2); op(b, 0x74); op(b, 0x6a); constant(b, 0); store(b, 0); end(b);
  increment(b, 7, 1); branch(b, 0); end(b); end(b);
  telemetry_add_const(m,b,runtime::T_INITIALIZED,256); telemetry_add_local(m,b,runtime::T_COPIED,4,4);
  put_local(b, 5, 24, 2); put_local(b, 5, 28, 4); put_const(b, 5, 20, 2); end(b);
  return function(m, sig, b);
}
fn emit_open(m: ModuleBuilder&, h: Helpers) -> u32 {
  let sig = signature(m, [I32, I32, I32, I32], I32);
  var b: u8[>..] = []; local_declarations(b, 1, I32);
  get(b, 0); get(b, 1); constant(b, 2); constant(b, 2); call(b, h.validate); set(b, 4);
  read_local(b, 4, 24); get(b, 2); op(b, 0x47); trap_if(b);
  read_local(b, 4, 28); get(b, 3); op(b, 0x47); trap_if(b);
  get(b, 3); constant(b, 64); op(b, 0x4b); trap_if(b);
  read_local(b, 4, 0); end(b); return function(m, sig, b);
}
fn runtime_helpers(m: ModuleBuilder&) -> Helpers {
  var h = Helpers {};
  h.validate = emit_validate(m); h.mark = emit_mark(m); h.reserve = emit_reserve(m, h);
  h.place = emit_place(m, h); h.release = emit_release(m, h); h.reset = emit_reset(m, h);
  h.seal = emit_seal(m, h); h.open = emit_open(m, h);
  for i in 8 { m.functions[i].role = 1; m.functions[i].source = i as u32 + 1; m.functions[i].depth = if i < 2 {1} else {2}; }
  return h;
}

fn runtime_fixture(out:u8[>..]&)->runtime::MemoryMap { runtime_fixture_mode(out,false) }
fn runtime_fixture_telemetry(out:u8[>..]&)->runtime::MemoryMap { runtime_fixture_mode(out,true) }
fn runtime_fixture_mode(out: u8[>..]&, telemetry:bool) -> runtime::MemoryMap {
  let map, ok = runtime::make_map(runtime::Config {
    pool_bytes: 4 * 4096, owner_slots: 4, frame_bytes: 256, ingress_bytes: 256, egress_bytes: 256, telemetry:telemetry,
  });
  assert(ok); with_module(map) { m => m.telemetry=telemetry; let h = runtime_helpers(m);
  export_memory(m); export_function(m, "reserve", h.reserve); export_function(m, "place", h.place);
  export_function(m, "release", h.release); export_function(m, "reset", h.reset);
  export_function(m, "seal", h.seal); export_function(m, "open", h.open);
  emit_telemetry_reader(m); encode(m, out); } return map;
}

// A lowering owns only numeric maps. No source tree or inference state is read.
struct Lowering {
  core: Core, module: ModuleBuilder&, helpers: Helpers,
  layouts: const u32[:], functions: const u32[:], signatures: const u32[:],
  plans: const u32[:], locals: const u32[:], offsets: const u32[:],
  flat_locals: const u32[:], adapter_entries: const Adapter[:], static_addresses: const u32[:], adapter_codes: const u32[:], environments: const u32[:], call_arguments: const u32[:], call_results: const u32[:], function_id: u32,
  base: u32, saved: u32, pc: u32, tmp0: u32, tmp1: u32,
  phi: u32, own_frame: u32, param_count: u32,
}
fn layout(c: Core, ids: const u32[:], type_id: u32) -> Layout { c.layouts[ids[type_id]] }
fn value_layout(s: Lowering, v: u32) -> Layout { layout(s.core, s.layouts, s.core.values[v].type_id) }
fn aggregate(l: Layout) -> bool { l.abi == ABI_INDIRECT }
fn refs(c: Core, span: Span) -> const u32[:] { c.refs[span.start..span.start + span.count] }
fn underlying(c: Core, type_id: u32) -> u32 {
  var id = type_id;
  for step in 65 {
    let t = c.types[id];
    if t.tag != TY_ALIAS && t.tag != TY_FORALL { return id; }
    id = c.refs[t.children.start];
  }
  abort("validated type alias cycle");
}
fn type_child(c: Core, type_id: u32, ordinal: u32) -> u32 {
  let t = c.types[underlying(c, type_id)];
  return if t.fields.count != 0 { c.fields[c.refs[t.fields.start + ordinal]].type_id }
    else { c.refs[t.children.start + ordinal] };
}
fn type_children(c: Core, type_id: u32) -> u32 {
  let t = c.types[underlying(c, type_id)]; return if t.fields.count != 0 { t.fields.count } else { t.children.count };
}
recursive fn fixed_layout(c: Core, type_id: u32, depth: u32) -> bool {
  if depth > 64 { return false; }
  let id = underlying(c, type_id); let t = c.types[id];
  if t.tag == TY_PARAM { return false; }
  if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_SUM || t.tag == TY_RESULT || t.tag == TY_EXISTS {
    for i in type_children(c, id) { if !fixed_layout(c, type_child(c, id, i as u32), depth + 1) { return false; } }
  }
  return true;
}
recursive fn closed_dictionary(c: Core, type_id: u32, depth: u32) -> bool {
  if depth > 64 { return false; }
  let t = c.types[type_id];
  if t.tag == TY_PARAM { return false; }
  if t.tag == TY_FORALL { return true; }
  for id in refs(c, t.children) { if !closed_dictionary(c, id, depth+1) { return false; } }
  for id in refs(c, t.fields) { if !closed_dictionary(c, c.fields[id].type_id, depth+1) { return false; } }
  if t.tag == TY_FN {
    let ct = c.contracts[t.contract];
    if !closed_dictionary(c, ct.arg, depth+1) || !closed_dictionary(c, ct.result, depth+1) { return false; }
  }
  return true;
}
fn flat(s: Lowering, v: u32) -> bool { s.flat_locals[v] != 0 }
fn scalar_bits(s: Lowering, b: u8[>..]&, v: u32) {
  get(b, s.locals[v]); if value_layout(s, v).abi == ABI_F32 { op(b, 0xbc); }
}
fn set_scalar_bits(s: Lowering, b: u8[>..]&, v: u32) {
  if value_layout(s, v).abi == ABI_F32 { op(b, 0xbe); } set(b, s.locals[v]);
}
fn read_word(s: Lowering, b: u8[>..]&, v: u32, offset: u32) {
  if flat(s, v) { get(b, s.flat_locals[v] + offset / 4); }
  else { value(s, b, v); load(b, offset); }
}
fn payload_store(s:Lowering,b:u8[>..]&,offset:u32) { store(b,offset); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,4); }
fn write_word(s: Lowering, b: u8[>..]&, v: u32, offset: u32) {
  if flat(s, v) { set(b, s.flat_locals[v] + offset / 4); }
  else { set(b, s.tmp1); value_address(s, b, v); get(b, s.tmp1); payload_store(s,b,offset); }
}
fn copy_flat_part(s: Lowering, b: u8[>..]&, to: u32, offset: u32, from: u32) {
  let l = value_layout(s, from);
  if aggregate(l) {
    for word in l.size / 4 { read_word(s, b, from, word * 4); write_word(s, b, to, offset + word * 4); }
  } else if l.abi != ABI_UNIT { scalar_bits(s, b, from); write_word(s, b, to, offset); }
}
fn project_flat(s: Lowering, b: u8[>..]&, to: u32, from: u32, offset: u32) {
  let l = value_layout(s, to);
  if aggregate(l) {
    for word in l.size / 4 { read_word(s, b, from, offset + word * 4); write_word(s, b, to, word * 4); }
  } else if l.abi != ABI_UNIT { read_word(s, b, from, offset); set_scalar_bits(s, b, to); }
}
fn reload_flat(s: Lowering, b: u8[>..]&, v: u32) {
  if flat(s, v) { value_address(s, b, v); load_value(s, b, v); }
}
fn emit_dictionary(s: Lowering, b: u8[>..]&, binder: u32) -> bool {
  let plan = s.core.abi_plans[s.plans[s.function_id]];
  var parameter = 1 + (if s.core.layouts[plan.result_layout].abi == ABI_INDIRECT {1 as u32} else {0});
  for own in refs(s.core, plan.dictionaries) { if own == binder { get(b, parameter); return true; } parameter++; }
  for id in refs(s.core, s.core.functions[s.function_id].environment_bindings) {
    let binding = s.core.environment_bindings[id];
    if binding.kind == KIND_TYPE && binding.binder == binder { get(b, 0); load(b, binding.offset); return true; }
  }
  return false;
}
fn emit_type_dictionary(s: Lowering, b: u8[>..]&, type_id: u32) -> bool {
  let id = underlying(s.core, type_id); let row = s.core.types[id];
  if row.tag == TY_PARAM { return emit_dictionary(s, b, row.binder); }
  if closed_dictionary(s.core, type_id, 0) {
    constant(b, s.module.map.static_base + s.layouts[type_id] * 16); return true;
  }
  var cases:u32 = 0;
  for realized, i in s.core.dictionary_realizations {
    if i == 0 || realized.type_id != type_id { continue; }
    constant(b, 1);
    for binder, parameter in refs(s.core, realized.parameters) {
      if !emit_dictionary(s, b, binder) { return false; } load(b, 12);
      let argument = s.core.refs[realized.arguments.start + parameter];
      constant(b, s.core.layouts[s.layouts[argument]].schema); op(b, 0x46); op(b, 0x71);
    }
    op(b, 0x04); op(b, I32); constant(b, s.module.map.static_base + realized.layout * 16); otherwise(b); cases++;
  }
  // Every reachable combination is realized by the validated whole-program
  // call plan. The shared body can still exist without an admitted invocation.
  op(b, 0x00); for i in cases { end(b); } return true;
}
fn emit_schema(s: Lowering, b: u8[>..]&, type_id: u32) -> bool {
  if !emit_type_dictionary(s, b, type_id) { return false; }
  load(b, 12); return true;
}
recursive fn emit_term_value(s: Lowering, b: u8[>..]&, term: u32) -> bool {
  if !id_ok(term, s.core.terms.len) { return false; }
  let row = s.core.terms[term]; let args = refs(s.core, row.args);
  if row.tag == EXPR_LITERAL { constant(b, row.literal); return true; }
  if row.tag == EXPR_VALUE { value(s, b, row.value); return true; }
  if row.tag == EXPR_BINDER { return emit_nat(s, b, row.binder); }
  if row.tag == EXPR_ARG {
    let f = s.core.functions[s.function_id]; if row.binder != f.contract { return false; }
    value(s, b, f.param); return true;
  }
  if row.tag == EXPR_FIELD && args.len == 1 {
    if !emit_term_value(s, b, args[0]) { return false; }
    field_address(s, b, s.core.terms[args[0]].type_id, row.literal);
    let target = layout(s.core, s.layouts, row.type_id);
    if target.abi == ABI_I32 || target.abi == ABI_F32 { load_scalar(b, target, 0); }
    else if target.abi == ABI_UNIT { op(b, 0x1a); }
    return true;
  }
  if (row.tag == EXPR_LEN || row.tag == EXPR_CAP || row.tag == EXPR_INIT) && args.len == 1 {
    if !emit_term_value(s, b, args[0]) { return false; }
    let ty = underlying(s.core, s.core.terms[args[0]].type_id);
    load(b, if row.tag == EXPR_CAP && s.core.types[ty].tag == TY_BUILDER {8} else {4}); return true;
  }
  if row.tag == EXPR_MAX_MINUS && args.len == 1 {
    constant(b, 0xffffffff); if !emit_term_value(s, b, args[0]) { return false; } op(b, 0x6b); return true;
  }
  if (row.tag == EXPR_ADD || row.tag == EXPR_SUB || row.tag == EXPR_MUL) && args.len == 2 {
    if !emit_term_value(s, b, args[0]) || !emit_term_value(s, b, args[1]) { return false; }
    op(b, if row.tag == EXPR_ADD {0x6a} else if row.tag == EXPR_SUB {0x6b} else {0x6c}); return true;
  }
  return false;
}

fn callable_adapter(c: Core, operation: u32) -> u32 {
  for row, i in c.callable_adapters { if i != 0 && row.op == operation { return i as u32; } }
  return 0;
}
fn adapter_capture(c: Core, adapter: u32, kind: u32, source: u32) -> u32 {
  if adapter == 0 { return 0; }
  for id in refs(c, c.callable_adapters[adapter].captures) {
    let row = c.adapter_captures[id]; if row.kind == kind && row.source == source { return id; }
  }
  return 0;
}
recursive fn emit_size(s: Lowering, b: u8[>..]&, type_id: u32, depth: u32) {
  assert(depth < 64);
  let id = underlying(s.core, type_id); let t = s.core.types[id];
  if fixed_layout(s.core, id, 0) { constant(b, layout(s.core, s.layouts, id).size); return; }
  if t.tag == TY_PARAM {
    assert(emit_dictionary(s, b, t.binder)); load(b, 0); return;
  }
  if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_EXISTS {
    constant(b, package_prefix(s.core, id));
    for i in type_children(s.core, id) { emit_size(s, b, type_child(s.core, id, i as u32), depth + 1); op(b, 0x6a); }
    return;
  }
  if t.tag == TY_SUM || t.tag == TY_RESULT {
    let accumulator = s.base + 5 + depth;
    constant(b, 0); set(b, accumulator);
    for i in type_children(s.core, id) {
      emit_size(s, b, type_child(s.core, id, i as u32), depth + 1); tee(b, s.tmp0);
      get(b, accumulator); op(b, 0x4b); when(b); get(b, s.tmp0); set(b, accumulator); end(b);
    }
    add_const(b, accumulator, 4); return;
  }
  constant(b, layout(s.core, s.layouts, id).size);
}
fn copy_type(s: Lowering, b: u8[>..]&, type_id: u32) {
  emit_size(s, b, type_id, 0);
  if s.module.telemetry { tee(b,s.base+69); telemetry_add_local(s.module,b,runtime::T_INITIALIZED,s.base+69,1); telemetry_add_local(s.module,b,runtime::T_COPIED,s.base+69,1); }
  op(b, 0xfc); uleb(b, 10); uleb(b, 0); uleb(b, 0);
}
fn zero_type(s: Lowering, b: u8[>..]&, type_id: u32) {
  constant(b, 0); emit_size(s, b, type_id, 0);
  if s.module.telemetry { tee(b,s.base+69); telemetry_add_local(s.module,b,runtime::T_INITIALIZED,s.base+69,1); }
  op(b, 0xfc); uleb(b, 11); uleb(b, 0);
}
fn field_address(s: Lowering, b: u8[>..]&, type_id: u32, ordinal: u32) {
  // Aggregate address is already on the stack. Runtime dictionaries determine
  // preceding generic fields; maximum admission sizes never become offsets.
  for i in ordinal { emit_size(s, b, type_child(s.core, type_id, i as u32), 0); op(b, 0x6a); }
}
fn borrowed_parameter(s: Lowering, v: u32) -> bool {
  v == s.core.functions[s.function_id].param && aggregate(value_layout(s, v)) && !flat(s, v)
}
fn value_address(s: Lowering, b: u8[>..]&, v: u32) {
  // The caller's indirect argument is immutable SSA storage throughout this
  // activation. Region writes through a descriptor never mutate its own words.
  if borrowed_parameter(s, v) { get(b, s.param_count - 1); }
  else { add_const(b, s.base, s.offsets[v]); }
}
fn value(s: Lowering, b: u8[>..]&, v: u32) {
  let l = value_layout(s, v);
  if aggregate(l) {
    if flat(s, v) {
      for word in l.size / 4 { value_address(s, b, v); get(b, s.flat_locals[v] + word); store(b, word * 4); }
      telemetry_add_const(s.module,b,runtime::T_INITIALIZED,l.size);
    }
    value_address(s, b, v);
  }
  else if l.abi != ABI_UNIT { get(b, s.locals[v]); }
}
fn store_scalar(b: u8[>..]&, l: Layout, offset: u32) {
  if l.abi == ABI_F32 { op(b, 0x38); uleb(b, 2); uleb(b, offset); }
  else { store(b, offset); }
}
fn load_scalar(b: u8[>..]&, l: Layout, offset: u32) {
  if l.abi == ABI_F32 { op(b, 0x2a); uleb(b, 2); uleb(b, offset); }
  else { load(b, offset); }
}
fn memory_copy(b: u8[>..]&, bytes: u32) {
  constant(b, bytes); op(b, 0xfc); uleb(b, 10); uleb(b, 0); uleb(b, 0);
}
fn memory_zero(b: u8[>..]&, bytes: u32) {
  constant(b, 0); constant(b, bytes); op(b, 0xfc); uleb(b, 11); uleb(b, 0);
}
fn copy_value(s: Lowering, b: u8[>..]&, to: u32, from: u32) {
  let l = value_layout(s, to);
  if flat(s, to) { copy_flat_part(s, b, to, 0, from); }
  else if aggregate(l) { value_address(s, b, to); value(s, b, from); copy_type(s, b, s.core.values[to].type_id); }
  else if l.abi != ABI_UNIT { value(s, b, from); set(b, s.locals[to]); }
}
fn store_value(s: Lowering, b: u8[>..]&, source: u32) {
  // Destination address is already on the operand stack.
  let l = value_layout(s, source);
  if flat(s, source) {
    set(b, s.tmp0);
    for word in l.size / 4 { get(b, s.tmp0); get(b, s.flat_locals[source] + word); store(b, word * 4); }
    telemetry_add_const(s.module,b,runtime::T_INITIALIZED,l.size);
  } else if aggregate(l) { value(s, b, source); copy_type(s, b, s.core.values[source].type_id); }
  else if l.abi != ABI_UNIT { value(s, b, source); store_scalar(b, l, 0); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,l.size); }
  else { op(b, 0x1a); }
}
fn load_value(s: Lowering, b: u8[>..]&, target: u32) {
  // Source address is already on the operand stack.
  let l = value_layout(s, target);
  if flat(s, target) {
    set(b, s.tmp0);
    for word in l.size / 4 { get(b, s.tmp0); load(b, word * 4); set(b, s.flat_locals[target] + word); }
  } else if aggregate(l) {
    set(b, s.tmp0); value_address(s, b, target); get(b, s.tmp0); copy_type(s, b, s.core.values[target].type_id);
  } else if l.abi != ABI_UNIT { load_scalar(b, l, 0); set(b, s.locals[target]); }
  else { op(b, 0x1a); }
}
fn package_prefix(c: Core, type_id: u32) -> u32 {
  let t = c.types[underlying(c, type_id)]; var words: u32 = 0;
  if t.tag == TY_EXISTS {
    for binder in refs(c, t.binders) { if c.binders[binder].kind == KIND_NAT { words++; } }
  }
  return words * 4;
}
fn arithmetic(tag: u32) -> u8 {
  if tag == OP_U32_ADD || tag == OP_U32_ADD_WRAP { return 0x6a; }
  if tag == OP_U32_SUB || tag == OP_U32_SUB_WRAP { return 0x6b; }
  if tag == OP_U32_MUL || tag == OP_U32_MUL_WRAP { return 0x6c; }
  if tag == OP_U32_DIV { return 0x6e; } if tag == OP_U32_REM { return 0x70; }
  if tag == OP_U32_EQ { return 0x46; } if tag == OP_U32_NE { return 0x47; }
  if tag == OP_U32_LT { return 0x49; } if tag == OP_U32_LE { return 0x4d; }
  if tag == OP_U32_GT { return 0x4b; } if tag == OP_U32_GE { return 0x4f; }
  if tag == OP_U32_AND || tag == OP_BOOL_AND { return 0x71; }
  if tag == OP_U32_OR || tag == OP_BOOL_OR { return 0x72; }
  if tag == OP_U32_XOR { return 0x73; } if tag == OP_U32_SHL { return 0x74; }
  if tag == OP_U32_SHR { return 0x76; }
  if tag == OP_F32_ADD { return 0x92; } if tag == OP_F32_SUB { return 0x93; }
  if tag == OP_F32_MUL { return 0x94; } if tag == OP_F32_DIV { return 0x95; }
  if tag == OP_F32_NEG { return 0x8c; } if tag == OP_F32_EQ { return 0x5b; }
  if tag == OP_F32_NE { return 0x5c; } if tag == OP_F32_LT { return 0x5d; }
  if tag == OP_F32_LE { return 0x5f; } if tag == OP_F32_GT { return 0x5e; }
  if tag == OP_F32_GE { return 0x60; } if tag == OP_BOOL_NOT { return 0x45; }
  if tag == OP_F32_SQRT { return 0x91; } if tag == OP_F32_ABS { return 0x8b; }
  if tag == OP_F32_MIN { return 0x96; } if tag == OP_F32_MAX { return 0x97; }
  if tag == OP_F32_CEIL { return 0x8d; } if tag == OP_F32_FLOOR { return 0x8e; }
  if tag == OP_F32_TRUNC { return 0x8f; } if tag == OP_F32_NEAREST { return 0x90; }
  if tag == OP_F32_FROM_BITS { return 0xbe; } if tag == OP_F32_TO_BITS { return 0xbc; }
  if tag == OP_U32_TO_F32 { return 0xb3; }
  return 0;
}
fn opcode_diagnostic(diags: Diagnostic[>..]&, code: u32, operation: Operation) -> bool {
  diags.push(Diagnostic {code, operation.origin, operation.tag, 0}); return false;
}
fn emit_nat(s: Lowering, b: u8[>..]&, binder: u32) -> bool {
  let plan = s.core.abi_plans[s.plans[s.function_id]];
  var hidden = 1 + (if s.core.layouts[plan.result_layout].abi == ABI_INDIRECT {1 as u32} else {0}) + plan.dictionaries.count;
  for witness_id in refs(s.core, plan.nat_witnesses) {
    let witness = s.core.nat_witnesses[witness_id];
    if witness.binder == binder {
      if witness.selector == NAT_HIDDEN { get(b, hidden); return true; }
      let f = s.core.functions[s.function_id]; var type_id = s.core.values[f.param].type_id;
      value(s, b, f.param);
      for ordinal in refs(s.core, witness.argument_path) {
        field_address(s, b, type_id, ordinal); type_id = type_child(s.core, type_id, ordinal);
      }
      load(b, if witness.selector == NAT_BUILDER_CAP {8} else if witness.selector == NAT_PACKAGE_PREFIX {witness.prefix_index * 4} else {4});
      return true;
    }
    if witness.selector == NAT_HIDDEN { hidden++; }
  }
  for id in refs(s.core, s.core.functions[s.function_id].environment_bindings) {
    let binding = s.core.environment_bindings[id];
    if binding.kind == KIND_NAT && binding.binder == binder { get(b, 0); load(b, binding.offset); return true; }
  }
  return false;
}
fn emit_call_plan(s: Lowering, b: u8[>..]&, operation_id: u32, operation: Operation, diags: Diagnostic[>..]&, forced_plan:u32) -> bool {
  let args = refs(s.core, operation.args); let results = refs(s.core, operation.results);
  let indirect = operation.tag == OP_CALL_INDIRECT;
  var target = operation.imm0;
  var plan_id: u32 = 0;
  var indirect_signature: u32 = 0;
  if indirect {
    let contract = s.core.types[underlying(s.core, s.core.values[args[0]].type_id)].contract;
    for p, i in s.core.abi_plans { if i != 0 && p.contract == contract { plan_id = i as u32; break; } }
    if forced_plan != 0 { plan_id = forced_plan; }
    if plan_id == 0 { return opcode_diagnostic(diags, 3011, operation); }
    var parameters: u8[>..] = []; let result = abi_parameters(s.core, s.core.abi_plans[plan_id], parameters);
    indirect_signature = signature(s.module, parameters, result);
  } else {
    if s.core.functions[target].evaluator_only { return opcode_diagnostic(diags,3039,operation); }
    plan_id = s.plans[target];
  }
  let plan = s.core.abi_plans[plan_id];
  let argument = args[if indirect { 1 } else { 0 }];
  let actual_arg = value_layout(s, argument);
  let actual_result = value_layout(s, results[0]);
  if s.core.layouts[plan.arg_layout].abi == ABI_INDIRECT && actual_arg.abi != ABI_INDIRECT && actual_arg.abi != ABI_UNIT {
    add_const(b, s.base, s.call_arguments[operation_id]); store_value(s, b, argument);
  }
  let result = s.core.layouts[plan.result_layout];
  if actual_result.abi == ABI_INDIRECT && (result.abi == ABI_I32 || result.abi == ABI_F32) { value_address(s,b,results[0]); }
  if indirect { read_word(s, b, args[0], 4); } else { constant(b, 0); }
  if result.abi == ABI_INDIRECT {
    if actual_result.abi == ABI_INDIRECT { value_address(s, b, results[0]); }
    else if actual_result.abi == ABI_UNIT { constant(b, 0); }
    else { add_const(b, s.base, s.call_results[operation_id]); }
  }
  // Dictionary pointers are compiler-generated static data; user integers never
  // enter this ABI position. One body handles every admitted substitution.
  for binder in refs(s.core, plan.dictionaries) {
    var substituted: u32 = 0;
    for sub in refs(s.core, operation.substitutions) {
      let row = s.core.substitutions[sub]; if row.binder == binder { substituted = row.value; }
    }
    if substituted == 0 { return opcode_diagnostic(diags, 3012, operation); }
    if !emit_type_dictionary(s, b, substituted) { return opcode_diagnostic(diags, 3012, operation); }
  }
  for witness_id in refs(s.core, plan.nat_witnesses) {
    let witness = s.core.nat_witnesses[witness_id];
    if witness.selector == NAT_HIDDEN {
      var term: u32 = 0;
      for sub in refs(s.core, operation.substitutions) { let row = s.core.substitutions[sub]; if row.binder == witness.binder { term = row.value; } }
      if term == 0 { return opcode_diagnostic(diags, 3013, operation); }
      if !emit_term_value(s, b, term) { return opcode_diagnostic(diags, 3013, operation); }
    }
  }
  if s.core.layouts[plan.arg_layout].abi != ABI_UNIT {
    if s.core.layouts[plan.arg_layout].abi == ABI_INDIRECT && actual_arg.abi != ABI_INDIRECT {
      if actual_arg.abi == ABI_UNIT { constant(b, 0); } else { add_const(b, s.base, s.call_arguments[operation_id]); }
    } else {
      value(s, b, argument);
      if actual_arg.abi == ABI_INDIRECT && s.core.layouts[plan.arg_layout].abi != ABI_INDIRECT { load_scalar(b,s.core.layouts[plan.arg_layout],0); }
    }
  }
  if indirect {
    s.module.indirect_contracts.push(plan.contract);
    read_word(s, b, args[0], 0); op(b, 0x11); uleb(b, indirect_signature); uleb(b, 0);
  } else { call(b, s.functions[target]); }
  if result.abi == ABI_I32 || result.abi == ABI_F32 {
    if actual_result.abi == ABI_INDIRECT { store_scalar(b,result,0); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,result.size); reload_flat(s,b,results[0]); } else { set(b, s.locals[results[0]]); }
  }
  else if result.abi == ABI_INDIRECT && actual_result.abi != ABI_INDIRECT && actual_result.abi != ABI_UNIT {
    add_const(b, s.base, s.call_results[operation_id]); load_value(s, b, results[0]);
  } else if result.abi == ABI_INDIRECT { reload_flat(s, b, results[0]); }
  return true;
}

fn realization_guard(s: Lowering, b: u8[>..]&, row: DictionaryRealization) -> bool {
  constant(b,1);
  for binder,i in refs(s.core,row.parameters) {
    if !emit_dictionary(s,b,binder) { return false; } load(b,12);
    let arg=s.core.refs[row.arguments.start+i]; constant(b,layout(s.core,s.layouts,arg).schema); op(b,0x46); op(b,0x71);
  } return true;
}
fn emit_call(s: Lowering, b: u8[>..]&, operation_id: u32, operation: Operation, diags: Diagnostic[>..]&) -> bool {
  if operation.tag != OP_CALL_INDIRECT { return emit_call_plan(s,b,operation_id,operation,diags,0); }
  let callable=s.core.values[s.core.refs[operation.args.start]].type_id;
  if closed_dictionary(s.core,callable,0) { return emit_call_plan(s,b,operation_id,operation,diags,0); }
  begin_block(b);
  for row,i in s.core.dictionary_realizations {
    if i==0 || row.type_id!=callable { continue; }
    let contract=s.core.types[underlying(s.core,row.concrete_type)].contract;
    var plan:u32=0; for p,j in s.core.abi_plans { if j!=0 && p.contract==contract { plan=j as u32; break; } }
    if plan==0 || !realization_guard(s,b,row) { return opcode_diagnostic(diags,3011,operation); }
    when(b); if !emit_call_plan(s,b,operation_id,operation,diags,plan) { return false; } branch(b,1); end(b);
  }
  op(b,0x00); end(b); return true;
}

fn emit_operation(s: Lowering, b: u8[>..]&, operation_id: u32, operation: Operation, diags: Diagnostic[>..]&) -> bool {
  let args = refs(s.core, operation.args); let results = refs(s.core, operation.results);
  let result = if results.len == 0 { 0 as u32 } else { results[0] };
  let tag = operation.tag;
  if tag == OP_UNIT || tag == OP_SPACE_END || tag == OP_DEST_DISCARD ||
     tag == OP_BUILDER_DISCARD || tag == OP_LOAN_END || tag == OP_DISCARD_ONCE || tag == OP_GENERIC_BIND { return true; }
  if tag == OP_STATIC {
    if !id_ok(operation.imm0, s.core.static_objects.len) { return opcode_diagnostic(diags, 3036, operation); }
    let object = s.core.static_objects[operation.imm0];
    if object.kind == STATIC_ARRAY {
      constant(b, if object.bytes.count == 0 {0} else {s.static_addresses[operation.imm0]}); write_word(s, b, result, 0);
      constant(b, object.count); write_word(s, b, result, 4);
    } else { constant(b, s.static_addresses[operation.imm0]); load_value(s, b, result); }
    return true;
  }
  if tag == OP_BOOL || tag == OP_U32 {
    constant(b, operation.imm0); set(b, s.locals[result]); return true;
  }
  if tag == OP_F32 {
    op(b, 0x43); for i in 4 { op(b, (operation.imm0 >> (i * 8)) as! u8); }
    set(b, s.locals[result]); return true;
  }
  if tag == OP_COPY || tag == OP_REFINE || tag == OP_FN_WEAKEN || tag == OP_INDEX_VALUE { copy_value(s, b, result, args[0]); return true; }
  if tag == OP_NAT_VALUE {
    if !emit_nat(s, b, operation.imm0) { return opcode_diagnostic(diags, 3013, operation); }
    set(b, s.locals[result]); return true;
  }
  let instruction = arithmetic(tag);
  if instruction != 0 {
    for arg in args { value(s, b, arg); } op(b, instruction); set(b, s.locals[result]); return true;
  }
  if tag == OP_U32_NOT { value(s, b, args[0]); constant(b, 0xffffffff); op(b, 0x73); set(b, s.locals[result]); return true; }
  if tag == OP_TUPLE || tag == OP_RECORD {
    let type_id = s.core.values[result].type_id;
    if flat(s, result) {
      var offset: u32 = 0;
      for arg in args { copy_flat_part(s, b, result, offset, arg); offset += value_layout(s, arg).size; }
      return true;
    }
    for arg, i in args { value_address(s, b, result); field_address(s, b, type_id, i as u32); store_value(s, b, arg); }
    return true;
  }
  if tag == OP_PROJECT {
    if flat(s, args[0]) { project_flat(s, b, result, args[0], known_field_offset(s.core, s.layouts, s.core.values[args[0]].type_id, operation.imm0)); return true; }
    value(s, b, args[0]); field_address(s, b, s.core.values[args[0]].type_id, operation.imm0);
    load_value(s, b, result); return true;
  }
  if tag == OP_DESTRUCTURE {
    for target, i in results {
      if flat(s, args[0]) { project_flat(s, b, target, args[0], known_field_offset(s.core, s.layouts, s.core.values[args[0]].type_id, i as u32)); }
      else { value(s, b, args[0]); field_address(s, b, s.core.values[args[0]].type_id, i as u32); load_value(s, b, target); }
    }
    return true;
  }
  if tag == OP_SUM {
    if flat(s, result) {
      for word in value_layout(s, result).size / 4 { constant(b, 0); write_word(s, b, result, word * 4); }
      if args.len != 0 { copy_flat_part(s, b, result, 4, args[0]); }
      constant(b, operation.imm0); write_word(s, b, result, 0); return true;
    }
    value_address(s, b, result); zero_type(s, b, s.core.values[result].type_id);
    if args.len != 0 { value_address(s, b, result); constant(b, 4); op(b, 0x6a); store_value(s, b, args[0]); }
    value_address(s, b, result); constant(b, operation.imm0); payload_store(s,b,0); return true;
  }
  if tag == OP_TAG { read_word(s, b, args[0], 0); set(b, s.locals[result]); return true; }
  if tag == OP_PAYLOAD {
    if flat(s, args[0]) { project_flat(s, b, result, args[0], 4); }
    else { value(s, b, args[0]); constant(b, 4); op(b, 0x6a); load_value(s, b, result); }
    return true;
  }
  if tag == OP_PACK {
    let prefix = package_prefix(s.core, s.core.values[result].type_id);
    if args.len != prefix / 4 + 1 { return opcode_diagnostic(diags, 3014, operation); }
    if flat(s, result) {
      for i in prefix / 4 { value(s, b, args[i]); write_word(s, b, result, i * 4); }
      copy_flat_part(s, b, result, prefix, args[args.len - 1]); return true;
    }
    for i in prefix as i64 / 4 { value_address(s, b, result); value(s, b, args[i]); payload_store(s,b,i as u32 * 4); }
    value_address(s, b, result); constant(b, prefix); op(b, 0x6a); store_value(s, b, args[args.len - 1]); return true;
  }
  if tag == OP_OPEN {
    let prefix = package_prefix(s.core, s.core.values[args[0]].type_id);
    if flat(s, args[0]) { project_flat(s, b, result, args[0], prefix); }
    else { value(s, b, args[0]); constant(b, prefix); op(b, 0x6a); load_value(s, b, result); }
    for i in results.len - 1 { read_word(s, b, args[0], i as u32 * 4); set(b, s.locals[results[i + 1]]); }
    return true;
  }
  if tag == OP_CALL || tag == OP_CALL_INDIRECT { return emit_call(s, b, operation_id, operation, diags); }
  if tag == OP_CLOSURE || tag == OP_FN_PLACE {
    let first_capture = if tag == OP_FN_PLACE { 1 } else { 0 };
    let target = s.core.functions[operation.imm0];
    let contract = s.core.types[underlying(s.core, s.core.values[result].type_id)].contract;
    var callback_plan: u32 = 0;
    for row, i in s.core.abi_plans { if i != 0 && row.contract == contract { callback_plan = i as u32; break; } }
    if callback_plan == 0 { return opcode_diagnostic(diags, 3011, operation); }
    var parameters: u8[>..] = []; let return_type = abi_parameters(s.core, s.core.abi_plans[callback_plan], parameters);
    if signature(s.module, parameters, return_type) != s.signatures[operation.imm0] && s.adapter_codes[operation_id] == 0 && closed_dictionary(s.core,s.core.values[result].type_id,0) {
      // A concrete scalar callback needs an explicit canonical ABI adapter when
      // its shared generic body uses dictionary/indirect slots. Never trap later
      // by putting a mismatched raw body in the callable's table slot.
      return opcode_diagnostic(diags, 3029, operation);
    }
    let adapter_id = callable_adapter(s.core, operation_id);
    let environment_offset = if adapter_id==0 {0 as u32} else {s.core.callable_adapters[adapter_id].target_environment_offset};
    for id in refs(s.core, target.environment_bindings) {
      let binding = s.core.environment_bindings[id];
      if tag == OP_FN_PLACE { value(s, b, args[0]); load(b, 0); }
      else { add_const(b, s.base, s.environments[result]); }
      if binding.kind == KIND_TYPE {
        if !emit_dictionary(s, b, binding.binder) { return opcode_diagnostic(diags, 3012, operation); }
      } else if binding.source_value != 0 && s.core.blocks[s.core.values[binding.source_value].block_id].function==s.function_id { value(s, b, binding.source_value); }
      else if !emit_nat(s, b, binding.binder) { return opcode_diagnostic(diags, 3013, operation); }
      payload_store(s,b,environment_offset+binding.offset);
    }
    if adapter_id != 0 {
      let adapter = s.core.callable_adapters[adapter_id];
      for capture_id in refs(s.core, adapter.captures) {
        let capture = s.core.adapter_captures[capture_id];
        if tag == OP_FN_PLACE { read_word(s, b, args[0], 0); } else { add_const(b, s.base, s.environments[result]); }
        if capture.kind == KIND_TYPE {
          if !emit_type_dictionary(s, b, capture.source) { return opcode_diagnostic(diags, 3012, operation); }
        } else if !emit_term_value(s, b, capture.source) { return opcode_diagnostic(diags, 3013, operation); }
        payload_store(s,b,capture.offset);
      }
    }
    var offset: u32 = environment_offset+target.environment_bindings.count*4;
    for i in args.len - first_capture {
      let capture = args[i + first_capture];
      if tag == OP_FN_PLACE { value(s, b, args[0]); load(b, 0); }
      else { add_const(b, s.base, s.environments[result]); }
      constant(b, environment_offset+target.environment_bindings.count * 4); op(b, 0x6a);
      for prior in i { emit_size(s, b, s.core.values[args[prior + first_capture]].type_id, 0); op(b, 0x6a); }
      store_value(s, b, capture); offset += value_layout(s, capture).size;
    }
    if closed_dictionary(s.core,s.core.values[result].type_id,0) {
      constant(b, if s.adapter_codes[operation_id] == 0 { s.functions[operation.imm0] - 8 } else { s.adapter_codes[operation_id] - 1 });
    } else {
      var cases:u32=0;
      for adapter in s.adapter_entries {
        if adapter.operation!=operation_id || adapter.realization==0 { continue; }
        if !realization_guard(s,b,s.core.dictionary_realizations[adapter.realization]) { return opcode_diagnostic(diags,3012,operation); }
        op(b,0x04); op(b,I32); constant(b,adapter.table_index); otherwise(b); cases++;
      }
      op(b,0x00); for i in cases { end(b); }
    }
    write_word(s, b, result, 0);
    if offset == 0 { constant(b, 0); }
    else if tag == OP_FN_PLACE { value(s, b, args[0]); load(b, 0); }
    else { add_const(b, s.base, s.environments[result]); }
    write_word(s, b, result, 4); return true;
  }
  if tag == OP_ADD_FITS || tag == OP_SUB_FITS || tag == OP_MUL_FITS {
    if tag == OP_ADD_FITS { value(s, b, args[0]); constant(b, 0xffffffff); value(s, b, args[1]); op(b, 0x6b); op(b, 0x4d); }
    else if tag == OP_SUB_FITS { value(s, b, args[1]); value(s, b, args[0]); op(b, 0x4d); }
    else {
      value(s, b, args[1]); op(b, 0x45); op(b, 0x04); op(b, I32); constant(b, 1);
      otherwise(b); value(s, b, args[0]); constant(b, 0xffffffff); value(s, b, args[1]); op(b, 0x6e); op(b, 0x4d); end(b);
    }
    set(b, s.locals[result]); return true;
  }
  if tag == OP_CHECKED_ADD || tag == OP_CHECKED_SUB || tag == OP_CHECKED_MUL ||
     tag == OP_CHECKED_DIV || tag == OP_CHECKED_SHL || tag == OP_CHECKED_SHR {
    value_address(s, b, result); memory_zero(b, value_layout(s, result).size); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,value_layout(s,result).size);
    value_address(s, b, result); constant(b, 1); payload_store(s,b,0);
    if tag == OP_CHECKED_ADD { value(s, b, args[0]); constant(b, 0xffffffff); value(s, b, args[1]); op(b, 0x6b); op(b, 0x4d); }
    else if tag == OP_CHECKED_SUB { value(s, b, args[1]); value(s, b, args[0]); op(b, 0x4d); }
    else if tag == OP_CHECKED_MUL {
      value(s, b, args[1]); op(b, 0x45); op(b, 0x04); op(b, I32); constant(b, 1);
      otherwise(b); value(s, b, args[0]); constant(b, 0xffffffff); value(s, b, args[1]); op(b, 0x6e); op(b, 0x4d); end(b);
    } else if tag == OP_CHECKED_DIV { value(s, b, args[1]); constant(b, 0); op(b, 0x47); }
    else { value(s, b, args[1]); constant(b, 32); op(b, 0x49); }
    when(b);
    value_address(s, b, result); value(s, b, args[0]); value(s, b, args[1]);
    op(b, if tag == OP_CHECKED_ADD { 0x6a } else if tag == OP_CHECKED_SUB { 0x6b } else if tag == OP_CHECKED_MUL { 0x6c }
      else if tag == OP_CHECKED_DIV { 0x6e } else if tag == OP_CHECKED_SHL { 0x74 } else { 0x76 });
    payload_store(s,b,4); value_address(s, b, result); constant(b, 0); payload_store(s,b,0); end(b); reload_flat(s, b, result); return true;
  }
  if tag == OP_F32_TO_U32 {
    value_address(s, b, result); memory_zero(b, value_layout(s, result).size); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,value_layout(s,result).size);
    value_address(s, b, result); constant(b, 1); payload_store(s,b,0);
    value(s, b, args[0]); op(b, 0x43); b.append([0 as u8, 0, 0, 0]); op(b, 0x60);
    value(s, b, args[0]); op(b, 0x43); b.append([0 as u8, 0, 128, 79]); op(b, 0x5d); op(b, 0x71);
    when(b); value_address(s, b, result); value(s, b, args[0]); op(b, 0xa9); payload_store(s,b,4);
    value_address(s, b, result); constant(b, 0); payload_store(s,b,0); end(b); reload_flat(s, b, result); return true;
  }
  if tag == OP_RESERVE || tag == OP_OWNED_BEGIN {
    value_address(s, b, result); value(s, b, args[0]); constant(b, if tag == OP_OWNED_BEGIN { 1 } else { 0 }); call(b, s.helpers.reserve); reload_flat(s, b, result); return true;
  }
  if tag == OP_TRY_ALLOC || tag == OP_ENV_TRY_ALLOC {
    value_address(s, b, result); value(s, b, args[0]); load(b, 0); value(s, b, args[0]); load(b, 4); value(s, b, args[1]);
    if tag == OP_ENV_TRY_ALLOC { constant(b, 1); constant(b, 4); }
    else {
      if !id_ok(operation.imm0, s.core.types.len) { return opcode_diagnostic(diags, 3015, operation); }
      emit_size(s, b, operation.imm0, 0);
      emit_size(s, b, operation.imm0, 0); op(b, 0x45); op(b, 0x04); op(b, I32);
      constant(b, 1); otherwise(b); constant(b, 4); end(b);
    }
    call(b, s.helpers.place); reload_flat(s, b, result); return true;
  }
  if tag == OP_REGION_CLOSE || tag == OP_OWNED_ABORT || tag == OP_OWNED_CLOSE {
    value(s, b, args[0]); load(b, 0); value(s, b, args[0]); load(b, 4);
    constant(b, if tag == OP_REGION_CLOSE { 1 } else if tag == OP_OWNED_CLOSE { 2 } else { 4 });
    call(b, s.helpers.release); return true;
  }
  if tag == OP_REGION_RESET {
    value(s, b, args[0]); load(b, 0); value(s, b, args[0]); load(b, 4); call(b, s.helpers.reset);
    // Physical result is (Owner,Space); both derive from the unchanged handle.
    value_address(s, b, result); value(s, b, args[0]); memory_copy(b, 8); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,8); telemetry_add_const(s.module,b,runtime::T_COPIED,8);
    value_address(s, b, result); constant(b, 8); op(b, 0x6a); value(s, b, args[0]); memory_copy(b, 8); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,8); telemetry_add_const(s.module,b,runtime::T_COPIED,8); reload_flat(s, b, result); return true;
  }
  if tag == OP_OWNED_SEAL {
    let l = value_layout(s, args[1]);
    if !aggregate(l) { add_const(b, s.base, s.phi); store_value(s, b, args[1]); }
    value(s, b, args[0]); load(b, 0); value(s, b, args[0]); load(b, 4);
    if !emit_schema(s, b, s.core.values[args[1]].type_id) { return opcode_diagnostic(diags, 3037, operation); }
    if aggregate(l) { value(s, b, args[1]); } else { add_const(b, s.base, s.phi); }
    emit_size(s, b, s.core.values[args[1]].type_id, 0); constant(b, 2); op(b, 0x76); call(b, s.helpers.seal);
    copy_value(s, b, result, args[0]); return true;
  }
  if tag == OP_OWNED_OPEN {
    let l = value_layout(s, result);
    value(s, b, args[0]); load(b, 0); value(s, b, args[0]); load(b, 4);
    if !emit_schema(s, b, s.core.values[result].type_id) { return opcode_diagnostic(diags, 3037, operation); }
    emit_size(s, b, s.core.values[result].type_id, 0); constant(b, 2); op(b, 0x76); call(b, s.helpers.open);
    load_value(s, b, result); return true;
  }
  if tag == OP_VIEW_LEN || tag == OP_DEST_CAP || tag == OP_BUILDER_LEN || tag == OP_BUILDER_CAP {
    read_word(s, b, args[0], if tag == OP_BUILDER_CAP { 8 } else { 4 }); set(b, s.locals[result]); return true;
  }
  if tag == OP_BUILDER_BEGIN {
    read_word(s, b, args[0], 0); write_word(s, b, result, 0);
    constant(b, 0); write_word(s, b, result, 4);
    read_word(s, b, args[0], 4); write_word(s, b, result, 8); return true;
  }
  if tag == OP_BUILDER_APPEND || tag == OP_BUILDER_SET {
    let input = args[0]; let element = args[if tag == OP_BUILDER_SET { 2 } else { 1 }];
    let size = value_layout(s, element).size;
    read_word(s, b, input, 0);
    if tag == OP_BUILDER_SET { value(s, b, args[1]); } else { read_word(s, b, input, 4); }
    emit_size(s, b, s.core.values[element].type_id, 0); op(b, 0x6c); op(b, 0x6a); store_value(s, b, element);
    copy_value(s, b, result, input);
    if tag == OP_BUILDER_APPEND { read_word(s, b, input, 4); constant(b, 1); op(b, 0x6a); write_word(s, b, result, 4); }
    return true;
  }
  if tag == OP_BUILDER_TRUNCATE {
    copy_value(s, b, result, args[0]); value(s, b, args[1]); write_word(s, b, result, 4); return true;
  }
  if tag == OP_BUILDER_TRY_APPEND {
    let input = args[0]; let element = args[1]; let l = value_layout(s, element);
    value_address(s, b, result); memory_zero(b, value_layout(s, result).size); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,value_layout(s,result).size);
    value(s, b, input); load(b, 4); value(s, b, input); load(b, 8); op(b, 0x49); when(b);
    value(s, b, input); load(b, 0); value(s, b, input); load(b, 4); emit_size(s, b, s.core.values[element].type_id, 0); op(b, 0x6c); op(b, 0x6a); store_value(s, b, element);
    value_address(s, b, result); constant(b, 4); op(b, 0x6a); value(s, b, input); memory_copy(b, 12); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,12); telemetry_add_const(s.module,b,runtime::T_COPIED,12);
    value_address(s, b, result); value(s, b, input); load(b, 4); constant(b, 1); op(b, 0x6a); payload_store(s,b,8);
    otherwise(b);
    value_address(s, b, result); constant(b, 4); op(b, 0x6a); value(s, b, input); memory_copy(b, 12); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,12); telemetry_add_const(s.module,b,runtime::T_COPIED,12);
    value_address(s, b, result); constant(b, 16); op(b, 0x6a); store_value(s, b, element);
    value_address(s, b, result); constant(b, 1); payload_store(s,b,0); end(b); reload_flat(s, b, result); return true;
  }
  if tag == OP_BUILDER_FREEZE {
    let prefix = package_prefix(s.core, s.core.values[result].type_id);
    for i in prefix as i64 / 4 { read_word(s, b, args[0], 4); write_word(s, b, result, i as u32 * 4); }
    read_word(s, b, args[0], 4); op(b, 0x04); op(b, I32);
    read_word(s, b, args[0], 0); otherwise(b); constant(b, 0); end(b); write_word(s, b, result, prefix);
    read_word(s, b, args[0], 4); write_word(s, b, result, prefix + 4); return true;
  }
  if tag == OP_VIEW_INDEX || tag == OP_BUILDER_GET {
    read_word(s, b, args[0], 0); value(s, b, args[1]); emit_size(s, b, s.core.values[result].type_id, 0); op(b, 0x6c); op(b, 0x6a);
    load_value(s, b, result); return true;
  }
  if tag == OP_TRY_INDEX {
    value_address(s, b, result); memory_zero(b, value_layout(s, result).size); telemetry_add_const(s.module,b,runtime::T_INITIALIZED,value_layout(s,result).size);
    value(s, b, args[1]); value(s, b, args[0]); load(b, 4); op(b, 0x49); when(b);
    value_address(s, b, result); value(s, b, args[1]); payload_store(s,b,4);
    value_address(s, b, result); constant(b, 1); payload_store(s,b,0); end(b); reload_flat(s, b, result); return true;
  }
  if tag == OP_DEST_SPLIT || tag == OP_VIEW_SLICE {
    let type_row = s.core.types[underlying(s.core, s.core.values[args[0]].type_id)];
    let element_type = s.core.refs[type_row.children.start];
    let elem = layout(s.core, s.layouts, element_type);
    let prefix = if tag == OP_VIEW_SLICE { package_prefix(s.core, s.core.values[result].type_id) } else { 0 };
    if tag == OP_DEST_SPLIT {
      value_address(s, b, result);
      if elem.size == 0 { constant(b, 0); } else { value(s, b, args[0]); load(b, 0); }
      payload_store(s,b,0); value_address(s, b, result); value(s, b, args[1]); payload_store(s,b,4);
      value_address(s, b, result);
      if elem.size == 0 { constant(b, 0); }
      else { value(s, b, args[0]); load(b, 0); value(s, b, args[1]); emit_size(s, b, element_type, 0); op(b, 0x6c); op(b, 0x6a); }
      payload_store(s,b,8); value_address(s, b, result); value(s, b, args[0]); load(b, 4); value(s, b, args[1]); op(b, 0x6b); payload_store(s,b,12);
    } else {
      for i in prefix as i64 / 4 { value_address(s, b, result); value(s, b, args[2]); payload_store(s,b,i as u32 * 4); }
      value_address(s, b, result);
      if elem.size == 0 { constant(b, 0); }
      else {
        value(s, b, args[2]); op(b, 0x04); op(b, I32);
        value(s, b, args[0]); load(b, 0); value(s, b, args[1]); emit_size(s, b, element_type, 0); op(b, 0x6c); op(b, 0x6a);
        otherwise(b); constant(b, 0); end(b);
      }
      payload_store(s,b,prefix); value_address(s, b, result); value(s, b, args[2]); payload_store(s,b,prefix + 4);
    }
    reload_flat(s, b, result); return true;
  }
  if tag == OP_LAYOUT_SIZE || tag == OP_LAYOUT_ALIGN {
    if !id_ok(operation.imm0, s.core.types.len) { return opcode_diagnostic(diags, 3015, operation); }
    let l = layout(s.core, s.layouts, operation.imm0);
    emit_size(s, b, operation.imm0, 0);
    if tag == OP_LAYOUT_ALIGN { op(b, 0x45); op(b, 0x04); op(b, I32); constant(b, 1); otherwise(b); constant(b, 4); end(b); }
    set(b, s.locals[result]); return true;
  }
  return opcode_diagnostic(diags, 3009, operation);
}

fn emit_edge_values(s: Lowering, b: u8[>..]&, edge: Edge) {
  if s.module.telemetry { for loop_row,i in s.core.loops { if i!=0 && loop_row.header==edge.from && loop_row.body==edge.to { telemetry_add_const(s.module,b,runtime::T_LOOPS,1); } } }
  let args = refs(s.core, edge.args); let params = refs(s.core, s.core.blocks[edge.to].params);
  var registers = true;
  for arg in args { if aggregate(value_layout(s, arg)) && !flat(s, arg) { registers = false; } }
  for param in params { if aggregate(value_layout(s, param)) && !flat(s, param) { registers = false; } }
  if registers {
    for arg in args {
      if flat(s, arg) { for word in value_layout(s, arg).size / 4 { get(b, s.flat_locals[arg] + word); } }
      else { value(s, b, arg); }
    }
    var i = params.len;
    while i > 0 {
      i--; let param = params[i];
      if flat(s, param) {
        var word = value_layout(s, param).size / 4;
        while word > 0 { word--; set(b, s.flat_locals[param] + word); }
      } else if value_layout(s, param).abi != ABI_UNIT { set(b, s.locals[param]); }
    }
    return;
  }
  var offset = s.phi;
  // All edge sources are copied before any destination is changed (parallel phi).
  for arg in args {
    let l = value_layout(s, arg);
    add_const(b, s.base, offset); store_value(s, b, arg); offset += l.size;
  }
  offset = s.phi;
  for param in params {
    add_const(b, s.base, offset); load_value(s, b, param); offset += value_layout(s, param).size;
  }
}
fn emit_edge(s: Lowering, b: u8[>..]&, edge: Edge) { emit_edge_values(s, b, edge); constant(b, edge.to); set(b, s.pc); }
fn restore_frame(s: Lowering, b: u8[>..]&) {
  if s.own_frame != 0 { constant(b, s.module.map.control + 4); get(b, s.saved); store(b, 0); }
}
fn emit_terminator(s: Lowering, b: u8[>..]&, term: Terminator, diags: Diagnostic[>..]&) -> bool {
  if term.tag == TERM_RETURN {
    let plan = s.core.abi_plans[s.plans[s.function_id]]; let l = s.core.layouts[plan.result_layout];
    if l.abi == ABI_INDIRECT { get(b, 1); value(s, b, term.subject); copy_type(s, b, s.core.values[term.subject].type_id); }
    if s.module.telemetry { emit_size(s,b,s.core.values[term.subject].type_id,0); set(b,s.base+69); telemetry_high_local(s.module,b,runtime::T_RESULT_HIGH,s.base+69,0); }
    restore_frame(s, b);
    if l.abi == ABI_I32 || l.abi == ABI_F32 { value(s, b, term.subject); }
    op(b, 0x0f); return true;
  }
  if term.tag == TERM_UNREACHABLE { op(b, 0x00); return true; }
  let edges = refs(s.core, term.edges);
  if term.tag == TERM_JUMP { emit_edge(s, b, s.core.edges[edges[0]]); branch(b, 1); return true; }
  if term.tag == TERM_BRANCH {
    value(s, b, term.subject); when(b); emit_edge(s, b, s.core.edges[edges[0]]);
    otherwise(b); emit_edge(s, b, s.core.edges[edges[1]]); end(b); branch(b, 1); return true;
  }
  if term.tag == TERM_SWITCH {
    value(s, b, term.subject);
    if aggregate(value_layout(s, term.subject)) { load(b, 0); }
    set(b, s.tmp1);
    for edge in edges {
      let e = s.core.edges[edge]; get(b, s.tmp1); constant(b, e.case_tag); op(b, 0x46); when(b);
      emit_edge(s, b, e); branch(b, 2); end(b);
    }
    op(b, 0x00); return true;
  }
  diags.push(Diagnostic {3016, term.origin, term.tag, 0}); return false;
}
fn abi_parameters(c: Core, plan: AbiPlan, out: u8[>..]&) -> u8 {
  out.push(I32); // Every canonical entry starts with environment.
  let result = c.layouts[plan.result_layout];
  if result.abi == ABI_INDIRECT { out.push(I32); }
  for binder in refs(c, plan.dictionaries) { out.push(I32); }
  for witness in refs(c, plan.nat_witnesses) { if c.nat_witnesses[witness].selector == NAT_HIDDEN { out.push(I32); } }
  let arg = c.layouts[plan.arg_layout];
  if arg.abi != ABI_UNIT { out.push(if arg.abi == ABI_F32 { F32 } else { I32 }); }
  return if result.abi == ABI_F32 { F32 } else if result.abi == ABI_I32 { I32 } else { 0 };
}
struct ControlLabel { target: u32, level: u32 }
fn loop_header(c: Core, block_id: u32) -> u32 {
  for row, i in c.loops { if i != 0 && row.header == block_id { return i as u32; } } return 0;
}
fn structured_eligible(c: Core, fid: u32) -> bool {
  var unmerged = false;
  for block_id in refs(c, c.functions[fid].blocks) {
    let row = c.blocks[block_id]; let term = c.terminators[row.term];
    if (term.tag == TERM_BRANCH || term.tag == TERM_SWITCH) && row.merge == 0 { unmerged = true; }
  }
  if unmerged {
    // Early-return trees need no program-counter dispatch. Repeated targets
    // reject reachable cycles and shared tails without merge rows. This list
    // holds at most one ID per function block, independent of module size.
    // Larger/unstructured graphs retain the general dispatcher unchanged.
    if c.functions[fid].blocks.count > 64 { return false; }
    var incoming: u32[>..] = [c.functions[fid].entry];
    for block_id in refs(c, c.functions[fid].blocks) {
      for edge_id in refs(c, c.terminators[c.blocks[block_id].term].edges) {
        let target = c.edges[edge_id].to;
        for previous in incoming { if previous == target { return false; } }
        incoming.push(target);
      }
    }
  }
  for block_id in refs(c, c.functions[fid].blocks) {
    let row = c.blocks[block_id]; let term = c.terminators[row.term]; let loop_id = loop_header(c, block_id);
    if loop_id != 0 {
      let loop_row = c.loops[loop_id];
      if term.tag != TERM_BRANCH || term.edges.count != 2 { return false; }
      let yes = c.edges[c.refs[term.edges.start]]; let no = c.edges[c.refs[term.edges.start + 1]];
      if yes.to != loop_row.body || no.to != loop_row.exit { return false; }
    }
  }
  return true;
}
fn branch_control(b: u8[>..]&, target: u32, labels: const ControlLabel[:], nesting: u32) -> bool {
  var i = labels.len;
  while i > 0 { i--; if labels[i].target == target { assert(nesting >= labels[i].level); branch(b, nesting - labels[i].level); return true; } }
  return false;
}
recursive fn emit_structured(s: Lowering, b: u8[>..]&, start: u32, stop: u32,
                             labels: ControlLabel[>..<]&, nesting: u32, seen: bool[:],
                             diagnostics: Diagnostic[>..]&, depth: u32) -> bool {
  if depth > 64 { diagnostics.push(Diagnostic {3035, 0, start, depth}); return false; }
  var current = start;
  while current != 0 && current != stop {
    if seen[current] { diagnostics.push(Diagnostic {3035, 0, current, 0}); return false; }
    seen[current] = true;
    let row = s.core.blocks[current]; let term = s.core.terminators[row.term];
    let loop_id = loop_header(s.core, current);
    if loop_id != 0 {
      let loop_row = s.core.loops[loop_id];
      begin_block(b); labels.push(ControlLabel {loop_row.exit, nesting + 1});
      begin_loop(b); labels.push(ControlLabel {loop_row.header, nesting + 2});
      for operation in refs(s.core, row.ops) { if !emit_operation(s, b, operation, s.core.ops[operation], diagnostics) { return false; } }
      value(s, b, term.subject); op(b, 0x45); when(b);
      emit_edge_values(s, b, s.core.edges[s.core.refs[term.edges.start + 1]]); branch(b, 2); end(b);
      let edge = s.core.edges[s.core.refs[term.edges.start]]; emit_edge_values(s, b, edge);
      if !emit_structured(s, b, edge.to, loop_row.header, labels, nesting + 2, seen, diagnostics, depth + 1) { return false; }
      end(b); end(b); labels.pop(); labels.pop(); current = loop_row.exit; continue;
    }
    for operation in refs(s.core, row.ops) { if !emit_operation(s, b, operation, s.core.ops[operation], diagnostics) { return false; } }
    if term.tag == TERM_RETURN || term.tag == TERM_UNREACHABLE { return emit_terminator(s, b, term, diagnostics); }
    let edges = refs(s.core, term.edges);
    if term.tag == TERM_JUMP {
      let edge = s.core.edges[edges[0]]; emit_edge_values(s, b, edge);
      if branch_control(b, edge.to, labels, nesting) { return true; }
      current = edge.to; continue;
    }
    if term.tag == TERM_BRANCH {
      value(s, b, term.subject); when(b);
      let yes = s.core.edges[edges[0]]; emit_edge_values(s, b, yes);
      if !branch_control(b, yes.to, labels, nesting + 1) && yes.to != row.merge {
        if !emit_structured(s, b, yes.to, row.merge, labels, nesting + 1, seen, diagnostics, depth + 1) { return false; }
      }
      otherwise(b); let no = s.core.edges[edges[1]]; emit_edge_values(s, b, no);
      if !branch_control(b, no.to, labels, nesting + 1) && no.to != row.merge {
        if !emit_structured(s, b, no.to, row.merge, labels, nesting + 1, seen, diagnostics, depth + 1) { return false; }
      }
      end(b); current = row.merge; continue;
    }
    if term.tag == TERM_SWITCH {
      value(s, b, term.subject); if aggregate(value_layout(s, term.subject)) { load(b, 0); } set(b, s.tmp1);
      for edge_id, i in edges {
        let edge = s.core.edges[edge_id]; get(b, s.tmp1); constant(b, edge.case_tag); op(b, 0x46); when(b);
        emit_edge_values(s, b, edge);
        if !branch_control(b, edge.to, labels, nesting + i as u32 + 1) && edge.to != row.merge {
          if !emit_structured(s, b, edge.to, row.merge, labels, nesting + i as u32 + 1, seen, diagnostics, depth + 1) { return false; }
        }
        otherwise(b);
      }
      op(b, 0x00); for edge in edges { end(b); } current = row.merge; continue;
    }
    diagnostics.push(Diagnostic {3035, term.origin, term.tag, 0}); return false;
  }
  return true;
}
fn lower_function(c: Core, m: ModuleBuilder&, h: Helpers, layouts: const u32[:],
                  functions: const u32[:], signatures: const u32[:], plans: const u32[:], adapter_codes: const u32[:], adapter_entries: const Adapter[:], static_addresses: const u32[:],
                  fid: u32, diags: Diagnostic[>..]&) -> bool {
  let f = c.functions[fid]; let plan = c.abi_plans[plans[fid]];
  let indirect_start = m.indirect_contracts.len as u32;
  var params: u8[>..] = []; let result_type = abi_parameters(c, plan, params);
  var included: bool[>..] = []; var local_ids: u32[>..] = []; var flat_ids: u32[>..] = [];
  var offsets: u32[>..] = []; var environments: u32[>..] = [];
  var call_arguments: u32[>..] = []; var call_results: u32[>..] = [];
  for operation in c.ops { call_arguments.push(0); call_results.push(0); }
  for v, i in c.values {
    included.push(i != 0 && ((id_ok(v.block_id, c.blocks.len) && c.blocks[v.block_id].function == fid) || i == f.param));
    local_ids.push(0); flat_ids.push(0); offsets.push(0); environments.push(0);
  }
  for capture in refs(c, f.captures) { included[c.captures[capture].local_value] = true; }
  var i32_count: u32 = 0; var f32_count: u32 = 0; var frame: u32 = 0;
  for v, i in c.values {
    if !included[i] { continue; }
    let l = layout(c, layouts, v.type_id);
    if l.abi == ABI_I32 { local_ids[i] = params.len as u32 + i32_count; i32_count++; }
    if l.abi == ABI_F32 { f32_count++; }
    if l.abi == ABI_INDIRECT {
      if fixed_layout(c, v.type_id, 0) { flat_ids[i] = params.len as u32 + i32_count; i32_count += l.size / 4; }
      // A nonflat indirect parameter already has stable caller-owned storage.
      // Keep baseline resource admission conservative; omit only this physical
      // slot and entry copy after the completed body has been admitted.
      if i == f.param && flat_ids[i] == 0 { continue; }
      offsets[i] = frame;
      if l.size > 16 * 1024 * 1024 - frame { diags.push(Diagnostic {3020, f.origin, frame, l.size}); return false; }
      frame += l.size;
    }
  }
  let base = params.len as u32 + i32_count;
  var f32_local = base + 69 + (if m.telemetry {1 as u32} else {0});
  for v, i in c.values { if included[i] && layout(c, layouts, v.type_id).abi == ABI_F32 { local_ids[i] = f32_local; f32_local++; } }
  var phi_bytes: u32 = 0;
  for block_id in refs(c, f.blocks) {
    let row = c.blocks[block_id];
    for edge_id in refs(c, c.terminators[row.term].edges) {
      var bytes: u32 = 0;
      for value_id in refs(c, c.edges[edge_id].args) { bytes += layout(c, layouts, c.values[value_id].type_id).size; }
      phi_bytes = max(phi_bytes, bytes);
    }
    for op_id in refs(c, row.ops) {
      let operation = c.ops[op_id];
      if operation.tag == OP_CALL {
        let target_plan = c.abi_plans[plans[operation.imm0]];
        let argument = c.refs[operation.args.start]; let result = c.refs[operation.results.start];
        let actual_arg = layout(c, layouts, c.values[argument].type_id);
        let actual_result = layout(c, layouts, c.values[result].type_id);
        if c.layouts[target_plan.arg_layout].abi == ABI_INDIRECT && actual_arg.abi != ABI_INDIRECT {
          call_arguments[op_id] = frame; frame += actual_arg.size;
        }
        if c.layouts[target_plan.result_layout].abi == ABI_INDIRECT && actual_result.abi != ABI_INDIRECT {
          call_results[op_id] = frame; frame += actual_result.size;
        }
      }
      if operation.tag == OP_CLOSURE {
        let result = c.refs[operation.results.start]; environments[result] = frame;
        let adapter_id = callable_adapter(c, op_id);
        if adapter_id != 0 { frame += c.layouts[c.callable_adapters[adapter_id].environment_layout].size; }
        else { frame += c.layouts[c.abi_plans[plans[operation.imm0]].env_layout].size; }
      }
      if operation.tag == OP_OWNED_SEAL {
        let value_id = c.refs[operation.args.start + 1];
        phi_bytes = max(phi_bytes, layout(c, layouts, c.values[value_id].type_id).size);
      }
    }
  }
  let phi = frame; frame += phi_bytes;
  if frame > plan.frame || frame > m.map.frame_bytes {
    diags.push(Diagnostic {3020, f.origin, frame, plan.frame}); return false;
  }
  let s = Lowering {c, m, h, layouts, functions, signatures, plans, local_ids[..], offsets[..],
    flat_ids[..], adapter_entries, static_addresses, adapter_codes, environments[..], call_arguments[..], call_results[..], fid, base, base + 1, base + 2, base + 3, base + 4, phi, frame, params.len as u32};
  var b: u8[>..] = [];
  uleb(b, if f32_count == 0 { 1 } else { 2 }); uleb(b, i32_count + 69 + (if m.telemetry {1 as u32} else {0})); op(b, I32);
  if f32_count != 0 { uleb(b, f32_count); op(b, F32); }
  // A zero-byte activation has no local frame addresses or frontier mutation.
  // Public wrappers still preflight the complete allowance before effects.
  if frame != 0 {
    constant(b, m.map.control + 4); load(b, 0); tee(b, s.saved);
    constant(b, m.map.frame_bytes - frame); op(b, 0x4b); trap_if(b);
    add_const(b, s.saved, m.map.frame); set(b, s.base);
    constant(b, m.map.control + 4); add_const(b, s.saved, frame); store(b, 0);
  } else if m.telemetry {
    // Attribute a zero-byte callee to its caller's actual live frontier.
    constant(b, m.map.control + 4); load(b, 0); set(b, s.saved);
  }
  telemetry_add_const(m,b,runtime::T_CALLS,1); telemetry_high_local(m,b,runtime::T_SCRATCH_HIGH,s.saved,frame);
  let arg = c.layouts[plan.arg_layout];
  if arg.abi == ABI_INDIRECT {
    if !borrowed_parameter(s, f.param) { get(b, params.len as u32 - 1); load_value(s, b, f.param); }
  } else if arg.abi != ABI_UNIT { get(b, params.len as u32 - 1); set(b, local_ids[f.param]); }
  for capture_id, i in refs(c, f.captures) {
    let capture = c.captures[capture_id]; get(b, 0); constant(b, f.environment_bindings.count * 4); op(b, 0x6a);
    for prior in i { let earlier = c.captures[c.refs[f.captures.start + prior]]; emit_size(s, b, c.values[earlier.local_value].type_id, 0); op(b, 0x6a); }
    load_value(s, b, capture.local_value);
  }
  if structured_eligible(c, fid) {
    var labels: ControlLabel[>..<] = []; var seen: bool[>..] = []; for row in c.blocks { seen.push(false); }
    if !emit_structured(s, b, f.entry, 0, labels, 0, seen, diags, 0) { return false; }
  } else if f.blocks.count == 1 {
    let row = c.blocks[c.refs[f.blocks.start]];
    for operation in refs(c, row.ops) { if !emit_operation(s, b, operation, c.ops[operation], diags) { return false; } }
    if !emit_terminator(s, b, c.terminators[row.term], diags) { return false; }
  } else {
    constant(b, f.entry); set(b, s.pc);
    begin_loop(b);
    for block_id in refs(c, f.blocks) {
      get(b, s.pc); constant(b, block_id); op(b, 0x46); when(b);
      let row = c.blocks[block_id];
      for operation in refs(c, row.ops) { if !emit_operation(s, b, operation, c.ops[operation], diags) { return false; } }
      if !emit_terminator(s, b, c.terminators[row.term], diags) { return false; }
      end(b);
    }
    op(b, 0x00); end(b);
  }
  op(b, 0x00); end(b); // No unspecified fallthrough result.
  var compacted: u8[>..] = [];
  if !compact_locals(b, params.len as u32, compacted) { diags.push(Diagnostic {3038, f.origin, fid, 0}); return false; }
  let emitted = function(m, signatures[fid], compacted); assert(emitted == functions[fid]);
  m.functions[emitted].indirect = Span {indirect_start, m.indirect_contracts.len as u32 - indirect_start};
  m.functions[emitted].role = 2; m.functions[emitted].source = fid; m.functions[emitted].contract = f.contract;
  let body_frame,body_depth,body_ok=wasm_body_resources(c,fid); if !body_ok { return false; }
  m.functions[emitted].own_frame = frame; m.functions[emitted].frame = body_frame; m.functions[emitted].depth = body_depth; return true;
}
recursive fn scalar_term(c: Core, contract: u32, term: u32, b: u8[>..]&, depth: u32) -> bool {
  if depth > 64 || !id_ok(term, c.terms.len) { return false; }
  let t = c.terms[term];
  if t.tag == EXPR_LITERAL { constant(b, t.literal); return true; }
  if t.tag == EXPR_ARG && t.binder == contract && c.types[underlying(c, c.contracts[contract].arg)].tag == TY_U32 {
    get(b, 0); return true;
  }
  if t.tag == EXPR_MAX_MINUS && t.args.count == 1 {
    constant(b, 0xffffffff);
    if !scalar_term(c, contract, c.refs[t.args.start], b, depth + 1) { return false; }
    op(b, 0x6b); return true;
  }
  return false;
}
fn scalar_predicate(c: Core, contract: u32, fact: Fact, b: u8[>..]&) -> bool {
  if fact.tag == FACT_SUB_FITS {
    if !scalar_term(c, contract, fact.right, b, 0) || !scalar_term(c, contract, fact.left, b, 0) { return false; }
    op(b, 0x4d); return true;
  }
  if fact.tag == FACT_ADD_FITS {
    if !scalar_term(c, contract, fact.left, b, 0) { return false; }
    constant(b, 0xffffffff); if !scalar_term(c, contract, fact.right, b, 0) { return false; }
    op(b, 0x6b); op(b, 0x4d); return true;
  }
  if fact.tag == FACT_MUL_FITS {
    if !scalar_term(c, contract, fact.right, b, 0) { return false; }
    op(b, 0x45); op(b, 0x04); op(b, I32); constant(b, 1); otherwise(b);
    if !scalar_term(c, contract, fact.left, b, 0) { return false; }
    constant(b, 0xffffffff); if !scalar_term(c, contract, fact.right, b, 0) { return false; }
    op(b, 0x6e); op(b, 0x4d); end(b); return true;
  }
  if fact.tag == FACT_EQ || fact.tag == FACT_LT || fact.tag == FACT_LE {
    if !scalar_term(c, contract, fact.left, b, 0) || !scalar_term(c, contract, fact.right, b, 0) { return false; }
    op(b, if fact.tag == FACT_EQ { 0x46 } else if fact.tag == FACT_LT { 0x49 } else { 0x4d }); return true;
  }
  return false; // A scalar host argument cannot supply Index authority.
}
fn scalar_export(c: Core, m: ModuleBuilder&, functions: const u32[:], plans: const u32[:], ex: Export,
                 diags: Diagnostic[>..]&) -> bool {
  let fid = ex.function; let f = c.functions[fid]; let plan = c.abi_plans[plans[fid]];
  let indirect_start = m.indirect_contracts.len as u32;
  let argument = c.layouts[plan.arg_layout]; let result = c.layouts[plan.result_layout];
  if aggregate(argument) || aggregate(result) || f.captures.count != 0 || plan.dictionaries.count != 0 || plan.nat_witnesses.count != 0 {
    diags.push(Diagnostic {3021, f.origin, fid, 0}); return false;
  }
  var params: u8[>..] = [];
  if argument.abi != ABI_UNIT { params.push(if argument.abi == ABI_F32 { F32 } else { I32 }); }
  let ret = if result.abi == ABI_UNIT { 0 as u8 } else if result.abi == ABI_F32 { F32 } else { I32 };
  let sig = signature(m, params, ret); var b: u8[>..] = []; local_declarations(b, 0, I32);
  // Raw host scalars supply no proof evidence. Reject invalid inputs before
  // entering a checked body; this ABI has no status/result failure envelope.
  if c.types[underlying(c, c.contracts[f.contract].arg)].tag == TY_BOOL {
    get(b, 0); constant(b, 1); op(b, 0x4b); trap_if(b);
  }
  for fact_id in refs(c, c.contracts[f.contract].requires) {
    if !scalar_predicate(c, f.contract, c.facts[fact_id], b) {
      diags.push(Diagnostic {3025, f.origin, fact_id, 0}); return false;
    }
    op(b, 0x45); trap_if(b);
  }
  // Public entry preflight occurs before the source body can have effects.
  if plan.frame > m.map.frame_bytes { diags.push(Diagnostic {3020, f.origin, plan.frame, m.map.frame_bytes}); return false; }
  constant(b, m.map.control + 4); load(b, 0); constant(b, m.map.frame_bytes - plan.frame); op(b, 0x4b); trap_if(b);
  constant(b, 0); if argument.abi != ABI_UNIT { get(b, 0); } call(b, functions[fid]); end(b);
  let index = function(m, sig, b); m.functions[index].role = 3; m.functions[index].source = fid;
  m.functions[index].frame = plan.frame; m.functions[index].depth = plan.depth + 1;
  export_function(m, name_bytes(c, ex.name), index); return true;
}

recursive fn wire_plain(c: Core, layouts: const u32[:], type_id: u32, depth: u32) -> bool {
  if depth > 32 { return false; }
  let id = underlying(c, type_id); let t = c.types[id];
  if t.domain != 0 || t.tag == TY_INDEX || (layout(c, layouts, id).flags & 1) == 0 { return false; }
  if t.tag == TY_UNIT || t.tag == TY_U32 || t.tag == TY_BOOL || t.tag == TY_F32 { return true; }
  if t.tag != TY_TUPLE && t.tag != TY_RECORD && t.tag != TY_SUM && t.tag != TY_EXISTS { return false; }
  for binder in refs(c, t.binders) { if c.binders[binder].kind == KIND_DOMAIN { return false; } }
  for i in type_children(c, id) { if !wire_plain(c, layouts, type_child(c, id, i as u32), depth + 1) { return false; } }
  return true;
}
fn bridge_fail_if(b: u8[>..]&, status: u32, outer_depth: u32) {
  when(b); constant(b, status); set(b, 3); branch(b, outer_depth + 1); end(b);
}
recursive fn plain_guard(c: Core, layouts: const u32[:], type_id: u32, b: u8[>..]&, base: u32,
                         offset: u32, exit_depth: u32, depth: u32) {
  assert(depth <= 32); let id = underlying(c, type_id); let t = c.types[id];
  if t.tag == TY_BOOL { read_local(b, base, offset); constant(b, 1); op(b, 0x4b); bridge_fail_if(b, 1, exit_depth); }
  if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_EXISTS {
    var at = offset + package_prefix(c, id);
    for i in type_children(c, id) {
      let child = type_child(c, id, i as u32); plain_guard(c, layouts, child, b, base, at, exit_depth, depth + 1);
      at += layout(c, layouts, child).size;
    }
  }
  if t.tag == TY_SUM {
    let count = type_children(c, id);
    read_local(b, base, offset); constant(b, count); op(b, 0x4f); bridge_fail_if(b, 1, exit_depth);
    for i in count {
      let child = type_child(c, id, i as u32); let used = layout(c, layouts, child).size;
      read_local(b, base, offset); constant(b, i as u32); op(b, 0x46); when(b);
      plain_guard(c, layouts, child, b, base, offset + 4, exit_depth + 1, depth + 1);
      for word in (layout(c, layouts, id).size - used - 4) / 4 {
        read_local(b, base, offset + 4 + used + word * 4); bridge_fail_if(b, 1, exit_depth + 1);
      }
      end(b);
    }
  }
}
fn known_field_offset(c: Core, layouts: const u32[:], type_id: u32, ordinal: u32) -> u32 {
  var offset: u32 = 0;
  for i in ordinal { offset += layout(c, layouts, type_child(c, type_id, i as u32)).size; }
  return offset;
}
recursive fn argument_path(c: Core, term: u32, contract: u32, path: u32[>..]&, depth: u32) -> bool {
  if depth > 64 || !id_ok(term, c.terms.len) { return false; }
  let t = c.terms[term];
  if t.tag == EXPR_ARG { return t.binder == contract; }
  if t.tag == EXPR_FIELD && t.args.count == 1 {
    if !argument_path(c, c.refs[t.args.start], contract, path, depth + 1) { return false; }
    path.push(t.literal); return true;
  }
  return false;
}
fn wire_location(c: Core, layouts: const u32[:], ex: Export, path: const u32[:]) -> u32, u32, bool {
  if path.len == 0 { return 0, ex.arg_type, true; }
  var type_id = underlying(c, ex.arg_type); var offset: u32 = 0;
  for ordinal, level in path {
    if ordinal >= type_children(c, type_id) { return 0, 0, false; }
    for preceding in ordinal {
      let sibling = underlying(c, type_child(c, type_id, preceding as u32));
      if level != 0 || c.types[sibling].tag != TY_DEST { offset += layout(c, layouts, sibling).size; }
    }
    type_id = underlying(c, type_child(c, type_id, ordinal));
  }
  return offset, type_id, true;
}
fn emit_wire_observation(c: Core, layouts: const u32[:], ex: Export, path: const u32[:],
                         observation: u32, map: runtime::MemoryMap, b: u8[>..]&) -> bool {
  let offset, type_id, ok = wire_location(c, layouts, ex, path); if !ok { return false; }
  let t = c.types[type_id];
  if observation == EXPR_CAP && t.tag == TY_DEST { constant(b, ex.output_capacity); return true; }
  if observation == EXPR_LEN && t.tag == TY_VIEW { constant(b, map.ingress + 32 + offset); load(b, 0); return true; }
  if observation == EXPR_FIELD && (t.tag == TY_U32 || t.tag == TY_BOOL) {
    constant(b, map.ingress + 32 + offset); load(b, 0); return true;
  }
  return false;
}
recursive fn bridge_term(c: Core, layouts: const u32[:], plans: const u32[:], ex: Export,
                         term: u32, map: runtime::MemoryMap, b: u8[>..]&, depth: u32) -> bool {
  if depth > 64 || !id_ok(term, c.terms.len) { return false; }
  let t = c.terms[term];
  if t.tag == EXPR_LITERAL { constant(b, t.literal); return true; }
  if t.tag == EXPR_MAX_MINUS && t.args.count == 1 {
    constant(b, 0xffffffff);
    if !bridge_term(c, layouts, plans, ex, c.refs[t.args.start], map, b, depth + 1) { return false; }
    op(b, 0x6b); return true;
  }
  if t.tag == EXPR_BINDER {
    let plan = c.abi_plans[plans[ex.function]];
    for witness_id in refs(c, plan.nat_witnesses) {
      let witness = c.nat_witnesses[witness_id];
      if witness.binder == t.binder {
        let observation = if witness.selector == NAT_VIEW_LEN { EXPR_LEN } else if witness.selector == NAT_DEST_CAP { EXPR_CAP } else { 0 };
        if observation == 0 { return false; }
        return emit_wire_observation(c, layouts, ex, refs(c, witness.argument_path), observation, map, b);
      }
    }
    return false;
  }
  if t.tag == EXPR_FIELD || ((t.tag == EXPR_LEN || t.tag == EXPR_CAP || t.tag == EXPR_INIT) && t.args.count == 1) {
    var path: u32[>..] = [];
    let base = if t.tag == EXPR_FIELD { term } else { c.refs[t.args.start] };
    if !argument_path(c, base, c.functions[ex.function].contract, path, depth + 1) { return false; }
    return emit_wire_observation(c, layouts, ex, path, t.tag, map, b);
  }
  return false;
}
fn bridge_predicate(c: Core, layouts: const u32[:], plans: const u32[:], ex: Export, fact: Fact,
                    map: runtime::MemoryMap, b: u8[>..]&) -> bool {
  if fact.tag == FACT_SUB_FITS {
    if !bridge_term(c, layouts, plans, ex, fact.right, map, b, 0) || !bridge_term(c, layouts, plans, ex, fact.left, map, b, 0) { return false; }
    op(b, 0x4d); return true;
  }
  if fact.tag == FACT_ADD_FITS {
    if !bridge_term(c, layouts, plans, ex, fact.left, map, b, 0) { return false; }
    constant(b, 0xffffffff); if !bridge_term(c, layouts, plans, ex, fact.right, map, b, 0) { return false; }
    op(b, 0x6b); op(b, 0x4d); return true;
  }
  if fact.tag == FACT_MUL_FITS {
    if !bridge_term(c, layouts, plans, ex, fact.right, map, b, 0) { return false; }
    op(b, 0x45); op(b, 0x04); op(b, I32); constant(b, 1); otherwise(b);
    if !bridge_term(c, layouts, plans, ex, fact.left, map, b, 0) { return false; }
    constant(b, 0xffffffff); if !bridge_term(c, layouts, plans, ex, fact.right, map, b, 0) { return false; }
    op(b, 0x6e); op(b, 0x4d); end(b); return true;
  }
  if fact.tag == FACT_EQ || fact.tag == FACT_LT || fact.tag == FACT_LE {
    if !bridge_term(c, layouts, plans, ex, fact.left, map, b, 0) || !bridge_term(c, layouts, plans, ex, fact.right, map, b, 0) { return false; }
    op(b, if fact.tag == FACT_EQ { 0x46 } else if fact.tag == FACT_LT { 0x49 } else { 0x4d }); return true;
  }
  return false; // Wire schemas never import Index authority.
}
fn bridge_schema(c: Core, layouts: const u32[:], ex: Export, diags: Diagnostic[>..]&) -> u32, u32, u32, bool {
  let f = c.functions[ex.function]; let ct = c.contracts[f.contract];
  let argument = underlying(c, ex.arg_type); let result = underlying(c, ex.result_type);
  if f.captures.count != 0 || c.types[underlying(c, f.type_id)].mode != MODE_MANY || c.types[argument].tag != TY_RECORD || c.types[result].tag != TY_RESULT {
    diags.push(Diagnostic {3023, f.origin, ex.function, 0}); return 0, 0, 0, false;
  }
  let success = underlying(c, type_child(c, result, 0)); let failure = underlying(c, type_child(c, result, 1));
  if c.types[success].tag != TY_EXISTS { diags.push(Diagnostic {3023, f.origin, success, 0}); return 0, 0, 0, false; }
  let view = underlying(c, type_child(c, success, 0));
  if c.types[view].tag != TY_VIEW || package_prefix(c, success) != 4 {
    diags.push(Diagnostic {3023, f.origin, view, 0}); return 0, 0, 0, false;
  }
  let output_type = type_child(c, view, 0);
  if !wire_plain(c, layouts, output_type, 0) { diags.push(Diagnostic {3024, f.origin, output_type, 0}); return 0, 0, 0, false; }
  if c.types[failure].tag != TY_UNIT {
    if c.types[failure].tag != TY_SUM { diags.push(Diagnostic {3023, f.origin, failure, 0}); return 0, 0, 0, false; }
    for i in type_children(c, failure) { if layout(c, layouts, type_child(c, failure, i as u32)).size != 0 { diags.push(Diagnostic {3023, f.origin, failure, 0}); return 0, 0, 0, false; } }
  }
  // Only capabilities supplied in the argument can account for source effects.
  for effect in refs(c, ct.effects) {
    let e = c.effects[effect]; var accounted = false;
    if e.kind == EFFECT_READ || e.kind == EFFECT_WRITE {
      for i in type_children(c, argument) {
        let field = c.types[underlying(c, type_child(c, argument, i as u32))];
        if field.region != 0 && field.region == e.region &&
          (field.tag == TY_DEST || (field.tag == TY_VIEW && e.kind == EFFECT_READ)) { accounted = true; }
      }
    }
    if !accounted { diags.push(Diagnostic {3025, f.origin, e.kind, e.region}); return 0, 0, 0, false; }
  }
  var outputs: u32 = 0; var inputs: u32 = 0; var fixed: u32 = 0; var worst: u64 = 0;
  var domains: u32[>..] = [];
  for i in type_children(c, argument) {
    let field = underlying(c, type_child(c, argument, i as u32)); let t = c.types[field];
    if t.tag == TY_DEST {
      outputs++;
      if layout(c, layouts, type_child(c, field, 0)).schema != layout(c, layouts, output_type).schema {
        diags.push(Diagnostic {3023, f.origin, field, 0}); return 0, 0, 0, false;
      }
      worst += ex.output_capacity as u64 * layout(c, layouts, output_type).size;
    } else if t.tag == TY_VIEW {
      if t.domain == 0 { diags.push(Diagnostic {3028, f.origin, field, 0}); return 0, 0, 0, false; }
      for previous in domains { if previous == t.domain { diags.push(Diagnostic {3028, f.origin, field, t.domain}); return 0, 0, 0, false; } }
      domains.push(t.domain);
      let elem = type_child(c, field, 0);
      if !wire_plain(c, layouts, elem, 0) || inputs >= ex.input_maxima.count { diags.push(Diagnostic {3024, f.origin, elem, 0}); return 0, 0, 0, false; }
      worst += c.refs[ex.input_maxima.start + inputs] as u64 * layout(c, layouts, elem).size;
      inputs++; fixed += 8;
    } else {
      if !wire_plain(c, layouts, field, 0) { diags.push(Diagnostic {3024, f.origin, field, 0}); return 0, 0, 0, false; }
      fixed += layout(c, layouts, field).size;
    }
  }
  if outputs != 1 || inputs != ex.input_maxima.count || worst > ex.work_bytes {
    diags.push(Diagnostic {3026, f.origin, ex.work_bytes, outputs}); return 0, 0, 0, false;
  }
  for binder in refs(c, ct.binders) {
    let kind = c.binders[binder].kind;
    if kind == KIND_REGION || kind == KIND_DOMAIN {
      var mapped = false;
      for i in type_children(c, argument) {
        let field = c.types[underlying(c, type_child(c, argument, i as u32))];
        if (kind == KIND_REGION && field.region == binder && (field.tag == TY_VIEW || field.tag == TY_DEST)) ||
           (kind == KIND_DOMAIN && field.tag == TY_VIEW && field.domain == binder) { mapped = true; }
      }
      if !mapped { diags.push(Diagnostic {3028, f.origin, binder, 0}); return 0, 0, 0, false; }
    }
  }
  return output_type, failure, fixed, true;
}
fn bridge_export(c: Core, m: ModuleBuilder&, h: Helpers, layouts: const u32[:], functions: const u32[:],
                 plans: const u32[:], ex: Export, export_id: u32, diags: Diagnostic[>..]&) -> u32, bool {
  let output_type, error_type, fixed, eligible = bridge_schema(c, layouts, ex, diags);
  if !eligible { return 0, false; }
  let argument = underlying(c, ex.arg_type); let arg_size = layout(c, layouts, argument).size;
  let result_size = layout(c, layouts, ex.result_type).size;
  let own_frame = arg_size + result_size + 20;
  let plan = c.abi_plans[plans[ex.function]];
  if own_frame > ex.frame || plan.frame > ex.frame - own_frame || ex.depth < 2 + max(plan.depth, 2) {
    diags.push(Diagnostic {3027, c.functions[ex.function].origin, own_frame + plan.frame, ex.frame}); return 0, false;
  }
  let out_stride = layout(c, layouts, output_type).size;
  let sig = signature(m, [I32, I32, I32], I32);
  var b: u8[>..] = []; local_declarations(b, 22, I32);
  // 3=status 4=saved frame 5=frame base 6=slot 7=generation 8=required
  // 9=items 10=detail 11=payload bytes 12=i 13=source 14=count 15=destination
  // 16=bytes 17=arg pointer 18=result pointer 19/20=temporaries 21=region base
  // 22=payload size 23=helper result pointer 24=reserved.
  constant(b, m.map.control); load(b, 0); when(b); constant(b, 4); op(b, 0x0f); end(b);
  constant(b, m.map.control); constant(b, 1); store(b, 0);
  constant(b, m.map.control + 4); load(b, 0); set(b, 4);
  constant(b, 1); set(b, 3);
  begin_block(b); // Every recoverable status exits to the same cleanup block.
  get(b, 0); constant(b, export_id); op(b, 0x47); bridge_fail_if(b, 1, 0);
  get(b, 1); constant(b, 32); op(b, 0x49); bridge_fail_if(b, 1, 0);
  get(b, 1); constant(b, m.map.ingress_bytes); op(b, 0x4b); bridge_fail_if(b, 1, 0);
  get(b, 2); constant(b, m.map.egress_bytes - 32); op(b, 0x4b); bridge_fail_if(b, 1, 0);
  constant(b, m.map.ingress); set(b, 13);
  read_local(b, 13, 0); constant(b, runtime::ABI_TAG); op(b, 0x47); bridge_fail_if(b, 1, 0);
  read_local(b, 13, 4); get(b, 0); op(b, 0x47); bridge_fail_if(b, 1, 0);
  for offset in [8 as u32, 16, 20, 24, 28] { read_local(b, 13, offset); bridge_fail_if(b, 1, 0); }
  get(b, 1); constant(b, 32); op(b, 0x6b); set(b, 22);
  read_local(b, 13, 12); get(b, 22); op(b, 0x47); bridge_fail_if(b, 1, 0);
  get(b, 22); constant(b, fixed); op(b, 0x49); bridge_fail_if(b, 1, 0);
  var wire_offset: u32 = 0; var input_index: u32 = 0;
  for field_index in type_children(c, argument) {
    let field = underlying(c, type_child(c, argument, field_index as u32)); let t = c.types[field];
    if t.tag == TY_DEST { continue; }
    if t.tag == TY_VIEW {
      let elem = type_child(c, field, 0); let stride = layout(c, layouts, elem).size;
      constant(b, m.map.ingress + 32 + wire_offset); set(b, 13);
      read_local(b, 13, 0); set(b, 14); read_local(b, 13, 4); set(b, 19);
      get(b, 14); constant(b, c.refs[ex.input_maxima.start + input_index]); op(b, 0x4b); bridge_fail_if(b, 1, 0);
      get(b, 19); constant(b, 3); op(b, 0x71); bridge_fail_if(b, 1, 0);
      get(b, 19); constant(b, fixed); op(b, 0x49); bridge_fail_if(b, 1, 0);
      get(b, 19); get(b, 22); op(b, 0x4b); bridge_fail_if(b, 1, 0);
      if stride != 0 {
        get(b, 14); constant(b, 0xffffffff / stride); op(b, 0x4b); bridge_fail_if(b, 1, 0);
        get(b, 14); get(b, 22); get(b, 19); op(b, 0x6b); constant(b, stride); op(b, 0x6e); op(b, 0x4b); bridge_fail_if(b, 1, 0);
        add_const(b, 19, m.map.ingress + 32); set(b, 13); constant(b, 0); set(b, 12);
        begin_block(b); begin_loop(b); get(b, 12); get(b, 14); op(b, 0x4f); branch_if(b, 1);
        plain_guard(c, layouts, elem, b, 13, 0, 2, 0);
        increment(b, 13, stride); increment(b, 12, 1); branch(b, 0); end(b); end(b);
      }
      input_index++; wire_offset += 8;
    } else {
      constant(b, m.map.ingress + 32 + wire_offset); set(b, 13);
      plain_guard(c, layouts, field, b, 13, 0, 0, 0); wire_offset += layout(c, layouts, field).size;
    }
  }
  // Every occurrence of a declared Nat must agree with its designated witness,
  // including two arrays sharing n or an input n shared with destination C.
  wire_offset = 0;
  for field_index in type_children(c, argument) {
    let field = underlying(c, type_child(c, argument, field_index as u32)); let t = c.types[field];
    if t.tag == TY_VIEW || t.tag == TY_DEST {
      if t.tag == TY_VIEW { constant(b, m.map.ingress + 32 + wire_offset); load(b, 0); }
      else { constant(b, ex.output_capacity); }
      let witness = if t.tag == TY_VIEW { t.nat } else { t.capacity };
      if !bridge_term(c, layouts, plans, ex, witness, m.map, b, 0) { diags.push(Diagnostic {3028, 0, witness, 0}); return 0, false; }
      op(b, 0x47); bridge_fail_if(b, 1, 0);
    }
    if t.tag != TY_DEST { wire_offset += layout(c, layouts, field).size; }
  }
  for fact_id in refs(c, c.contracts[c.functions[ex.function].contract].requires) {
    if !bridge_predicate(c, layouts, plans, ex, c.facts[fact_id], m.map, b) {
      diags.push(Diagnostic {3025, c.functions[ex.function].origin, fact_id, 0}); return 0, false;
    }
    op(b, 0x45); bridge_fail_if(b, 1, 0);
  }
  // Preflight before reservation or source-visible effects.
  if ex.frame > m.map.frame_bytes { constant(b, 5); set(b, 3); branch(b, 0); }
  else { get(b, 4); constant(b, m.map.frame_bytes - ex.frame); op(b, 0x4b); bridge_fail_if(b, 5, 0); }
  add_const(b, 4, m.map.frame); tee(b, 5); set(b, 17);
  add_const(b, 5, arg_size); set(b, 18); add_const(b, 5, arg_size + result_size); set(b, 23);
  constant(b, m.map.control + 4); add_const(b, 4, own_frame); store(b, 0);
  telemetry_high_local(m,b,runtime::T_SCRATCH_HIGH,4,own_frame);
  get(b, 23); constant(b, ex.work_bytes); constant(b, 0); call(b, h.reserve);
  read_local(b, 23, 0); when(b); read_local(b, 23, 4); set(b, 10); constant(b, 3); set(b, 3); branch(b, 1); end(b);
  read_local(b, 23, 4); set(b, 6); read_local(b, 23, 8); set(b, 7);
  wire_offset = 0;
  for field_index in type_children(c, argument) {
    let field = underlying(c, type_child(c, argument, field_index as u32)); let t = c.types[field];
    let offset = known_field_offset(c, layouts, argument, field_index as u32);
    if t.tag == TY_VIEW || t.tag == TY_DEST {
      let elem = type_child(c, field, 0); let l = layout(c, layouts, elem);
      if t.tag == TY_DEST { constant(b, ex.output_capacity); }
      else { constant(b, m.map.ingress + 32 + wire_offset); load(b, 0); }
      set(b, 14); get(b, 23); get(b, 6); get(b, 7); get(b, 14); constant(b, l.size); constant(b, l.align); call(b, h.place);
      read_local(b, 23, 0); trap_if(b); // The checked worst-case plan guarantees placement.
      read_local(b, 23, 12); set(b, 15);
      if t.tag == TY_VIEW {
        if l.size != 0 {
          get(b, 15); constant(b, m.map.ingress + 32 + wire_offset + 4); load(b, 0);
          constant(b, m.map.ingress + 32); op(b, 0x6a);
          get(b, 14); constant(b, l.size); op(b, 0x6c); op(b, 0xfc); uleb(b, 10); uleb(b, 0); uleb(b, 0);
          telemetry_add_local(m,b,runtime::T_INITIALIZED,14,l.size); telemetry_add_local(m,b,runtime::T_COPIED,14,l.size);
        }
        wire_offset += 8;
      }
      get(b, 17); get(b, 15); store(b, offset); get(b, 17); get(b, 14); store(b, offset + 4); telemetry_add_const(m,b,runtime::T_INITIALIZED,8);
    } else {
      add_const(b, 17, offset); constant(b, m.map.ingress + 32 + wire_offset); memory_copy(b, layout(c, layouts, field).size);
      telemetry_add_const(m,b,runtime::T_INITIALIZED,layout(c,layouts,field).size); telemetry_add_const(m,b,runtime::T_COPIED,layout(c,layouts,field).size);
      wire_offset += layout(c, layouts, field).size;
    }
  }
  constant(b, 0); get(b, 18);
  for binder in refs(c, plan.dictionaries) {
    var selected: u32 = 0;
    for sid in refs(c, ex.substitutions) { let sub = c.substitutions[sid]; if sub.binder == binder { selected = sub.value; } }
    if selected == 0 || c.types[underlying(c, selected)].tag == TY_PARAM { diags.push(Diagnostic {3028, 0, binder, 0}); return 0, false; }
    constant(b, m.map.static_base + layouts[selected] * 16);
  }
  for wid in refs(c, plan.nat_witnesses) {
    let witness = c.nat_witnesses[wid];
    if witness.selector == NAT_HIDDEN {
      diags.push(Diagnostic {3028, 0, witness.binder, 0}); return 0, false;
    }
  }
  get(b, 17); call(b, functions[ex.function]);
  read_local(b, 18, 0); when(b);
  if c.types[error_type].tag != TY_UNIT { read_local(b, 18, 4); set(b, 10); }
  constant(b, 6); set(b, 3); branch(b, 1); end(b);
  // Result = tag, Nat prefix, View(data,length). Witness duplication is checked.
  read_local(b, 18, 12); set(b, 9); read_local(b, 18, 4); get(b, 9); op(b, 0x47); trap_if(b);
  if out_stride == 0 { constant(b, 8); }
  else {
    get(b, 9); constant(b, (0xffffffff - 8) / out_stride); op(b, 0x4b); trap_if(b);
    get(b, 9); constant(b, out_stride); op(b, 0x6c); constant(b, 8); op(b, 0x6a);
  }
  set(b, 8); telemetry_high_local(m,b,runtime::T_RESULT_HIGH,8,0);
  get(b, 8); get(b, 2); op(b, 0x4b); bridge_fail_if(b, 2, 0);
  constant(b, m.map.egress + 32); get(b, 9); store(b, 0);
  constant(b, m.map.egress + 32); constant(b, 8); store(b, 4); telemetry_add_const(m,b,runtime::T_INITIALIZED,8);
  if out_stride != 0 {
    constant(b, m.map.egress + 40); read_local(b, 18, 8);
    get(b, 9); constant(b, out_stride); op(b, 0x6c); op(b, 0xfc); uleb(b, 10); uleb(b, 0); uleb(b, 0);
    telemetry_add_local(m,b,runtime::T_INITIALIZED,9,out_stride); telemetry_add_local(m,b,runtime::T_COPIED,9,out_stride);
  }
  get(b, 8); set(b, 11); constant(b, 0); set(b, 3);
  end(b); // Cleanup is shared by all normal statuses.
  get(b, 6); when(b); get(b, 6); get(b, 7); constant(b, 1); call(b, h.release); end(b);
  constant(b, m.map.control + 4); get(b, 4); store(b, 0);
  constant(b, m.map.egress); set(b, 13);
  put_const(b, 13, 0, runtime::ABI_TAG); put_local(b, 13, 4, 0);
  put_local(b, 13, 12, 11); put_local(b, 13, 16, 8); put_local(b, 13, 20, 9);
  put_local(b, 13, 24, 10); put_const(b, 13, 28, 0); put_local(b, 13, 8, 3);
  constant(b, m.map.control); constant(b, 0); store(b, 0);
  get(b, 3); end(b); let index = function(m, sig, b);
  m.functions[index].role = 4; m.functions[index].source = ex.function; m.functions[index].own_frame = own_frame;
  m.functions[index].frame = ex.frame; m.functions[index].depth = ex.depth - 1; return index, true;
}
fn bridge_dispatch(m: ModuleBuilder&, exports: const u32[:], functions: const u32[:]) {
  let sig = signature(m, [I32, I32, I32], I32); var b: u8[>..] = []; local_declarations(b, 0, I32);
  for id, i in exports {
    get(b, 0); constant(b, id); op(b, 0x46); when(b);
    get(b, 0); get(b, 1); get(b, 2); call(b, functions[i]); op(b, 0x0f); end(b);
  }
  // Unknown export still respects Busy and publishes a complete invalid header.
  constant(b, m.map.control); load(b, 0); when(b); constant(b, 4); op(b, 0x0f); end(b);
  constant(b, m.map.control); constant(b, 1); store(b, 0);
  constant(b, m.map.egress); constant(b, runtime::ABI_TAG); store(b, 0);
  constant(b, m.map.egress); get(b, 0); store(b, 4);
  for i in 5 { constant(b, m.map.egress); constant(b, 0); store(b, 12 + i as u32 * 4); }
  constant(b, m.map.egress); constant(b, 1); store(b, 8);
  constant(b, m.map.control); constant(b, 0); store(b, 0); constant(b, 1); end(b);
  let index = function(m, sig, b); m.functions[index].role = 5;
  for target in functions { m.functions[index].frame = max(m.functions[index].frame, m.functions[target].frame); m.functions[index].depth = max(m.functions[index].depth, m.functions[target].depth + 1); }
  export_function(m, "blot_call", index); export_memory(m);
}
struct Reader { bytes: const u8[:], at: u32 = 0, valid: bool = true }
fn read_byte(r: Reader&) -> u8 {
  if r.at >= r.bytes.len { r.valid = false; return 0; }
  let byte = r.bytes[r.at]; r.at++; return byte;
}
fn read_uleb(r: Reader&) -> u32 {
  var value: u32 = 0;
  for i in 5 {
    let byte = read_byte(r);
    if i == 4 && byte > 15 { r.valid = false; return 0; }
    value |= ((byte as u32) & 127) << (i * 7);
    if byte < 128 { return value; }
  }
  r.valid = false; return 0;
}
fn skip_i32(r: Reader&) {
  for i in 5 {
    let byte = read_byte(r);
    if i == 4 && byte > 15 && byte < 112 { r.valid = false; }
    if byte < 128 { return; }
  }
  r.valid = false;
}
// Decode only the closed instruction set emitted by this backend. Parameters,
// instruction order and local types stay fixed; removing an unreferenced local
// cannot change Wasm's zero initialization or any control-flow assignment.
fn instruction_local(r: Reader&) -> u32 {
  let instruction = read_byte(r);
  if instruction == 0x20 || instruction == 0x21 || instruction == 0x22 { return read_uleb(r); }
  if instruction == 0x02 || instruction == 0x03 || instruction == 0x04 { read_byte(r); }
  else if instruction == 0x0c || instruction == 0x0d || instruction == 0x10 { read_uleb(r); }
  else if instruction == 0x11 || instruction == 0x28 || instruction == 0x2a || instruction == 0x2d || instruction == 0x36 || instruction == 0x38 { read_uleb(r); read_uleb(r); }
  else if instruction == 0x41 { skip_i32(r); }
  else if instruction == 0x43 { for i in 4 { read_byte(r); } }
  else if instruction == 0xfc {
    let sub = read_uleb(r);
    if sub == 10 { read_uleb(r); read_uleb(r); }
    else if sub == 11 { read_uleb(r); }
    else { r.valid = false; }
  } else if instruction == 0x00 || instruction == 0x05 || instruction == 0x0b || instruction == 0x0f || instruction == 0x1a || instruction == 0x1b ||
    (instruction >= 0x45 && instruction <= 0x4f) || (instruction >= 0x5b && instruction <= 0x60) ||
    (instruction >= 0x6a && instruction <= 0x76) || (instruction >= 0x8b && instruction <= 0x97) ||
    instruction == 0xa9 || instruction == 0xb3 || instruction == 0xbc || instruction == 0xbe { }
  else { r.valid = false; }
  return 0xffffffff;
}
fn compact_locals(bytes: const u8[:], parameters: u32, out: u8[>..]&) -> bool {
  var r = Reader {bytes}; let groups = read_uleb(r);
  if groups == 0 || groups > 2 || parameters > 1048576 { return false; }
  let integers = read_uleb(r); if read_byte(r) != I32 || integers > 1048576 - parameters { return false; }
  var floats: u32 = 0;
  if groups == 2 { floats = read_uleb(r); if read_byte(r) != F32 || floats > 1048576 - parameters - integers { return false; } }
  let start = r.at;
  var remap: u32[>..] = [];
  for index in parameters + integers + floats { remap.push(if index < parameters { index } else { 0xffffffff }); }
  while r.valid && r.at < bytes.len {
    let local = instruction_local(r);
    if local != 0xffffffff {
      if local >= remap.len { return false; }
      if local >= parameters { remap[local] = 0; }
    }
  }
  if !r.valid { return false; }
  var kept_integers: u32 = 0; var kept_floats: u32 = 0;
  for index in integers {
    let old = parameters + index;
    if remap[old] != 0xffffffff { remap[old] = parameters + kept_integers; kept_integers++; }
  }
  for index in floats {
    let old = parameters + integers + index;
    if remap[old] != 0xffffffff { remap[old] = parameters + kept_integers + kept_floats; kept_floats++; }
  }
  uleb(out, (if kept_integers != 0 {1 as u32} else {0}) + (if kept_floats != 0 {1 as u32} else {0}));
  if kept_integers != 0 { uleb(out, kept_integers); op(out, I32); }
  if kept_floats != 0 { uleb(out, kept_floats); op(out, F32); }
  r.at = start;
  while r.valid && r.at < bytes.len {
    let instruction = r.at; let local = instruction_local(r);
    if local == 0xffffffff { out.append(bytes[instruction..r.at]); }
    else { op(out, bytes[instruction]); uleb(out, remap[local]); }
  }
  return r.valid;
}
fn scan_function(m: ModuleBuilder&, f: Func, direct: u32[>..]&, indirect: u32[>..]&) -> bool {
  var r = Reader {m.bodies[f.start..f.start + f.length]};
  let groups = read_uleb(r); var local_count = m.types[f.type_id].count;
  if groups > 2 { return false; }
  for group in groups {
    let count = read_uleb(r); let ty = read_byte(r);
    if count > 1048576 - local_count || (ty != I32 && ty != F32) { return false; } local_count += count;
  }
  var nesting: u32 = 1;
  while r.valid && r.at < r.bytes.len {
    let instruction = read_byte(r);
    if instruction == 0x02 || instruction == 0x03 || instruction == 0x04 {
      let ty = read_byte(r); if ty != VOID && ty != I32 && ty != F32 { return false; } nesting++;
    } else if instruction == 0x0b {
      if nesting == 0 { return false; } nesting--;
      if nesting == 0 && r.at != r.bytes.len { return false; }
    } else if instruction == 0x0c || instruction == 0x0d {
      if read_uleb(r) >= nesting { return false; }
    } else if instruction == 0x10 {
      let target = read_uleb(r); if target >= m.functions.len { return false; } direct.push(target);
    } else if instruction == 0x11 {
      let type_id = read_uleb(r); if type_id >= m.types.len || read_uleb(r) != 0 || m.table.len == 0 { return false; }
      indirect.push(type_id);
    } else if instruction == 0x20 || instruction == 0x21 || instruction == 0x22 {
      if read_uleb(r) >= local_count { return false; }
    } else if instruction == 0x28 || instruction == 0x2a || instruction == 0x2d || instruction == 0x36 || instruction == 0x38 {
      let alignment = read_uleb(r); let offset = read_uleb(r);
      if alignment > (if instruction == 0x2d {0 as u32} else {2}) { return false; }
    } else if instruction == 0x41 { skip_i32(r); }
    else if instruction == 0x43 { for i in 4 { read_byte(r); } }
    else if instruction == 0xfc {
      let sub = read_uleb(r);
      if sub == 10 { if read_uleb(r) != 0 || read_uleb(r) != 0 { return false; } }
      else if sub == 11 { if read_uleb(r) != 0 { return false; } }
      else { return false; }
    } else if instruction == 0x00 || instruction == 0x05 || instruction == 0x0f || instruction == 0x1a || instruction == 0x1b ||
      (instruction >= 0x45 && instruction <= 0x4f) || (instruction >= 0x5b && instruction <= 0x60) ||
      (instruction >= 0x6a && instruction <= 0x76) || (instruction >= 0x8b && instruction <= 0x97) ||
      instruction == 0xa9 || instruction == 0xb3 || instruction == 0xbc || instruction == 0xbe { }
    else { return false; } // Includes memory.grow, reference types, imports/global tricks.
  }
  return r.valid && nesting == 0;
}
fn fixed_word(out: u8[>..]&, word: u32) { for i in 4 { out.push((word >> (i * 8)) as! u8); } }
fn fixed_digest(out: u8[>..]&, digest: k1hash::Digest) { for word in digest.words { fixed_word(out, word); } }
fn certificate(c: Core, m: ModuleBuilder&, code: const u8[:], out: u8[>..]&, diagnostics: Diagnostic[>..]&) -> bool {
  var payload: u8[>..] = []; name(payload, "blot.k1.certificate"); payload.append("K1CERT01");
  payload.append(ABI_HASH); fixed_digest(payload, memory_geometry_hash(m.map));
  fixed_digest(payload, k1hash::blake3(code));
  memory_geometry_bytes(m.map, payload);
  fixed_word(payload, c.phase.sealed_created as! u32); fixed_word(payload, (c.phase.sealed_created >> 32) as u32);
  var typed_signatures:wasmcheck::Signature[>..]=[]; var function_types:u32[>..]=[];
  for sig in m.types { typed_signatures.push(wasmcheck::Signature {Span {sig.start,sig.count},sig.result}); }
  var function_bodies:wasmcheck::FunctionBody[>..]=[]; var export_rows:wasmcheck::Export[>..]=[];
  for f in m.functions { function_types.push(f.type_id); function_bodies.push(wasmcheck::FunctionBody {Span {f.start,f.length}}); }
  for ex in m.exports { export_rows.push(wasmcheck::Export {Span {ex.start,ex.length},ex.kind,ex.index}); }
  if !wasmcheck::module_bytes(code,typed_signatures,m.parameters,function_types,function_bodies,m.bodies,m.table,export_rows,m.names,m.map.pages,m.map.static_base,m.data) {
    diagnostics.push(Diagnostic {3038,0,0,0}); return false;
  }
  fixed_word(payload, m.functions.len as u32);
  for f, index in m.functions {
    if f.role == 0 || f.role > 7 || f.depth == 0 || f.depth > 128 || f.frame > m.map.frame_bytes || f.frame < f.own_frame {
      diagnostics.push(Diagnostic {3030, 0, index as u32, f.role}); return false;
    }
    var direct: u32[>..] = []; var indirect: u32[>..] = [];
    if !scan_function(m, f, direct, indirect) { diagnostics.push(Diagnostic {3031, 0, index as u32, 0}); return false; }
    for target in direct {
      let callee = m.functions[target];
      if f.depth <= callee.depth || f.frame < f.own_frame || callee.frame > f.frame - f.own_frame {
        diagnostics.push(Diagnostic {3032, 0, index as u32, target}); return false;
      }
    }
    let contracts = m.indirect_contracts[f.indirect.start..f.indirect.start + f.indirect.count];
    for contract_id in contracts {
      let ct = c.contracts[contract_id];
      if f.depth <= ct.depth || f.frame < f.own_frame || ct.frame > f.frame - f.own_frame {
        diagnostics.push(Diagnostic {3032, 0, index as u32, contract_id}); return false;
      }
    }
    if contracts.len != indirect.len { diagnostics.push(Diagnostic {3033, 0, index as u32, 0}); return false; }
    for word in [index as u32, f.type_id, f.role, f.source, f.own_frame, f.frame, f.depth] { fixed_word(payload, word); }
    fixed_digest(payload, k1hash::blake3(m.bodies[f.start..f.start + f.length]));
    fixed_word(payload, direct.len as u32); for target in direct { fixed_word(payload, target); }
    fixed_word(payload, indirect.len as u32);
    for ty, i in indirect { fixed_word(payload, ty); fixed_word(payload, contracts[i]); }
  }
  fixed_word(payload, m.table.len as u32);
  for target in m.table {
    if target >= m.functions.len || (m.functions[target].role != 2 && m.functions[target].role != 6) { diagnostics.push(Diagnostic {3034, 0, target, 0}); return false; }
    fixed_word(payload, target); fixed_word(payload, m.functions[target].contract);
  }
  fixed_word(payload, c.ops.len as u32 - 1);
  for operation, i in c.ops {
    if i == 0 { continue; }
    for word in [i as u32, operation.tag, operation.registry, operation.origin, operation.evidence.count] { fixed_word(payload, word); }
    for evidence in refs(c, operation.evidence) { fixed_word(payload, evidence); }
  }
  fixed_word(payload, c.exports.len as u32 - 1);
  for ex, i in c.exports {
    if i == 0 { continue; }
    for word in [i as u32, ex.kind, ex.function, ex.frame, ex.depth] { fixed_word(payload, word); }
  }
  section(out, 0, payload); return true;
}
struct Adapter { operation: u32, metadata: u32, realization:u32, callback_plan: u32, own_frame: u32, signature: u32, function: u32, table_index:u32 }
fn substitution(c: Core, operation: Operation, binder: u32) -> u32 {
  for id in refs(c, operation.substitutions) { let row = c.substitutions[id]; if row.binder == binder { return row.value; } }
  return 0;
}
fn realized_argument(c:Core, type_id:u32, realization:u32)->u32 {
  if realization==0 || closed_dictionary(c,type_id,0) { return type_id; }
  let mapping=c.dictionary_realizations[realization]; let type_row=c.types[underlying(c,type_id)];
  if type_row.tag==TY_PARAM {
    for bid,i in refs(c,mapping.parameters) { if bid==type_row.binder { return c.refs[mapping.arguments.start+i]; } }
    return 0;
  }
  for row,i in c.dictionary_realizations {
    if i==0 || row.type_id!=type_id { continue; } var same=true;
    for bid,j in refs(c,row.parameters) {
      var actual:u32=0; for own,k in refs(c,mapping.parameters) { if own==bid { actual=c.refs[mapping.arguments.start+k]; break; } }
      if actual!=c.refs[row.arguments.start+j] { same=false; break; }
    }
    if same { return row.concrete_type; }
  } return 0;
}
fn prepare_adapters(c: Core, m: ModuleBuilder&, plans: const u32[:], layouts: const u32[:],
                    adapters: Adapter[>..]&, codes: u32[>..]&, first_adapter: u32,
                    diagnostics: Diagnostic[>..]&) -> bool {
  for operation in c.ops { codes.push(0); }
  for operation,i in c.ops {
    if i==0 || (operation.tag!=OP_CLOSURE && operation.tag!=OP_FN_PLACE) { continue; }
    let source=c.functions[operation.imm0];
    if source.evaluator_only { return opcode_diagnostic(diagnostics,3039,operation); }
    let source_plan=c.abi_plans[plans[operation.imm0]];
    let type_id=c.values[c.refs[operation.results.start]].type_id;
    let dynamic=!closed_dictionary(c,type_id,0);
    if !dynamic && operation.substitutions.count==0 { continue; }
    var choices:u32[>..]=[];
    if dynamic { for row,j in c.dictionary_realizations { if j!=0 && row.type_id==type_id { choices.push(j as u32); } } }
    else { choices.push(0); }
    for choice in choices {
      let concrete=if choice==0 {type_id} else {c.dictionary_realizations[choice].concrete_type};
      let contract=c.types[underlying(c,concrete)].contract; var callback:u32=0;
      for row,j in c.abi_plans { if j!=0 && row.contract==contract { callback=j as u32; break; } }
      if callback==0 { return opcode_diagnostic(diagnostics,3011,operation); }
      let target=c.abi_plans[callback]; let metadata=callable_adapter(c,i as u32);
      if target.dictionaries.count!=0 || c.contracts[contract].binders.count!=0 { return opcode_diagnostic(diagnostics,3029,operation); }
      for binder in refs(c,source_plan.dictionaries) {
        let selected=substitution(c,operation,binder);
        if !id_ok(selected,c.types.len) { return opcode_diagnostic(diagnostics,3029,operation); }
        if choice!=0 { if realized_argument(c,selected,choice)==0 { return opcode_diagnostic(diagnostics,3012,operation); } }
        else if !closed_dictionary(c,selected,0) && adapter_capture(c,metadata,KIND_TYPE,selected)==0 { return opcode_diagnostic(diagnostics,3029,operation); }
      }
      for wid in refs(c,source_plan.nat_witnesses) {
        let witness=c.nat_witnesses[wid]; if witness.selector!=NAT_HIDDEN { continue; }
        let selected=substitution(c,operation,witness.binder);
        if !id_ok(selected,c.terms.len) { return opcode_diagnostic(diagnostics,3029,operation); }
        if c.terms[selected].tag!=EXPR_LITERAL && adapter_capture(c,metadata,KIND_NAT,selected)==0 { return opcode_diagnostic(diagnostics,3029,operation); }
      }
      var frame:u32=0; let argument=c.layouts[target.arg_layout]; let output=c.layouts[target.result_layout];
      if c.layouts[source_plan.arg_layout].abi==ABI_INDIRECT && (argument.abi==ABI_I32 || argument.abi==ABI_F32) { frame+=4; }
      if c.layouts[source_plan.result_layout].abi==ABI_INDIRECT && (output.abi==ABI_I32 || output.abi==ABI_F32) { frame+=4; }
      let body_frame,body_depth,body_ok=wasm_body_resources(c,operation.imm0);
      if !body_ok || target.depth<=body_depth || target.frame<frame || body_frame>target.frame-frame { return opcode_diagnostic(diagnostics,3027,operation); }
      var params:u8[>..]=[]; let ret=abi_parameters(c,target,params); let sig=signature(m,params,ret);
      let index=first_adapter+adapters.len as u32; let table_index=m.table.len as u32; m.table.push(index);
      if choice==0 { codes[i]=table_index+1; }
      adapters.push(Adapter {i as u32,metadata,choice,callback,frame,sig,index,table_index});
    }
  } return true;
}

fn emit_adapter(c: Core, m: ModuleBuilder&, layouts: const u32[:], plans: const u32[:],
                functions: const u32[:], adapter: Adapter) {
  let operation = c.ops[adapter.operation]; let target = c.abi_plans[plans[operation.imm0]];
  let callback = c.abi_plans[adapter.callback_plan];
  let argument = c.layouts[callback.arg_layout]; let result = c.layouts[callback.result_layout];
  let target_arg = c.layouts[target.arg_layout]; let target_result = c.layouts[target.result_layout];
  let spill_arg = target_arg.abi == ABI_INDIRECT && (argument.abi == ABI_I32 || argument.abi == ABI_F32);
  let spill_result = target_result.abi == ABI_INDIRECT && (result.abi == ABI_I32 || result.abi == ABI_F32);
  let argument_slot: u32 = 0; let result_slot = if spill_arg {4 as u32} else {0};
  let parameter_count = m.types[adapter.signature].count;
  let saved = parameter_count; let base = saved + 1;
  var b: u8[>..] = []; local_declarations(b, 2, I32);
  if adapter.own_frame != 0 {
    constant(b, m.map.control + 4); load(b, 0); tee(b, saved);
    constant(b, m.map.frame_bytes - adapter.own_frame); op(b, 0x4b); trap_if(b);
    add_const(b, saved, m.map.frame); set(b, base);
    constant(b, m.map.control + 4); add_const(b, saved, adapter.own_frame); store(b, 0);
  } else if m.telemetry {
    constant(b, m.map.control + 4); load(b, 0); set(b, saved);
  }
  telemetry_high_local(m,b,runtime::T_SCRATCH_HIGH,saved,adapter.own_frame);
  if spill_arg { get(b, base); get(b, parameter_count - 1); store_scalar(b, argument, argument_slot); telemetry_add_const(m,b,runtime::T_INITIALIZED,argument.size); }
  get(b, 0);
  if adapter.metadata!=0 && c.callable_adapters[adapter.metadata].target_environment_offset!=0 {
    constant(b,c.callable_adapters[adapter.metadata].target_environment_offset); op(b,0x6a);
  }
  if target_result.abi == ABI_INDIRECT {
    if result.abi == ABI_INDIRECT { get(b, 1); }
    else if result.abi == ABI_UNIT { constant(b, 0); }
    else { add_const(b, base, result_slot); }
  }
  for binder in refs(c, target.dictionaries) {
    let selected = substitution(c, operation, binder); let capture = adapter_capture(c, adapter.metadata, KIND_TYPE, selected);
    if adapter.realization != 0 { constant(b,m.map.static_base+layouts[realized_argument(c,selected,adapter.realization)]*16); }
    else if capture != 0 { get(b, 0); load(b, c.adapter_captures[capture].offset); }
    else { constant(b, m.map.static_base + layouts[selected] * 16); }
  }
  for wid in refs(c, target.nat_witnesses) {
    let witness = c.nat_witnesses[wid];
    if witness.selector == NAT_HIDDEN {
      let selected = substitution(c, operation, witness.binder); let capture = adapter_capture(c, adapter.metadata, KIND_NAT, selected);
      if capture != 0 { get(b, 0); load(b, c.adapter_captures[capture].offset); } else { constant(b, c.terms[selected].literal); }
    }
  }
  if target_arg.abi != ABI_UNIT {
    if target_arg.abi == ABI_INDIRECT && argument.abi == ABI_UNIT { constant(b, 0); }
    else if spill_arg { add_const(b, base, argument_slot); }
    else { get(b, parameter_count - 1); }
  }
  call(b, functions[operation.imm0]);
  if spill_result { get(b, base); load_scalar(b, result, result_slot); }
  if adapter.own_frame != 0 { constant(b, m.map.control + 4); get(b, saved); store(b, 0); } end(b);
  let index = function(m, adapter.signature, b); assert(index == adapter.function);
  m.functions[index].role = 6; m.functions[index].source = operation.imm0; m.functions[index].contract = callback.contract;
  m.functions[index].own_frame = adapter.own_frame; m.functions[index].frame = callback.frame; m.functions[index].depth = callback.depth;
}
fn static_dictionary(c:Core,environment:StaticObject,offset:u32)->u32 {
  for id in refs(c,environment.relocations) { let rel=c.static_relocations[id]; if rel.offset==offset && rel.kind==STATIC_DICTIONARY { return rel.target; } }
  return 0;
}
fn realization_binding(c:Core,row:DictionaryRealization,binder:u32)->u32 {
  for id,i in refs(c,row.parameters) { if id==binder { return c.refs[row.arguments.start+i]; } } return 0;
}
fn static_adapter(c:Core,layouts:const u32[:],functions:const u32[:],adapters:const Adapter[:],
                  codes:const u32[:],constructor:u32,environment_id:u32)->u32,bool {
  if !id_ok(constructor,c.ops.len) { return 0,false; }
  let op=c.ops[constructor]; if op.tag!=OP_CLOSURE || !id_ok(op.imm0,c.functions.len) || c.functions[op.imm0].evaluator_only { return 0,false; }
  let type_id=c.values[c.refs[op.results.start]].type_id;
  if closed_dictionary(c,type_id,0) { return if codes[constructor]==0 {functions[op.imm0]-8} else {codes[constructor]-1},true; }
  if !id_ok(environment_id,c.static_objects.len) { return 0,false; }
  let environment=c.static_objects[environment_id];
  if environment.kind!=STATIC_ENVIRONMENT || environment.constructor!=constructor || environment.function!=op.imm0 { return 0,false; }
  for adapter in adapters {
    if adapter.operation!=constructor || adapter.realization==0 { continue; }
    let row=c.dictionary_realizations[adapter.realization]; var matches=true; var checked=false;
    let environment_offset=if adapter.metadata==0 {0 as u32} else {c.callable_adapters[adapter.metadata].target_environment_offset};
    for eid in refs(c,c.functions[op.imm0].environment_bindings) {
      let binding=c.environment_bindings[eid]; if binding.kind!=KIND_TYPE { continue; }
      let expected=realization_binding(c,row,binding.binder); if expected==0 { continue; }
      let actual=static_dictionary(c,environment,environment_offset+binding.offset); checked=true;
      if actual==0 || c.layouts[layouts[actual]].schema!=c.layouts[layouts[expected]].schema { matches=false; break; }
    }
    if adapter.metadata!=0 { for cid in refs(c,c.callable_adapters[adapter.metadata].captures) {
      let capture=c.adapter_captures[cid]; if capture.kind!=KIND_TYPE { continue; }
      let expected=realized_argument(c,capture.source,adapter.realization); let actual=static_dictionary(c,environment,capture.offset); checked=true;
      if expected==0 || actual==0 || c.layouts[layouts[actual]].schema!=c.layouts[layouts[expected]].schema { matches=false; break; }
    } }
    if matches && checked { return adapter.table_index,true; }
  }
  return 0,false;
}
fn emit_core(c: Core, config: runtime::Config, out: u8[>..]&, diags: Diagnostic[>..]&, manifest: const u8[:]) -> bool {
  if c.phase.phase < PHASE_SEALED || c.phase.active != 0 || c.phase.created != c.phase.completed || c.phase.created != c.phase.sealed_created {
    diags.push(Diagnostic {3000, 0, c.phase.phase, 0}); return false;
  }
  var cfg = config;
  if c.layouts.len > 1048576 { diags.push(Diagnostic {3001, 0, 0, 0}); return false; }
  let static_bytes, static_ok = wasm_static_bytes(c);
  if !static_ok { diags.push(Diagnostic {3001, 0, 0, 0}); return false; }
  cfg.static_bytes = static_bytes;
  let map, map_ok = runtime::make_map(cfg);
  if !map_ok { diags.push(Diagnostic {3001, 0, 0, 0}); return false; }
  var layouts: u32[>..] = []; for t in c.types { layouts.push(0); }
  for row, i in c.layouts { if i != 0 && id_ok(row.type_id, layouts.len) { layouts[row.type_id] = i as u32; } }
  var plans: u32[>..] = []; var functions: u32[>..] = []; var signatures: u32[>..] = [];
  for f in c.functions { plans.push(0); functions.push(0); signatures.push(0); }
  for row, i in c.abi_plans { if i != 0 && id_ok(row.function, plans.len) { plans[row.function] = i as u32; } }
  for f, i in c.functions { if i != 0 && plans[i] == 0 { diags.push(Diagnostic {3002, f.origin, i as u32, 0}); return false; } }
  var success = true;
  with_module(map) { m =>
    m.telemetry=cfg.telemetry;
    for row in c.layouts {
      for word in [row.size, row.align, row.flags, row.schema] { for i in 4 { m.data.push((word >> (i * 8)) as! u8); } }
    }
    let h = runtime_helpers(m); let first = m.functions.len as u32;
    var source_count:u32 = 0;
    for f, i in c.functions {
      if i == 0 || f.evaluator_only { continue; }
      functions[i] = first + source_count; source_count++;
      var params: u8[>..] = []; let result = abi_parameters(c, c.abi_plans[plans[i]], params);
      signatures[i] = signature(m, params, result); m.table.push(functions[i]);
    }
    var adapters: Adapter[>..] = []; var adapter_codes: u32[>..] = [];
    success = prepare_adapters(c, m, plans, layouts, adapters, adapter_codes, first + source_count, diags);
    var static_addresses: u32[>..] = []; static_addresses.push(0);
    for object, i in c.static_objects {
      if i == 0 { continue; }
      if object.bytes.count == 0 { static_addresses.push(0); continue; }
      while m.data.len % 4 != 0 { m.data.push(0); }
      static_addresses.push(m.map.static_base + m.data.len as u32);
      m.data.append(c.bytes[object.bytes.start..object.bytes.start + object.bytes.count]);
    }
    for object, i in c.static_objects {
      if i == 0 || !success { continue; }
      for rid in refs(c, object.relocations) {
        let rel = c.static_relocations[rid]; var word: u32 = 0;
        if object.bytes.count < 4 || rel.offset > object.bytes.count - 4 || rel.offset % 4 != 0 { diags.push(Diagnostic {3036, 0, i as u32, rid}); success = false; break; }
        if rel.kind == STATIC_ADDRESS && id_ok(rel.target, static_addresses.len) {
          let address = static_addresses[rel.target] as u64 + rel.addend as u64;
          if address > 0xffffffff { success = false; break; } word = address as u32;
        } else if rel.kind == STATIC_DICTIONARY && id_ok(rel.target,c.types.len) && layouts[rel.target]!=0 && closed_dictionary(c,rel.target,0) {
          word=m.map.static_base+layouts[rel.target]*16;
        } else if rel.kind == STATIC_FUNCTION && id_ok(rel.target, functions.len) && !c.functions[rel.target].evaluator_only { word = functions[rel.target] - first; }
        else if rel.kind == STATIC_CLOSURE && id_ok(rel.target, c.ops.len) && !c.functions[c.ops[rel.target].imm0].evaluator_only {
          let selected,valid=static_adapter(c,layouts,functions,adapters,adapter_codes,rel.target,rel.addend);
          if !valid { diags.push(Diagnostic {3036,0,i as u32,rid}); success=false; break; } word=selected;
        } else { diags.push(Diagnostic {3036, 0, i as u32, rid}); success = false; break; }
        let offset = static_addresses[i] - m.map.static_base + rel.offset;
        for byte in 4 { m.data[offset + byte] = (word >> (byte * 8)) as! u8; }
      }
    }
    for f, i in c.functions {
      if !success { break; }
      if i != 0 && !f.evaluator_only && !lower_function(c, m, h, layouts, functions, signatures, plans, adapter_codes, adapters, static_addresses, i as u32, diags) { success = false; break; }
    }
    if success { for adapter in adapters { emit_adapter(c, m, layouts, plans, functions, adapter); } }
    if success {
      var bridge_exports: u32[>..] = []; var bridge_functions: u32[>..] = [];
      for ex, i in c.exports {
        if i == 0 { continue; }
        if ex.kind == 1 {
          if !scalar_export(c, m, functions, plans, ex, diags) { success = false; break; }
        } else if ex.kind == 2 {
          let index, ok = bridge_export(c, m, h, layouts, functions, plans, ex, i as u32, diags);
          if !ok { success = false; break; } bridge_exports.push(i as u32); bridge_functions.push(index);
        } else { diags.push(Diagnostic {3022, 0, ex.kind, ex.function}); success = false; break; }
      }
      if success && bridge_exports.len != 0 { bridge_dispatch(m, bridge_exports, bridge_functions); }
    }
    if success {
      emit_telemetry_reader(m);
      var encoded: u8[>..] = []; var cert: u8[>..] = []; encode(m, encoded);
      if manifest.len != 0 { var custom: u8[>..] = []; name(custom, "blot.k1.manifest"); custom.append(manifest); section(encoded, 0, custom); }
      success = certificate(c, m, encoded, cert, diags);
      if success && encoded.len + cert.len > LIMIT_ARTIFACT { diags.push(Diagnostic {3001, 0, 0, 0}); success = false; }
      if success { out.append(encoded); out.append(cert); }
    }
  }
  return success;
}
fn ::wasm_emit(c: Core, out: u8[>..]&, diagnostics: Diagnostic[>..]&) -> bool {
  wasm::emit_core(c, runtime::Config {}, out, diagnostics, [])
}
fn ::wasm_own_frame(c: Core, fid: u32) -> u32, bool {
  if !id_ok(fid, c.functions.len) { return 0, false; }
  let f = c.functions[fid]; var ids: u32[>..] = [];
  for t in c.types { ids.push(0); }
  for row, i in c.layouts { if i != 0 && id_ok(row.type_id, ids.len) { ids[row.type_id] = i as u32; } }
  var included: bool[>..] = [];
  for v, i in c.values { included.push(i != 0 && ((id_ok(v.block_id, c.blocks.len) && c.blocks[v.block_id].function == fid) || i == f.param)); }
  for capture in wasm::refs(c, f.captures) { included[c.captures[capture].local_value] = true; }
  var total: u64 = 0; var scratch: u64 = 0;
  for v, i in c.values {
    if !included[i] { continue; }
    if !id_ok(v.type_id, ids.len) || ids[v.type_id] == 0 { return 0, false; }
    let l = c.layouts[ids[v.type_id]]; if l.abi == ABI_INDIRECT { total += l.size; }
  }
  for block_id in wasm::refs(c, f.blocks) {
    let block_row = c.blocks[block_id];
    for edge in wasm::refs(c, c.terminators[block_row.term].edges) {
      var count: u64 = 0;
      for v in wasm::refs(c, c.edges[edge].args) { count += c.layouts[ids[c.values[v].type_id]].size; }
      scratch = max(scratch, count);
    }
    for operation_id in wasm::refs(c, block_row.ops) {
      let operation = c.ops[operation_id];
      if operation.tag == OP_CALL {
        var target_plan: u32 = 0;
        for plan, i in c.abi_plans { if i != 0 && plan.function == operation.imm0 { target_plan = i as u32; break; } }
        if target_plan == 0 { return 0, false; }
        let target = c.abi_plans[target_plan];
        let argument = c.refs[operation.args.start]; let result = c.refs[operation.results.start];
        let actual_arg = c.layouts[ids[c.values[argument].type_id]];
        let actual_result = c.layouts[ids[c.values[result].type_id]];
        if c.layouts[target.arg_layout].abi == ABI_INDIRECT && actual_arg.abi != ABI_INDIRECT { total += actual_arg.size; }
        if c.layouts[target.result_layout].abi == ABI_INDIRECT && actual_result.abi != ABI_INDIRECT { total += actual_result.size; }
      }
      if operation.tag == OP_CLOSURE {
        let adapter_id = wasm::callable_adapter(c, operation_id);
        var environment:u32=0;
        if adapter_id != 0 { environment=c.callable_adapters[adapter_id].environment_layout; }
        else { for plan,i in c.abi_plans { if i!=0 && plan.function==operation.imm0 { environment=plan.env_layout; break; } } }
        if !id_ok(environment,c.layouts.len) { return 0,false; } total += c.layouts[environment].size;
      }
      if operation.tag == OP_OWNED_SEAL {
        let v = c.refs[operation.args.start + 1]; scratch = max(scratch, c.layouts[ids[c.values[v].type_id]].size as u64);
      }
    }
  }
  total += scratch;
  return if total <= 16 * 1024 * 1024 { total as u32 } else { 0 }, total <= 16 * 1024 * 1024;
}

fn ::wasm_emit_manifest_telemetry(c:Core,out:u8[>..]&,manifest:const u8[:],diagnostics:Diagnostic[>..]&)->bool {
  wasm::emit_core(c,runtime::Config {telemetry:true},out,diagnostics,manifest)
}

fn ::wasm_emit_manifest(c: Core, out: u8[>..]&, manifest: const u8[:], diagnostics: Diagnostic[>..]&) -> bool {
  wasm::emit_core(c, runtime::Config {}, out, diagnostics, manifest)
}

// Shared with manifest geometry: dictionaries followed by aligned readonly objects.
fn ::wasm_static_bytes(c: Core) -> u32, bool {
  var bytes = c.layouts.len as u64 * 16;
  for object, i in c.static_objects {
    if i == 0 || object.bytes.count == 0 { continue; }
    bytes = (bytes + 3) & 0xfffffffffffffffc; bytes += object.bytes.count;
    if bytes > 16 * 1024 * 1024 { return 0, false; }
  }
  return bytes as u32, true;
}

fn ::wasm_body_resources(c:Core,fid:u32)->u32,u32,bool {
  let own,ok=wasm_own_frame(c,fid); if !ok { return 0,0,false; }
  var frame:u32=0; var depth:u32=0;
  for bid in wasm::refs(c,c.functions[fid].blocks) { for oid in wasm::refs(c,c.blocks[bid].ops) {
    let operation=c.ops[oid]; var contract:u32=0;
    if operation.tag==OP_CALL { contract=c.functions[operation.imm0].contract; }
    if operation.tag==OP_CALL_INDIRECT { contract=c.types[wasm::underlying(c,c.values[c.refs[operation.args.start]].type_id)].contract; }
    if contract!=0 { frame=max(frame,c.contracts[contract].frame); depth=max(depth,c.contracts[contract].depth); }
    if operation.tag==OP_RESERVE || operation.tag==OP_TRY_ALLOC || operation.tag==OP_ENV_TRY_ALLOC || operation.tag==OP_REGION_CLOSE || operation.tag==OP_REGION_RESET || operation.tag==OP_OWNED_BEGIN || operation.tag==OP_OWNED_SEAL || operation.tag==OP_OWNED_ABORT || operation.tag==OP_OWNED_OPEN || operation.tag==OP_OWNED_CLOSE { depth=max(depth,2); }
  } }
  return own+frame,depth+1,true;
}
