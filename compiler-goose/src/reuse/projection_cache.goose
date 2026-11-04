namespace blot_reuse_projection_cache;
import dictionary;

struct Answer { value: u32, visits: u32, height: u16 }
struct Cache {
    answers: dictionary<u32, Answer>&, labels: dictionary<u32, Answer>&,
    source: u64 = 0, target: u64 = 0, generation: u16 = 0, physical: u64 = 0,
}
fn init(answers: dictionary<u32, Answer>&, labels: dictionary<u32, Answer>&) -> Cache {
    Cache { answers, labels }
}
fn deinit(cache: Cache&) { clearRetainingCapacity(cache); }
fn clearRetainingCapacity(cache: Cache&) {
    cache.answers.clear(); cache.labels.clear();
    cache.source = 0; cache.target = 0; cache.generation = 0; cache.physical = 0;
}
fn activate(cache: Cache&, source: u64, target: u64, generation: u16, physical: u64) -> bool {
    if source == 0 || target == 0 || cache.source != source || cache.target != target ||
        cache.generation != generation || cache.physical != physical {
        cache.answers.clear(); cache.labels.clear();
        cache.source = source; cache.target = target;
        cache.generation = generation; cache.physical = physical;
    }
    return source != 0 && target != 0 && generation != 65535 && physical != 18446744073709551615;
}
