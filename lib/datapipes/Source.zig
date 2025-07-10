const std = @import("std");
const Allocator = std.mem.Allocator;
const Runner = @import("Runner.zig");
const Value = @import("../datapipes.zig").Value;
const Step = @import("Step.zig");
const Self = @This();

pub const VTable = struct {
    run: *const fn (*anyopaque, Allocator, *Step, *Runner) anyerror!Value,
    deinit: *const fn (*anyopaque, Allocator) void,
};

const vtable_step: Step.VTable = .{
    .getInput = null,
    .getOutput = vtable_getOutput,
    .run = vtable_run,
    .deinit = vtable_deinit,
};

step: *Step,
ptr: *anyopaque,
vtable: *const VTable,
output: ?Value,

fn vtable_getOutput(o: *anyopaque) !Value {
    const self: *Self = @ptrCast(@alignCast(o));
    return &self.output;
}

fn vtable_run(o: *anyopaque, alloc: Allocator, step: *Step, runner: *Runner) !?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    const output = try self.vtable.run(self.ptr, alloc, step, runner);
    self.output = output;
    return output;
}

fn vtable_deinit(o: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(o));
    self.vtable.deinit(self.ptr, alloc);
}
