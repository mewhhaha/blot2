import { deepStrictEqual as equal, ok } from "node:assert/strict";

// Source contracts for a non-executable specimen, not compiler/gameplay tests.
const root = new URL("../case-study/ecs/", import.meta.url);
const sources = new Map<string, string>();
sources.set("game.blot", await Deno.readTextFile(new URL("game.blot", root)));
for await (const entry of Deno.readDir(new URL("engine/", root))) {
  if (entry.isFile && entry.name.endsWith(".blot")) {
    const path = `engine/${entry.name}`;
    sources.set(path, await Deno.readTextFile(new URL(path, root)));
  }
}
function source(path: string): string {
  const text = sources.get(path);
  ok(text !== undefined, `Missing module ${path}`);
  return text;
}
function body(path: string, name: string): string {
  const text = source(path);
  const start = text.search(new RegExp(`^(?:export )?fn ${name}\\b`, "m"));
  ok(start >= 0, `Missing function ${path}:${name}`);
  const next = text.slice(start + 1).search(
    /^(?:export )?(?:fn|const|type|data) |^#\[/m,
  );
  return next < 0 ? text.slice(start) : text.slice(start, start + 1 + next);
}
function matrix(text: string, prefix: string): string[] {
  const start = text.indexOf(prefix);
  ok(start >= 0, `Missing matrix ${prefix}`);
  const values = text.slice(start + prefix.length).split("]", 1)[0];
  return values.split(",").map((value) => value.trim()).filter(Boolean);
}

Deno.test("source module graph resolves local imports and keeps foundations explicit", () => {
  const foundations = new Set([
    "engine/ecs",
    "engine/render",
    "engine/assets",
    "engine/snapshot",
    "std/bytes",
    "std/host",
  ]);
  const edges = new Map<string, string[]>();
  for (const [path, text] of sources) {
    const dependencies: string[] = [];
    for (const match of text.matchAll(/^import .* from "([^"]+)"/gm)) {
      const specifier = match[1];
      if (!specifier.startsWith(".")) {
        ok(foundations.has(specifier), `Undocumented foundation ${specifier}`);
        continue;
      }
      const target = new URL(`${specifier}.blot`, new URL(path, root));
      const relative = target.pathname.slice(root.pathname.length);
      ok(sources.has(relative), `${path} imports missing module ${relative}`);
      dependencies.push(relative);
    }
    edges.set(path, dependencies);
  }
  const reached = new Set<string>();
  function visit(path: string, ancestors: string[]) {
    ok(
      !ancestors.includes(path),
      `Import cycle: ${[...ancestors, path].join(" -> ")}`,
    );
    reached.add(path);
    for (const dependency of edges.get(path) ?? []) {
      visit(dependency, [...ancestors, path]);
    }
  }
  visit("game.blot", []);
  equal([...reached].sort(), [...sources.keys()].sort());
});

Deno.test("game and engine modules reserve intrinsics for compiler primitives", () => {
  const primitives = new Set<string>();
  for (const [path, text] of sources) {
    for (const primitive of text.match(/@[a-z_][\w.]*/g) ?? []) {
      primitives.add(primitive);
    }
    ok(!/\bcase[^\n]*:/.test(text), `${path}: use case ... of`);
    ok(!/Result\.map_err\b/.test(text), `${path}: prelude spells map_error`);
  }
  equal([...primitives], ["@panic"]);
  ok(!source("game.blot").includes("@"));
});

Deno.test("game composes an application from plugins, resources and ordered systems", () => {
  const game = source("game.blot");
  equal([...game.matchAll(/^export fn (\w+)/gm)].map((match) => match[1]), [
    "main",
  ]);
  ok(body("game.blot", "main").includes("(io: Io) => app.bind sandbox io"));
  ok(game.includes('let application = app.new "Blot — PLAY"'));
  ok(game.includes("application := input.plugin self"));
  ok(game.includes("application := camera.plugin"));
  ok(game.includes("application := app.insert_resource (Editor {"));
  for (
    const [stage, system] of [
      ["Start", "seed_scene"],
      ["Event", "edit_scene"],
      ["Update", "animate"],
      ["Render", "draw_scene"],
      ["Render", "boxes.draw_mesh"],
      ["Render", "draw_selection"],
      ["Render", "describe_mode"],
    ]
  ) {
    ok(game.includes(`app.add_system ${stage} ${system} self`));
  }
  ok(game.indexOf("input.plugin") < game.indexOf("camera.plugin"));
  ok(game.indexOf("camera.plugin") < game.indexOf("app.add_system Event"));
  ok(game.includes("return app.build application"));
  ok(
    !/ecs\.(?:build|scope|checkpoint)|snapshot\.|\.submit|set_title/.test(game),
  );
  ok(body("engine/app.blot", "insert_resource").includes("ecs.resource value"));
  const registration = body("engine/app.blot", "add_system");
  ok(registration.includes("(const system)"));
  ok(registration.includes("ecs.system (stage, system)"));
});

