import frontend;
import work;

fn main() {
    let source = "let id: U32 -> U32 = fn x => return x\n";
    var measured = work::Meter {};
    let result = frontend::parse_scalar_with_work(source, measured);
    assert(result.status == 0);
    let token_visits = measured.semantic;
    assert(token_visits > 0 && measured.phase_semantic[0] == token_visits);
    assert(measured.proof_visits == 0 && measured.core_operations == 0);

    // The last allowed actual token visit succeeds; the next required visit
    // fails before passing the classified token to the parser or incrementing
    // the meter. Byte scanning is separately bounded and not yet recorded.
    var exact = work::Meter { semantic: 1048576 - token_visits };
    assert(frontend::parse_scalar_with_work(source, exact).status == 0);
    assert(exact.semantic == 1048576 && exact.phase_semantic[0] == token_visits);
    var short = work::Meter { semantic: 1048577 - token_visits };
    let denied = frontend::parse_scalar_with_work(source, short);
    assert(denied.status == 12 && short.semantic == 1048576);
    assert(short.phase_semantic[0] == token_visits - 1);
    assert(denied.start >= 0 && denied.start <= source.len && denied.end == denied.start);

    // Repeated parsing pays its token work again against the same job.
    var repeated = work::Meter {};
    assert(frontend::parse_scalar_with_work(source, repeated).status == 0);
    assert(frontend::parse_scalar_with_work(source, repeated).status == 0);
    assert(repeated.semantic == token_visits * 2);
    var corrupt = work::Meter {};
    corrupt.phase_semantic[0] = 1;
    assert(frontend::parse_scalar_with_work(source, corrupt).status == 13);
    assert(corrupt.semantic == 0);
    // Blank lines are source trivia, not a million semantic AST records.
    // Their byte-scanning telemetry remains a separate, unfinished concern.
    var dense: u8[>..] = [];
    for i in 1048577 { dense.push('\n'); }
    dense.append(source);
    var dense_work = work::Meter {};
    assert(frontend::parse_scalar_with_work(dense, dense_work).status == 0);
    assert(dense_work.semantic == token_visits);
    assert(frontend::parse_scalar(dense).status == 0);
    var comment: u8[>..] = [];
    comment.append("//");
    for i in 1048577 { comment.push('a'); }
    comment.push('\n'); comment.append(source);
    var comment_work = work::Meter {};
    assert(frontend::parse_scalar_with_work(comment, comment_work).status == 0);
    assert(comment_work.semantic == token_visits);
    assert(frontend::parse_scalar(source).status == 0);
    print("metered frontend token laws passed");
}
