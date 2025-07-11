const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const xev = @import("xev");
const Task = if (builtin.single_threaded) void else xev.ThreadPool.Task;
const Job = @import("Job.zig");
const Self = @This();

task: Task,
loop: xev.Loop,
jobs: []?*Job,

pub fn create(alloc: Allocator, max_jobs: usize) !*Self {
    const jobs = try alloc.alloc(?*Job, max_jobs);
    errdefer alloc.free(jobs);

    @memset(jobs, null);

    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        .task = if (Task != void) .{
            .callback = runTask,
        } else {},
        .loop = try .init(.{}),
        .jobs = jobs,
    };
    return self;
}

fn runTask(task: *Task) void {
    const self: *Self = @fieldParentPtr("task", task);
    self.run() catch unreachable;
}

pub fn isDone(self: *Self) bool {
    for (self.jobs) |*opt_job| {
        if (opt_job.*) |job| {
            if (!job.isDone()) return false;
        }
    }
    return true;
}

pub fn run(self: *Self) !void {
    for (self.jobs) |*opt_job| {
        if (opt_job.*) |job| {
            try job.x_async.notify();
        }
    }

    try self.loop.run(.until_done);
}

pub fn findFreeJob(self: *Self) ?*?*Job {
    for (self.jobs) |*job| {
        if (job.* == null) return job;
    }
    return null;
}

pub fn pushJob(self: *Self, alloc: Allocator, comptime f: anytype, args: anytype, result: ?*?Job.Result) !void {
    if (self.findFreeJob()) |job| {
        const PushedJob = struct {
            args: @TypeOf(args),
            result: ?*?Job.Result,

            pub fn run(o: ?*anyopaque) anyerror!?Job.Result.Value {
                const j: *@This() = @ptrCast(@alignCast(o));
                const v = @call(.auto, f, j.args) catch |e| {
                    if (j.result) |res| {
                        res.* = .{
                            .err = .{ .tag = @errorName(e) },
                        };
                    }
                    return e;
                };

                if (j.result) |res| {
                    res.* = .{ .value = v };
                }
                return v;
            }

            pub fn deinit(o: *anyopaque, a: Allocator) void {
                const j: *@This() = @ptrCast(@alignCast(o));
                a.destroy(j);
            }
        };

        const j = try alloc.create(PushedJob);
        errdefer alloc.destroy(j);
        j.* = .{
            .args = args,
            .result = result,
        };

        job.* = try .create(alloc, &self.loop, j, PushedJob.deinit, PushedJob.run);
        return;
    }
    // TODO: push this to a qeue
    return error.TooManyJobs;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    for (self.jobs) |*opt_job| {
        if (opt_job.*) |job| job.deinit(alloc);
    }

    alloc.free(self.jobs);
    self.loop.deinit();
    alloc.destroy(self);
}
