#ifdef CID_INPUT
static Term input_run(Env e, Term* fields, IoWork* work) {
  const char* variant = getenv("BEND_REPRO_CASE");
  if (!variant || strcmp(variant, "scalar") == 0) return 0;
  if (strcmp(variant, "pair") == 0) return 1;
  err_fail("BEND_REPRO_CASE must be scalar or pair");
  return 0;
}

static void __attribute__((constructor)) input_use(void) {
  io_eff(CID_INPUT, input_run, 0);
}
#endif

#ifdef CID_OBSERVE
static Term observe_run(Env e, Term* fields, IoWork* work) {
  // The result list has been consumed; the joined pool cannot change the lists.
  uint64_t free_words = 0;
  for (unsigned cls = 0; cls < NCLS_ALL; cls++) {
    uint64_t generation = (uint64_t)KEEP(cls) << cls;
    free_words += (uint64_t)bank_at(e.mem, cls)->rd * generation;
    for (unsigned lane = 0; lane <= pool_size; lane++) {
      free_words += ALC[lane][ALC_WORDS + cls];
      if (ALC[lane][2 * ALC_WORDS + cls]) free_words += generation;
    }
  }
  uint64_t extent = (uint64_t)a32_load(a32_at(e.mem, H_BUMP)) * PAGE_LEN;
  if (free_words > extent) err_fail("free words exceed heap extent");
  printf("count=%llu in_use_bytes=%llu\n", (unsigned long long)fields[0],
    (unsigned long long)(extent - free_words) * 8);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) observe_use(void) {
  io_eff(CID_OBSERVE, observe_run, 0);
}
#endif
