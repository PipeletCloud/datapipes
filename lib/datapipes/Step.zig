const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Runner = @import("Runner.zig");
const Value = @import("../datapipes.zig").Value;
const Self = @This();

pub const Map = struct {
    input: *Self,
    output: ?Value,
};

pub const Kind = enum {
    source,
    transformation,
    output,
};

pub const VTable = struct {
    getInput: ?*const fn (*anyopaque, Allocator, *Self, *Runner) anyerror!*?Value,
    getOutput: ?*const fn (*anyopaque, Allocator, *Self, *Runner) anyerror!*?Value,
    run: *const fn (*anyopaque, Allocator, *Self, *Runner) anyerror!?Value,
    deinit: *const fn (*anyopaque, Allocator) void,
};

tag: []const u8,
kind: Kind,
ref_count: usize,
ptr: *anyopaque,
vtable: *const VTable,
pipes: std.ArrayListUnmanaged(Map),

pub inline fn init(tag: []const u8, kind: Kind, ptr: *anyopaque, vtable: *const VTable) Self {
    return .{
        .tag = tag,
        .kind = kind,
        .ref_count = 0,
        .ptr = ptr,
        .vtable = vtable,
        .pipes = .{},
    };
}

pub fn getInput(self: *Self, alloc: Allocator, step: *Self, runner: *Runner) !*?Value {
    if (self.vtable.getInput) |f| {
        return f(self.ptr, alloc, step, runner);
    }
    return error.NoInput;
}

pub fn getOutput(self: *Self, alloc: Allocator, step: *Self, runner: *Runner) !*?Value {
    if (self.vtable.getOutput) |f| {
        return f(self.ptr, alloc, step, runner);
    }
    return error.NoOutput;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    assert(self.ref_count == 0);

    for (self.pipes.items) |*i| {
        i.input.unref(alloc);
        if (i.output) |*o| o.deinit(alloc);
    }

    self.pipes.deinit(alloc);

    self.vtable.deinit(self.ptr, alloc);
}

pub fn unref(self: *Self, alloc: Allocator) void {
    if (self.ref_count > 0) {
        self.ref_count -= 1;
        return;
    }

    self.deinit(alloc);
}

pub fn ref(self: *Self) *Self {
    self.ref_count += 1;
    return self;
}

pub fn pipe(self: *Self, alloc: Allocator, source: *Self) !void {
    try self.pipes.append(alloc, .{
        .input = source.ref(),
        .output = null,
    });
}

pub fn run(self: *Self, alloc: Allocator, runner: *Runner) !void {
    for (self.pipes.items) |*p| {
        if (p.output) |*o| o.deinit(alloc);
        p.output = try self.vtable.run(self.ptr, alloc, p.input, runner);
    }
}
