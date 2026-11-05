// Exclusive coordinator phases; inclusive region/pass clocks remain separate.
// Each worker process owns its own installation and merges copied counters.
namespace blot_phase_profile;
import std;
import support.native;
import support.json;
import support.option;
import support.error;
import work_counters;
type Error=blot_error::Error;
enum Phase {other,assets,inputs,load,lex,parse,check,lower,freeze,validation,backend}
let phase_names=["other","assets","inputs","load","lex","parse","check","lower","freeze","validation","backend"];
let phases=[Phase.other,Phase.assets,Phase.inputs,Phase.load,Phase.lex,Phase.parse,Phase.check,Phase.lower,Phase.freeze,Phase.validation,Phase.backend];
fn phaseIndex(phase:Phase)->i64 {for value,index in phases {if value==phase {return index;}}abort("invalid phase");}
fn difference(now:u64,before:u64)->u64 {if now<before {return 0;}return now-before;}
fn add(a:u64,b:u64)->u64 {return blot_work_counters::saturating_add(a,b);}
struct Key {slot:u32=0,generation:u64=0}
struct Profile {key:Key=Key{..}}
struct ProfileState {
    live:bool=false,generation:u64=0,started:u64=0,previous:u64=0,active:Phase=Phase.other,
    checking:blot_work_counters::Frontend=blot_work_counters::Frontend{..},
    nanos:u64[11]=[0;11],requested_bytes:u64[11]=[0;11],allocations:u64[11]=[0;11],rss_growth_kib:u64[11]=[0;11],
    peak_rss_kib:u64=0,rss_sampled:u64=0,allocation_coverage:bool=false,
}
reusable var profiles:ProfileState[>..]=[];
var installed:Key=Key{..};
fn validProfile(key:Key)->bool {return key.slot!=0 && key.slot-1<profiles.len && profiles[key.slot-1].live && profiles[key.slot-1].generation==key.generation;}
fn state(self_:Profile)->ProfileState& {assert(validProfile(self_.key));return profiles[self_.key.slot-1];}
fn initProfile()->Profile {let now=blot_native::clock_ns();let generation=blot_native::fresh_owner_id();let at=profiles.alloc_index(ProfileState{live:true,generation:generation,started:now,previous:now,peak_rss_kib:blot_native::peak_rss_kib(),rss_sampled:now,..});assert(at<0xffffffff);return Profile{Key{(at+1) as u32,generation}};}
fn deinit(self_:Profile&) {if self_.key.slot==0 {return;}assert(validProfile(self_.key) && installed!=self_.key);profiles[self_.key.slot-1].live=false;profiles.free(self_.key.slot-1);self_=Profile{..};}
fn sampleRss(self_:ProfileState&,phase:i64) {let peak=blot_native::peak_rss_kib();self_.rss_growth_kib[phase]=add(self_.rss_growth_kib[phase],difference(peak,self_.peak_rss_kib));self_.peak_rss_kib=max(self_.peak_rss_kib,peak);self_.rss_sampled=self_.previous;}
fn account(self_:ProfileState&) {let now=blot_native::clock_ns();let phase=phaseIndex(self_.active);self_.nanos[phase]=add(self_.nanos[phase],difference(now,self_.previous));self_.previous=now;if difference(now,self_.rss_sampled)>=2000000 {self_.sampleRss(phase);}}
struct PhaseRecord {us:u64=0,requested_bytes:blot_support::Option<u64> =blot_support::none<u64>(),allocations:blot_support::Option<u64> =blot_support::none<u64>(),rss_growth_kib:u64=0}
fn jsonStringify(self_:PhaseRecord,writer:blot_json::Writer&)->Error {return blot_json::jsonStringify(self_,writer);}
struct Record {profiled:bool=false,total_us:u64=0,peak_rss_kib:u64=0,phases:PhaseRecord[11]=[PhaseRecord{..};11],checking:blot_work_counters::Frontend=blot_work_counters::Frontend{..},allocation_coverage:bool=false}
fn jsonStringify(self_:Record,writer:blot_json::Writer&)->Error {
    let error=writer.beginObject();if error!=blot_error::Error.none {return error;}if self_.profiled {
        writer.field("total_us",self_.total_us);writer.field("peak_rss_kib",self_.peak_rss_kib);writer.key("phases");writer.beginObject();for name,index in phase_names {writer.field(name,self_.phases[index]);}writer.endObject();writer.field("checking",self_.checking);
        // Null counters distinguish unavailable allocator coverage from zero.
        writer.field("allocation_coverage",self_.allocation_coverage);
    }writer.endObject();return writer.failure;
}
fn record(self_:Profile&)->Record {let data .= self_.state();data.account();data.sampleRss(phaseIndex(data.active));let trace .= currentTrace();if trace {trace.flushPasses();}var result=Record{profiled:true,total_us:difference(data.previous,data.started)/1000,peak_rss_kib:data.peak_rss_kib,checking:data.checking,allocation_coverage:data.allocation_coverage,..};for ns,index in data.nanos {result.phases[index].us=ns/1000;result.phases[index].rss_growth_kib=data.rss_growth_kib[index];if data.allocation_coverage {result.phases[index].requested_bytes=blot_support::some(blot_native::atomic_load(data.requested_bytes[index]));result.phases[index].allocations=blot_support::some(blot_native::atomic_load(data.allocations[index]));}}return result;}
struct Installation {previous:Key=Key{..}}
fn install(profile:Profile&)->Installation {assert(validProfile(profile.key));let result=Installation{installed};installed=profile.key;return result;}
fn restore(self_:Installation) {assert(self_.previous.slot==0 || validProfile(self_.previous));installed=self_.previous;}
struct Scope {profile:Key=Key{..},previous:Phase=Phase.other}
fn enter(phase:Phase)->Scope {if installed.slot==0 {return Scope{..};}assert(validProfile(installed));let data:ProfileState& =profiles[installed.slot-1];data.account();let previous=data.active;data.active=phase;tracePhases(data);return Scope{installed,previous};}
fn exit(self_:Scope) {if self_.profile.slot==0 {return;}assert(validProfile(self_.profile));let data:ProfileState& =profiles[self_.profile.slot-1];data.account();data.active=self_.previous;tracePhases(data);}

