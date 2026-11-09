// Scalar ordering observes owned definitions without publishing borrowed headers.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.native_assets;
import backend.native_asset_readers;
import support.error;
import reuse.source_overlays;
fn populated()->blot_backend_native_assets::Session {
    var module:u8[>..]=[];module.append("/tmp/a.blot");
    var path:u8[>..]=[];path.append("/tmp/a.bin");
    var ty:u8[>..]=[];ty.append("Asset");
    var name:u8[>..]=[];name.append("asset");
    var media:u8[>..]=[];media.append("application/octet-stream");
    let definitions=[blot_backend_native_assets::Definition{module:module[..],path:path[..],kind:blot_backend_native_assets::Kind.reference,ty:blot_support::some<const u8[:]>(ty[..]),export_name:blot_support::some<const u8[:]>(name[..]),mediaType:blot_support::some<const u8[:]>(media[..])},blot_backend_native_assets::Definition{module:"/tmp/b.blot",path:"/tmp/b.json",kind:blot_backend_native_assets::Kind.json}];
    let roots=["/tmp/assets-root"];
    let session,error=blot_backend_native_assets::init(blot_backend_native_assets::Options{imports:definitions[..],roots:roots[..]});assert(error==blot_error::Error.none);
    module.clear();path.clear();ty.clear();name.clear();media.clear();return session;
}
fn main() {
    let assets=[blot_reuse_source_overlays::Source{path:"/tmp/a.bin",contents:blot_support::some<const u8[:]>("payload")},blot_reuse_source_overlays::Source{path:"/tmp/b.json",contents:blot_support::some<const u8[:]>("{\"score\":3}")},blot_reuse_source_overlays::Source{path:"/tmp/assets-root/text.json",contents:blot_support::some<const u8[:]>("{\"hello\":\"world\"}")}];
    for cycle in 0..3 {
        var session=populated();assert(session.options.imports.len==2 && session.options.roots[0]=="/tmp/assets-root");
        let first,error=session.prepare("/tmp/entry.blot",[],assets[..]);assert(error==blot_error::Error.none && first!=null);
        assert(!first.issue.present && first.modules.items.len==3 && first.sources.items.len==3 && first.dependencies.items.len==3 && first.resources.items.len==1);
        assert(first.modules.items[0].module=="/tmp/a.blot" && first.modules.items[1].module=="/tmp/assets-root/text.json.blot" && first.modules.items[2].module=="/tmp/b.blot");
        let value=first.modules.items[0].definition;assert(value.path=="/tmp/a.bin" && value.kind==blot_backend_native_assets::Kind.reference);
        assert(value.ty.present && value.ty.value=="Asset" && value.export_name.present && value.export_name.value=="asset" && value.mediaType.present && value.mediaType.value=="application/octet-stream");
        assert(!first.modules.items[2].definition.ty.present && first.modules.items[2].source.len!=0);
        assert(first.resources.items[0].id==1 && first.resources.items[0].bytes=="payload");
        assert(first.stats.parsed==3 && first.stats.reused==0);
        session.commit(first);
        var malformed=assets;malformed[1].contents=blot_support::some<const u8[:]>("{");
        let rejected,error=session.prepare("/tmp/entry.blot",[],malformed[..]);assert(error==blot_error::Error.none && rejected!=null && rejected.issue.present);
        assert(rejected.issue.value.filename=="/tmp/b.json" && rejected.issue.value.code=="asset_json" && rejected.issue.value.message=="Malformed JSON asset");
        var generated,error=blot_backend_native_asset_readers::generate(blot_backend_native_asset_readers::Kind.json,"{\"other\":4}");assert(error==blot_error::Error.none);generated.deinit();
        assert(rejected.issue.value.code=="asset_json" && rejected.issue.value.message=="Malformed JSON asset");rejected.deinit();
        let second,error=session.prepare("/tmp/entry.blot",[],assets[..]);assert(error==blot_error::Error.none && second!=null && !second.issue.present);
        assert(second.stats.parsed==0 && second.stats.reused==3 && second.modules.items[0].definition.ty.value=="Asset");
        session.commit(second);session.deinit();assert(session.owned_definitions.len==0 && session.owned_roots.len==0 && session.texts.items.len==0);
    }
    let definitions=[blot_backend_native_assets::Definition{module:"/tmp/duplicate.blot",path:"/tmp/b.json",kind:blot_backend_native_assets::Kind.json},blot_backend_native_assets::Definition{module:"/tmp/duplicate.blot",path:"/tmp/b.json",kind:blot_backend_native_assets::Kind.json}];
    var duplicate,error=blot_backend_native_assets::init(blot_backend_native_assets::Options{imports:definitions[..]});assert(error==blot_error::Error.none);
    let candidate,error=duplicate.prepare("/tmp/entry.blot",[],assets[..]);assert(candidate==null && error==blot_error::Error.duplicate_asset_module);duplicate.deinit();
    print("native asset metadata passed: source scope, scalar ordering, discovery, prepare, reader failure ownership, reuse, duplicates and cleanup");
}
