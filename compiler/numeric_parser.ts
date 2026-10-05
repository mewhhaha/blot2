// Host syntax interpreter for Blot's unchanged Baba island plan.
// The plan is decoded by Baba's public API; its generated artifacts are never
// rewritten. All recognition state and output use owned numeric tables.
import {
  type CompactFrontendProgram,
  CpuFrontend,
  type CpuFrontendOptions,
  type FrontendDiagnostic,
  type GpuFrontendResult,
} from "@mewhhaha/baba/runtime/webgpu";

type Plan = CpuFrontend["plan"];
type Lexer = CpuFrontend["lexer"];
const TOKEN = 4, NODE = 5, EDGE = 4;
const LEXICAL = 1, DELIMITER = 2, SYNTAX = 3;
const TOKEN_CAPACITY = 4, NODE_CAPACITY = 5, EDGE_CAPACITY = 6;

export interface NumericWork {
  calls: number;
  activeRejects: number;
  activeComparisons: number;
  candidateAttempts: number;
  allocatedNodes: number;
  allocatedEdges: number;
  peakLiveNodes: number;
  peakLiveEdges: number;
  peakActiveCalls: number;
  arenaCapacityBytes: number;
  retainedNodes: number;
  retainedEdges: number;
}

class Words {
  data: Int32Array;
  length = 0;
  constructor(capacity: number) {
    this.data = new Int32Array(Math.max(16, capacity));
  }
  reserve(count: number) {
    const needed = this.length + count;
    if (needed <= this.data.length) return;
    const grown = new Int32Array(Math.max(needed, this.data.length * 2));
    grown.set(this.data.subarray(0, this.length));
    this.data = grown;
  }
  finish() {
    return this.data.slice(0, this.length);
  }
}

function diagnostic(
  code: number,
  start: number,
  end: number,
  subjectId: number,
  parameter0: number,
  parameter1: number,
): FrontendDiagnostic {
  const record = new Int32Array([
    code,
    start,
    end,
    subjectId,
    parameter0,
    parameter1,
    0,
    0,
  ]);
  let name: string, message: string;
  if (code === LEXICAL) {
    name = "GPU_FRONTEND_LEXICAL_ERROR";
    message =
      `No token matches source span [${start}, ${end}); first UTF-16 unit is ${parameter0}.`;
  } else if (code === DELIMITER) {
    name = "GPU_FRONTEND_MALFORMED_DELIMITER";
    message =
      `Delimiter at span [${start}, ${end}) expected terminal ${parameter0}, received ${parameter1}.`;
  } else if (code >= TOKEN_CAPACITY && code <= EDGE_CAPACITY) {
    const subject = code === TOKEN_CAPACITY
      ? "tokens"
      : code === NODE_CAPACITY
      ? "nodes"
      : "edges";
    name = `GPU_FRONTEND_${subject.toUpperCase().slice(0, -1)}_CAPACITY`;
    message =
      `GPU frontend produced ${parameter0} ${subject}, exceeding the source budget (${parameter1}).`;
  } else {
    name = "GPU_FRONTEND_SYNTAX_ERROR";
    message =
      `Island ${parameter0} rejected syntax at span [${start}, ${end}).`;
  }
  return { code: name, message, start, end, subjectId, record };
}

/** General recursive island interpretation with owned numeric state. */
export class NumericParser {
  readonly plan: Plan;
  readonly lexer: Lexer;
  readonly stateBase: Int32Array;
  readonly stateAccept: Uint8Array;
  readonly startState: Int32Array;
  readonly terminals: Int32Array;
  readonly islandRows: Int32Array;
  readonly islandTransitions: Int32Array;
  readonly boundaryOpen: Int32Array;
  readonly closeByOpen: Int32Array;
  readonly openByClose: Int32Array;
  readonly terminalCount: number;
  lastWork: NumericWork = {
    calls: 0,
    activeRejects: 0,
    activeComparisons: 0,
    candidateAttempts: 0,
    allocatedNodes: 0,
    allocatedEdges: 0,
    peakLiveNodes: 0,
    peakLiveEdges: 0,
    peakActiveCalls: 0,
    arenaCapacityBytes: 0,
    retainedNodes: 0,
    retainedEdges: 0,
  };

