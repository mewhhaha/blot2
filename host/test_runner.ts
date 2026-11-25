import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  formatDiagnosticReport,
  type RawDiagnosticRecord,
} from "./diagnostics.ts";
import { expandGeneratorRules } from "./generators.ts";
import { readGuestAbi } from "./guest.ts";
import { resolveProject } from "./packages.ts";
import {
  extractNativeCompiler,
  extractStandardLibrary,
  findCheckoutCompiler,
} from "./packaged_native.ts";
import { decodeText } from "./text.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "./zig_project_client.ts";
import {
  serveTestWorker,
  TEST_WORKER_ARG,
  TEST_WORKER_URL,
  testTransport,
  type TestWorkerRequest,
  type TestWorkerResponse,
} from "./test_worker.ts";

if (Deno.build.standalone && Deno.args[0] === TEST_WORKER_ARG) {
  await serveTestWorker();
  Deno.exit(0);
}

export const TEST_REPORT_MAGIC = 0x4254_5354;
export const TEST_REPORT_VERSION = 1;

export interface TestFailure {
  group: string;
  label: string;
  message: string;
  expected: string;
  actual: string;
}

export interface TestReport {
  passed: number;
  failed: number;
  failures: TestFailure[];
}

/** Decode a BTST v1 packet, throwing on malformed input. */
export function decodeTestReport(
  words: Uint32Array | readonly number[],
): TestReport {
  let offset = 0;
  function word(): number {
    if (offset >= words.length) throw new Error("Truncated BTST report");
    const value = words[offset++];
    if (!Number.isInteger(value) || value < 0 || value > 0xFFFF_FFFF) {
      throw new Error("Invalid U32 word in BTST report");
    }
    return value;
  }
  function field(): string {
    const length = word();
    if (length > words.length - offset) throw new Error("Truncated BTST text");
    const start = offset;
    offset += length;
    return decodeText(words.slice(start, offset));
  }
  if (word() !== TEST_REPORT_MAGIC) {
    throw new Error("Invalid BTST report magic");
  }
  const version = word();
  if (version !== TEST_REPORT_VERSION) {
    throw new Error(`Unsupported BTST report version ${version}`);
  }
  const passed = word();
  const failed = word();
  if (failed > Math.floor((words.length - offset) / 5)) {
    throw new Error("Truncated BTST failure records");
  }
  const failures: TestFailure[] = [];
  for (let i = 0; i < failed; i++) {
    failures.push({
      group: field(),
      label: field(),
      message: field(),
      expected: field(),
      actual: field(),
    });
  }
  if (offset !== words.length) throw new Error("Trailing words in BTST report");
  return { passed, failed, failures };
}

export type TestKind = "check" | "trap";
export interface TestMetadata {
  kind: TestKind;
  exportName: string;
  displayName: string;
  filename: string;
  line: number;
}

/** Return undefined when blot:tests is absent, and throw on a malformed section. */
export function readTestMetadata(
  wasm: WebAssembly.Module | Uint8Array<ArrayBuffer>,
): TestMetadata[] | undefined {
  const module = wasm instanceof WebAssembly.Module
    ? wasm
    : new WebAssembly.Module(wasm);
  const sections = WebAssembly.Module.customSections(module, "blot:tests");
  if (!sections.length) return undefined;
  if (sections.length !== 1) throw new Error("Duplicate blot:tests section");
  const bytes = new Uint8Array(sections[0]);
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  let offset = 0;
  function byte(): number {
    if (offset >= bytes.length) throw new Error("Truncated blot:tests section");
    return bytes[offset++];
  }
  function u32(): number {
    let value = 0;
    for (let shift = 0; shift <= 28; shift += 7) {
      const next = byte();
      if (shift === 28 && next > 0x0F) break;
      value += (next & 0x7F) * 2 ** shift;
      if (next < 0x80) return value;
    }
    throw new Error("Invalid u32 LEB128 in blot:tests section");
  }
  function string(): string {
    const length = u32();
    if (length > bytes.length - offset) {
      throw new Error("Truncated UTF-8 field in blot:tests section");
    }
    const start = offset;
    offset += length;
    try {
      return decoder.decode(bytes.subarray(start, offset));
    } catch (cause) {
      throw new Error("Invalid UTF-8 in blot:tests section", { cause });
    }
  }
  const version = byte();
  if (version !== 1) {
    throw new Error(`Unsupported blot:tests version ${version}`);
  }
  const count = u32();
  if (count > Math.floor((bytes.length - offset) / 5)) {
    throw new Error("Truncated blot:tests entries");
  }
  const tests: TestMetadata[] = [];
  for (let i = 0; i < count; i++) {
    const kind = byte();
    if (kind !== 0 && kind !== 1) {
      throw new Error(`Invalid blot:tests kind ${kind}`);
    }
    tests.push({
      kind: kind === 0 ? "check" : "trap",
      exportName: string(),
      displayName: string(),
      filename: string(),
      line: u32(),
    });
  }
  if (offset !== bytes.length) {
    throw new Error("Trailing bytes in blot:tests section");
  }
  return tests;
}

