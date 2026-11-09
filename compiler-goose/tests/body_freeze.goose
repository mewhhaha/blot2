// Instantiate the production freeze/publication path without constructing Engine.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.check;
import check.types;
import check.parameter_patterns;
import parse.ast;
import parse.symbols;
import reuse.body_check_cache;
import reuse.body_check_freeze;
import support.error;
import support.option;
type Cache=blot_reuse_body_check_cache::Cache;
type Chunk=blot_reuse_body_check_cache::Chunk;
type Body=blot_reuse_body_check_cache::Body;
type Fact=blot_reuse_body_check_cache::Fact;
fn freeze(with_body:bool)->Chunk? {
    var pool,error=blot_parse_symbols::initPooled();assert(error==blot_error::Error.none);
    var tree,error=blot_parse_ast::initPooled();assert(error==blot_error::Error.none);
    var types,error=blot_check_types::initPooled();assert(error==blot_error::Error.none);
    var patterns,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
    var checked=default<blot_check_check::Checked>();
    checked.types=types;checked.parameter_patterns=patterns;checked.unit=1;
    var bodies=blot_reuse_body_check_cache::FreezeBodies{..};
    var roots=blot_reuse_body_check_cache::Scratch_u32{..};
    var rows=blot_reuse_body_check_cache::Scratch_u32{..};
    var effect_rows=blot_reuse_body_check_cache::Scratch_u32{..};
    var labels=blot_reuse_body_check_cache::Scratch_u32{..};
    if with_body {
        let facts=blot_reuse_body_check_cache::copyOwned([Fact{ty:blot_check_types::u32_type,..}]);
        let body=blot_reuse_body_check_cache::canonicalBody(Body{
            name:blot_reuse_body_check_cache::copyOwned("body"),
            source:blot_reuse_body_check_cache::copyOwned("owned source"),facts:facts,..});
        assert(bodies.push(body)==blot_error::Error.none);
        assert(roots.push(blot_check_types::u32_type)==blot_error::Error.none);
    }
    let chunk,error=blot_reuse_body_check_cache::freezeChunk(tree,pool,checked,
        blot_support::none<blot_reuse_body_check_cache::ExternalNames>(),
        bodies.items,roots.items,rows.items,effect_rows.items,labels.items);
    assert(error==blot_error::Error.none && chunk!=null);
    // freezeChunk transfers each body's owned runs into its published owner.
    bodies.clear();bodies.deinit();roots.deinit();rows.deinit();effect_rows.deinit();labels.deinit();
    patterns.deinit();types.deinit();tree.deinit();pool.deinit();
    return chunk;
}
fn checkBody(cache:const Cache&) {
    let body .= cache.find("body");assert(body!=null);
    assert(body.name=="body" && body.source=="owned source" && body.facts.len==1);
    assert(body.owner.live && body.owner.bodies.len==1);
    let ty=body.facts[0].ty;
    assert(ty<body.owner.graph.nodes.len && body.owner.graph.nodes[ty].tag==blot_check_types::Tag.unsigned32);
}
fn emptyChunk() {
    let chunk .= freeze(false);assert(chunk!=null);
    assert(chunk.live && chunk.references==1 && chunk.bodies.len==0);
    chunk.release();
}
fn ownedPublication() {
    var cache,error=blot_reuse_body_check_cache::initPooled();assert(error==blot_error::Error.none);
    {
        let chunk .= freeze(true);assert(chunk!=null);
        assert(chunk.live && chunk.bodies.len==1 && chunk.graph.nodes.len>0);
        assert(blot_reuse_body_check_cache::publishChunk(cache,chunk)==blot_error::Error.none);
    }
    checkBody(cache);
    let payload,error=cache.payload();assert(error==blot_error::Error.none);
    assert(payload.chunks==1 && payload.graph_nodes>0 && payload.bytes>0);
    var retained,error=cache.clone();assert(error==blot_error::Error.none);
    cache.deinit();checkBody(retained);
    retained.deinit();
}
fn main() {
    for cycle in 0..3 {emptyChunk();ownedPublication();}
    print("body freeze passed: initialized stores, owned graph/body publication, retained cache and cleanup");
}