  constructor(cpu: CpuFrontend) {
    this.plan = cpu.plan;
    this.lexer = cpu.lexer;
    if (!this.lexer.guardFree || this.plan.semanticRecipes.length !== 0) {
      throw new Error(
        "Numeric parser requires a guard-free plan without host semantic recipes.",
      );
    }
    this.terminalCount = Math.max(...this.plan.terminalClassification) + 1;
    const count = this.plan.islands.reduce(
      (sum, island) => sum + island.states.length,
      0,
    );
    this.stateBase = new Int32Array(this.plan.islands.length);
    this.startState = new Int32Array(this.plan.islands.length);
    this.stateAccept = new Uint8Array(count);
    this.terminals = new Int32Array(count * this.terminalCount * 2).fill(-1);
    this.islandRows = new Int32Array(count + 1);
    const nested: number[] = [];
    let base = 0;
    for (const island of this.plan.islands) {
      this.stateBase[island.id] = base;
      this.startState[island.id] = island.startState;
      for (const state of island.states) {
        const id = base + state.id;
        this.stateAccept[id] = Number(state.accepting);
        this.islandRows[id] = nested.length / 3;
        for (const transition of state.transitions) {
          if (transition.inputKind === "terminal") {
            const at = (id * this.terminalCount + transition.input) * 2;
            // Baba chooses the first matching terminal transition.
            if (this.terminals[at] < 0) {
              this.terminals[at] = transition.target;
              this.terminals[at + 1] = transition.emit.field;
            }
          } else {
            nested.push(
              transition.input,
              transition.target,
              transition.emit.field,
            );
          }
        }
      }
      base += island.states.length;
    }
    this.islandRows[count] = nested.length / 3;
    this.islandTransitions = new Int32Array(nested);
    this.boundaryOpen = new Int32Array(this.plan.islands.length).fill(-1);
    this.closeByOpen = new Int32Array(this.terminalCount).fill(-1);
    this.openByClose = new Int32Array(this.terminalCount).fill(-1);
    for (let id = 0; id < this.plan.boundaries.length; id++) {
      const boundary = this.plan.boundaries[id];
      if (boundary.kind !== "paired" && boundary.kind !== "separated") continue;
      this.boundaryOpen[id] = boundary.openTerminal;
      const oldClose = this.closeByOpen[boundary.openTerminal];
      const oldOpen = this.openByClose[boundary.closeTerminal];
      if (
        (oldClose >= 0 && oldClose !== boundary.closeTerminal) ||
        (oldOpen >= 0 && oldOpen !== boundary.openTerminal)
      ) {
        throw new Error("Inconsistent delimiter plan.");
      }
      this.closeByOpen[boundary.openTerminal] = boundary.closeTerminal;
      this.openByClose[boundary.closeTerminal] = boundary.openTerminal;
    }
  }