export interface TestRunOptions extends
  Pick<
    ZigProjectCompilerOptions,
    | "prelude"
    | "stdRoot"
    | "imports"
    | "dependencies"
    | "wasm3"
    | "relaxedSimd"
    | "tailCalls"
  > {
  executable?: string | URL;
  /** Relative paths resolve from root, which defaults to the working directory. */
  root?: string;
  paths?: readonly string[];
  filter?: string;
  jobs?: number;
  bail?: boolean;
  release?: boolean;
  /** Per-test deadline in seconds, defaulting to 30. */
  deadline?: number;
  inputMode?: "project" | "source";
}

export type TestModuleKind = "checks" | "traps" | "rejected";
export interface TestModule {
  path: string;
  kind: TestModuleKind;
  expectedRejection?: string;
}

export interface TestCaseResult {
  kind: TestKind | "rejected" | "module";
  exportName?: string;
  displayName?: string;
  filename?: string;
  line?: number;
  status: "passed" | "failed" | "timeout";
  elapsedMs: number;
  assertionsPassed: number;
  assertionsFailed: number;
  failures?: TestFailure[];
  message?: string;
  diagnostics?: RawDiagnosticRecord[];
}

export interface TestModuleResult {
  path: string;
  kind: TestModuleKind;
  tests: TestCaseResult[];
  elapsedMs: number;
}

export interface TestRunReport {
  success: boolean;
  modules: TestModuleResult[];
  testsPassed: number;
  testsFailed: number;
  assertionsPassed: number;
  assertionsFailed: number;
  elapsedMs: number;
  jobs: number;
  message?: string;
}