Deno.test("lifecycle scopes successor worlds and narrows captured host capabilities", () => {
  const app = "engine/app.blot";
  const bind = body(app, "bind");
  ok(bind.includes("create: create_world simulation"));
  ok(bind.includes("event: apply_event simulation io.files"));
  ok(bind.includes("update: advance_world simulation"));
  ok(bind.includes("render: render_frame simulation io.window io.render"));
  ok(body(app, "create_world").includes("do ecs.scope (simulation.create ())"));
  ok(body(app, "create_world").includes("return ecs.checkpoint world"));
  ok(
    body(app, "advance_world").includes("do ecs.scope (ecs.checkpoint world)"),
  );
  for (
    const [name, stage] of [
      ["create_world", "Start"],
      ["apply_event", "Event"],
      ["advance_world", "Update"],
      ["render_frame", "Render"],
    ]
  ) {
    ok(body(app, name).includes(`simulation.run ${stage}`));
  }
  const render = body(app, "render_frame");
  ok(render.includes("let (_, (packet, title)) = do ecs.scope world"));
  ok(
    render.indexOf("render.collect") < render.indexOf("renderer.submit packet"),
  );
  equal([...source(app).matchAll(/renderer\.submit/g)].length, 1);
  const platform = source("engine/platform.blot");
  equal([...platform.matchAll(/! \{Foreign\}/g)].length, 6);
  ok(platform.includes("read: Unit -> Result Bytes IoError"));
  ok(platform.includes("write: Bytes -> Result Unit IoError"));
});

Deno.test("input edges, selection and edit commands use typed state and flat matches", () => {
  const receive = body("engine/input.blot", "receive");
  ok(receive.includes("case event.kind, was_held of"));
  ok(
    receive.includes("1, False => (KeyPressed code, [...previous.held, code])"),
  );
  ok(
    receive.includes("2, _ => (KeyReleased code, without previous.held code)"),
  );
  ok(receive.includes("3, _ => (FocusLost, [])"));
  ok(receive.includes("_, _ => (Ignored, previous.held)"));
  ok(body("engine/input.blot", "key").includes("return code - 32"));
  const game = source("game.blot");
  ok(game.includes("selected: Maybe ecs.EntityId, grab_offset: Maybe Vec2"));
  ok(
    body("game.blot", "apply_action").includes(
      "case action, editor.mode, editor.selected, ground_point of",
    ),
  );
  ok(
    body("game.blot", "select").includes(
      "case controls.picked, ground_point of",
    ),
  );
  ok(
    body("game.blot", "draw_selection").includes(
      "case editor.mode, editor.selected of",
    ),
  );
  ok(
    !/no_entity|Held[A-Z]|EditCommand|SpawnRequested|Position[XYZ]|Scale[XYZ]/
      .test(game),
  );
  ok(
    body("engine/camera.blot", "receive").includes(
      "FocusLost, _ => (camera, False)",
    ),
  );
});

Deno.test("camera and model matrices preserve column-major frame layouts", () => {
  const camera = body("engine/camera.blot", "project");
  equal(matrix(camera, "render.view ["), [
    "right_x",
    "up_x",
    "back_x",
    "0.0",
    "0.0",
    "up_y",
    "back_y",
    "0.0",
    "right_z",
    "up_z",
    "back_z",
    "0.0",
    "0.0",
    "0.0",
    "F32.neg distance",
    "1.0",
  ]);
  equal(matrix(camera, "render.projection ["), [
    "F32.div (F32.mul tangent height) width",
    "0.0",
    "0.0",
    "0.0",
    "0.0",
    "tangent",
    "0.0",
    "0.0",
    "0.0",
    "0.0",
    "depth",
    "-1.0",
    "0.0",
    "0.0",
    "translation",
    "0.0",
  ]);
  equal(matrix(body("engine/spatial.blot", "matrix"), "return ["), [
    "F32.mul cosine transform.scale.x",
    "0.0",
    "F32.neg (F32.mul sine transform.scale.x)",
    "0.0",
    "0.0",
    "transform.scale.y",
    "0.0",
    "0.0",
    "F32.mul sine transform.scale.z",
    "0.0",
    "F32.mul cosine transform.scale.z",
    "0.0",
    "transform.position.x",
    "transform.position.y",
    "transform.position.z",
    "1.0",
  ]);
  const outline = body("engine/boxes.blot", "outline");
  ok(outline.includes("for axis in [X, Y, Z]:"));
  ok(
    outline.includes(
      "for (first, second) in [(-1.0, -1.0), (-1.0, 1.0), (1.0, -1.0), (1.0, 1.0)]:",
    ),
  );
  equal([...outline.matchAll(/\bcase\b/g)].length, 1);
  ok(outline.includes("position: spatial.offset transform local"));
  ok(
    body("game.blot", "draw_scene").includes(
      "scale: Vec3 { x: 5.0, y: 0.1, z: 4.0 }",
    ),
  );
});

Deno.test("save/load stays in source, clears requests and checkpoints restored worlds", () => {
  const event = body("engine/app.blot", "apply_event");
  ok(event.includes("snapshot.encode (simulation.schema, next_world)"));
  ok(event.includes("files.write bytes"));
  ok(event.includes("files.read ()"));
  ok(event.includes("snapshot.decode (simulation.schema, bytes)"));
  ok(event.includes("Result.map_error InvalidSnapshot"));
  ok(event.includes("Result.map ecs.checkpoint"));
  ok(event.indexOf("ecs.set Idle") < event.indexOf("files.write"));
  ok(
    event.indexOf("ecs.set (PendingInput Nothing)") <
      event.indexOf("files.write"),
  );
  ok(!/files\.(read|write)\s+(?:world|next_world)/.test(event));
});
