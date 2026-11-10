// Decoded module and identity owners remain live through pin use.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.worker_packet;
import driver.compile_workspace;
fn main() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);let name,error=owner.copy("worker-module");assert(error==blot_error::Error.none);let modules=[blot_check_core::Module{unit:1,names:owner.mutable(name),..}];var bytes:u8[>..]=[];var writer=blot_eval_worker_packet::Writer{bytes};blot_eval_worker_packet::writeCatalog(writer,modules[..]);assert(writer.failure==blot_error::Error.none);owner.deinit();
 var reader=blot_eval_worker_packet::Reader{bytes};var catalog=blot_eval_worker_packet::readCatalog(reader);assert(reader.failure==blot_error::Error.none && catalog.modules.len==1);bytes.clear();
 var identity_bytes:u8[>..]=[];var identity_writer=blot_eval_worker_packet::Writer{identity_bytes};let owners=[blot_backend_runtime_identity::Name{start:0,len:12}];blot_eval_worker_packet::writeIdentity(identity_writer,blot_backend_runtime_identity::View{bytes:"/worker.blot",owners:owners[..],..});assert(identity_writer.failure==blot_error::Error.none);
 var identity_reader=blot_eval_worker_packet::Reader{identity_bytes};var identity=blot_eval_worker_packet::readIdentity(identity_reader);assert(identity_reader.failure==blot_error::Error.none);identity_bytes.clear();
 let pins,error=blot_eval_worker_packet::pin(catalog,identity);assert(error==blot_error::Error.none && pins.len==1);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());assert(frame.release()==blot_error::Error.none);
 assert(pins[0].unit==1 && pins[0].module.names=="worker-module" && pins[0].canonical_path=="/worker.blot" && pins[0].stamp.present);assert(pins[0].stamp.value==blot_reuse_code_artifacts::stamp(pins[0].module));
 blot_eval_worker_packet::pins.free_slice(pins);identity.deinit();catalog.deinit();
}