  ingest(source: string, options: CpuFrontendOptions = {}): GpuFrontendResult {
    for (const key of ["maxTokens", "maxNodes", "maxEdges"] as const) {
      const value = options[key];
      if (value !== undefined && (!Number.isSafeInteger(value) || value < 0)) {
        throw new TypeError(
          `${key} must be a non-negative safe integer; received ${value}.`,
        );
      }
    }
    const began = performance.now();
    const diagnostics: FrontendDiagnostic[] = [];
    const tokens = this.lex(source, diagnostics);
    if (
      options.maxTokens !== undefined &&
      tokens.length / TOKEN > options.maxTokens
    ) {
      diagnostics.push(
        diagnostic(
          TOKEN_CAPACITY,
          0,
          source.length,
          tokens.length / TOKEN,
          tokens.length / TOKEN,
          options.maxTokens,
        ),
      );
    }
    const lexed = performance.now();
    const syntax = new Int32Array(tokens.length / TOKEN);
    const matched = new Int32Array(syntax.length).fill(-1);
    const stack = new Int32Array(syntax.length);
    let syntaxLength = 0, depth = 0;
    for (let index = 0; index < tokens.length / TOKEN; index++) {
      const terminal = tokens[index * TOKEN];
      if (terminal < 0) continue;
      const cursor = syntaxLength++;
      syntax[cursor] = index;
      if (this.closeByOpen[terminal] >= 0) {
        stack[depth++] = cursor;
      } else if (this.openByClose[terminal] >= 0) {
        const opener = depth > 0 ? stack[--depth] : -1;
        const expected = opener >= 0
          ? this.closeByOpen[tokens[syntax[opener] * TOKEN]]
          : -1;
        if (expected !== terminal) {
          diagnostics.push(
            diagnostic(
              DELIMITER,
              tokens[index * TOKEN + 1],
              tokens[index * TOKEN + 2],
              index,
              expected,
              terminal,
            ),
          );
        } else matched[opener] = cursor;
      }
    }
    for (let index = 0; index < depth; index++) {
      const token = syntax[stack[index]];
      diagnostics.push(
        diagnostic(
          DELIMITER,
          tokens[token * TOKEN + 1],
          tokens[token * TOKEN + 2],
          token,
          this.closeByOpen[tokens[token * TOKEN]],
          -1,
        ),
      );
    }
    const delimited = performance.now();
    const work: NumericWork = {
      calls: 0,
      activeRejects: 0,
      activeComparisons: 0,
      candidateAttempts: 0,
      allocatedNodes: 0,
      allocatedEdges: 0,
      peakLiveNodes: 0,
      peakLiveEdges: 0,
      peakActiveCalls: 0,
      arenaCapacityBytes: 0,
      retainedNodes: 0,
      retainedEdges: 0,
    };
    const run = new Recognition(
      this,
      tokens,
      syntax.subarray(0, syntaxLength),
      matched,
      work,
    );
    let root = -1;
    if (diagnostics.length === 0) {
      root = run.island(this.plan.rootIsland, 0, syntaxLength);
      if (root < 0 || run.nextToken !== syntaxLength) {
        const at = root >= 0 ? run.nextToken : run.farthestToken;
        const token = at < syntaxLength ? syntax[at] * TOKEN : -1;
        diagnostics.push(
          diagnostic(
            SYNTAX,
            token >= 0 ? tokens[token + 1] : 0,
            token >= 0 ? tokens[token + 2] : 0,
            at,
            run.progressIsland,
            run.progressState,
          ),
        );
        root = -1;
      }
    }
    const recognized = performance.now();
    let program: CompactFrontendProgram | null = null;
    if (root >= 0) {
      program = run.compact(root);
      const nodeCount = program.nodes.length / 8;
      const edgeCount = program.edges.length / 4;
      const start = program.nodes[2], end = program.nodes[3];
      if (options.maxNodes !== undefined && nodeCount > options.maxNodes) {
        diagnostics.push(
          diagnostic(
            NODE_CAPACITY,
            start,
            end,
            nodeCount,
            nodeCount,
            options.maxNodes,
          ),
        );
      } else if (
        options.maxEdges !== undefined && edgeCount > options.maxEdges
      ) {
        diagnostics.push(
          diagnostic(
            EDGE_CAPACITY,
            start,
            end,
            edgeCount,
            edgeCount,
            options.maxEdges,
          ),
        );
      }
    }
    const compacted = performance.now();
    diagnostics.sort((left, right) =>
      left.start - right.start ||
      left.record[0] - right.record[0] || left.subjectId - right.subjectId
    );
    work.arenaCapacityBytes = run.nodes.data.byteLength +
      run.edges.data.byteLength +
      run.active.data.byteLength + run.activeHead.byteLength;
    this.lastWork = work;
    const finished = performance.now();
    const timings = {
      uploadMs: 0,
      lexMs: lexed - began,
      delimitersMs: delimited - lexed,
      islandsMs: recognized - delimited,
      semanticsMs: compacted - recognized,
      readbackMs: finished - compacted,
      totalMs: finished - began,
      stagesMs: null,
    };
    return diagnostics.length > 0 || program === null
      ? { ok: false, program: null, diagnostics, timings }
      : { ok: true, program, diagnostics: [], timings };
  }

  private lex(source: string, diagnostics: FrontendDiagnostic[]) {
    const out = new Words(Math.ceil(source.length / 3) * TOKEN);
    const { lexer, plan } = this;
    let position = 0;
    while (position < source.length) {
      let state = lexer.startState, cursor = position;
      let acceptedEnd = -1, acceptedSpec = -1;
      while (cursor < source.length) {
        const first = source.charCodeAt(cursor);
        let point = first, width = 1;
        if (first >= 0xd800 && first <= 0xdbff && cursor + 1 < source.length) {
          const second = source.charCodeAt(cursor + 1);
          if (second >= 0xdc00 && second <= 0xdfff) {
            point = 0x10000 + ((first - 0xd800) << 10) + second - 0xdc00;
            width = 2;
          }
        }
        let target = -1;
        if (point < 128 && lexer.asciiTransitions !== null) {
          target = lexer.asciiTransitions[state * 128 + point];
        } else {
          let low = lexer.transitionRows[state],
            high = lexer.transitionRows[state + 1];
          while (low < high) {
            const middle = (low + high) >>> 1;
            const at = middle * 3;
            if (point < lexer.transitions[at]) high = middle;
            else if (point > lexer.transitions[at + 1]) low = middle + 1;
            else {
              target = lexer.transitions[at + 2];
              break;
            }
          }
        }
        if (target < 0) break;
        cursor += width;
        state = target;
        const spec = lexer.acceptSpecByState[state];
        if (spec >= 0) {
          acceptedEnd = cursor;
          acceptedSpec = spec;
        }
      }
      if (acceptedEnd < 0) {
        const first = source.charCodeAt(position),
          second = source.charCodeAt(position + 1);
        const width = first >= 0xd800 && first <= 0xdbff && second >= 0xdc00 &&
            second <= 0xdfff
          ? 2
          : 1;
        diagnostics.push(
          diagnostic(LEXICAL, position, position + width, position, first, 0),
        );
        position += width;
      } else {
        out.reserve(TOKEN);
        out.data[out.length++] = plan.terminalClassification[acceptedSpec];
        out.data[out.length++] = position;
        out.data[out.length++] = acceptedEnd;
        out.data[out.length++] = acceptedSpec;
        position = acceptedEnd;
      }
    }
    return out.finish();
  }
}

