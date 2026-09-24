// Linux-only native child CPU sampling for diagnostic benchmark scripts.
import { fileURLToPath } from "node:url";

export const nativeCpuHz = Deno.build.os === "linux"
  ? Number(
    new TextDecoder().decode(
      (await new Deno.Command("getconf", {
        args: ["CLK_TCK"],
      }).output()).stdout,
    ).trim(),
  )
  : undefined;
if (
  nativeCpuHz !== undefined &&
  (!Number.isInteger(nativeCpuHz) || nativeCpuHz <= 0)
) {
  throw new Error(`Invalid Linux CLK_TCK: ${nativeCpuHz}`);
}

export async function ownedNativeChildren(): Promise<Set<number>> {
  const found = new Set<number>();
  if (Deno.build.os !== "linux") return found;
  for await (const task of Deno.readDir("/proc/self/task")) {
    if (!task.isDirectory) continue;
    let value: string;
    try {
      value = await Deno.readTextFile(`/proc/self/task/${task.name}/children`);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) continue;
      throw error;
    }
    for (const part of value.trim().split(/\s+/).filter(Boolean)) {
      found.add(Number(part));
    }
  }
  return found;
}

export async function matchingNativeChild(
  executable: URL,
  excluded: Set<number>,
): Promise<number | undefined> {
  if (Deno.build.os !== "linux") return undefined;
  const path = await Deno.realPath(fileURLToPath(executable));
  const matches: number[] = [];
  for (const pid of await ownedNativeChildren()) {
    if (excluded.has(pid)) continue;
    try {
      if (await Deno.readLink(`/proc/${pid}/exe`) === path) matches.push(pid);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) continue;
      throw error;
    }
  }
  if (matches.length !== 1) {
    throw new Error(`Expected one owned ${path} child, got ${matches}`);
  }
  return matches[0];
}

export type NativeCpuSample = { ticks: bigint; policy: number; nice: number };

export async function nativeCpuSample(
  pid: number | undefined,
): Promise<NativeCpuSample | undefined> {
  if (pid === undefined) return undefined;
  const stat = await Deno.readTextFile(`/proc/${pid}/stat`);
  // The parenthesized comm field may contain spaces or parentheses. Fields
  // after its last ')' begin at field 3 (state).
  const fields = stat.slice(stat.lastIndexOf(")") + 2).trim().split(/\s+/);
  return {
    ticks: BigInt(fields[11]) + BigInt(fields[12]), // utime + stime, fields 14–15
    nice: Number(fields[16]), // field 19
    policy: Number(fields[38]), // field 41; 5 is SCHED_IDLE on Linux
  };
}

export function nativeCpuMilliseconds(
  before: NativeCpuSample | undefined,
  after: NativeCpuSample | undefined,
): number | null {
  return before && after && nativeCpuHz !== undefined
    ? Number(after.ticks - before.ticks) * 1000 / nativeCpuHz
    : null;
}

export function nativeScheduler(sample: NativeCpuSample | undefined) {
  return sample ? { policy: sample.policy, nice: sample.nice } : null;
}
