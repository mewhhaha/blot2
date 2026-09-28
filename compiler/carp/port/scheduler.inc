/* Bounded, cooperative fork/join pool. Only the generated weighted batch
 * boundaries submit work. Awaiting threads help the queue, so nested forks
 * cannot exhaust the pool and deadlock. All results retain source order. */
static pthread_mutex_t bp_pool_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t bp_pool_ready = PTHREAD_COND_INITIALIZER;
static BPObj *bp_pool_head, *bp_pool_tail;
static pthread_t bp_workers[63];
static BPStatistics bp_worker_statistics[63];
static unsigned bp_worker_count;
static bool bp_pool_stopping;
static _Thread_local bool bp_is_worker;
static _Atomic uint64_t bp_tasks_submitted, bp_tasks_by_workers;

static BPObj *bp_pop_task(void) {
  BPObj *task = bp_pool_head;
  if (task) {
    bp_pool_head = task->queue_next;
    if (!bp_pool_head) bp_pool_tail = NULL;
    task->queue_next = NULL;
  }
  return task;
}

static void bp_execute_task(BPObj *task) {
  if (bp_is_worker) atomic_fetch_add_explicit(&bp_tasks_by_workers, 1, memory_order_relaxed);
  Long arguments[2] = {task->values[0], task->values[1]};
  task->values[0] = task->values[1] = (Long)BP_UNDEF;
  Long result = bp_call((int)task->tag, 2, arguments);
  task->values[2] = result;
  atomic_store_explicit(&task->flags, 1, memory_order_release);
  pthread_mutex_lock(&bp_pool_mutex);
  pthread_cond_broadcast(&bp_pool_ready);
  pthread_mutex_unlock(&bp_pool_mutex);
  bp_drop(bp_value(task)); /* release the queue's ownership */
}

static void *bp_worker_main(void *statistics) {
  bp_is_worker = true;
  for (;;) {
    pthread_mutex_lock(&bp_pool_mutex);
    while (!bp_pool_head && !bp_pool_stopping)
      pthread_cond_wait(&bp_pool_ready, &bp_pool_mutex);
    BPObj *task = bp_pop_task();
    bool stop = bp_pool_stopping;
    pthread_mutex_unlock(&bp_pool_mutex);
    if (task) bp_execute_task(task);
    else if (stop) break;
  }
  *(BPStatistics *)statistics = bp_statistics;
  return NULL;
}

static void bp_pool_start(unsigned threads) {
  bp_parallel = threads > 1;
  /* Publish all immutable caches before any worker can access them. */
  for (int i = 0; i < BP_LITERALS; i++) (void)bp_literal(i);
  for (int i = 0; i < BP_SHAPES; i++)
    if (bp_shapes[i].count == 0) (void)bp_record(i, 0, NULL);
  for (int i = 0; i < BP_FUNCTIONS; i++)
    if (bp_functions[i].captures == 0) (void)bp_function(i);
  for (unsigned i = 1; i < threads; i++) {
    int status = pthread_create(&bp_workers[bp_worker_count], NULL, bp_worker_main, &bp_worker_statistics[bp_worker_count]);
    if (status != 0) bp_fail("could not create compiler worker");
    bp_worker_count++;
  }
}

Long bp_future2(int function, Long first, Long second) {
  if (!bp_worker_count) return bp_call2(function, first, second);
  BPObj *task = bp_alloc(BP_FUTURE, 3);
  task->tag = (uint32_t)function;
  task->values[0] = first;
  task->values[1] = second;
  task->values[2] = (Long)BP_UNDEF;
  Long value = bp_value(task);
  (void)bp_keep(value); /* caller and queue each own one reference */
  atomic_fetch_add_explicit(&bp_tasks_submitted, 1, memory_order_relaxed);
  pthread_mutex_lock(&bp_pool_mutex);
  if (bp_pool_tail) bp_pool_tail->queue_next = task;
  else bp_pool_head = task;
  bp_pool_tail = task;
  pthread_cond_signal(&bp_pool_ready);
  pthread_mutex_unlock(&bp_pool_mutex);
  return value;
}

Long bp_await(Long value) {
  if (!bp_isptr(value) || bp_obj(value)->kind != BP_FUTURE) return value;
  BPObj *future = bp_obj(value);
  while (!atomic_load_explicit(&future->flags, memory_order_acquire)) {
    pthread_mutex_lock(&bp_pool_mutex);
    while (!bp_pool_head && !atomic_load_explicit(&future->flags, memory_order_acquire))
      pthread_cond_wait(&bp_pool_ready, &bp_pool_mutex);
    BPObj *task = bp_pop_task();
    pthread_mutex_unlock(&bp_pool_mutex);
    if (task) bp_execute_task(task);
  }
  Long result = bp_keep(future->values[2]);
  bp_drop(value);
  return result;
}

static void bp_pool_stop(void) {
  pthread_mutex_lock(&bp_pool_mutex);
  bp_pool_stopping = true;
  pthread_cond_broadcast(&bp_pool_ready);
  pthread_mutex_unlock(&bp_pool_mutex);
  for (unsigned i = 0; i < bp_worker_count; i++) {
    if (pthread_join(bp_workers[i], NULL)) bp_fail("failed to join compiler worker");
    /* pthread_join synchronizes the final write to each worker's statistics. */
    bp_statistics.objects_created += bp_worker_statistics[i].objects_created;
    bp_statistics.objects_destroyed += bp_worker_statistics[i].objects_destroyed;
    bp_statistics.frames_created += bp_worker_statistics[i].frames_created;
    bp_statistics.frames_destroyed += bp_worker_statistics[i].frames_destroyed;
  }
  if (bp_pool_head) bp_fail("compiler stopped with pending work");
}
