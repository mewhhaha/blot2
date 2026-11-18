// Collect checker-generated names from the dependency-ordered source headers.
namespace blot_reuse_project_check;
import .project_check;

struct ContractName {
    exported: u32,
    unit: u32,
    declaration: u32,
}

fn seedContractName(source: Project&, contract: ContractName, namespace_: u32, alias: u32) -> Error {
    let tree: const blot_parse_ast::Tree& = source.unit(contract.unit).tree;
    let header = tree.node(contract.declaration);
    let body = tree.node(header.b);
    for member in tree.list(blot_parse_ast::List{start: body.a, len: body.b, ..}) {
        let node = tree.node(member);
        if node.tag != blot_parse_ast::tag_contract_value_member {continue;}
        let error = blot_check_check::prepareQualifiedName(source.symbols, namespace_, alias, node.a);
        if error != blot_error::Error.none {return error;}
    }
    return blot_error::Error.none;
}

fn preparePersistentNames(source: Project&, skip:u32=0) -> bool, Error {
    // Mixed projects currently use their checked producer catalogs.
    if source.input_mode != blot_reuse_project::InputMode.project || source.compiledCount() != 0 {
        return false, blot_error::Error.none;
    }
    var ranges: blot_reuse_project::Range[>..] = [];
    ranges.resize(source.units.len, blot_reuse_project::Range{..});
    var contracts: ContractName[>..] = [];
    for unit in source.order.items {
        if unit==skip {continue;}
        let error=prepareUnitNames(source,unit,ranges[..],contracts);
        if error!=blot_error::Error.none {return false,error;}
    }
    return true, blot_error::Error.none;
}

fn prepareUnitNames(source:Project&,unit:u32,ranges:blot_reuse_project::Range[:],contracts:ContractName[>..]&) -> Error {
    let tree: const blot_parse_ast::Tree& = source.unit(unit).tree;
    let locals = blot_check_check::prepareGeneratedNames(source.symbols, tree, default<const blot_check_check::ImportedCatalog[:]>());
    if locals != blot_error::Error.none {return locals;}
    let start = contracts.len;
    for root in tree.roots.items {
        let node = tree.node(root);
        if node.tag != blot_parse_ast::tag_contract_decl {continue;}
        let contract = ContractName{exported: node.a, unit: unit, declaration: root};
        let error = seedContractName(source, contract, 0, node.a);
        if error != blot_error::Error.none {return error;}
        if !blot_parse_ast::declaration_traits(tree, root).private {
            contracts.push(contract);
        }
    }
    var forwards: ContractName[>..] = [];
    for edge in source.unitImports(unit) {
        let info = tree.import_decl(edge.declaration.node);
        let range = ranges[edge.target - 1];
        let available = contracts[range.start..range.start + range.len];
        if info.namespace_ != 0 {
            for contract in available {
                let error = seedContractName(source, contract, info.namespace_, contract.exported);
                if error != blot_error::Error.none {return error;}
            }
        } else {
            let forwarding = tree.node(edge.declaration.node).tag == blot_parse_ast::tag_export_decl;
            for binding in tree.list(info.bindings) {
                let names = tree.import_binding(binding);
                for contract in available {
                    if names.name != contract.exported {continue;}
                    let error = seedContractName(source, contract, 0, names.alias);
                    if error != blot_error::Error.none {return error;}
                    if forwarding {
                        forwards.push(ContractName{exported: names.alias, unit: contract.unit, declaration: contract.declaration});
                    }
                }
            }
        }
    }
    let prelude = source.prelude_unit;
    if source.unit(unit).implicit_prelude && prelude != 0 && prelude != unit {
        let range = ranges[prelude - 1];
        for contract in contracts[range.start..range.start + range.len] {
            let error = seedContractName(source, contract, 0, contract.exported);
            if error != blot_error::Error.none {return error;}
        }
    }
    contracts.append(forwards[..]);
    if contracts.len > 0xffffffff {return blot_error::Error.symbol_limit;}
    ranges[unit - 1] = blot_reuse_project::Range{start: start as u32, len: (contracts.len - start) as u32, ..};
    return blot_error::Error.none;
}
