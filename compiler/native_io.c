#define BLOT_NATIVE_MAX_WORDS 16777216u

static void blot_native_read_exact(uint8_t* bytes, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    ssize_t count = read(STDIN_FILENO, bytes + offset, length - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count < 0) err_fail("native protocol: stdin read failed");
    if (count == 0) err_fail("native protocol: truncated frame");
    offset += (size_t)count;
  }
}

static void blot_native_write_exact(const uint8_t* bytes, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    ssize_t count = write(STDOUT_FILENO, bytes + offset, length - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) err_fail("native protocol: stdout write failed");
    offset += (size_t)count;
  }
}

static uint32_t blot_native_word(const uint8_t* bytes) {
  return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 |
    (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}

static void blot_native_store(uint8_t* bytes, uint32_t word) {
  bytes[0] = (uint8_t)word;
  bytes[1] = (uint8_t)(word >> 8);
  bytes[2] = (uint8_t)(word >> 16);
  bytes[3] = (uint8_t)(word >> 24);
}

#ifdef CID_RECEIVE
// Bend 2.0.21 stores task queues in slot-major planes. Leaving their drained
// positions advancing between requests gradually faults in every slot plane.
// This effect runs after corpus_eval has joined the CPU pool. Clear both the
// used slots and their cursors: resetting cursors alone would let a consumer
// mistake an old slot's publication bit for a newly published task.
static void blot_native_reset_queues(Corpus heap) {
  if (io_gpu || pool_size == 1) return;
  uint32_t slots = 0;
  for (uint32_t lane = 0; lane < LANES; lane += 1) {
    uint32_t put = a32_load(ring_put(heap, lane));
    if (a32_load(ring_get(heap, lane)) != put) {
      err_fail("native protocol: task queue is not drained at request boundary");
    }
    if (put > slots) slots = put;
  }
  if (slots > RING_LEN) slots = RING_LEN;
  memset(heap + RING_OFF, 0, (size_t)slots * LANES * sizeof(u64));
  memset(ring_word(heap, 0, RING_LEN), 0, 2 * LANES * sizeof(u64));
}

static Term blot_native_receive_run(Env e, Term* fields, IoWork* work) {
  blot_native_reset_queues(e.mem);
  uint8_t prefix[4];
  ssize_t count;
  do {
    count = read(STDIN_FILENO, prefix, 1);
  } while (count < 0 && errno == EINTR);
  if (count < 0) err_fail("native protocol: stdin read failed");
  if (count == 0) return term_pak(CID_NONE, 0);
  blot_native_read_exact(prefix + 1, 3);
  uint32_t length = blot_native_word(prefix);
  if (length > BLOT_NATIVE_MAX_WORDS) {
    err_fail("native protocol: frame exceeds 16777216 words");
  }
  size_t byte_length = (size_t)length * 4;
  uint8_t* bytes = io_mem(malloc(byte_length == 0 ? 1 : byte_length));
  blot_native_read_exact(bytes, byte_length);
  uint32_t depth = 0;
  while ((1u << depth) < length) depth += 1;
  Term zero = 0;
  Term words = blk_new(e, false, depth, 0, 1, &zero);
  if (err_seen(e.mem)) err_fail("native protocol: request buffer allocation failed");
  for (uint32_t index = 0; index < length; index += 1) {
    blk_write(e.mem, false, term_loc(words), index,
      blot_native_word(bytes + (size_t)index * 4));
  }
  free(bytes);
  return io_box(e, CID_SOME, io_node(e, CID_NATIVE_IO_FRAME, words, length));
}

static void __attribute__((constructor)) blot_native_receive_use(void) {
  io_eff(CID_RECEIVE, blot_native_receive_run, 0);
}
#endif

#ifdef CID_SEND
static Term blot_native_send_run(Env e, Term* fields, IoWork* work) {
  uint32_t length = (uint32_t)fields[0];
  if (length > BLOT_NATIVE_MAX_WORDS) {
    err_fail("native protocol: response exceeds 16777216 words");
  }
  size_t byte_length = (size_t)length * 4;
  uint8_t* bytes = io_mem(malloc(byte_length == 0 ? 1 : byte_length));
  size_t offset = 0;
  Term words = fields[1];
  while (term_aux(words) == CID_CON) {
    if (byte_length - offset < 4) {
      err_fail("native protocol: response header exceeds its declared length");
    }
    Term cell[2];
    spare_free(e, cls_fit(2), ctr_take(e, words, 2, cell));
    blot_native_store(bytes + offset, (uint32_t)cell[0]);
    offset += 4;
    words = cell[1];
  }
  if (term_aux(words) != CID_NIL) {
    err_fail("native protocol: response is not a word list");
  }
  Term blocks = fields[2];
  while (term_aux(blocks) == CID_CON) {
    Term cell[2];
    spare_free(e, cls_fit(2), ctr_take(e, blocks, 2, cell));
    blocks = cell[1];
    if (term_aux(cell[0]) != CID_NATIVE_OUTPUT_BLOCK) {
      err_fail("native protocol: response contains an invalid byte block");
    }
    Term block[2];
    spare_free(e, cls_fit(2), ctr_take(e, cell[0], 2, block));
    uint64_t remaining = block[0];
    if (remaining > byte_length - offset) {
      err_fail("native protocol: byte block exceeds the declared response length");
    }
    words = block[1];
    while (term_aux(words) == CID_CON) {
      spare_free(e, cls_fit(2), ctr_take(e, words, 2, cell));
      words = cell[1];
      uint32_t word = (uint32_t)cell[0];
      if (remaining == 0) {
        err_fail("native protocol: byte block contains extra words");
      }
      if (remaining >= 4) {
        blot_native_store(bytes + offset, word);
        offset += 4;
        remaining -= 4;
      } else {
        // Intermediate block padding is not part of the byte stream.
        while (remaining > 0) {
          bytes[offset++] = (uint8_t)word;
          word >>= 8;
          remaining -= 1;
        }
        if (word != 0) err_fail("native protocol: nonzero byte block padding");
      }
    }
    if (term_aux(words) != CID_NIL || remaining != 0) {
      err_fail("native protocol: truncated byte block");
    }
  }
  if (term_aux(blocks) != CID_NIL || byte_length - offset >= 4) {
    err_fail("native protocol: response length differs from its chunks");
  }
  memset(bytes + offset, 0, byte_length - offset);
  uint8_t prefix[4];
  blot_native_store(prefix, length);
  blot_native_write_exact(prefix, 4);
  blot_native_write_exact(bytes, (size_t)length * 4);
  free(bytes);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) blot_native_send_use(void) {
  io_eff(CID_SEND, blot_native_send_run, 0);
}
#endif
