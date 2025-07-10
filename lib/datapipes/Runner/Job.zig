const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const xev = @import("xev");
const Self = @This();

pub const Result = union(enum) {
    value: Value,
    err: Error,

    pub const Value = @import("../../datapipes.zig").Value;

    pub const Error = struct {
        tag: []const u8,
    };

    pub fn deinit(self: *Result, alloc: Allocator) void {
        return switch (self.*) {
            .value => |val| val.deinit(alloc),
            .err => {},
        };
    }
};

pub const RunFunc = *const fn (?*anyopaque) anyerror!?Result.Value;
pub const DeinitFunc = *const fn (*anyopaque, Allocator) void;

ptr: ?*anyopaque,
deinitFn: ?DeinitFunc,
runFn: RunFunc,
completion: xev.Completion,
x_async: xev.Async,
result: ?Result,

pub fn init(self: *Self, loop: *xev.Loop, ptr: *anyopaque, deinitFn: ?DeinitFunc, runFn: RunFunc) !void {
    self.* = .{
        .ptr = ptr,
        .deinitFn = deinitFn,
        .runFn = runFn,
        .completion = undefined,
        .x_async = try .init(),
        .result = null,
    };

    self.x_async.wait(loop, &self.completion, Self, self, waitCallback);
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    self.x_async.deinit();
    if (self.result) |r| r.deinit(alloc);
    if (self.ptr) |p| {
        if (self.deinitFn) |f| f(p, alloc);
    }
}

fn waitCallback(self_: ?*Self, _: *xev.Loop, _: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    const self = self_.? catch unreachable;
    _ = r catch |err| {
        self.result = .{
            .err = .{ .tag = @errorName(err) },
        };
        return .rearm;
    };

    return if (self.run()) .rearm else .disarm;
}

pub fn run(self: *Self) bool {
    if (self.result) |_| return false;

    self.result = if (self.vtable.run(self.ptr)) |value| .{ .value = value } else |err| .{ .err = .{ .tag = @errorName(err) } };
    return true;
}
