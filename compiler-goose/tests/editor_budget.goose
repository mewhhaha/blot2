// Fixed editor payloads retain a reference to the request's actual budget.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.check;
import reuse.project_check;
import reuse.completion_fit;
fn main() {
    var budget=blot_reuse_completion_fit::Budget{remaining:10};
    let editor=blot_reuse_project_check::Editor.query{blot_reuse_project_check::EditorQuery{unit:1,marker:blot_check_check::EditorMarker{..},budget:budget}};
    blot_reuse_project_check::accountEditorBudget(blot_reuse_project_check::Editor.none,8,true,[]);
    assert(budget.remaining==10 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,3,false,[]);
    assert(budget.remaining==7 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,7,false,[]);
    assert(budget.remaining==0 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,1,false,[]);
    assert(budget.remaining==0 && budget.exhausted);
    budget=blot_reuse_completion_fit::Budget{remaining:10};
    blot_reuse_project_check::accountEditorBudget(editor,2,true,[]);
    assert(budget.remaining==8 && budget.exhausted);
    budget=blot_reuse_completion_fit::Budget{remaining:10};
    var issues=[default<blot_check_check::Diagnostic>(),default<blot_check_check::Diagnostic>()];
    issues[0].code=blot_check_check::Code.unknown_name;issues[1].code=blot_check_check::Code.inference_budget;
    blot_reuse_project_check::accountEditorBudget(editor,3,false,issues[..1]);
    assert(budget.remaining==7 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,2,false,issues[..]);
    assert(budget.remaining==0 && budget.exhausted);
    print("editor budget passed: owner mutation, exact spend, exhaustion, initializer and diagnostics");
}
