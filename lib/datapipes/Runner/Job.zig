const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const xev = @import("xev");
const Self = @This();

pub const Result = union(enum) {
    value: ?Value,
    err: Error,

    pub const Value = @import("../../datapipes.zig").Value;

    pub const Error = struct {
        tag: []const u8,
    };

    pub fn deinit(self: *Result, alloc: Allocator) void {
        return switch (self.*) {
            .value => |*o_val| if (o_val.*) |*val| val.deinit(alloc) else {},
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

pub fn create(alloc: Allocator, loop: *xev.Loop, ptr: *anyopaque, deinitFn: ?DeinitFunc, runFn: RunFunc) !*Self {
    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        .ptr = ptr,
        .deinitFn = deinitFn,
        .runFn = runFn,
        .completion = undefined,
        .x_async = try .init(),
        .result = null,
    };

    self.x_async.wait(loop, &self.completion, Self, self, waitCallback);
    return self;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    self.x_async.deinit();
    if (self.result) |*r| r.deinit(alloc);
    if (self.ptr) |p| {
        if (self.deinitFn) |f| f(p, alloc);
    }
    alloc.destroy(self);
}

fn waitCallback(self_: ?*Self, _: *xev.Loop, _: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    const self = self_ orelse unreachable;
    _ = r catch |err| {
        self.result = .{
            .err = .{ .tag = @errorName(err) },
        };
        return .rearm;
    };

    return if (self.run()) .disarm else .rearm;
}

pub fn run(self: *Self) bool {
    if (self.result) |_| return false;

    self.result = if (self.runFn(self.ptr)) |value| .{ .value = value } else |err| .{ .err = .{ .tag = @errorName(err) } };
    return true;
}
