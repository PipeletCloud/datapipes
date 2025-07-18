const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const closure = @import("closure");
const scalarcore = @import("scalarcore");
const Pipe = @import("Pipe.zig");
const Self = @This();

pub const State = enum {
    waiting,
    running,
    failed,
    done,
};

pub const WorkFunc = fn (*Self, []const *Self, *Pipe, Allocator, *scalarcore.Runner, ?*anyopaque) anyerror!bool;
pub const DeinitFunc = fn (?*anyopaque, Allocator) void;

tag: []const u8,
atomic_tx: std.atomic.Value(usize) = .init(0),
atomic_rx: std.atomic.Value(usize) = .init(0),
atomic_state: std.atomic.Value(u32) = .init(@intFromEnum(State.waiting)),
work: *const WorkFunc,
userdata: ?*anyopaque,
deinit_userdata: ?*const DeinitFunc,
ref_count: std.atomic.Value(usize) = .init(0),

pub fn init(tag: []const u8, work: *const WorkFunc, userdata: ?*anyopaque, deinit_userdata: ?*const DeinitFunc) Self {
    return .{
        .tag = tag,
        .work = work,
        .userdata = userdata,
        .deinit_userdata = deinit_userdata,
    };
}

pub fn runSync(self: *Self, pipe: *Pipe, parents: []const *Self, alloc: Allocator, runner: *scalarcore.Runner) !bool {
    if (self.state() == .waiting) {
        self.atomic_tx.store(0, .monotonic);
        self.atomic_rx.store(0, .monotonic);
        self.atomic_state.store(@intFromEnum(State.running), .monotonic);
    }

    const should_continue = self.work(self, parents, pipe, alloc, runner, self.userdata) catch |err| {
        self.atomic_state.store(@intFromEnum(State.failed), .monotonic);
        return err;
    };

    if (!should_continue) self.atomic_state.store(@intFromEnum(State.done), .monotonic);
    return should_continue;
}

pub fn runAsync(self: *Self, pipe: *Pipe, parents: []const *Self, alloc: Allocator, runner: *scalarcore.Runner) !void {
    const rj = try alloc.create(closure.FixedClosure(runSync).Arguments);
    errdefer alloc.destroy(rj);

    rj.* = .{ self, pipe, parents, alloc, runner };

    _ = try runner.pushJob(alloc, runAsyncCallback, rj);
}

fn runAsyncCallback(userdata: ?*anyopaque) anyerror!bool {
    const rj: *closure.FixedClosure(runSync).Arguments = @ptrCast(@alignCast(userdata orelse unreachable));
    defer rj[3].destroy(rj);
    return try @call(.auto, runSync, rj.*);
}

pub fn ref(self: *Self) *Self {
    _ = self.ref_count.fetchAdd(1, .acq_rel);
    return self;
}

pub fn state(self: *const Self) State {
    return @enumFromInt(self.atomic_state.load(.monotonic));
}

pub fn unref(self: *Self, alloc: Allocator) void {
    if (self.ref_count.fetchSub(1, .acq_rel) == 0) {
        return self.deinit(alloc);
    }
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    assert(self.ref_count.load(.monotonic) == 0);
    if (self.deinit_userdata) |f| f(self.userdata, alloc);
}

test {
    std.testing.refAllDecls(@This());
}
