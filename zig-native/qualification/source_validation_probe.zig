const std = @import("std");
const retained = @import("retained_revision.zig");
const memory = @import("memory.zig");
fn sliceBytes(value: anytype) usize {
    return value.len * @sizeOf(@TypeOf(value[0]));
}
fn receiptBytes(record: anytype) usize {
    var total: usize = 0;
    inline for (.{ "sources", "scalar_reads", "call_reads", "call_publications", "views", "plain_facts" }) |field| total += sliceBytes(@field(record, field));
    return total;
}
const RetainedTables = struct { selected: Storage, principal: Storage, refinement: Storage };
fn retainedTables(metadata: anytype) RetainedTables {
    const refinement = metadata.refinement_queries;
    var result: RetainedTables = .{
        .selected = .{},
        .principal = .{},
        .refinement = .{ .records = refinement.records.items.len, .payload_bytes = refinement.owned_bytes, .capacity_bytes = refinement.capacity_bytes },
    };
    if (@hasField(@TypeOf(metadata.*), "specialization_queries")) {
        const selected = metadata.specialization_queries;
        const principal = metadata.principal_queries;
        result.selected = .{ .records = selected.records.items.len, .payload_bytes = selected.owned_bytes, .capacity_bytes = selected.capacity_bytes };
        result.principal = .{ .records = principal.records.items.len, .payload_bytes = principal.owned_bytes, .capacity_bytes = principal.capacity_bytes };
    } else {
        result.selected.records = metadata.specialization_receipts.items.len;
        result.selected.capacity_bytes = metadata.specialization_receipts.capacity * @sizeOf(@TypeOf(metadata.specialization_receipts.items[0]));
        for (metadata.specialization_receipts.items) |record| result.selected.payload_bytes += receiptBytes(record);
        result.principal.records = metadata.principal_proofs.items.len;
        result.principal.capacity_bytes = metadata.principal_proofs.capacity * @sizeOf(@TypeOf(metadata.principal_proofs.items[0]));
        for (metadata.principal_proofs.items) |proof| {
            result.principal.payload_bytes += sliceBytes(proof.types) + sliceBytes(proof.rows);
            if (proof.inputs) |inputs| inline for (.{ "scalar_reads", "plain_reads", "plain_publications", "call_publications" }) |field| {
                result.principal.payload_bytes += sliceBytes(@field(inputs, field));
            };
        }
    }
    return result;
}
const Storage = struct { records: usize = 0, payload_bytes: usize = 0, capacity_bytes: usize = 0 };

fn outcomeBytes(outcome: anytype) usize {
    return switch (outcome) {
        .bytes => |bytes| bytes.len,
        .failure => 0,
    };
}
fn observationStorage(options: anytype, paths: anytype, files: anytype, imports: anytype) Storage {
    var result: Storage = .{ .records = 1, .payload_bytes = sliceBytes(options.aliases), .capacity_bytes = paths.capacity * @sizeOf(@TypeOf(paths.items[0])) + files.capacity * @sizeOf(@TypeOf(files.items[0])) + imports.capacity * @sizeOf(@TypeOf(imports.items[0])) };
    if (options.prelude_path) |path| result.payload_bytes += path.len;
    if (options.std_root) |path| result.payload_bytes += path.len;
    for (options.aliases) |alias| result.payload_bytes += alias.prefix.len + alias.root.len;
    for (paths.items) |entry| result.payload_bytes += entry.key.len + outcomeBytes(entry.result);
    for (files.items) |entry| result.payload_bytes += entry.key.len + outcomeBytes(entry.result);
    for (imports.items) |entry| result.payload_bytes += entry.source.len + entry.request.len + outcomeBytes(entry.result);
    return result;
}
fn inputStorage(snapshot: anytype) Storage {
    if (@hasField(@TypeOf(snapshot), "record")) {
        const dependencies = snapshot.record.dependencies;
        return observationStorage(snapshot.record.key.options, dependencies.paths, dependencies.files, dependencies.imports);
    }
    return observationStorage(snapshot.options, snapshot.paths, snapshot.files, snapshot.imports);
}
fn validationStorage(metadata: anytype) Storage {
    const certificate = if (metadata.pools.?.dependency_certificate) |certificate| certificate else return .{};
    if (@hasField(@TypeOf(certificate), "record")) {
        const storage = certificate.storage();
        return .{ .records = storage.records, .payload_bytes = storage.payload_bytes, .capacity_bytes = storage.capacity_bytes };
    }
    return .{ .records = 1, .payload_bytes = sliceBytes(certificate.modules) + sliceBytes(certificate.context.owners) };
}

