// Wasm32 wire layouts: offsets never depend on Goose host representation.
namespace blot_runtime_runtime_layout;
import std;
import backend.runtime_ir;

type Role = u32;
let ROLE_scalar: Role = 0;
let ROLE_reference: Role = 1;
let ROLE_value: Role = 2;
let ROLE_table_function: Role = 3;
let ROLE_owner_token: Role = 4;

type ProviderKind = u32;
let ProviderKind_callback: ProviderKind = 0;
let ProviderKind_state_read: ProviderKind = 1;
let ProviderKind_state_write: ProviderKind = 2;
let ProviderKind_request: ProviderKind = 3;

type RequestStatus = u32;
let RequestStatus_running: RequestStatus = 0;
let RequestStatus_exited: RequestStatus = 1;
let RequestStatus_broken: RequestStatus = 2;

struct Closure {
    function: u32,
    environment: u32,
}
let Closure_bytes: u32 = 8;
let Closure_function: u32 = 0;
let Closure_environment: u32 = 4;
fn layout_roles(value: Closure) -> Role[2] { [ ROLE_table_function, ROLE_reference ] }

struct Owning {
    payload: u32,
    token: u32,
}
let Owning_bytes: u32 = 8;
let Owning_payload: u32 = 0;
let Owning_token: u32 = 4;
fn layout_roles(value: Owning) -> Role[2] { [ ROLE_value, ROLE_scalar ] }

struct OwningView {
    payload: u32,
    token: u32,
    owner: u32,
}
let OwningView_bytes: u32 = 12;
let OwningView_payload: u32 = 0;
let OwningView_token: u32 = 4;
let OwningView_owner: u32 = 8;
fn layout_roles(value: OwningView) -> Role[3] { [ ROLE_value, ROLE_scalar, ROLE_reference ] }

struct PublicOwnerLease {
    owner: u32,
    next: u32,
    token: u32,
    schema: u32,
    kind: u32,
}
let PublicOwnerLease_bytes: u32 = 20;
let PublicOwnerLease_owner: u32 = 0;
let PublicOwnerLease_next: u32 = 4;
let PublicOwnerLease_token: u32 = 8;
let PublicOwnerLease_schema: u32 = 12;
let PublicOwnerLease_kind: u32 = 16;
fn layout_roles(value: PublicOwnerLease) -> Role[5] { [ ROLE_reference, ROLE_reference, ROLE_scalar, ROLE_scalar, ROLE_scalar ] }

struct HostClosure {
    function: u32,
    environment: u32,
    handle: u32,
}
let HostClosure_bytes: u32 = 12;
let HostClosure_function: u32 = 0;
let HostClosure_environment: u32 = 4;
let HostClosure_handle: u32 = 8;
fn layout_roles(value: HostClosure) -> Role[3] { [ ROLE_table_function, ROLE_owner_token, ROLE_scalar ] }

struct Pair {
    first: u32,
    second: u32,
}
let Pair_bytes: u32 = 8;
let Pair_first: u32 = 0;
let Pair_second: u32 = 4;
fn layout_roles(value: Pair) -> Role[2] { [ ROLE_value, ROLE_value ] }

struct Cursor {
    collection: u32,
    index: u32,
    leaf: u32 = 0,
    base: u32 = 0,
}
let Cursor_bytes: u32 = 16;
let Cursor_collection: u32 = 0;
let Cursor_index: u32 = 4;
let Cursor_leaf: u32 = 8;
let Cursor_base: u32 = 12;
fn layout_roles(value: Cursor) -> Role[4] { [ ROLE_reference, ROLE_scalar, ROLE_reference, ROLE_scalar ] }

