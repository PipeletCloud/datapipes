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
cores: []?Core,
thread_pool: ThreadPool,

fn findAvailableCore(self: *Self, alloc: Allocator) ?*Core {
    for (self.cores) |*opt_core| {
        if (opt_core) |*core| {
            if (core.findFreeJob() == null) return core;
        }
    }

    for (self.cores) |*core| {
        if (core.* == null) {
            try core.?.init(alloc, self.max_jobs);
            return core.?;
        }
    }
    return null;
}

pub fn pushJob(self: *Self, alloc: Allocator, comptime f: anytype, args: anytype, result: ?*?Job.Result) !void {
    if (self.findAvailableCore(alloc)) |core| {
        return try core.pushJob(alloc, f, args, result);
    }
    // TODO: push this to a qeue
    return error.TooManyJobs;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    for (self.cores) |*opt_core| {
        if (opt_core.*) |*core| core.deinit(alloc);
    }
    alloc.free(self.cores);
}

test {
    _ = Options;
    _ = Core;
    _ = Job;
}
