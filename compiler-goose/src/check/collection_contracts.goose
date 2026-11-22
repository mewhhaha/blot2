// Collection shapes require exact immutable type and callback evidence.
namespace blot_check_collection_contracts;
import backend.collection_ops;
import check.core;
import check.storage_types;
import check.types;
import support.error;
import support.option;

fn validate(types: const blot_check_core::Types&, operation: blot_check_core::ArrayOp,
            inputs: const blot_check_types::Id[:], output_: blot_check_types::Id, proof) -> blot_error::Error {
    if inputs.len == 0 || inputs.len != blot_backend_collection_ops::arity(operation) { return blot_error::Error.invalid_artifact; }
    if operation == blot_backend_collection_ops::Op.get && blot_check_storage_types::info(types, inputs[0]).present {
        let element = blot_check_storage_types::readableElement(types, inputs[0]); if !element.present { return blot_error::Error.invalid_artifact; }
        let index = proof.same(blot_check_types::u32_type, inputs[1]); if index != blot_error::Error.none { return index; } return proof.same(element.value, output_);
    }
    let first = types.node(inputs[0]); let result = types.node(output_);
    match operation {
        flatten => { if first.tag != blot_check_types::Tag.array || result.tag != blot_check_types::Tag.array { return blot_error::Error.invalid_artifact; } return proof.same(first.a, output_); },
        length, get, set, append, prepend, identity, concat, slice => {
            if first.tag != blot_check_types::Tag.array { return blot_error::Error.invalid_artifact; }
            match operation {
                length => { return proof.same(blot_check_types::u32_type, output_); },
                get => { let index = proof.same(blot_check_types::u32_type, inputs[1]); if index != blot_error::Error.none { return index; } return proof.same(first.a, output_); },
                set => { let index = proof.same(blot_check_types::u32_type, inputs[1]); if index != blot_error::Error.none { return index; } let item = proof.same(first.a, inputs[2]); if item != blot_error::Error.none { return item; } return proof.same(inputs[0], output_); },
                append, prepend => { let item = proof.same(first.a, inputs[1]); if item != blot_error::Error.none { return item; } return proof.same(inputs[0], output_); },
                concat => { let other = proof.same(inputs[0], inputs[1]); if other != blot_error::Error.none { return other; } return proof.same(inputs[0], output_); },
                slice => { let start = proof.same(blot_check_types::u32_type, inputs[1]); if start != blot_error::Error.none { return start; } let end = proof.same(blot_check_types::u32_type, inputs[2]); if end != blot_error::Error.none { return end; } return proof.same(inputs[0], output_); },
                identity => { return proof.same(inputs[0], output_); }, _ => { assert(false); },
            }
        },
        fill, generate => {
            let count = proof.same(blot_check_types::u32_type, inputs[0]); if count != blot_error::Error.none { return count; }
            if result.tag != blot_check_types::Tag.array { return blot_error::Error.invalid_artifact; }
            if operation == blot_backend_collection_ops::Op.fill { return proof.same(result.a, inputs[1]); }
            let generator = types.node(inputs[1]); if generator.tag != blot_check_types::Tag.function { return blot_error::Error.invalid_artifact; }
            let callback = proof.callback(generator.c); if callback != blot_error::Error.none { return callback; }
            let parameter = proof.same(blot_check_types::u32_type, generator.a); if parameter != blot_error::Error.none { return parameter; } return proof.same(result.a, generator.b);
        },
        simd_load, simd_store => {
            let writing = operation == blot_backend_collection_ops::Op.simd_store;
            if writing && first.tag != blot_check_types::Tag.array { return blot_error::Error.invalid_artifact; }
            let index = proof.same(blot_check_types::u32_type, inputs[1]); if index != blot_error::Error.none { return index; }
            var lane_type = output_; if writing { lane_type = inputs[2]; }
            let lanes = types.node(lane_type);
            if lanes.tag != blot_check_types::Tag.product || lanes.b != 4 { return blot_error::Error.invalid_artifact; }
            let items = types.list(blot_check_types::List {lanes.a, lanes.b, ..});
            let readable = blot_check_storage_types::readableElement(types, inputs[0]);
            if readable.present {
                let error = proof.same(readable.value, items[0]); if error != blot_error::Error.none { return error; }
            } else {
                let error = proof.collection(inputs[0], items[0], true); if error != blot_error::Error.none { return error; }
            }
            for lane in items[1..] { let error = proof.same(items[0], lane); if error != blot_error::Error.none { return error; } }
            if writing { return proof.same(inputs[0], output_); }
        },
    }
    return blot_error::Error.none;
}
