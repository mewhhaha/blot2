import { createBackgroundCompiler } from "./background_compiler.ts";
import { createCodeReload, type ReloadEvent } from "./code_reload.ts";
import { createFixedStepClock, planFixedSteps } from "./fixed_step.ts";
import { createGame, type Game, renderGame, stepGame } from "./game.ts";
import type {
  Frame,
  GameEvent,
  PickHit,
  Point,
  RenderFrame,
  Viewport,
} from "./protocol.ts";
import { readWorldSnapshot, writeWorldSnapshot } from "./snapshot.ts";

export async function createGameRuntime(options: {
  readonly sourcePath: string;
  readonly compilerExecutable?: string;
  readonly viewport: () => Viewport;
  readonly pick: (frame: RenderFrame, point: Point) => PickHit | undefined;
  readonly validate: (frame: RenderFrame) => void;
  readonly ready?: (frame: RenderFrame) => boolean;
  readonly prepare?: (frame: RenderFrame) => Promise<void>;
  readonly report: (event: ReloadEvent) => void;
}) {
  const compiler = createBackgroundCompiler({
    executable: options.compilerExecutable,
  });
  let game: Game;
  let lastFrame: RenderFrame;
  try {
    const source = await Deno.readTextFile(options.sourcePath);
    const compiled = await compiler.compile(source, options.sourcePath);
    game = await createGame(compiled.artifact, options.viewport());
    lastFrame = renderGame(game, options.viewport());
    options.validate(lastFrame);
    await options.prepare?.(lastFrame);
    if (options.ready && !options.ready(lastFrame)) {
      throw new Error("Initial guest render assets are unavailable");
    }
  } catch (error) {
    await compiler.close();
    throw error;
  }
  let previous = game;
  let clock = createFixedStepClock();
  let rebase = false;
  let closed = false;
  let closing: Promise<void> | undefined;
  const pending: GameEvent[] = [];
  const reload = createCodeReload({
    current: () => game,
    compile: compiler.compile,
    report: options.report,
  });
  function requireOpen() {
    if (closed) throw new Error("Game runtime is closed");
  }

  return {
    get game(): Game {
      return game;
    },
    frame(frame: Frame): RenderFrame {
      requireOpen();
      const plan = planFixedSteps(clock, frame.timestamp, { rebase });
      pending.push(...frame.events);
      const events = pending.slice();
      const advance = (initial: Game) => {
        let current = initial;
        let before = initial.runtime === game.runtime && !plan.rebaseReason
          ? previous
          : initial;
        for (let step = 0; step < plan.steps; step++) {
          before = current;
          current = stepGame(current, {
            dt: plan.stepSeconds,
            viewport: frame.viewport,
            events: step === 0 ? events : [],
            pick: (snapshot, point) =>
              options.pick(renderGame(snapshot, frame.viewport), point),
          });
        }
        const rendered = renderGame(current, frame.viewport, {
          previous: before,
          alpha: plan.alpha,
        });
        options.validate(rendered);
        return {
          current,
          before,
          rendered,
          ready: options.ready?.(rendered) ?? true,
        };
      };
      let advanced: ReturnType<typeof advance> | undefined;
      // Wait for a real simulation step so candidate code is exercised before
      // publication. Input is only removed after either candidate or old code succeeds.
      const published = plan.steps > 0
        ? reload.publish(game, (candidate) => {
          advanced = advance({ ...candidate, commands: game.commands });
          if (!advanced.ready) return undefined;
          advanced.rendered = renderGame(advanced.current, frame.viewport);
          options.validate(advanced.rendered);
          if (
            options.ready && !options.ready(advanced.rendered)
          ) return undefined;
          return advanced.current;
        })
        : undefined;
      if (!published) advanced = advance(game);
      if (!advanced) {
        throw new Error("Frame transition did not produce a result");
      }
      if (!advanced.ready) {
        rebase = true;
        return { ...lastFrame, commands: [] };
      }
      game = { ...advanced.current, commands: [] };
      previous = advanced.before;
      clock = plan.clock;
      rebase = false;
      if (plan.steps > 0) pending.splice(0, events.length);
      lastFrame = advanced.rendered;
      if (published) {
        // The new instance has no interpolation history from its predecessor.
        previous = game;
        clock = planFixedSteps(clock, frame.timestamp, { rebase: true }).clock;
        return advanced.rendered;
      }
      return advanced.rendered;
    },
    watch() {
      requireOpen();
      return reload.watch(options.sourcePath);
    },
    refresh() {
      requireOpen();
      return reload.refresh(options.sourcePath);
    },
    async idle() {
      await reload.idle();
    },
    async save(path: string) {
      requireOpen();
      // Immutable ownership makes saving safe while simulation keeps advancing.
      await writeWorldSnapshot(path, game);
    },
    async load(path: string) {
      requireOpen();
      const owner = game;
      const world = await readWorldSnapshot(
        path,
        owner.artifact,
        owner.runtime,
      );
      requireOpen();
      if (game.runtime !== owner.runtime) {
        throw new Error("Code changed while loading the save; retry load");
      }
      const restored = { ...game, world };
      const viewport = options.viewport();
      const probe = stepGame(restored, {
        dt: 0,
        viewport,
        events: [{ tag: "FocusLost" }],
        pick: (snapshot, point) =>
          options.pick(renderGame(snapshot, viewport), point),
      });
      const rendered = renderGame(probe, viewport);
      options.validate(rendered);
      await options.prepare?.(rendered);
      requireOpen();
      if (game.runtime !== owner.runtime) {
        throw new Error("Code changed while validating the save; retry load");
      }
      if (options.ready && !options.ready(rendered)) {
        throw new Error("Saved world render assets are unavailable");
      }
      game = restored;
      previous = restored;
      rebase = true;
      // Physical keys/pointer buttons from a saved frame may no longer be held.
      pending.unshift({ tag: "FocusLost" });
    },
    close(): Promise<void> {
      if (closing) return closing;
      closed = true;
      closing = (async () => {
        // Stop reporting edits before cancellation rejects pending compilations.
        // Both owners must finish even if either close fails.
        const stopped = await Promise.allSettled([
          reload.close(),
          compiler.close(),
        ]);
        pending.length = 0;
        const failures = stopped.flatMap((result) =>
          result.status === "rejected" ? [result.reason] : []
        );
        if (failures.length === 1) throw failures[0];
        if (failures.length > 1) {
          throw new AggregateError(failures, "Game runtime failed to close");
        }
      })();
      return closing;
    },
  };
}
