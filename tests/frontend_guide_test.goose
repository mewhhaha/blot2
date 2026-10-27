import tests.frontend_lifecycle_test;
fn frontend_guide_find(source: const u8[:], start: i64, needle: const u8[:]) -> i64 { var at = start; while at + needle.len <= source.len { if source[at..at + needle.len] == needle { return at; } at++; } return -1; }
fn test_frontend_guide_examples() {
    var guide: u8[>..] = []; assert(read_file("docs/guide.md", guide)); var cursor: i64 = 0; var examples: u32 = 0; var rejected: u32 = 0;
    loop { let start = frontend_guide_find(guide, cursor, "```blot\n"); if start < 0 { break; } let begin = start + 8; let end = frontend_guide_find(guide, begin, "\n```"); assert(end >= begin); let source = guide[begin..end + 1];
        if frontend_guide_find(source, 0, "// Rejected with k1_static_limit:") >= 0 { frontend_planned(source, false, FE_STATIC_LIMIT); rejected++; }
        else { assert(frontend_guide_find(source, 0, "// Rejected with") < 0); frontend_planned(source, true, 0); }
        examples++; cursor = end + 4;
    }
    assert(examples >= 4 && rejected == 1);
}
