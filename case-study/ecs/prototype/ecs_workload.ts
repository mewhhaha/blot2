// Archived compiler-coupled prototype; not part of the current compiler.
// Independent component pairs exercise inferred storage, helper effects, queries,
// scheduling and Wasm linking as the number of systems grows.
export function ecsWorkload(systemCount: number): string {
  if (
    !Number.isSafeInteger(systemCount) || systemCount < 1 || systemCount > 256
  ) {
    throw new RangeError("ECS workload requires 1..256 systems");
  }
  const declarations = ["#[resource]\ndata DeltaTime = DeltaTime U32"];
  for (let index = 0; index < systemCount; index++) {
    declarations.push(`
#[component]
data Position${index} = Position${index} U32
#[component]
data Velocity${index} = Velocity${index} U32
const read_position_${index} = fn () => @ecs.get Position${index}
const move_${index} = fn () => do:
  use position <- read_position_${index} ()
  use velocity <- @ecs.get Velocity${index}
  use time <- @ecs.get DeltaTime
  let Position${index} current = position
  let Velocity${index} speed = velocity
  let DeltaTime seconds = time
  use @ecs.set (Position${index} (current + speed * seconds))
  return ()`);
  }
  return declarations.join("\n") + "\n";
}