enum Space {source,core}
enum OptimizationPass {inline_,scalar,vector,row_products,lifetime,reduce,rc}
let pass_names=["inline","scalar","vector","row_products","lifetime","reduce","rc"];
let passes=[OptimizationPass.inline_,OptimizationPass.scalar,OptimizationPass.vector,OptimizationPass.row_products,OptimizationPass.lifetime,OptimizationPass.reduce,OptimizationPass.rc];
fn passIndex(pass:OptimizationPass)->i64 {for value,index in passes {if value==pass {return index;}}abort("invalid pass");}
fn spaceName(space:Space)->const u8[:] {if space==Space.core {return "core";}return "source";}
struct PassTotals {us:u64=0,cpu_us:u64=0,input:u64=0,output:u64=0,calls:u64=0}
struct Trace {key:Key=Key{..}}
struct TraceState {live:bool=false,generation:u64=0,started:u64=0,build:u32=0,next:u64=1,passes:PassTotals[7]=[PassTotals{..};7],canonical:Trace=Trace{..}}
reusable var traces:TraceState[>..]=[];
var installed_trace:Key=Key{..};
var trace_space:Space=Space.source;
fn validTrace(key:Key)->bool {return key.slot!=0 && key.slot-1<traces.len && traces[key.slot-1].live && traces[key.slot-1].generation==key.generation;}
fn state(self_:Trace)->TraceState& {assert(validTrace(self_.key));return traces[self_.key.slot-1];}
fn initTrace(build:u32)->Trace {let generation=blot_native::fresh_owner_id();let at=traces.alloc_index(TraceState{live:true,generation:generation,started:blot_native::clock_ns(),build:build,..});assert(at<0xffffffff);let result=Trace{Key{(at+1) as u32,generation}};traces[at].canonical=result;return result;}
fn deinit(self_:Trace&) {if self_.key.slot==0 {return;}assert(validTrace(self_.key) && installed_trace!=self_.key);traces[self_.key.slot-1].live=false;traces.free(self_.key.slot-1);self_=Trace{..};}
fn elapsed(self_:Trace)->u64 {return difference(blot_native::clock_ns(),self_.state().started)/1000;}
fn currentTrace()->Trace? {if installed_trace.slot==0 {return null;}assert(validTrace(installed_trace));return traces[installed_trace.slot-1].canonical;}
struct TraceInstallation {previous:Key=Key{..}}
fn installTrace(trace:Trace?)->TraceInstallation {let previous=installed_trace;installed_trace=Key{..};if trace {assert(validTrace(trace.key));installed_trace=trace.key;}return TraceInstallation{previous};}
fn restore(self_:TraceInstallation) {assert(self_.previous.slot==0 || validTrace(self_.previous));installed_trace=self_.previous;}
struct SpaceScope {previous:Space=Space.source}
fn enterSpace(space:Space)->SpaceScope {let previous=trace_space;trace_space=space;return SpaceScope{previous};}
fn restore(self_:SpaceScope) {trace_space=self_.previous;}
fn currentSpace()->Space {return trace_space;}
fn cpuNanos()->blot_support::Option<u64> {if !blot_native::thread_cpu_available() {return blot_support::none<u64>();}return blot_support::some(blot_native::thread_cpu_ns());}
struct Region {owner:Key=Key{..},space:Space=Space.source,id:u64=0,stage:const u8[:]="",unit:u32=0,start:u32=0,end:u32=0,started:u64=0,cpu:blot_support::Option<u64> =blot_support::none<u64>(),pass:blot_support::Option<OptimizationPass> =blot_support::none<OptimizationPass>()}
fn writeBegin(owner:Trace,space:Space,kind:const u8[:],writer:blot_json::Writer&)->Error {writer.beginObject();writer.field("build",owner.state().build);writer.field("space",spaceName(space));writer.field("kind",kind);return writer.failure;}
fn writeEnd(writer:blot_json::Writer&) {writer.endObject();if writer.failure!=blot_error::Error.none {return;}writer.out.push('\n');if writer.out.len>4096 {return;}blot_native::debug_write(writer.out[..]);}
fn region(stage:const u8[:],unit:u32,start:u32,end:u32)->Region {
    let owner .= currentTrace();if !owner {return Region{..};}let data .= owner.state();let id=blot_native::atomic_add(data.next,1);let value=Region{owner:owner.key,space:trace_space,id:id,stage:stage,unit:unit,start:start,end:end,started:owner.elapsed(),cpu:cpuNanos(),..};
    var bytes:u8[>..]=[];bytes.append("BLOT_PROFILE ");var writer=blot_json::Writer{out:bytes,options:blot_json::Options{..},..};writeBegin(owner,trace_space,"begin",writer);writer.field("id",id);writer.field("thread",blot_native::thread_id());writer.field("stage",stage);writer.field("unit",unit);writer.field("start",start);writer.field("end",end);writer.field("at_us",value.started);writeEnd(writer);return value;
}
fn optimizationPass(pass:OptimizationPass)->Region {let owner .= currentTrace();if !owner {return Region{..};}return Region{owner:owner.key,started:owner.elapsed(),cpu:cpuNanos(),pass:blot_support::some(pass),..};}
fn exit(self_:Region) {self_.exitWithItems(0,0);}
fn exitWithItems(self_:Region,input_items:i64,output_items:i64) {
    if self_.owner.slot==0 {return;}assert(validTrace(self_.owner));let owner=Trace{self_.owner};let now=owner.elapsed();let cpu=cpuNanos();var cpu_us=blot_support::none<u64>();if cpu.present && self_.cpu.present {cpu_us=blot_support::some(difference(cpu.value,self_.cpu.value)/1000);}
    if self_.pass.present {let totals:PassTotals& =owner.state().passes[passIndex(self_.pass.value)];blot_native::atomic_add(totals.us,difference(now,self_.started));if cpu_us.present {blot_native::atomic_add(totals.cpu_us,cpu_us.value);}blot_native::atomic_add(totals.input,input_items as u64);blot_native::atomic_add(totals.output,output_items as u64);blot_native::atomic_add(totals.calls,1);return;}
    var bytes:u8[>..]=[];bytes.append("BLOT_PROFILE ");var writer=blot_json::Writer{out:bytes,options:blot_json::Options{..},..};writeBegin(owner,self_.space,"end",writer);writer.field("id",self_.id);writer.field("thread",blot_native::thread_id());writer.field("stage",self_.stage);writer.field("unit",self_.unit);writer.field("start",self_.start);writer.field("end",self_.end);writer.field("at_us",now);writer.field("us",difference(now,self_.started));writer.field("input_items",input_items);writer.field("output_items",output_items);writer.field("cpu_us",cpu_us);writeEnd(writer);
}
fn flushPasses(self_:Trace) {
    for pass,index in passes {let totals=self_.state().passes[index];if totals.calls==0 {continue;}var bytes:u8[>..]=[];bytes.append("BLOT_PROFILE ");var writer=blot_json::Writer{out:bytes,options:blot_json::Options{..},..};writeBegin(self_,Space.core,"end",writer);var stage:u8[>..]=[];stage.append("runtime-ir.total.");stage.append(pass_names[index]);writer.field("id",0);writer.field("thread",0);writer.field("stage",stage[..]);writer.field("unit",0);writer.field("start",0);writer.field("end",0);writer.field("at_us",self_.elapsed());writer.field("us",totals.us);writer.field("cpu_us",totals.cpu_us);writer.field("input_items",totals.input);writer.field("output_items",totals.output);writer.field("calls",totals.calls);writeEnd(writer);}
}
fn detail(stage:const u8[:],unit:u32,start:u32,end:u32,items:u64) {let owner .= currentTrace();if !owner {return;}var bytes:u8[>..]=[];bytes.append("BLOT_PROFILE ");var writer=blot_json::Writer{out:bytes,options:blot_json::Options{..},..};writeBegin(owner,trace_space,"detail",writer);writer.field("thread",blot_native::thread_id());writer.field("stage",stage);writer.field("unit",unit);writer.field("start",start);writer.field("end",end);writer.field("items",items);writer.field("at_us",owner.elapsed());writeEnd(writer);}
fn traceModule(unit:u32,filename:const u8[:],bytes:i64) {let owner .= currentTrace();if !owner {return;}var output:u8[>..]=[];output.append("BLOT_PROFILE ");var writer=blot_json::Writer{out:output,options:blot_json::Options{..},..};writeBegin(owner,trace_space,"module",writer);writer.field("unit",unit);writer.field("filename",filename);writer.field("bytes",bytes);writeEnd(writer);}
fn tracePhases(profile:const ProfileState&) {let owner .= currentTrace();if !owner {return;}var micros:u64[11]=[0;11];for ns,index in profile.nanos {micros[index]=ns/1000;}var output:u8[>..]=[];output.append("BLOT_PROFILE ");var writer=blot_json::Writer{out:output,options:blot_json::Options{..},..};writeBegin(owner,trace_space,"phases",writer);writer.field("active",phase_names[phaseIndex(profile.active)]);writer.field("phase_us",micros[..]);writer.field("at_us",owner.elapsed());writeEnd(writer);}