struct ProviderFrame {
    operation: u32,
    target: u32,
    outer: u32,
    kind: ProviderKind,
}
let ProviderFrame_bytes: u32 = 16;
let ProviderFrame_operation: u32 = 0;
let ProviderFrame_target: u32 = 4;
let ProviderFrame_outer: u32 = 8;
let ProviderFrame_kind: u32 = 12;
fn layout_roles(value: ProviderFrame) -> Role[4] { [ ROLE_scalar, ROLE_reference, ROLE_reference, ROLE_scalar ] }

struct EffectAuthority {
    active: u32,
}
let EffectAuthority_bytes: u32 = 4;
let EffectAuthority_active: u32 = 0;
fn layout_roles(value: EffectAuthority) -> Role[1] { [ ROLE_scalar ] }

struct ScopedProvider {
    operation: u32,
    implementation: u32,
    owner: u32,
}
let ScopedProvider_bytes: u32 = 12;
let ScopedProvider_operation: u32 = 0;
let ScopedProvider_implementation: u32 = 4;
let ScopedProvider_owner: u32 = 8;
fn layout_roles(value: ScopedProvider) -> Role[3] { [ ROLE_scalar, ROLE_reference, ROLE_reference ] }

struct ScopedStateProvider {
    read: u32,
    write: u32,
    initial: u32,
    owner: u32,
}
let ScopedStateProvider_bytes: u32 = 16;
let ScopedStateProvider_read: u32 = 0;
let ScopedStateProvider_write: u32 = 4;
let ScopedStateProvider_initial: u32 = 8;
let ScopedStateProvider_owner: u32 = 12;
fn layout_roles(value: ScopedStateProvider) -> Role[4] { [ ROLE_scalar, ROLE_scalar, ROLE_value, ROLE_reference ] }

struct ScopedFrame {
    operation: u32,
    target: u32,
    outer: u32,
    kind: u32,
    owner: u32,
}
let ScopedFrame_bytes: u32 = 20;
let ScopedFrame_operation: u32 = 0;
let ScopedFrame_target: u32 = 4;
let ScopedFrame_outer: u32 = 8;
let ScopedFrame_kind: u32 = 12;
let ScopedFrame_owner: u32 = 16;
let ScopedFrame_tag: u32 = 6;
fn layout_roles(value: ScopedFrame) -> Role[5] { [ ROLE_scalar, ROLE_reference, ROLE_reference, ROLE_scalar, ROLE_reference ] }

struct ScopedStateFrame {
    read: u32,
    value: u32,
    outer: u32,
    kind: u32,
    write: u32,
    owner: u32,
}
let ScopedStateFrame_bytes: u32 = 24;
let ScopedStateFrame_read: u32 = 0;
let ScopedStateFrame_value: u32 = 4;
let ScopedStateFrame_outer: u32 = 8;
let ScopedStateFrame_kind: u32 = 12;
let ScopedStateFrame_write: u32 = 16;
let ScopedStateFrame_owner: u32 = 20;
let ScopedStateFrame_tag: u32 = 5;
fn layout_roles(value: ScopedStateFrame) -> Role[6] { [ ROLE_scalar, ROLE_value, ROLE_reference, ROLE_scalar, ROLE_scalar, ROLE_reference ] }

struct StateCell {
    value: u32,
}
let StateCell_bytes: u32 = 4;
let StateCell_value: u32 = 0;
fn layout_roles(value: StateCell) -> Role[1] { [ ROLE_value ] }

struct StateFrame {
    read: u32,
    value: u32,
    outer: u32,
    kind: u32,
    write: u32,
}
let StateFrame_bytes: u32 = 20;
let StateFrame_read: u32 = 0;
let StateFrame_value: u32 = 4;
let StateFrame_outer: u32 = 8;
let StateFrame_kind: u32 = 12;
let StateFrame_write: u32 = 16;
let StateFrame_tag: u32 = 4;
fn layout_roles(value: StateFrame) -> Role[5] { [ ROLE_scalar, ROLE_value, ROLE_reference, ROLE_scalar, ROLE_scalar ] }