class Recognition {
  readonly nodes: Words;
  readonly edges: Words;
  readonly activeHead: Int32Array;
  readonly active: Words;
  nextToken = 0;
  farthestToken = 0;
  progressIsland: number;
  progressState = 0;
  constructor(
    readonly parser: NumericParser,
    readonly tokens: Int32Array,
    readonly syntax: Int32Array,
    readonly matches: Int32Array,
    readonly work: NumericWork,
  ) {
    this.nodes = new Words(syntax.length * NODE);
    this.edges = new Words(syntax.length * EDGE);
    this.activeHead = new Int32Array(parser.plan.islands.length).fill(-1);
    this.active = new Words(128);
    this.progressIsland = parser.plan.rootIsland;
  }

  island(id: number, start: number, limit: number): number {
    this.work.calls++;
    for (
      let head = this.activeHead[id];
      head >= 0;
      head = this.active.data[head + 2]
    ) {
      this.work.activeComparisons++;
      if (
        this.active.data[head] === start && this.active.data[head + 1] === limit
      ) {
        this.work.activeRejects++;
        return -1;
      }
    }
    const frame = this.active.length;
    this.active.reserve(3);
    this.active.data[this.active.length++] = start;
    this.active.data[this.active.length++] = limit;
    this.active.data[this.active.length++] = this.activeHead[id];
    this.activeHead[id] = frame;
    this.work.peakActiveCalls = Math.max(
      this.work.peakActiveCalls,
      this.active.length / 3,
    );
    const savedNodes = this.nodes.length, savedEdges = this.edges.length;
    let result = -1;
    try {
      const p = this.parser;
      let state = p.startState[id], cursor = start;
      let firstEdge = -1, lastEdge = -1, count = 0;
      while (cursor < limit) {
        if (cursor >= this.farthestToken) {
          this.farthestToken = cursor;
          this.progressIsland = id;
          this.progressState = state;
        }
        const stateId = p.stateBase[id] + state;
        const terminal = this.tokens[this.syntax[cursor] * TOKEN];
        const transition = (stateId * p.terminalCount + terminal) * 2;
        const terminalTarget = p.terminals[transition];
        let bestNode = -1, bestNext = -1, bestTarget = -1, bestField = -1;
        for (
          let index = p.islandRows[stateId];
          index < p.islandRows[stateId + 1];
          index++
        ) {
          const at = index * 3, nested = p.islandTransitions[at];
          const open = p.boundaryOpen[nested];
          let nestedLimit = limit;
          if (open >= 0) {
            if (
              terminal !== open || this.matches[cursor] < 0 ||
              this.matches[cursor] >= limit
            ) continue;
            nestedLimit = this.matches[cursor] + 1;
          }
          this.work.candidateAttempts++;
          const savedNodes = this.nodes.length, savedEdges = this.edges.length;
          const node = this.island(nested, cursor, nestedLimit);
          const next = this.nextToken;
          if (node < 0) continue;
          if (
            (open >= 0 && next !== nestedLimit) ||
            (bestNode >= 0 && bestNext > next)
          ) {
            this.nodes.length = savedNodes;
            this.edges.length = savedEdges;
            continue;
          }
          if (bestNode >= 0 && bestNext === next) return -1;
          bestNode = node;
          bestNext = next;
          bestTarget = p.islandTransitions[at + 1];
          bestField = p.islandTransitions[at + 2];
        }
        let field: number, category: number, target: number;
        if (terminalTarget >= 0 && (bestNode < 0 || bestNext <= cursor + 1)) {
          if (bestNode >= 0 && bestNext === cursor + 1) return -1;
          field = p.terminals[transition + 1];
          category = 0;
          target = this.syntax[cursor];
          state = terminalTarget;
          cursor++;
        } else {
          if (bestNode < 0) break;
          field = bestField;
          category = 1;
          target = bestNode;
          state = bestTarget;
          cursor = bestNext;
        }
        this.edges.reserve(EDGE);
        const edge = this.edges.length;
        this.edges.data[edge] = field;
        this.edges.data[edge + 1] = category;
        this.edges.data[edge + 2] = target;
        this.edges.data[edge + 3] = -1;
        this.edges.length += EDGE;
        this.work.allocatedEdges++;
        this.work.peakLiveEdges = Math.max(
          this.work.peakLiveEdges,
          this.edges.length / EDGE,
        );
        if (lastEdge >= 0) this.edges.data[lastEdge + 3] = edge;
        else firstEdge = edge;
        lastEdge = edge;
        count++;
      }
      if (!p.stateAccept[p.stateBase[id] + state]) return -1;
      const first = start < this.syntax.length
        ? this.tokens[this.syntax[start] * TOKEN + 1]
        : 0;
      const end = cursor > start
        ? this.tokens[this.syntax[cursor - 1] * TOKEN + 2]
        : first;
      this.nodes.reserve(NODE);
      const node = this.nodes.length / NODE;
      const at = this.nodes.length;
      this.nodes.data[at] = id;
      this.nodes.data[at + 1] = first;
      this.nodes.data[at + 2] = end;
      this.nodes.data[at + 3] = firstEdge;
      this.nodes.data[at + 4] = count;
      this.nodes.length += NODE;
      this.work.allocatedNodes++;
      this.work.peakLiveNodes = Math.max(
        this.work.peakLiveNodes,
        this.nodes.length / NODE,
      );
      this.nextToken = cursor;
      result = node;
      return result;
    } finally {
      this.activeHead[id] = this.active.data[frame + 2];
      this.active.length = frame;
      if (result < 0) {
        this.nodes.length = savedNodes;
        this.edges.length = savedEdges;
      }
    }
  }

