function seed_read() {
  return Number(globalThis.Deno?.env.get("BORROW_ORACLE_SEED") ?? "0") >>> 0;
}
