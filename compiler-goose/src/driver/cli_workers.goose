// Persistent framed worker loop. Each request configures the exact inherited
// inference budget before entering its concrete Goose compiler program.
namespace blot_cli;
import support.process_pool;
import support.io;
import support.error;
import backend.runtime_parallel;
import eval.component_worker;
import reuse.independent_worker;
import driver.project_executor;
import main;
fn worker()->blot_error::Error {
 blot_process_pool::markWorker();let input=blot_io::Reader{0};let output=blot_io::Writer{1};
 loop {
  var frame,error=blot_process_pool::readFrame(input);if error==blot_error::Error.end_of_stream {return blot_error::Error.none;}if error!=blot_error::Error.none {return error;}var reply:u8[>..<]=[];
  var failure=frame.failure;if failure==blot_error::Error.none {failure=blot_main::configureInferenceBudget(frame.inference_budget);}if failure==blot_error::Error.none {
   match frame.kind {
    runtime=>{failure=blot_backend_runtime_parallel::executePacket(frame.bytes,reply);},
    semantic=>{failure=blot_eval_component_worker::executePacket(frame.bytes,reply);},
    check=>{failure=blot_project_executor::executeCheckPacket(frame.bytes,reply);},
    lower=>{failure=blot_project_executor::executeLowerPacket(frame.bytes,reply);},
    independent=>{failure=blot_reuse_independent_call_proof::executePacket(frame.bytes,reply);},
   }
  }
  let written=blot_process_pool::writeFrame(output,frame.kind,frame.id,reply[..],failure);frame.deinit();if written!=blot_error::Error.none {return written;}
 }
}
