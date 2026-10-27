namespace predicate_wasm;
import predicate_core;
import predicate_header;
import predicate_verify;
import public_frontend;
import scalar_plan;
import scalar_core;
import fixture_geometry;
import wasm_scalar_validation;
import wasm;
fn emit(source:u8[:],p:predicate_core::Program&)->u8[] {
 if !predicate_verify::verify(source,p) {return [];}
 let normalized=predicate_header::normalize(source,p.head);let b=p.body;let flat=public_frontend::projected(normalized,b.let_start,b.effect_start,b.resources_end);
 var c=b.core;let base=b.let_start;
 for o in [c.name_start,c.name_end,c.parameter_start,c.parameter_end,c.left_start,c.left_end] {if o<base || o>normalized.len {return [];}}
 c.name_start-=base;c.name_end-=base;c.parameter_start-=base;c.parameter_end-=base;c.left_start-=base;c.left_end-=base;
 if c.operator_start!=0 || c.operator_end!=0 || c.right_start!=0 || c.right_end!=0 {
  for o in [c.operator_start,c.operator_end,c.right_start,c.right_end] {if o<base || o>normalized.len {return [];}}
  c.operator_start-=base;c.operator_end-=base;c.right_start-=base;c.right_end-=base;
 }
 let plan=scalar_plan::make(c);if !scalar_plan::validate(plan) {return [];}
 let bytes=wasm::emit_scalar_v2(flat[c.name_start..c.name_end],plan);var geometry,status=fixture_geometry::build();
 if !status || wasm_scalar_validation::verify(flat,plan,geometry,bytes)!=0 {return [];}return bytes;
}
