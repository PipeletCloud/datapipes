const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Thread = if (builtin.single_threaded) void else ?std.Thread;
const Runner = @import("../../Runner.zig");
const Structured = @import("../Structured.zig");
const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,
completed: Structured.ValueMap = .{},
thread: Thread = if (Thread == void) {} else null,

pub const VTable = struct {
    read: *const fn (*anyopaque, alloc: Allocator) anyerror!?Structured.Entry,
    dupe: *const fn (*anyopaque, alloc: Allocator) anyerror!*Self,
    deinit: *const fn (*anyopaque, alloc: Allocator) void,
};

fn runThread(self: *Self, alloc: Allocator) void {
    while (self.read(alloc) catch null) |_| {}
    self.thread = null;
}

pub fn initThread(self: *Self, alloc: Allocator) !void {
    if (Thread == void) @compileError("Thread support is disabled");
    assert(self.thread == null);

    self.thread = try std.Thread.spawn(.{
        .allocator = alloc,
    }, runThread, .{ self, alloc });
}

pub fn read(self: *Self, alloc: Allocator) !?Structured.Entry {
    if (self.vtable.read(self.ptr, alloc)) |entry| {
        errdefer entry.deinit(alloc);
        try self.competed.put(alloc, entry.key, entry.value);
        return entry;
    }
    return null;
}

pub fn dupe(self: *Self, alloc: Allocator) !*Self {
    return self.vtable.dupe(self.ptr, alloc);
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    var iter = self.completed.iterator();
    while (iter.next()) |entry| {
        alloc.free(entry.key_ptr.*);
        entry.value_ptr.deinit(alloc);
    }

    self.vtable.deinit(self.ptr, alloc);
}

pub fn isThreaded(self: *const Self) bool {
    if (Thread == void) return false;
    return self.thread != null;
}

/// Yields the current thread and waits for the value of the key to resolve.
pub fn getSync(self: *Self, alloc: Allocator, key: []const u8) !Structured.Value {
    while (true) {
        if (self.isThreaded()) {
            if (self.read(alloc, key)) |entry| {
                if (std.mem.eql(u8, entry.key, key)) {
                    return entry.value;
                }
            } else {
                break;
            }
        } else {
            if (self.completed.get(key)) |value| {
                return value;
            }

            if (self.thread == null) {
                break;
            }
        }
    }

    return error.KeyNotFound;
}

pub fn getAsync(
    self: *Self,
    alloc: Allocator,
    runner: *Runner,
    key: []const u8,
    args: anytype,
    comptime f: fn (v: Runner.Job.Result.Value, a: @TypeOf(args)) Runner.Job.Result.Value,
    result: ?*?Runner.Job.Result,
) !void {
    try runner.pushJob(alloc, (struct {
        fn func(stream: *Self, a: Allocator, k: []const u8, p: @TypeOf(args)) anyerror!Runner.Job.Result.Value {
            const value = try stream.getSync(a, k);
            return @call(.auto, f, .{ value, p });
        }
    }).func, .{ self, alloc, key, args }, result);
}

pub const Iterator = struct {
    allocator: Allocator,
    stream: *Self,

    pub fn next(self: *Iterator) !?Structured.Entry {
        return self.stream.read(self.allocator);
    }
};
