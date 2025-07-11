const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Runner = @import("Runner.zig");
const Value = @import("../datapipes.zig").Value;
const Self = @This();

pub const Kind = enum {
    source,
    transformation,
    output,
};

pub const VTable = struct {
    getInput: ?*const fn (*anyopaque, Allocator, ?*Self, *Runner) anyerror!*?Value,
    getOutput: ?*const fn (*anyopaque, Allocator, ?*Self, *Runner) anyerror!*?Value,
    run: *const fn (*anyopaque, Allocator, ?*Self, *Runner) anyerror!?Value,
    deinit: *const fn (*anyopaque, Allocator) void,
};

tag: []const u8,
kind: Kind,
ref_count: usize,
ptr: *anyopaque,
vtable: *const VTable,
pipe_from: ?*Self,

pub inline fn init(tag: []const u8, kind: Kind, ptr: *anyopaque, vtable: *const VTable) Self {
    return .{
        .tag = tag,
        .kind = kind,
        .ref_count = 0,
        .ptr = ptr,
        .vtable = vtable,
        .pipe_from = null,
    };
}

pub fn getInput(self: *Self, alloc: Allocator, runner: *Runner) !*?Value {
    if (self.vtable.getInput) |f| {
        assert(self.pipe_from != self);
        return f(self.ptr, alloc, self.pipe_from, runner);
    }
    return error.NoInput;
}

pub fn getOutput(self: *Self, alloc: Allocator, runner: *Runner) !*?Value {
    if (self.vtable.getOutput) |f| {
        assert(self.pipe_from != self);
        return f(self.ptr, alloc, self.pipe_from, runner);
    }
    return error.NoOutput;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    assert(self.ref_count == 0);

    if (self.pipe_from) |i| i.unref(alloc);

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

pub fn pipe(self: *Self, alloc: Allocator, source: *Self) void {
    assert(source != self);
    if (self.pipe_from) |i| i.unref(alloc);
    self.pipe_from = source.ref();
}

pub fn run(self: *Self, alloc: Allocator, runner: *Runner) !?Value {
    return try self.vtable.run(self.ptr, alloc, self.pipe_from, runner);
}
