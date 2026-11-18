// Three Wasm layouts of the same sequence of Gdev Intent values. Capture and
// iteration live outside the timed kernel. Only concat writes the second list.
#include <stddef.h>
#include <stdint.h>

enum { capacity = 65536, fixed_stride = 20 };
static uint8_t source[capacity * fixed_stride], tags[capacity],
    payload[capacity * 16];
static uint8_t joined[capacity * fixed_stride], joined_payload[capacity * 16];
static uint32_t count, used, middle, split_payload;
static const uint8_t words[] = {0, 4, 1, 1};

static uint32_t load(const uint8_t *p) {
  uint32_t v;
  __builtin_memcpy(&v, p, sizeof v);
  return v;
}
static void store(uint8_t *p, uint32_t v) { __builtin_memcpy(p, &v, sizeof v); }

void reset(void) { count = used = middle = split_payload = 0; }
void split(void) {
  middle = count;
  split_payload = used;
}
void append(unsigned layout, unsigned tag, unsigned a, unsigned b, unsigned c,
            unsigned d) {
  if (count >= capacity || tag >= 4)
    __builtin_trap();
  uint32_t fields[] = {a, b, c, d};
  uint8_t *dest;
  if (layout == 0) {
    dest = source + count * fixed_stride;
    store(dest, tag);
    dest += 4;
  } else if (layout == 1) {
    source[used++] = tag;
    dest = source + used;
  } else {
    tags[count] = tag;
    dest = payload + used;
  }
  for (unsigned i = 0; i < words[tag]; ++i)
    store(dest + 4 * i, fields[i]);
  if (layout != 0)
    used += 4 * words[tag];
  ++count;
}
unsigned bytes(unsigned layout) {
  if (layout == 0)
    return count * fixed_stride;
  if (layout == 1)
    return used;
  return count + used;
}
static unsigned traverse(unsigned layout, unsigned all, unsigned copied,
                         unsigned ordered) {
  const uint8_t *p = source, *t = tags, *v = payload;
  if (copied) {
    p = joined;
    t = joined;
    v = joined_payload;
  }
  uint32_t sum = 0;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t tag;
    const uint8_t *fields;
    if (layout == 0) {
      tag = load(p);
      fields = p + 4;
      p += fixed_stride;
    } else if (layout == 1) {
      tag = *p++;
      fields = p;
      p += words[tag] * 4;
    } else {
      tag = t[i];
      fields = v;
      if (all)
        v += words[tag] * 4;
    }
    if (ordered)
      sum *= 16777619u;
    sum += tag;
    if (all) {
      for (unsigned j = 0; j < words[tag]; ++j) {
        if (ordered)
          sum *= 16777619u;
        sum += load(fields + 4 * j);
      }
    }
  }
  return sum;
}
unsigned scan(unsigned layout, unsigned all, unsigned copied) {
  return traverse(layout, all, copied, 0);
}
unsigned joined_hash(unsigned layout) { return traverse(layout, 1, 1, 1); }
// Two independently addressable ranges, copied in reverse order to make an
// incorrect join observable. Verify endpoints as well as the complete data.
static void join(uint8_t *out, const uint8_t *src, unsigned cut, unsigned n) {
  __builtin_memcpy(out, src + cut, n - cut);
  __builtin_memcpy(out + n - cut, src, cut);
}
unsigned concat(unsigned layout) {
  if (layout == 0)
    join(joined, source, middle * fixed_stride, count * fixed_stride);
  else if (layout == 1)
    join(joined, source, split_payload, used);
  else {
    join(joined, tags, middle, count);
    join(joined_payload, payload, split_payload, used);
  }
  return joined[0];
}
