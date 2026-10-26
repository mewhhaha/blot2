// Private source-owned job -> checked structured Wasm fixture. The final
// checker reconstructs the worker and compares only reviewed setup/helpers.
// Caller-controlled raw owner state, real loans, public ABI, frame preflight,
// arithmetic-NaN permitted sets and M13 qualification remain outside scope.
namespace i08_job_wasm;
import i08_job_core;
import i08_job_verify;
import particle_lower_wasm;
import particle_lower_target;
fn emit(job:i08_job_core::Job&,source:u8[:])->u8[] {
    if !i08_job_verify::verify(job,source) {return [];}
    let bytes=particle_lower_wasm::emit(job.core,source,job.core.context);
    if bytes.len==0 || !particle_lower_target::verify(job.core,source,job.core.context,bytes) {return [];}
    return bytes;
}
