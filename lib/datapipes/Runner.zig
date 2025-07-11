const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const xev = @import("xev");
const ThreadPool = if (builtin.single_threaded) void else xev.ThreadPool;
const Self = @This();

pub const Options = struct {
    max_jobs: ?usize = null,
    max_cores: ?usize = null,

    fn getCpuCount() !usize {
        if (ThreadPool == void) return 1;
        return std.Thread.getCpuCount();
    }

    pub fn maxCores(self: Options) !usize {
        if (self.max_cores) |max_cores| return max_cores;
        return getCpuCount();
    }

    pub fn maxJobs(self: Options) !usize {
        if (self.max_jobs) |max_jobs| return max_jobs;
        return getCpuCount();
    }
};

pub const Core = @import("Runner/Core.zig");
pub const Job = @import("Runner/Job.zig");

max_jobs: usize,
cores: []?*Core,
thread_pool: ThreadPool,

pub fn init(self: *Self, alloc: Allocator, options: Options) !void {
    const cores = try alloc.alloc(?*Core, try options.maxCores());
    errdefer alloc.free(cores);

    @memset(cores, null);

    self.* = .{
        .max_jobs = try options.maxJobs(),
        .cores = cores,
        .thread_pool = if (ThreadPool != void) .init(.{ .max_threads = @intCast(cores.len) }) else {},
    };
}

fn findAvailableCore(self: *Self, alloc: Allocator) !?*Core {
    for (self.cores) |*opt_core| {
        if (opt_core.*) |core| {
            if (core.findFreeJob() == null) return core;
        }
    }

    for (self.cores) |*core| {
        if (core.* == null) {
            core.* = try .create(alloc, self.max_jobs);
            return core.*;
        }
    }
    return null;
}

pub fn pushJob(self: *Self, alloc: Allocator, comptime f: anytype, args: anytype, result: ?*?Job.Result) !void {
    if (try self.findAvailableCore(alloc)) |core| {
        return try core.pushJob(alloc, f, args, result);
    }
    // TODO: push this to a queue
    return error.TooManyJobs;
}

pub fn run(self: *Self) !void {
    if (ThreadPool != void) {
        var batch: ThreadPool.Batch = .{};
        for (self.cores) |*opt_core| {
            if (opt_core.*) |core| {
                batch.push(.from(&core.task));
            }
        }

        self.thread_pool.schedule(batch);
    } else {
        for (self.cores) |*opt_core| {
            if (opt_core.*) |core| {
                try core.run();
            }
        }
    }
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    if (ThreadPool != void) {
        self.thread_pool.shutdown();
        self.thread_pool.deinit();
    }

    for (self.cores) |*opt_core| {
        if (opt_core.*) |core| core.deinit(alloc);
    }
    alloc.free(self.cores);
}

test {
    _ = Options;
    _ = Core;
    _ = Job;
}
