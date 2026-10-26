// Private source-local forwarding obligation. A well-formed program records
// a formal caller loan and a direct call; it does not establish that any
// external host value, unchecked descriptor or caller actually has a loan.
namespace viewcall_core;
import viewproof_core;
struct Program {source:u8[]=[],split:i64=0,callee:viewproof_core::Program=viewproof_core::Program {},
 name:viewproof_core::Span=viewproof_core::Span {},region:viewproof_core::Span=viewproof_core::Span {},nat:viewproof_core::Span=viewproof_core::Span {},domain:viewproof_core::Span=viewproof_core::Span {},
 view:viewproof_core::Span=viewproof_core::Span {},index:viewproof_core::Span=viewproof_core::Span {},middle:viewproof_core::Span=viewproof_core::Span {},call:viewproof_core::Span=viewproof_core::Span {},loan_arg:viewproof_core::Span=viewproof_core::Span {}}