const ignoredDirectories = new Set([
  ".git",
  "build",
  "target",
  "node_modules",
  "compiler-goose",
  "generated",
]);
const testDeclaration =
  /^[ \t]*(?:@\[[^\r\n]*\][ \t]*)?(?:#entry[ \t]+(?:func|const|let)[ \t]+(?:test_|trap_)\w*|test[ \t]+(?:expect_trap[ \t]+)?")/m;

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function rejection(source: string): string | undefined {
  for (const line of source.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (!trimmed.startsWith("//")) break;
    const marker = /^\/\/\s*rejects:\s*(.*)$/.exec(trimmed);
    if (marker) return marker[1] || undefined;
  }
}

export async function discoverTestModules(
  options: Pick<TestRunOptions, "root" | "paths" | "filter"> = {},
): Promise<TestModule[]> {
  const cwd = resolve(options.root ?? Deno.cwd());
  const explicit = options.paths ?? [];
  const project = explicit.length
    ? undefined
    : await resolveProject(join(cwd, "blot.json"));
  const root = project?.root ?? cwd;
  const candidates = new Map<string, boolean>();
  function add(path: string, explicitFile: boolean) {
    candidates.set(path, explicitFile || candidates.get(path) === true);
  }
  async function walk(
    path: string,
    select: (path: string) => boolean,
    ignoreDirectories: boolean,
  ) {
    for await (const entry of Deno.readDir(path)) {
      const child = join(path, entry.name);
      if (
        entry.isDirectory &&
        !(ignoreDirectories && ignoredDirectories.has(entry.name))
      ) {
        await walk(child, select, ignoreDirectories);
      } else if (entry.isFile && select(child)) {
        add(child, false);
      }
    }
  }
  async function include(path: string) {
    const stat = await Deno.stat(path);
    if (stat.isDirectory) {
      await walk(path, (file) => file.endsWith(".blot"), false);
    } else if (stat.isFile) add(path, true);
    else throw new Error(`Expected a test file or directory: ${path}`);
  }
  const paths = explicit.length ? explicit : project?.tests?.files;
  if (paths !== undefined) {
    for (const path of paths) await include(resolve(root, path));
  } else {
    const testsRoot = join(root, "tests");
    const testDirectories = new Set([
      testsRoot,
      join(testsRoot, "traps"),
      join(testsRoot, "rejected"),
    ]);
    await walk(root, (path) =>
      path.endsWith(".test.blot") ||
      (path.endsWith(".blot") && testDirectories.has(dirname(path))), true);
  }
  const modules: TestModule[] = [];
  for (const [path, explicitFile] of candidates) {
    const source = await Deno.readTextFile(path);
    const expectedRejection = rejection(source);
    const directories = dirname(path).split(sep);
    const kind = expectedRejection || directories.includes("rejected")
      ? "rejected"
      : directories.includes("traps")
      ? "traps"
      : "checks";
    if (
      !explicitFile && kind !== "rejected" &&
      !testDeclaration.test(source)
    ) continue;
    const filter = options.filter;
    if (
      filter !== undefined && !path.includes(filter) &&
      (kind === "rejected" || !source.includes(filter))
    ) continue;
    modules.push({
      path,
      kind,
      ...(expectedRejection && { expectedRejection }),
    });
  }
  return modules.sort((a, b) => compare(a.path, b.path));
}

const defaultStdRoot = new URL("../std/", import.meta.url);
const maxDeadline = 2_147_483_647 / 1000;
const defaultJobs = () =>
  Math.min(
    4,
    Math.max(1, Math.floor((navigator.hardwareConcurrency || 4) / 2)),
  );

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

// V8 can keep executing a non-yielding Wasm loop after Worker.terminate().
// Running the worker in a child process lets the deadline preempt that loop.
class TestWorkerProcess {
  readonly #child = new Deno.Command(Deno.execPath(), {
    args: Deno.build.standalone ? [TEST_WORKER_ARG] : [
      "run",
      "--no-prompt",
      "--no-remote",
      "--allow-read",
      TEST_WORKER_URL.href,
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "inherit",
  }).spawn();
  readonly #reader = this.#child.stdout.getReader({ mode: "byob" });
  readonly #writer = this.#child.stdin.getWriter();
  readonly #transport = testTransport(this.#reader, this.#writer);

  async ready() {
    if ((await this.#transport.read<"ready">())?.data !== "ready") {
      throw new Error("Test worker failed to start");
    }
  }

  async run(request: TestWorkerRequest): Promise<TestWorkerResponse> {
    await this.#transport.write(request.test, request.bytes);
    const response = await this.#transport.read<
      Omit<TestWorkerResponse, "packet"> & { hasPacket: boolean }
    >();
    if (!response) {
      throw new Error("Test worker exited before returning a result");
    }
    const { data, payload } = response;
    const { hasPacket, ...outcome } = data;
    return {
      ...outcome,
      ...(hasPacket && { packet: new Uint32Array(payload.buffer) }),
    };
  }

  async dispose(force: boolean) {
    if (force) {
      try {
        this.#child.kill("SIGKILL");
      } catch (error) {
        if (
          !(error instanceof Deno.errors.NotFound) &&
          !(error instanceof TypeError)
        ) throw error;
      }
    }
    await Promise.allSettled([
      this.#writer.close(),
      this.#reader.cancel(),
      this.#child.status,
    ]);
    this.#writer.releaseLock();
    this.#reader.releaseLock();
  }
}

interface WorkerSlot {
  worker?: TestWorkerProcess;
}

class TestWorkers {
  readonly #idle: WorkerSlot[] = [];
  readonly #waiting: Array<(slot: WorkerSlot) => void> = [];
  #created = 0;

  constructor(private readonly jobs: number) {}

  #acquire(): WorkerSlot | Promise<WorkerSlot> {
    const idle = this.#idle.pop();
    if (idle) return idle;
    if (this.#created < this.jobs) {
      this.#created++;
      return {};
    }
    return new Promise<WorkerSlot>((resolve) => this.#waiting.push(resolve));
  }

  async run(
    request: TestWorkerRequest,
    deadlineMs: number,
    stopped: () => boolean,
    onFailure: () => void,
  ): Promise<TestCaseResult | undefined> {
    const slot = await this.#acquire();
    let started = performance.now();
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      if (stopped()) return;
      if (!slot.worker) {
        slot.worker = new TestWorkerProcess();
        await slot.worker.ready();
      }
      if (stopped()) return;
      started = performance.now();
      const invocation = slot.worker.run(request);
      const timeout = new Promise<undefined>((resolve) => {
        timer = setTimeout(() => resolve(undefined), deadlineMs);
      });
      const response = await Promise.race([invocation, timeout]);
      const elapsedMs = performance.now() - started;
      if (!response) {
        onFailure();
        await this.#terminate(slot);
        await invocation.catch(() => undefined);
        return {
          ...request.test,
          status: "timeout",
          elapsedMs,
          assertionsPassed: 0,
          assertionsFailed: 0,
          message: `Timeout after ${deadlineMs / 1000}s`,
        };
      }
      const { packet, ...outcome } = response;
      const report = packet === undefined
        ? undefined
        : decodeTestReport(packet);
      const result: TestCaseResult = {
        ...request.test,
        ...outcome,
        ...(report && {
          status: report.failed ? "failed" : "passed",
          assertionsPassed: report.passed,
          assertionsFailed: report.failed,
          failures: report.failures,
        }),
        elapsedMs,
      };
      if (result.status !== "passed") onFailure();
      return result;
    } catch (error) {
      onFailure();
      await this.#terminate(slot);
      return {
        ...request.test,
        status: "failed",
        elapsedMs: performance.now() - started,
        assertionsPassed: 0,
        assertionsFailed: 0,
        message: errorMessage(error),
      };
    } finally {
      clearTimeout(timer);
      const waiter = this.#waiting.shift();
      if (waiter) waiter(slot);
      else this.#idle.push(slot);
    }
  }

  async #terminate(slot: WorkerSlot) {
    const worker = slot.worker;
    delete slot.worker;
    await worker?.dispose(true);
  }

  async dispose() {
    await Promise.all(this.#idle.map((slot) => slot.worker?.dispose(false)));
  }
}