fn cpuMicros() u64 {
    var usage: std.os.linux.rusage = undefined;
    if (std.os.linux.getrusage(std.os.linux.rusage.SELF, &usage) != 0) return 0;
    return @intCast((usage.utime.sec + usage.stime.sec) * 1000000 + usage.utime.usec + usage.stime.usec);
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return error.ExpectedEntryAndEditPath;
    const original = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], init.arena.allocator(), .limited(1024 * 1024));
    const edited = try init.arena.allocator().dupe(u8, original);
    const prefix = if (std.mem.find(u8, edited, "const f0 = make 1\n") != null) "const f0 = make " else if (std.mem.find(u8, edited, "const f_0 = fn value => @u32.add value ") != null) "const f_0 = fn value => @u32.add value " else "const changed = ";
    const point = std.mem.find(u8, edited, prefix) orelse return error.MissingEditPoint;
    edited[point + prefix.len] = '3';
    const requested = try std.fmt.parseInt(u8, args[3], 10);
    var tracked: memory.TrackedAllocator = .{ .backing = std.heap.smp_allocator };
    {
        var session = try retained.Session.initEmpty(tracked.allocator(), .{});
        defer session.deinit();
        if (comptime @hasField(@TypeOf(session.policy), "semantic_components")) {
            session.policy.semantic_components = requested != 0;
            session.policy.semantic_workers = @max(1, requested);
        }
        session.profile_backend = std.mem.eql(u8, args[4], "profile");
        for (0..21) |round| {
            for ([_][]const u8{ "population_or_noop", "edit", "revert", "noop" }, 0..) |phase, step| {
                const before = tracked.counts;
                tracked.counts.peak_bytes = tracked.counts.live_bytes;
                const before_cpu = cpuMicros();
                const started = std.Io.Clock.awake.now(init.io);
                var prepared = try session.prepareRevisionWithSources(init.io, args[1], null, .{}, &.{.{ .path = args[2], .contents = if (step == 1) edited else original }});
                const candidate = switch (prepared) {
                    .ready => |candidate| candidate,
                    .rejected => {
                        prepared.deinit();
                        return error.UnexpectedRejectedRevision;
                    },
                };
                var digest: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(candidate.result().?.result.compiled.bytes, &digest, .{});
                const reused = candidate.stats.reused_output;
                const work = candidate.result().?.result.compiled.counters;
                const timing = candidate.result().?.result.compiled.timing;
                const compiled = candidate.result().?.result.compiled;
                const refinement = compiled.refinements;
                const selected_queries = compiled.completed_queries;
                const principal_queries = compiled.principal;
                const source_validation = if (@hasField(@TypeOf(compiled), "source_validation")) compiled.source_validation else null;
                const query_tables = if (@hasField(@TypeOf(compiled), "query_tables")) compiled.query_tables else null;
                if (!session.commit(candidate)) {
                    candidate.deinit();
                    return error.CommitFailed;
                }
                candidate.deinit();
                const cpu_us = cpuMicros() - before_cpu;
                const wall_us: u64 = @intCast(@max(0, started.durationTo(std.Io.Clock.awake.now(init.io)).toMicroseconds()));
                const retained_query_tables = retainedTables(&session.current.?.artifacts.metadata);
                const source_inputs = inputStorage(session.current.?.snapshot);
                const validation_certificate = validationStorage(&session.current.?.artifacts.metadata);
                const row = .{ .round = round, .phase = phase, .requested_bytes = tracked.counts.allocated_bytes - before.allocated_bytes, .allocations = tracked.counts.allocations - before.allocations, .peak_live_bytes = tracked.counts.peak_bytes, .retained_live_bytes = tracked.counts.live_bytes, .reused_output = reused, .wasm_digest = digest, .cpu_us = cpu_us, .wall_us = wall_us, .work_counters = work, .refinement = refinement, .selected_queries = selected_queries, .principal_queries = principal_queries, .source_validation = source_validation, .source_inputs = source_inputs, .validation_certificate = validation_certificate, .query_tables = query_tables, .retained_query_tables = retained_query_tables, .timing = timing };
                const json = try std.json.Stringify.valueAlloc(init.arena.allocator(), row, .{});
                std.debug.print("{s}\n", .{json});
            }
        }
    }
    if (tracked.counts.live_bytes != 0) return error.TeardownLeak;
    std.debug.print("{{\"teardown_live_bytes\":0}}\n", .{});
}
