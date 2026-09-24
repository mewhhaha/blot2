Term seed_read_run(Env e, Term* f, IoWork* w) {
  const char *source = getenv("BORROW_ORACLE_SEED");
  return (Term)(uint32_t)(source ? strtoul(source, NULL, 10) : 0);
}

static void __attribute__((constructor)) seed_read_use(void) {
  io_eff(CID_SEED_READ, seed_read_run, 0);
}
