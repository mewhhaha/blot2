// Producer services inspect the exact retained catalog selected by this check.
namespace squid_reuse_project_check;
import .project_check;
import backend.opaque_storage;
fn producerCapability(self_:const Engine&,target:ExternalTarget)->squid_support::Option<squid_check_check::ProducerCapability> {
 let module=self_.catalogModule(target.unit);if !module.present {return squid_support::none<squid_check_check::ProducerCapability>();}match module.value.owner {
 typed payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return squid_support::none<squid_check_check::ProducerCapability>();}let binding=owner.bindings[target.binding];return squid_support::some(squid_check_check::ProducerCapability{parameters:binding.capability_parameters, ..});},
 frozen payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return squid_support::none<squid_check_check::ProducerCapability>();}let binding=owner.bindings[target.binding];return squid_support::some(squid_check_check::ProducerCapability{parameters:binding.capability_parameters, ..});},
 source payload=>{let owner .= payload.value;if target.binding>=owner.declarations.len || owner.declarations[target.binding].external.present {return squid_support::none<squid_check_check::ProducerCapability>();}let declaration=owner.declarations[target.binding];return squid_support::some(squid_check_check::ProducerCapability{parameters:declaration.capability_parameters, ..});},inactive=>{return squid_support::none<squid_check_check::ProducerCapability>();},
 }}
// The scheme `target`'s own module published, for a member that reaches an
// importing module through another module's catalog.
fn producerInterface(self_:const Engine&,target:ExternalTarget)->squid_support::Option<squid_check_check::SchemeInterface> {
 if self_.source_validation {return squid_support::none<squid_check_check::SchemeInterface>();}let module=self_.catalogModule(target.unit);if !module.present {return squid_support::none<squid_check_check::SchemeInterface>();}match module.value.owner {
 typed payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return squid_support::none<squid_check_check::SchemeInterface>();}return squid_support::some(checkedInterface(owner,target));},
 frozen payload=>{let owner .= payload.value;if target.binding>=owner.bindings.len || owner.bindings[target.binding].external.present {return squid_support::none<squid_check_check::SchemeInterface>();}return squid_support::some(squid_check_check::ImportedCatalog{frozen:squid_support::Option<squid_check_check::FrozenProducer>{true,squid_check_check::frozenProducer(owner,module.value.summaries)},kind:squid_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..}.interface(target.binding));},
 _=>{return squid_support::none<squid_check_check::SchemeInterface>();},
 }}
fn producerStorage(self_:const Engine&,identity_:squid_check_types::NominalIdentity)->squid_support::Option<squid_backend_opaque_storage::Storage> {
 if identity_.unit==0 || identity_.unit>self_.source.units.len {return squid_support::none<squid_backend_opaque_storage::Storage>();}let module=self_.catalogModule(identity_.unit);if !module.present {return squid_support::none<squid_backend_opaque_storage::Storage>();}for nominal in module.value.catalog().nominals {if nominal.is_opaque && nominal.identity==identity_ {return squid_support::some(nominal.storage);}}return squid_support::none<squid_backend_opaque_storage::Storage>();
}