struct Provider {
    operation: u32,
    implementation: u32,
}
let Provider_bytes: u32 = 8;
let Provider_operation: u32 = 0;
let Provider_implementation: u32 = 4;
fn layout_roles(value: Provider) -> Role[2] { [ ROLE_scalar, ROLE_reference ] }

struct StateProvider {
    read: u32,
    write: u32,
    initial: u32,
}
let StateProvider_bytes: u32 = 12;
let StateProvider_read: u32 = 0;
let StateProvider_write: u32 = 4;
let StateProvider_initial: u32 = 8;
fn layout_roles(value: StateProvider) -> Role[3] { [ ROLE_scalar, ROLE_scalar, ROLE_value ] }

struct RequestCell {
    status: RequestStatus,
    exit: u32,
    state: u32,
}
let RequestCell_bytes: u32 = 12;
let RequestCell_status: u32 = 0;
let RequestCell_exit: u32 = 4;
let RequestCell_state: u32 = 8;
fn layout_roles(value: RequestCell) -> Role[3] { [ ROLE_scalar, ROLE_value, ROLE_value ] }

struct RequestFrame {
    operation: u32,
    target: u32,
    outer: u32,
    kind: ProviderKind,
    cell: u32,
    runner_outer: u32,
}
let RequestFrame_bytes: u32 = 24;
let RequestFrame_operation: u32 = 0;
let RequestFrame_target: u32 = 4;
let RequestFrame_outer: u32 = 8;
let RequestFrame_kind: u32 = 12;
let RequestFrame_cell: u32 = 16;
let RequestFrame_runner_outer: u32 = 20;
fn layout_roles(value: RequestFrame) -> Role[6] { [ ROLE_scalar, ROLE_reference, ROLE_reference, ROLE_scalar, ROLE_reference, ROLE_reference ] }

struct ScopedRequestFrame {
    operation: u32,
    target: u32,
    outer: u32,
    kind: u32,
    cell: u32,
    runner_outer: u32,
    owner: u32,
}
let ScopedRequestFrame_bytes: u32 = 28;
let ScopedRequestFrame_operation: u32 = 0;
let ScopedRequestFrame_target: u32 = 4;
let ScopedRequestFrame_outer: u32 = 8;
let ScopedRequestFrame_kind: u32 = 12;
let ScopedRequestFrame_cell: u32 = 16;
let ScopedRequestFrame_runner_outer: u32 = 20;
let ScopedRequestFrame_owner: u32 = 24;
let ScopedRequestFrame_tag: u32 = 7;
fn layout_roles(value: ScopedRequestFrame) -> Role[7] { [ ROLE_scalar, ROLE_reference, ROLE_reference, ROLE_scalar, ROLE_reference, ROLE_reference, ROLE_reference ] }

struct Decision {
    kind: u32,
    payload: u32,
    state: u32,
}
let Decision_bytes: u32 = 12;
let Decision_kind: u32 = 0;
let Decision_payload: u32 = 4;
let Decision_state: u32 = 8;
fn layout_roles(value: Decision) -> Role[3] { [ ROLE_scalar, ROLE_value, ROLE_value ] }

struct Array {
    length: u32,
}
let Array_bytes: u32 = 4;
let Array_length: u32 = 0;
fn layout_roles(value: Array) -> Role[1] { [ ROLE_scalar ] }

struct ListDescriptor {
    length: u32,
    root: u32,
    cached_leaf: u32,
    cached_base: u32,
    scalar_elements: u32,
    immutable: u32,
    leaf_limit: u32,
    directory: u32,
}
let ListDescriptor_bytes: u32 = 32;
let ListDescriptor_length: u32 = 0;
let ListDescriptor_root: u32 = 4;
let ListDescriptor_cached_leaf: u32 = 8;
let ListDescriptor_cached_base: u32 = 12;
let ListDescriptor_scalar_elements: u32 = 16;
let ListDescriptor_immutable: u32 = 20;
let ListDescriptor_leaf_limit: u32 = 24;
let ListDescriptor_directory: u32 = 28;
fn layout_roles(value: ListDescriptor) -> Role[8] { [ ROLE_scalar, ROLE_reference, ROLE_reference, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_reference ] }

