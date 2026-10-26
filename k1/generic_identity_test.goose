import os;
import generic_identity;
import generic_identity_verify;
import generic_dictionary;
import generic_dictionary_verify;
import generic_layout_plan;
import generic_identity_wasm;
import generic_identity_wasm_verify;
import public_artifact;

fn main() {
    let source = "pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
    let body = generic_identity::parse(source);
    assert(body.status == 0 && generic_identity_verify::verify(source, body));
    let other_source = "pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return y\n";
    assert(generic_identity::parse(other_source).status != 0 && !generic_identity_verify::verify(other_source, body));
    let drop_source = "pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return ()\n";
    assert(generic_identity::parse(drop_source).status != 0 && !generic_identity_verify::verify(drop_source, body));
    let renamed_source = "pub let apply: forall [Item: Type] => Fn[static, Many, Item, Item] ! {} resources {depth: 1, frame: 256} = fn value => return value\n";
    let renamed = generic_identity::parse(renamed_source);
    assert(renamed.status == 0 && generic_identity_verify::verify(renamed_source, renamed));
    var forged = body; forged.copied = 1;
    assert(!generic_identity_verify::verify(source, forged));
    forged = body; forged.discarded = 1;
    assert(!generic_identity_verify::verify(source, forged));
    forged = body; forged.binder_start = 0;
    assert(!generic_identity_verify::verify(source, forged));
    var unit = generic_dictionary::Schema { kind: 0, words: 0, producer: "pkg/unit" };
    var scalar = generic_dictionary::Schema { kind: 1, words: 1, producer: "pkg/u32" };
    var words16 = generic_dictionary::Schema { kind: 2, words: 16, producer: "pkg/row16" };
    var words17 = generic_dictionary::Schema { kind: 2, words: 17, producer: "pkg/row17" };
    var words63 = generic_dictionary::Schema { kind: 2, words: 63, producer: "pkg/row63" };
    var words64 = generic_dictionary::Schema { kind: 2, words: 64, producer: "pkg/row64" };
    var affine = generic_dictionary::Schema { kind: 3, words: 2, producer: "pkg/owner" };
    var d0 = generic_dictionary::make(unit, 1); var d1 = generic_dictionary::make(scalar, 2);
    var d16 = generic_dictionary::make(words16, 3); var d17 = generic_dictionary::make(words17, 4);
    var d63 = generic_dictionary::make(words63, 5); var d64 = generic_dictionary::make(words64, 6);
    var da = generic_dictionary::make(affine, 7);
    assert(d0.status == 0 && d0.dictionary.flags == 7 && d0.dictionary.size == 0);
    assert(d1.status == 0 && d1.dictionary.flags == 3 && d1.dictionary.size == 4);
    assert(da.status == 0 && da.dictionary.flags == 0 && da.dictionary.size == 8);
    assert(generic_dictionary_verify::verify(d1, d1.schema, 2));
    assert(!generic_dictionary_verify::verify(d1, d1.schema, 3));
    assert(!generic_dictionary_verify::verify(d1, d16.schema, 2));
    var other_owner = generic_dictionary::Schema { kind: 1, words: 1, producer: "other/u32" };
    var spoof = generic_dictionary::make(other_owner, 2);
    assert(!generic_dictionary_verify::verify(spoof, d1.schema, 2));
    d1.dictionary.flags = 7; assert(!generic_dictionary_verify::verify(d1, d1.schema, 2)); d1.dictionary.flags = 3;
    d1.dictionary.size = 8; assert(!generic_dictionary_verify::verify(d1, d1.schema, 2)); d1.dictionary.size = 4;
    d1.dictionary.alignment = 1; assert(!generic_dictionary_verify::verify(d1, d1.schema, 2)); d1.dictionary.alignment = 4;
    let exact_schema = copy(d1.schema);
    for i in d1.schema.len {
        d1.schema[i] ^= 1;
        assert(!generic_dictionary_verify::verify(d1, exact_schema, 2));
        d1.schema[i] ^= 1;
    }
    d1.schema[8] = 255;
    assert(!generic_dictionary_verify::verify(d1, d1.schema, 2));
    d1.schema[8] = 1;
    var bad = generic_dictionary::Schema { kind: 2, words: 65, producer: "bad" };
    assert(generic_dictionary::make(bad, 1).status != 0);
    assert(generic_dictionary::make(unit, 0).status != 0);
    assert(generic_layout_plan::plain_element(d16, d16.schema, 3));
    assert(!generic_layout_plan::plain_element(d17, d17.schema, 4));
    assert(!generic_layout_plan::plain_element(da, da.schema, 7));
    let fits = generic_layout_plan::result_layout(d63, d63.schema, 5, d0, d0.schema, 1);
    let too_big = generic_layout_plan::result_layout(d64, d64.schema, 6, d0, d0.schema, 1);
    assert(fits.status == 0 && fits.size == 256 && fits.alignment == 4);
    assert(too_big.status == 2);
    let p0 = generic_layout_plan::instantiate(source, body, d0, d0.schema, 1);
    let p1 = generic_layout_plan::instantiate(source, body, d1, d1.schema, 2);
    let p16 = generic_layout_plan::instantiate(source, body, d16, d16.schema, 3);
    let p63 = generic_layout_plan::instantiate(source, body, d63, d63.schema, 5);
    let p64 = generic_layout_plan::instantiate(source, body, d64, d64.schema, 6);
    let pa = generic_layout_plan::instantiate(source, body, da, da.schema, 7);
    assert(p0.status == 0 && p1.status == 0 && p16.status == 0 && p63.status == 0 && p64.status == 0 && pa.status == 0);
    assert(p0.body_key[..] == p1.body_key[..] && p1.body_key[..] == p16.body_key[..] && p16.body_key[..] == pa.body_key[..] &&
        pa.body_key[..] == p63.body_key[..] && p63.body_key[..] == p64.body_key[..]);
    assert(generic_layout_plan::slots(p0, 0, 0, 256, 65536, true, true));
    assert(generic_layout_plan::slots(p16, 1024, 2048, 256, 65536, true, true));
    assert(!generic_layout_plan::slots(p16, 1024, 1028, 256, 65536, true, true));
    assert(!generic_layout_plan::slots(p16, 1024, 2049, 256, 65536, true, true));
    assert(!generic_layout_plan::slots(p16, 1024, 2048, 256, 65536, false, true));
    assert(!generic_layout_plan::slots(p16, 1024, 2048, 256, 65536, true, false));
    assert(!generic_layout_plan::slots(p16, 1024, 65520, 256, 65536, true, true));
    assert(!generic_layout_plan::slots(p16, 1024, 256, 256, 65536, true, true));
    assert(generic_layout_plan::slots_checked(source, body, d16, d16.schema, 3, 1024, 2048, 256, 65536, true, true));
    assert(!generic_layout_plan::slots_checked(source, body, d16, d1.schema, 3, 1024, 2048, 256, 65536, true, true));
    assert(!generic_layout_plan::slots_checked(other_source, body, d16, d16.schema, 3, 1024, 2048, 256, 65536, true, true));
    let w0 = generic_identity_wasm::emit(source, body, d0, d0.schema, 1);
    let w1 = generic_identity_wasm::emit(source, body, d1, d1.schema, 2);
    let w16 = generic_identity_wasm::emit(source, body, d16, d16.schema, 3);
    let w63 = generic_identity_wasm::emit(source, body, d63, d63.schema, 5);
    let w64 = generic_identity_wasm::emit(source, body, d64, d64.schema, 6);
    let wa = generic_identity_wasm::emit(source, body, da, da.schema, 7);
    assert(w0.len > 0 && w0[..] == w1[..] && w1[..] == w16[..] && w16[..] == wa[..] &&
        w16[..] == w63[..] && w63[..] == w64[..]);
    assert(generic_identity_wasm_verify::verify(source, body, w0));
    assert(generic_identity_wasm_verify::verify_linked(source, body, d16, d16.schema, 3, w0));
    assert(!generic_identity_wasm_verify::verify_linked(source, body, d16, d1.schema, 3, w0));
    assert(!generic_identity_wasm_verify::verify_linked(source, body, d16, d16.schema, 2, w0));
    assert(!generic_identity_wasm_verify::verify_linked(other_source, body, d16, d16.schema, 3, w0));
    let renamed_wasm = generic_identity_wasm::emit(renamed_source, renamed, d1, d1.schema, 2);
    assert(generic_identity_wasm_verify::verify(renamed_source, renamed, renamed_wasm));
    var bad_wasm: u8[>..] = []; bad_wasm.append(w0);
    for i in bad_wasm.len {
        bad_wasm[i] ^= 1;
        assert(!generic_identity_wasm_verify::verify(source, body, bad_wasm));
        assert(!generic_identity_wasm_verify::verify_linked(source, body, d16, d16.schema, 3, bad_wasm));
        bad_wasm[i] ^= 1;
    }
    assert(!generic_identity_wasm_verify::verify(other_source, body, w0));
    assert(write_file("generic_identity.wasm", w0));
    // Transfer the actual independently checked dictionary records to the
    // execution witness, rather than reconstructing their fields in JS.
    var dictionaries: u8[>..] = [];
    for d in [d0.dictionary, d1.dictionary, da.dictionary, d16.dictionary, d63.dictionary, d64.dictionary] {
        public_artifact::put32(dictionaries, d.size); public_artifact::put32(dictionaries, d.alignment);
        public_artifact::put32(dictionaries, d.flags); public_artifact::put32(dictionaries, d.schema_id);
    }
    assert(write_file("generic_identity_dicts.bin", dictionaries));
    print("source-bound generic identity and dictionary laws passed");
}
