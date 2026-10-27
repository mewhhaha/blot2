import src.tooling;
fn test_tooling() {
    let source = "let  f: U32 -> U32 = fn x => do:  \r\n  return  do:\r\n    break  x   // preserve  comment\r\n";
    var output:u8[>..] = []; var diags:Diagnostic[>..] = [];
    assert(format_source(source, output, diags));
    assert(find(output, "// preserve  comment") >= 0);
    var again:u8[>..] = []; assert(format_source(output, again, diags)); assert(output == again);
    var rejected:u8[>..] = []; assert(!format_source("let = broken", rejected, diags)); assert(rejected.len == 0);
    var findings:MigrationFinding[>..] = [];
    migration_findings("// use while +\nimport \"./use.blot\" as m\nuse x = fn y => y + 1\n", findings);
    assert(findings.len == 3 && findings[0].code == 1 && findings[1].code == 3 && findings[2].code == 6);
    var completions:u8[>..] = []; complete_prefix("builder.", completions);
    assert(starts_with(completions, "builder.append\n") && find(completions, "region.") < 0);
    print("K1 formatter preserves parsed control targets; migration ignores comments/paths; completion passed");
}
