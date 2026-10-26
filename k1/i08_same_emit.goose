import os;
import i08_same_backend;
fn main() {
    assert(write_file("i08-same.wasm",i08_same_backend::emit()));
    for i in 5 {
        let name=if i==0 {"i08-same-fault-0.wasm"} else if i==1 {"i08-same-fault-1.wasm"} else if i==2 {"i08-same-fault-2.wasm"} else if i==3 {"i08-same-fault-3.wasm"} else {"i08-same-fault-4.wasm"};
        assert(write_file(name,i08_same_backend::emit_test(i)));
    }
}
