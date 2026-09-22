import { strict as assert } from "node:assert";

const [input, output, traceDirectory = "build"] = Deno.args;
if (!input || !output || Deno.args.length > 3) {
  throw new Error(
    "Usage: compiler/cpu_scaling_trace.ts input.c output.c [trace-directory]",
  );
}
await Deno.mkdir(traceDirectory, { recursive: true });
const tracePath = JSON.stringify(traceDirectory);
let source = await Deno.readTextFile(input);
function replaceOnce(before: string, after: string) {
  assert.equal(source.split(before).length, 2, `unique marker: ${before}`);
  source = source.replace(before, after);
}

replaceOnce(
  "// Dialect\n",
  `
typedef struct { const char* name; double wall; double cpu; int seq; int nofork; } BlotStamp;
static BlotStamp blot_stamps[4096];
static unsigned blot_stamp_count;
static unsigned blot_request_count;
static bool blot_trace_active;
static double blot_clock(clockid_t clock) {
  struct timespec now;
  if (clock_gettime(clock, &now) != 0) abort();
  return (double)now.tv_sec * 1000.0 + (double)now.tv_nsec / 1000000.0;
}
static void blot_stamp(const char* name) {
  if (!blot_trace_active) return;
  if (blot_stamp_count == 4096) abort();
  BlotStamp* stamp = &blot_stamps[blot_stamp_count++];
  stamp->name = name;
  stamp->wall = blot_clock(CLOCK_MONOTONIC);
  stamp->cpu = blot_clock(CLOCK_PROCESS_CPUTIME_ID);
  stamp->seq = -1;
  stamp->nofork = -1;
}
static void blot_segment(const char* name, int seq, int nofork) {
  blot_stamp(name);
  if (!blot_trace_active) return;
  blot_stamps[blot_stamp_count - 1].seq = seq;
  blot_stamps[blot_stamp_count - 1].nofork = nofork;
}
static void blot_trace_begin(void) {
  blot_stamp_count = 0;
  blot_trace_active = true;
  blot_stamp("receive");
}
static void blot_trace_finish(unsigned workers) {
  if (!blot_trace_active) return;
  blot_stamp("payload_ready");
  blot_trace_active = false;
  char path[256];
  if (snprintf(path, sizeof path, "%s/cpu-scaling-events-%d.jsonl", ${tracePath}, (int)getpid()) >= sizeof path) abort();
  FILE* out = fopen(path, "a");
  if (!out) abort();
  fprintf(out, "{\\"pid\\":%d,\\"workers\\":%u,\\"request\\":%u,\\"events\\":[", (int)getpid(), workers, blot_request_count++);
  for (unsigned index = 0; index < blot_stamp_count; index++) {
    BlotStamp* stamp = &blot_stamps[index];
    fprintf(out, "%s{\\"phase\\":\\"%s\\",\\"wall_ms\\":%.6f,\\"cpu_ms\\":%.6f,\\"seq\\":%d,\\"nofork\\":%d}", index ? "," : "", stamp->name, stamp->wall - blot_stamps[0].wall, stamp->cpu - blot_stamps[0].cpu, stamp->seq, stamp->nofork);
  }
  fputs("]}\\n", out);
  if (fclose(out) != 0) abort();
}

// Dialect
`,
);

const boundaries = {
  NATIVE_REQUEST_DECODE: "decode_request",
  RESPOND: "dispatch",
  SOURCE_MODULES_SOURCE_MODULE: "lower",
  MAIN_ANALYZE: "analysis",
  GROUPS_PLAN: "dependency_plan",
  ...(source.includes("  WL_CASE(FID_CHECK_SCHEDULER_CHECK_JOBS)\n  {")
    ? { CHECK_SCHEDULER_CHECK_JOBS: "inference" }
    : {
      CHECK_SCHEDULER_SCHEDULE: "schedule",
      CHECK_SCHEDULER_CHECK_FRONTIER: "inference_prepare",
      CHECK_SCHEDULER_CHECK_BATCH: "inference_execute",
    }),
  CONST_EVAL_EVALUATE_CONSTANTS: "constants",
  ...(source.includes("  WL_CASE(FID_WASM_EMIT_PLAN)\n  {")
    ? { WASM_EMIT_PLAN: "wasm" }
    : { WASM_EMIT: "wasm" }),
  WASM_PREPARE: "reachability",
  WASM_PREPARE_JOBS: "projection",
  WASM_COMPILE_ENTRIES: "codegen",
  ...(source.includes("  WL_CASE(FID_WASM_LINK_PLAN)\n  {")
    ? { WASM_LINK_PLAN: "link" }
    : { WASM_LINK: "link" }),
  ...(source.includes("  WL_CASE(FID_NATIVE_OUTPUT_ENCODE_ARTIFACT)\n  {")
    ? { NATIVE_OUTPUT_ENCODE_ARTIFACT: "encode_response" }
    : { NATIVE_RESPONSE_ENCODE_ARTIFACT: "encode_response" }),
  ...(source.includes("  WL_CASE(FID_NATIVE_OUTPUT_PACK_CHUNKS)\n  {")
    ? { NATIVE_OUTPUT_PACK_CHUNKS: "pack_output_chunks" }
    : {}),
  NATIVE_SESSION_UPDATE_SOURCE: "session_lower",
  ...(source.includes("  WL_CASE(FID_GROUPS_PREPARE_PLAN_USAGES)\n  {")
    ? { GROUPS_PREPARE_PLAN_USAGES: "prepare_dependency_plan" }
    : { GROUPS_PREPARE_PLAN_GRAPH: "prepare_dependency_plan" }),
  NATIVE_CACHE_KEYS_PLANNING: "planning_key",
  NATIVE_SESSION_CHECK_PLAN: "session_inference",
  NATIVE_SESSION_EVALUATE_CONSTANTS: "session_constants",
  NATIVE_SESSION_COMPILE_JOBS: "session_codegen",
  COMPLETED: "session_encode_response",
};
for (const [name, phase] of Object.entries(boundaries)) {
  const marker = `  WL_CASE(FID_${name})\n  {`;
  replaceOnce(
    marker,
    `${marker}\n    blot_segment("${phase}", seq, fid_nofk(FID_${name}));`,
  );
}
replaceOnce(
  "  if (count == 0) return term_pak(CID_NONE, 0);",
  "  if (count == 0) return term_pak(CID_NONE, 0);\n  blot_trace_begin();",
);
replaceOnce(
  "  blot_native_read_exact(bytes, byte_length);",
  '  blot_native_read_exact(bytes, byte_length);\n  blot_stamp("load_request_buffer");',
);
replaceOnce(
  "static Term blot_native_send_run(Env e, Term* fields, IoWork* work) {",
  'static Term blot_native_send_run(Env e, Term* fields, IoWork* work) {\n  blot_stamp("send");',
);
replaceOnce(
  "  blot_native_write_exact(bytes, (size_t)length * 4);",
  // The parent can dispose the child as soon as the complete payload arrives.
  // Flush diagnostics first; the final interval excludes the payload write.
  "  blot_trace_finish(pool_size);\n  blot_native_write_exact(bytes, (size_t)length * 4);",
);
await Deno.writeTextFile(output, source);
