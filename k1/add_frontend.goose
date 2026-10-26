// Untrusted candidate producer for a private x + 0 experiment only. Its
// result is not proof, a portable artifact, or public K1 source admission.
namespace add_frontend;
import lexer;
import frontend;
import scalar_core;
import add_source;

// status 0 success, 1 syntax, 2 unsupported, 3 unbound, 4 missing return,
// 5 source limit, 6 bad target, 7 type mismatch, 10 arithmetic not established,
// 11 internal source/candidate mismatch (never a source-admission success).
struct Result { status: i64 = 0, core: scalar_core::ScalarCore = scalar_core::ScalarCore {} }
fn parse(source: u8[:]) -> Result {
    var state = lexer::init(source);
    var token = lexer::next(source, state);
    var plus: i64 = -1;
    var plus_count: i64 = 0;
    while token.kind != 0 {
        if token.kind == 9 { return Result { status: token.status }; }
        if token.kind == 5 && source[token.start..token.end] == "+" {
            plus = token.start; plus_count += 1;
        }
        token = lexer::next(source, state);
    }
    if plus_count != 1 {
        let plain = frontend::parse_scalar(source);
        if plain.status == 1 || plain.status == 3 || plain.status == 4 || plain.status == 5 ||
           plain.status == 6 || plain.status == 7 { return Result { status: plain.status }; }
        return Result { status: 2 };
    }
    var projected: u8[>..] = [];
    projected.append(source);
    projected[plus] = '&';
    let parsed = frontend::parse_scalar(projected);
    if parsed.status != 0 { return Result { status: parsed.status }; }
    if parsed.binary_op != 1 || parsed.operator_start != plus { return Result { status: 2 }; }
    if parsed.kind != 0 || parsed.right_kind != 1 || parsed.right_literal != 0 { return Result { status: 10 }; }
    var core = scalar_core::build(parsed.result_type, parsed.binary_op, parsed.kind,
        parsed.literal, parsed.right_kind, parsed.right_literal);
    core.name_start = parsed.name_start; core.name_end = parsed.name_end;
    core.parameter_start = parsed.parameter_start; core.parameter_end = parsed.parameter_end;
    core.left_start = parsed.start; core.left_end = parsed.end;
    core.operator_start = parsed.operator_start; core.operator_end = parsed.operator_end;
    core.right_start = parsed.right_start; core.right_end = parsed.right_end;
    core.values[2].op_id = 3;
    if add_source::validate(source, core) != 0 { return Result { status: 11 }; }
    return Result { core: core };
}
