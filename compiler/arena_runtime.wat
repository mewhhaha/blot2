;; Private nonmoving arena runtime. Regenerate arena_runtime.bend with
;; `deno run -A scripts/generate_arena_runtime.ts` after changing this file.
;; Dynamic allocations have a 16-byte header: block size, payload size,
;; mark flag, and free/work-list link. The first 164 memory bytes are reserved.
;; Dynamic blocks begin at or above 64 KiB to avoid common low-ID false roots.
;; Word 12 caches the allocation-start bitmap; bump allocation invalidates it.
;; Word 16 links static memo cells; word 20 selects persistent-root collection.
;; All user pointers address the payload. Scalar words are never rewritten.
(module
  (type $unary (func (param i32) (result i32)))
  (type $entry (func (param i32 i32 i32) (result i32)))
  (memory 1 65536)
  (global $cursor (mut i32) (i32.const 256))
  (func $allocate (type $unary) (param $bytes i32) (result i32)
    (local $class i32) (local $size i32) (local $head i32)
    (local $end i32) (local $pages i32) (local $bin i32)
    ;; The public zero allocation observes the arena cursor without allocating.
    (if (i32.eqz (local.get $bytes)) (then (return (global.get $cursor))))
    ;; Small blocks use power-of-two bins. Oversized blocks retain the full
    ;; Wasm32 allocation range and use the final bin with their exact size.
    (if (i32.gt_u (local.get $bytes) (i32.const 4294967276)) (then unreachable))
    (if (i32.gt_u (local.get $bytes) (i32.const 2147483632))
      (then
        (local.set $class (i32.const 32))
        (local.set $size (i32.and (i32.add (local.get $bytes) (i32.const 19)) (i32.const -4))))
      (else
        (local.set $class
          (i32.sub (i32.const 32)
            (i32.clz (i32.add (local.get $bytes) (i32.const 15)))))
        (local.set $size (i32.shl (i32.const 1) (local.get $class)))))
    (local.set $bin (i32.add (i32.const 32) (i32.shl (local.get $class) (i32.const 2))))
    (local.set $head (i32.load (local.get $bin)))
    ;; At most one oversized block fits in Wasm32. A smaller free block
    ;; cannot satisfy this request; leave it available for later requests.
    (if (i32.and (i32.ne (local.get $head) (i32.const 0)) (i32.eq (local.get $class) (i32.const 32)))
      (then (if (i32.lt_u (i32.load (local.get $head)) (local.get $size))
        (then (local.set $head (i32.const 0))))))
    (if (local.get $head)
      (then (i32.store (local.get $bin) (i32.load offset=12 (local.get $head))))
      (else
        (local.set $head (global.get $cursor))
        (if (i32.lt_u (local.get $head) (i32.const 65536))
          (then (local.set $head (i32.const 65536))))
        (local.set $end (i32.add (local.get $head) (local.get $size)))
        (if (i32.lt_u (local.get $end) (local.get $head)) (then unreachable))
        (local.set $pages
          (i32.add (i32.shr_u (i32.sub (local.get $end) (i32.const 1)) (i32.const 16)) (i32.const 1)))
        (if (i32.gt_u (local.get $pages) (memory.size))
          (then
            (if (i32.eq (memory.grow (i32.sub (local.get $pages) (memory.size))) (i32.const -1))
              (then unreachable))))
        (if (i32.eqz (i32.load (i32.const 4)))
          (then (i32.store (i32.const 4) (local.get $head))))
        (i32.store (i32.const 12) (i32.const 0))
        (global.set $cursor (local.get $end))
        (i32.store (local.get $head) (local.get $size))))
    (i32.store offset=4 (local.get $head) (local.get $bytes))
    (i32.store offset=8 (local.get $head) (i32.const 0))
    (i32.store offset=12 (local.get $head) (i32.const 0))
    (i32.add (local.get $head) (i32.const 16)))
  ;; Conservative recognition accepts only exact starts of allocated payloads.
  ;; The allocation-start bitmap is scratch beyond the arena cursor.
  (func $mark (type $entry) (param $value i32) (param $index i32) (param $start i32) (result i32)
    (local $head i32)
    (if (i32.and (local.get $value) (i32.const 3)) (then (return (i32.const 0))))
    (if (i32.or (i32.lt_u (local.get $value) (i32.add (local.get $start) (i32.const 16)))
                (i32.ge_u (local.get $value) (global.get $cursor)))
      (then (return (i32.const 0))))
    (local.set $head (i32.sub (local.get $value) (i32.const 16)))
    (if (i32.eqz (i32.and
          (i32.load (i32.add (local.get $index) (i32.shl (i32.shr_u (local.get $head) (i32.const 7)) (i32.const 2))))
          (i32.shl (i32.const 1) (i32.and (i32.shr_u (local.get $head) (i32.const 2)) (i32.const 31)))))
      (then (return (i32.const 0))))
    (if (i32.and (i32.ne (i32.load offset=4 (local.get $head)) (i32.const 0))
                 (i32.eqz (i32.load offset=8 (local.get $head))))
      (then
        (i32.store offset=8 (local.get $head) (i32.const 1))
        (i32.store offset=12 (local.get $head) (i32.load (i32.const 8)))
        (i32.store (i32.const 8) (local.get $head))))
    (i32.const 0))
  (func $collect (type $entry) (param $root i32) (param $floor i32) (param $unused i32) (result i32)
    (local $head i32) (local $count i32) (local $index i32) (local $end i32)
    (local $scratch_end i32) (local $pages i32) (local $slot i32) (local $limit i32)
    (local $size i32) (local $bin i32)
    (local.set $head (i32.load (i32.const 4)))
    (if (i32.eqz (local.get $head)) (then (return (local.get $root))))
    (local.set $count (local.get $head))
    (local.set $end (global.get $cursor))
    (local.set $index (local.get $end))
    ;; One bit per aligned word recognizes exact allocation starts in O(1).
    (local.set $scratch_end (i32.add (local.get $index)
      (i32.shl (i32.add (i32.shr_u (local.get $end) (i32.const 7)) (i32.const 1)) (i32.const 2))))
    (if (i32.lt_u (local.get $scratch_end) (local.get $index)) (then unreachable))
    (local.set $pages
      (i32.add (i32.shr_u (i32.sub (local.get $scratch_end) (i32.const 1)) (i32.const 16)) (i32.const 1)))
    (if (i32.gt_u (local.get $pages) (memory.size))
      (then
        (if (i32.eq (memory.grow (i32.sub (local.get $pages) (memory.size))) (i32.const -1))
          (then unreachable))))
    ;; Free-list reuse does not alter physical block starts. Rebuild the
    ;; scratch bitmap only when a bump allocation has invalidated it.
    (if (i32.ne (i32.load (i32.const 12)) (local.get $end))
      (then
        (local.set $slot (local.get $index))
        (block $cleared (loop $clearing
          (br_if $cleared (i32.ge_u (local.get $slot) (local.get $scratch_end)))
          (i32.store (local.get $slot) (i32.const 0))
          (local.set $slot (i32.add (local.get $slot) (i32.const 4)))
          (br $clearing)))
        (block $indexed (loop $indexing
          (br_if $indexed (i32.ge_u (local.get $head) (local.get $end)))
          (local.set $slot (i32.add (local.get $index) (i32.shl (i32.shr_u (local.get $head) (i32.const 7)) (i32.const 2))))
          (i32.store (local.get $slot) (i32.or (i32.load (local.get $slot))
            (i32.shl (i32.const 1) (i32.and (i32.shr_u (local.get $head) (i32.const 2)) (i32.const 31)))))
          (local.set $head (i32.add (local.get $head) (i32.load (local.get $head))))
          (br $indexing)))
        (i32.store (i32.const 12) (local.get $end))))
    (i32.store (i32.const 8) (i32.const 0))
    ;; Static memo cells have no allocator header. Their callback and cached
    ;; value are roots; offset 12 links the next cell emitted by the compiler.
    (local.set $slot (i32.load (i32.const 16)))
    (block $static_done (loop $static_memos
      (br_if $static_done (i32.eqz (local.get $slot)))
      (drop (call $mark (i32.load offset=4 (local.get $slot)) (local.get $index) (local.get $count)))
      (drop (call $mark (i32.load offset=8 (local.get $slot)) (local.get $index) (local.get $count)))
      (local.set $slot (i32.load offset=12 (local.get $slot)))
      (br $static_memos)))
    ;; Scan pinned pre-loop objects too: an owned update may install a newer
    ;; object in them. Merely exempting these blocks from sweep is insufficient.
    (local.set $head (i32.load (i32.const 4)))
    (block $pinned (loop $pinning
      (br_if $pinned (i32.ge_u (local.get $head) (local.get $floor)))
      (drop (call $mark (i32.add (local.get $head) (i32.const 16)) (local.get $index) (local.get $count)))
      (local.set $head (i32.add (local.get $head) (i32.load (local.get $head))))
      (br $pinning)))
    (drop (call $mark (local.get $root) (local.get $index) (local.get $count)))
    (block $traced (loop $tracing
      (local.set $head (i32.load (i32.const 8)))
      (br_if $traced (i32.eqz (local.get $head)))
      (i32.store (i32.const 8) (i32.load offset=12 (local.get $head)))
      (local.set $slot (i32.add (local.get $head) (i32.const 16)))
      (local.set $limit (i32.add (local.get $slot) (i32.load offset=4 (local.get $head))))
      (block $scanned (loop $scanning
        (br_if $scanned (i32.ge_u (i32.add (local.get $slot) (i32.const 3)) (local.get $limit)))
        (drop (call $mark (i32.load (local.get $slot)) (local.get $index) (local.get $count)))
        (local.set $slot (i32.add (local.get $slot) (i32.const 4)))
        (br $scanning)))
      (br $tracing)))
    (local.set $head (i32.load (i32.const 4)))
    (block $swept (loop $sweeping
      (br_if $swept (i32.ge_u (local.get $head) (local.get $end)))
      (local.set $size (i32.load (local.get $head)))
      (if (i32.and (i32.ge_u (local.get $head) (local.get $floor))
            (i32.and (i32.eqz (i32.load offset=8 (local.get $head)))
                     (i32.ne (i32.load offset=4 (local.get $head)) (i32.const 0))))
        (then
          (i32.store offset=4 (local.get $head) (i32.const 0))
          (local.set $bin
            (if (result i32) (i32.gt_u (local.get $size) (i32.const 2147483648))
              (then (i32.const 160))
              (else (i32.add (i32.const 32) (i32.shl (i32.ctz (local.get $size)) (i32.const 2))))))
          (i32.store offset=12 (local.get $head) (i32.load (local.get $bin)))
          (i32.store (local.get $bin) (local.get $head))))
      (i32.store offset=8 (local.get $head) (i32.const 0))
      (local.set $head (i32.add (local.get $head) (local.get $size)))
      (br $sweeping)))
    (local.get $root))
  (export "allocate" (func $allocate))
  (export "collect" (func $collect))
  (export "memory" (memory 0)))