struct CheckingState {live:bool=false,generation:u64=0,work:blot_work_counters::Frontend=blot_work_counters::Frontend{..}}
reusable var checking_states:CheckingState[>..]=[];
var checking_capture:Key=Key{..};
struct CheckingCapture {previous:Key=Key{..},key:Key=Key{..}}
fn captureChecking(output:blot_work_counters::Frontend&)->CheckingCapture {let generation=blot_native::fresh_owner_id();let at=checking_states.alloc_index(CheckingState{live:true,generation:generation,..});assert(at<0xffffffff);let key=Key{(at+1) as u32,generation};let result=CheckingCapture{checking_capture,key};checking_capture=key;return result;}
fn restore(self_:CheckingCapture,output:blot_work_counters::Frontend&) {assert(checking_capture==self_.key && self_.key.slot!=0);let data:CheckingState& =checking_states[self_.key.slot-1];assert(data.live && data.generation==self_.key.generation);output.merge(data.work);checking_capture=self_.previous;data.live=false;checking_states.free(self_.key.slot-1);}
fn recordChecking(work:blot_work_counters::Frontend) {if checking_capture.slot!=0 {let data:CheckingState& =checking_states[checking_capture.slot-1];assert(data.live && data.generation==checking_capture.generation);data.work.merge(work);return;}if installed.slot==0 {return;}assert(validProfile(installed));let data:ProfileState& =profiles[installed.slot-1];if data.active==Phase.check {data.checking.merge(work);}}

