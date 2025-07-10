const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const xev = @import("xev");
const Task = if (builtin.single_threaded) void else xev.ThreadPool.Task;
const Job = @import("Job.zig");
const Self = @This();

task: Task,
loop: xev.Loop,
jobs: []?Job,

pub fn init(self: *Job, alloc: Allocator, max_jobs: usize) !void {
    const jobs = try alloc.alloc(Job, max_jobs);
    errdefer alloc.free(jobs);

    self.* = .{
        .task = if (Task != void) .{
            .callback = runTask,
        } else {},
        .loop = try .init(.{}),
        .jobs = jobs,
    };
}

fn runTask(task: *Task) void {
    const self: *Self = @fieldParentPtr(task, "task");
    _ = self.loop.run(.until_done) catch unreachable;
}

pub fn findFreeJob(self: *Self) ?*?Job {
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
                    if (j.result) |*res| {
                        res.* = .{
                            .err = .{ .tag = @errorName(e) },
                        };
                    }
                    return e;
                };

                if (j.result) |*res| {
                    res.* = .{ .value = v };
                }
                return v;
            }

            pub fn deinit(o: *anyopaque, a: Allocator) void {
                const j: *@This() = @ptrCast(@alignCast(o));
                a.destroy(j);
            }
        };

        const j = alloc.create(PushedJob);
        j.* = .{
            .args = args,
            .result = result,
        };

        return try job.init(&self.loop, j, PushedJob.deinit, PushedJob.run);
    }
    // TODO: push this to a qeue
    return error.TooManyJobs;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    for (self.jobs) |*opt_job| {
        if (opt_job.*) |*job| job.deinit(alloc);
    }

    alloc.free(self.jobs);
    self.loop.deinit();
}
