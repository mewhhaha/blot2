// Producer services inspect the exact retained catalog selected by this check.
namespace blot_reuse_project_check;
import .project_check;
import backend.opaque_storage;
fn producerCapability(self_:const Engine&,target:ExternalTarget)->blot_support::Option<blot_check_check::ProducerCapability> {
 let module=self_.catalogModule(target.unit);if !module.present {return blot_support::none<blot_check_check::ProducerCapability>();}match module.value.owner {
 typed payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return blot_support::none<blot_check_check::ProducerCapability>();}let binding=owner.bindings[target.binding];return blot_support::some(blot_check_check::ProducerCapability{flow:binding.capability_flow,parameters:binding.capability_parameters,recipe:blot_support::some(blot_check_check::CapabilitySource{blot_check_check::Callees.live{blot_check_check::liveCallees(owner)},target.binding, ..}), ..});},
 frozen payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return blot_support::none<blot_check_check::ProducerCapability>();}let binding=owner.bindings[target.binding];return blot_support::some(blot_check_check::ProducerCapability{flow:binding.capability_flow,parameters:binding.capability_parameters,recipe:blot_support::some(blot_check_check::CapabilitySource{blot_check_check::Callees.frozen{blot_check_check::frozenCallees(owner)},target.binding, ..}), ..});},
 source payload=>{let owner .= payload.value;if target.binding>=owner.declarations.len || owner.declarations[target.binding].external.present {return blot_support::none<blot_check_check::ProducerCapability>();}let declaration=owner.declarations[target.binding];return blot_support::some(blot_check_check::ProducerCapability{flow:declaration.capability_flow,parameters:declaration.capability_parameters, ..});},inactive=>{return blot_support::none<blot_check_check::ProducerCapability>();},
 }}
// The scheme `target`'s own module published, for a member that reaches an
// importing module through another module's catalog.
fn producerInterface(self_:const Engine&,target:ExternalTarget)->blot_support::Option<blot_check_check::SchemeInterface> {
 if self_.source_validation {return blot_support::none<blot_check_check::SchemeInterface>();}let module=self_.catalogModule(target.unit);if !module.present {return blot_support::none<blot_check_check::SchemeInterface>();}match module.value.owner {
 typed payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return blot_support::none<blot_check_check::SchemeInterface>();}return blot_support::some(checkedInterface(owner,target));},
 frozen payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return blot_support::none<blot_check_check::SchemeInterface>();}return blot_support::some(blot_check_check::ImportedCatalog{frozen:blot_support::Option<blot_check_check::FrozenProducer>{true,blot_check_check::frozenProducer(owner,module.value.summaries)},kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..}.interface(target.binding));},
 _=>{return blot_support::none<blot_check_check::SchemeInterface>();},
 }}
fn producerStorage(self_:const Engine&,identity_:blot_check_types::NominalIdentity)->blot_support::Option<blot_backend_opaque_storage::Storage> {
 if identity_.unit==0 || identity_.unit>self_.source.units.len {return blot_support::none<blot_backend_opaque_storage::Storage>();}let module=self_.catalogModule(identity_.unit);if !module.present {return blot_support::none<blot_backend_opaque_storage::Storage>();}for nominal in module.value.catalog().nominals {if nominal.is_opaque && nominal.identity==identity_ {return blot_support::some(nominal.storage);}}return blot_support::none<blot_backend_opaque_storage::Storage>();
}
