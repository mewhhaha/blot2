namespace i08_cap_wasm;
import i08_cap_core;
import i08_cap_verify;
import i08_job_wasm;
fn emit(p:i08_cap_core::Package&,source:u8[:])->u8[] {
    if !i08_cap_verify::verify(p,source){return [];}
    return i08_job_wasm::emit(p.job,source);
}
