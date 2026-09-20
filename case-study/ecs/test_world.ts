import type { TypeId } from "../../compiler/host.ts";
import type { Game } from "./game.ts";

export const noEntity = 0xffff_ffff;
export const gameIdentity = (declaration: string): TypeId => ({
  $: "TypeId",
  module_name: "main",
  declaration,
});
export const resource = (game: Game, name: string): number =>
  game.runtime.readResource(game.world, gameIdentity(name));
export const component = (game: Game, name: string, entity = 0): number => {
  const value = game.runtime.readComponent(
    game.world,
    gameIdentity(name),
    entity,
  );
  if (value === null) {
    throw new Error(`Missing test component ${name} on ${entity}`);
  }
  return value;
};