function pathArgument(path: string | URL): string {
  return resolve(path instanceof URL ? fileURLToPath(path) : path);
}

function projectArguments(
  options: Pick<ZigProjectCompilerOptions, "prelude" | "stdRoot" | "imports">,
  inputMode: TestRunOptions["inputMode"],
): string[] {
  const args = [
    "--prelude",
    options.prelude == null ? "none" : pathArgument(options.prelude),
  ];
  if (options.stdRoot != null) {
    args.push("--std-root", pathArgument(options.stdRoot));
  }
  for (const [prefix, path] of Object.entries(options.imports ?? {})) {
    args.push("--alias", `${prefix}=${pathArgument(path)}`);
  }
  if (inputMode) args.push("--input-mode", inputMode);
  return args;
}

async function command(executable: string | URL, args: string[]) {
  const result = await new Deno.Command(executable, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const decoder = new TextDecoder();
  const stderr = decoder.decode(result.stderr).trim();
  const diagnostics: RawDiagnosticRecord[] = [];
  for (
    const line of decoder.decode(result.stdout).trim().split("\n").filter(
      Boolean,
    )
  ) {
    const record = JSON.parse(line);
    if (record.kind === "diagnostic") diagnostics.push(record);
  }
  return { ...result, diagnostics, stderr };
}

function moduleResult(
  kind: "module" | "rejected",
  status: "passed" | "failed",
  elapsedMs: number,
  message?: string,
  diagnostics?: RawDiagnosticRecord[],
): TestCaseResult {
  return {
    kind,
    status,
    elapsedMs,
    assertionsPassed: kind === "rejected" && status === "passed" ? 1 : 0,
    assertionsFailed: kind === "rejected" && status === "failed" ? 1 : 0,
    ...(message && { message }),
    ...(diagnostics?.length && { diagnostics }),
  };
}

type CompiledTestModule =
  | { bytes: Uint8Array<ArrayBuffer> }
  | { message: string; diagnostics: RawDiagnosticRecord[] };

async function compileModule(
  compiler: ZigProjectCompilerOptions,
  inputMode: TestRunOptions["inputMode"],
  tier: "development" | "optimized" | undefined,
): Promise<CompiledTestModule> {
  if (compiler.assets !== undefined && inputMode === "source") {
    throw new Error("Generator projects require --input-mode project");
  }
  if (
    compiler.assets !== undefined ||
    inputMode !== "source" && tier === undefined
  ) {
    // Sessions bind the entry path at open. An overlay would change the base
    // directory of relative imports if used to compile a different test file.
    const session = await createZigProjectCompiler(compiler);
    try {
      const result = await session.build();
      if (result.success) return { bytes: result.bytes };
      return {
        message: "Compilation failed",
        diagnostics: result.diagnostics as RawDiagnosticRecord[],
      };
    } finally {
      await session.dispose();
    }
  }
  const output = await Deno.makeTempFile({
    prefix: "blot-test-",
    suffix: ".wasm",
  });
  try {
    const args = projectArguments(compiler, inputMode);
    if (compiler.dependencies != null) {
      args.push("--dependencies", pathArgument(compiler.dependencies));
    }
    if (compiler.wasm3) args.push("--wasm3");
    else {
      if (compiler.relaxedSimd) args.push("--relaxed-simd");
      if (compiler.tailCalls) args.push("--tail-calls");
    }
    if (compiler.testMode) args.push("--test");
    if (tier !== undefined) args.push("--codegen-tier", tier);
    const built = await command(compiler.executable, [
      "build",
      pathArgument(compiler.entry),
      output,
      ...args,
    ]);
    if (built.success) return { bytes: await Deno.readFile(output) };
    return {
      message: built.stderr || `Compilation failed (exit ${built.code})`,
      diagnostics: built.diagnostics,
    };
  } finally {
    await Deno.remove(output);
  }
}

type TestEntry =
  & Pick<TestMetadata, "kind" | "exportName">
  & Partial<Omit<TestMetadata, "kind" | "exportName">>;

async function findTests(
  bytes: Uint8Array<ArrayBuffer>,
  moduleKind: TestModuleKind,
): Promise<TestEntry[]> {
  const module = await WebAssembly.compile(bytes);
  const metadata = readTestMetadata(module);
  const abi = readGuestAbi(module);
  const listed = new Set(metadata?.map((entry) => entry.exportName));
  const conventional: TestEntry[] = [...abi.functions, ...abi.constants]
    .filter(({ name }) =>
      !listed.has(name) &&
      (name.startsWith("test_") || name.startsWith("trap_"))
    )
    .sort((a, b) => compare(a.name, b.name))
    .map(({ name }) => ({
      exportName: name,
      kind: moduleKind === "traps" || name.startsWith("trap_")
        ? "trap"
        : "check",
    }));
  return metadata !== undefined ? [...metadata, ...conventional] : conventional;
}

async function compilerAdvertises(
  executable: string | URL,
  flag: RegExp,
): Promise<boolean> {
  const help = await new Deno.Command(executable, {
    args: ["--help"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  const decoder = new TextDecoder();
  return [help.stdout, help.stderr].some((bytes) =>
    flag.test(decoder.decode(bytes))
  );
}

function supportsCodegenTier(executable: string | URL): Promise<boolean> {
  return compilerAdvertises(executable, /--codegen-tier\b/);
}

function supportsTestMode(executable: string | URL): Promise<boolean> {
  return compilerAdvertises(executable, /--test\b/);
}

export async function runBlotTests(
  options: TestRunOptions = {},
): Promise<TestRunReport> {
  const jobs = options.jobs ?? defaultJobs();
  const deadline = options.deadline ?? 30;
  if (!Number.isSafeInteger(jobs) || jobs < 1) {
    throw new RangeError("jobs must be a positive integer");
  }
  if (!Number.isFinite(deadline) || deadline <= 0 || deadline > maxDeadline) {
    throw new RangeError(`deadline must be in (0, ${maxDeadline}] seconds`);
  }
  const start = performance.now();
  const modules: TestModuleResult[] = [];
  function report(message?: string): TestRunReport {
    let testsPassed = 0,
      testsFailed = 0,
      assertionsPassed = 0,
      assertionsFailed = 0;
    for (const module of modules) {
      for (const test of module.tests) {
        if (test.status === "passed") testsPassed++;
        else testsFailed++;
        assertionsPassed += test.assertionsPassed;
        assertionsFailed += test.assertionsFailed;
      }
    }
    return {
      success: !message && testsFailed === 0 && testsPassed > 0,
      modules: modules.sort((a, b) => compare(a.path, b.path)),
      testsPassed,
      testsFailed,
      assertionsPassed,
      assertionsFailed,
      elapsedMs: performance.now() - start,
      jobs,
      ...(message && { message }),
    };
  }
  const workers = new TestWorkers(jobs);
  const projectAssets = new Map<
    string,
    ReturnType<typeof expandGeneratorRules>
  >();
  let native: Awaited<ReturnType<typeof extractNativeCompiler>> | undefined;
  let library:
    | Promise<Awaited<ReturnType<typeof extractStandardLibrary>>>
    | undefined;
  try {
    const discovered = await discoverTestModules(options);
    const noTests = options.filter === undefined
      ? "No tests found"
      : "No tests matched filter";
    if (!discovered.length) {
      return report(
        options.filter === undefined ? "No test modules found" : noTests,
      );
    }
    const executable = options.executable ?? await findCheckoutCompiler() ??
      (native = await extractNativeCompiler()).path;
    const [codegenTier, testMode] = discovered.some((module) =>
        module.kind !== "rejected"
      )
      ? await Promise.all([
        supportsCodegenTier(executable),
        supportsTestMode(executable),
      ])
      : [false, false];
    const tier = codegenTier
      ? options.release ? "optimized" : "development"
      : undefined;

    let next = 0;
    let stopped = false;
    const stopOnFailure = () => {
      if (options.bail) stopped = true;
    };
    const runModule = async (module: TestModule): Promise<TestCaseResult[]> => {
      const started = performance.now();
      const elapsed = () => performance.now() - started;
      try {
        if (module.kind === "rejected" && !module.expectedRejection) {
          return [
            moduleResult(
              "rejected",
              "failed",
              elapsed(),
              "Missing leading // rejects: expectation",
            ),
          ];
        }
        const project = await resolveProject(module.path);
        let prelude = options.prelude;
        let stdRoot = options.stdRoot;
        const imports = { ...project?.imports };
        if (options.stdRoot !== undefined) delete imports["std/"];
        Object.assign(imports, options.imports);
        if (project) {
          if (prelude === undefined) prelude = project.prelude;
          stdRoot ??= null;
        } else {
          const standardRoot = Deno.build.standalone &&
              (prelude === undefined || stdRoot === undefined)
            ? (await (library ??= extractStandardLibrary())).path
            : fileURLToPath(defaultStdRoot);
          if (prelude === undefined) {
            prelude = join(standardRoot, "prelude.blot");
          }
          if (stdRoot === undefined) {
            stdRoot = Object.hasOwn(imports, "std/") ? null : standardRoot;
          }
        }
        const compiler: ZigProjectCompilerOptions = {
          executable,
          entry: module.path,
          prelude,
          stdRoot,
          imports,
          dependencies: options.dependencies,
          wasm3: options.wasm3,
          relaxedSimd: options.relaxedSimd,
          tailCalls: options.tailCalls,
          testMode,
        };
        if (project?.generators?.length) {
          let assets = projectAssets.get(project.root);
          if (!assets) {
            assets = expandGeneratorRules(
              project.root,
              project.generators,
              compiler,
            );
            projectAssets.set(project.root, assets);
          }
          compiler.assets = await assets;
        }
        if (module.kind === "rejected") {
          const expected = module.expectedRejection!;
          // The driver's check command takes source options. Bundle and Wasm
          // options apply to code generation only.
          const checked = compiler.assets !== undefined
            ? await compileModule(compiler, options.inputMode, tier).then((
              result,
            ) =>
              "bytes" in result
                ? { success: true, stderr: "", diagnostics: [] }
                : {
                  success: false,
                  stderr: "",
                  diagnostics: result.diagnostics,
                }
            )
            : await command(executable, [
              "check-project",
              module.path,
              ...projectArguments(compiler, options.inputMode),
            ]);
          if (checked.success) {
            return [
              moduleResult(
                "rejected",
                "failed",
                elapsed(),
                `Expected rejection "${expected}", but compilation succeeded`,
              ),
            ];
          }
          if (
            checked.diagnostics.some(({ code, message }) =>
              code === expected || message.includes(expected)
            )
          ) return [moduleResult("rejected", "passed", elapsed())];
          const detail = checked.stderr ? `\n${checked.stderr}` : "";
          return [
            moduleResult(
              "rejected",
              "failed",
              elapsed(),
              `Expected rejection "${expected}", but no diagnostic matched${detail}`,
              checked.diagnostics,
            ),
          ];
        }
        const compiled = await compileModule(compiler, options.inputMode, tier);
        if ("message" in compiled) {
          return [
            moduleResult(
              "module",
              "failed",
              elapsed(),
              compiled.message,
              compiled.diagnostics,
            ),
          ];
        }
        if (stopped) return [];
        const tests = (await findTests(compiled.bytes, module.kind)).filter((
          test,
        ) =>
          options.filter === undefined ||
          module.path.includes(options.filter) ||
          test.exportName.includes(options.filter) ||
          test.displayName?.includes(options.filter)
        );
        const results = await Promise.all(
          tests.map((test) =>
            workers.run(
              { bytes: compiled.bytes, test },
              deadline * 1000,
              () => stopped,
              stopOnFailure,
            )
          ),
        );
        return results.filter((test) => test !== undefined);
      } catch (error) {
        return [
          moduleResult("module", "failed", elapsed(), errorMessage(error)),
        ];
      }
    };
    const lane = async () => {
      while (!stopped && next < discovered.length) {
        const module = discovered[next++];
        const began = performance.now();
        const tests = await runModule(module);
        if (tests.some((test) => test.status !== "passed")) stopOnFailure();
        if (tests.length) {
          modules.push({
            path: module.path,
            kind: module.kind,
            tests,
            elapsedMs: performance.now() - began,
          });
        }
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(jobs, discovered.length) }, lane),
    );
    return report(modules.length ? undefined : noTests);
  } catch (error) {
    return report(errorMessage(error));
  } finally {
    try {
      await workers.dispose();
    } finally {
      try {
        await native?.dispose();
      } finally {
        await (await library?.catch(() => undefined))?.dispose();
      }
    }
  }
}

export async function formatTestRunReport(
  report: TestRunReport,
): Promise<string> {
  const lines: string[] = [];
  for (const module of report.modules) {
    const passed = module.tests.every((test) => test.status === "passed");
    const assertionsPassed = module.tests.reduce(
      (total, test) => total + test.assertionsPassed,
      0,
    );
    const assertionsFailed = module.tests.reduce(
      (total, test) => total + test.assertionsFailed,
      0,
    );
    lines.push(
      `${
        passed ? "ok" : "FAIL"
      } ${module.path} (${assertionsPassed} assertions passed, ${assertionsFailed} failed, ${
        module.elapsedMs.toFixed(1)
      } ms)`,
    );
    for (const test of module.tests) {
      if (test.status === "passed") continue;
      const name = test.displayName || test.exportName || test.kind;
      const location = test.filename
        ? ` (${test.filename}:${test.line})`
        : test.line
        ? ` (${module.path}:${test.line})`
        : "";
      lines.push(
        `  ${
          test.status === "timeout" ? "timeout" : "FAIL"
        } ${name}${location} (${test.elapsedMs.toFixed(1)} ms)`,
      );
      if (test.message) {
        lines.push(`    ${test.message.replaceAll("\n", "\n    ")}`);
      }
      for (const failure of test.failures ?? []) {
        const label = [failure.group, failure.label].filter(Boolean).join(
          " / ",
        );
        lines.push(
          `    ${[label, failure.message].filter(Boolean).join(": ")}`,
        );
        if (failure.expected) lines.push(`      expected: ${failure.expected}`);
        if (failure.actual) lines.push(`      actual: ${failure.actual}`);
      }
      if (test.diagnostics?.length) {
        const rendered = await formatDiagnosticReport(test.diagnostics);
        lines.push(`    ${rendered.replaceAll("\n", "\n    ")}`);
      }
    }
  }
  if (report.message) lines.push(report.message);
  const assertions = report.assertionsPassed + report.assertionsFailed;
  lines.push(
    `${report.modules.length} modules, ${report.testsPassed} tests passed, ${report.testsFailed} failed, ${assertions} assertions (${report.assertionsFailed} failed), ${
      report.elapsedMs.toFixed(1)
    } ms, ${report.jobs} jobs`,
  );
  return lines.join("\n");
}
