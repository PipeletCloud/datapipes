const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Runner = @import("Runner.zig");
const Value = @import("../datapipes.zig").Value;
const Step = @import("Step.zig");
const Self = @This();

pub const VTable = struct {
    run: *const fn (*anyopaque, Allocator, Value, *Runner) anyerror!void,
    deinit: *const fn (*anyopaque, Allocator) void,
};

const vtable_step: Step.VTable = .{
    .getInput = vtable_getInput,
    .getOutput = null,
    .run = vtable_run,
    .deinit = vtable_deinit,
};

step: Step,
ptr: *anyopaque,
vtable: *const VTable,
input: ?Value,

pub inline fn init(tag: []const u8, self: *Self, ptr: *anyopaque, vtable: *const VTable) Self {
    return .{
        .step = .init(tag, .output, self, &vtable_step),
        .ptr = ptr,
        .vtable = vtable,
        .input = null,
    };
}

fn vtable_getInput(o: *anyopaque, alloc: Allocator, step: ?*Step, runner: *Runner) !*?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    assert(step != &self.step);
    self.input = if (step) |s| (try s.getOutput(alloc, runner)).* else null;
    return &self.input;
}

fn vtable_run(o: *anyopaque, alloc: Allocator, step: ?*Step, runner: *Runner) !?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    assert(step != &self.step);
    const input = try self.step.getInput(alloc, runner);
    try self.vtable.run(self.ptr, alloc, input.* orelse return null, runner);
    return null;
}

fn vtable_deinit(o: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(o));
    self.vtable.deinit(self.ptr, alloc);
}