struct ListNode {
    owner_token: u32,
    height: u32,
    length: u32,
    capacity: u32,
}
let ListNode_bytes: u32 = 16;
let ListNode_owner_token: u32 = 0;
let ListNode_height: u32 = 4;
let ListNode_length: u32 = 8;
let ListNode_capacity: u32 = 12;
fn layout_roles(value: ListNode) -> Role[4] { [ ROLE_owner_token, ROLE_scalar, ROLE_scalar, ROLE_scalar ] }

struct ListBranch {
    owner_token: u32,
    height: u32,
    length: u32,
    capacity: u32,
    left: u32,
    right: u32,
}
let ListBranch_bytes: u32 = 24;
let ListBranch_owner_token: u32 = 0;
let ListBranch_height: u32 = 4;
let ListBranch_length: u32 = 8;
let ListBranch_capacity: u32 = 12;
let ListBranch_left: u32 = 16;
let ListBranch_right: u32 = 20;
fn layout_roles(value: ListBranch) -> Role[6] { [ ROLE_owner_token, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_reference, ROLE_reference ] }

struct ArenaHeader {
    block_size: u32,
    requested: u32,
    flags: u32,
    next: u32,
    strong: u32,
    layout: u32,
    candidate_prev: u32,
    candidate_next: u32,
}
let ArenaHeader_bytes: u32 = 32;
let ArenaHeader_block_size: u32 = 0;
let ArenaHeader_requested: u32 = 4;
let ArenaHeader_flags: u32 = 8;
let ArenaHeader_next: u32 = 12;
let ArenaHeader_strong: u32 = 16;
let ArenaHeader_layout: u32 = 20;
let ArenaHeader_candidate_prev: u32 = 24;
let ArenaHeader_candidate_next: u32 = 28;
fn layout_roles(value: ArenaHeader) -> Role[8] { [ ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_scalar, ROLE_scalar ] }

fn offset<T>(name: const u8[:]) -> u32 {
    var at: u32 = 0;
    const for <N, A> in fields<T> {
        if name == N { return at; }
        at += 4;
    }
    abort("unknown guest layout field");
}

fn fields<T>(out: Field[>..]&) {
    let roles = layout_roles(default<T>());
    for role, index in roles { out.push(Field { (index * 4) as u32, role }); }
}
fn fields<T>() -> Field[>..] {
    var result: Field[>..] = [];
    fields<T>(result);
    return result;
}

struct Field { offset: u32, role: Role }

fn referenceMask(roles: const u32[:], rest: u32) -> u32, bool {
    var mask: u32 = 0;
    var tail = rest;
    if roles.len > 31 { tail = roles[31]; }
    if tail != blot_backend_runtime_ir::ROLE_scalar && tail != blot_backend_runtime_ir::ROLE_reference { return 0, false; }
    for role, index in roles {
        if role != blot_backend_runtime_ir::ROLE_scalar && role != blot_backend_runtime_ir::ROLE_reference { return 0, false; }
        if index >= 31 { if role != tail { return 0, false; } }
        else if role == blot_backend_runtime_ir::ROLE_reference { mask |= 1 as u32 << (index as u32); }
    }
    if roles.len > 31 && rest != tail { return 0, false; }
    if rest == blot_backend_runtime_ir::ROLE_reference {
        var index = roles.len;
        while index < 31 { mask |= 1 as u32 << (index as u32); index++; }
    }
    if tail == blot_backend_runtime_ir::ROLE_reference { mask |= 2147483648; }
    return mask, true;
}

fn referenceWord(mask: u32, word: u32) -> bool {
    (mask >> min(word, 31)) & 1 != 0
}