// Charges only observed successful requests. Completeness must be supplied by
// an allocator integration; Goose's builtin grower is not such an integration.
struct CountingAllocator {profile:Key=Key{..}}
fn attach(self_:CountingAllocator&,profile:Profile&,complete:bool=false) {assert(validProfile(profile.key));self_.profile=profile.key;profile.state().allocation_coverage=complete;}
fn detach(self_:CountingAllocator&) {self_.profile=Key{..};}
fn charge(self_:CountingAllocator&,bytes:u64,allocations:u64) {if self_.profile.slot==0 {return;}assert(validProfile(self_.profile));let data:ProfileState& =profiles[self_.profile.slot-1];let index=phaseIndex(data.active);blot_native::atomic_add(data.requested_bytes[index],bytes);if allocations!=0 {blot_native::atomic_add(data.allocations[index],allocations);}}

// Process workers stream source/detail regions to the inherited stderr. Their
// IDs occupy a coordinator-reserved disjoint range and clocks use the same
// host monotonic origin; pass sums return as copied scalar telemetry.
struct WorkerContext {enabled:bool=false,build:u32=0,started_ns:u64=0,id_base:u64=0,space:Space=Space.source}
struct WorkerSnapshot {passes:PassTotals[7]=[PassTotals{..};7]}
struct WorkerInstallation {trace:Trace=Trace{..},previous:TraceInstallation=TraceInstallation{..},space:SpaceScope=SpaceScope{..}}
fn captureWorker()->WorkerContext {
    let owner .= currentTrace();if !owner {return WorkerContext{..};}let state .= owner.state();if state.next>0xfffffffeffffffff {return WorkerContext{..};}let base=blot_native::atomic_add(state.next,4294967296);return WorkerContext{enabled:true,build:state.build,started_ns:state.started,id_base:base,space:trace_space,..};
}
fn beginWorker(context:WorkerContext)->WorkerInstallation {
    if !context.enabled {return WorkerInstallation{..};}var trace=initTrace(context.build);let state .= trace.state();state.started=context.started_ns;state.next=context.id_base;let previous=installTrace(trace);let space=enterSpace(context.space);return WorkerInstallation{trace,previous,space};
}
fn finish(self_:WorkerInstallation&)->WorkerSnapshot {
    if self_.trace.key.slot==0 {return WorkerSnapshot{..};}let result=WorkerSnapshot{self_.trace.state().passes};self_.space.restore();self_.previous.restore();self_.trace.deinit();self_=WorkerInstallation{..};return result;
}
fn mergeWorker(snapshot:WorkerSnapshot) {
    let owner .= currentTrace();if !owner {return;}for entry,index in snapshot.passes {let totals:PassTotals& =owner.state().passes[index];blot_native::atomic_add(totals.us,entry.us);blot_native::atomic_add(totals.cpu_us,entry.cpu_us);blot_native::atomic_add(totals.input,entry.input);blot_native::atomic_add(totals.output,entry.output);blot_native::atomic_add(totals.calls,entry.calls);}
}