  compact(root: number): CompactFrontendProgram {
    const map = new Int32Array(this.nodes.length / NODE).fill(-1);
    const order = new Int32Array(map.length);
    const pending = new Int32Array(map.length);
    let count = 1, depth = 0, edgeCount = 0;
    order[0] = root;
    map[root] = 0;
    edgeCount += this.nodes.data[root * NODE + 4];
    let edge = this.nodes.data[root * NODE + 3];
    while (edge >= 0 || depth > 0) {
      if (edge < 0) {
        edge = pending[--depth];
        continue;
      }
      if (this.edges.data[edge + 1] === 1) {
        pending[depth++] = this.edges.data[edge + 3];
        const node = this.edges.data[edge + 2];
        order[count] = node;
        map[node] = count++;
        edgeCount += this.nodes.data[node * NODE + 4];
        edge = this.nodes.data[node * NODE + 3];
      } else edge = this.edges.data[edge + 3];
    }
    const nodes = new Int32Array(count * 8),
      edges = new Int32Array(edgeCount * 4);
    let edgeOffset = 0;
    for (let index = 0; index < count; index++) {
      const old = order[index] * NODE, at = index * 8;
      nodes[at] = this.parser.plan.islands[this.nodes.data[old]].ruleId;
      nodes[at + 2] = this.nodes.data[old + 1];
      nodes[at + 3] = this.nodes.data[old + 2];
      nodes[at + 4] = edgeOffset;
      nodes[at + 5] = this.nodes.data[old + 4];
      nodes[at + 6] = -1;
      nodes[at + 7] = -1;
      let ordinal = 0;
      for (
        let edge = this.nodes.data[old + 3];
        edge >= 0;
        edge = this.edges.data[edge + 3]
      ) {
        const at = edgeOffset++ * 4, category = this.edges.data[edge + 1];
        edges[at] = this.edges.data[edge];
        edges[at + 1] = ordinal++;
        edges[at + 2] = category;
        edges[at + 3] = category === 1
          ? map[this.edges.data[edge + 2]]
          : this.edges.data[edge + 2];
      }
    }
    this.work.retainedNodes = count;
    this.work.retainedEdges = edgeCount;
    return {
      tokens: this.tokens,
      nodes,
      edges,
      symbols: new Int32Array(),
      types: new Int32Array([0]),
    };
  }
}
