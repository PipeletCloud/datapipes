const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Thread = if (builtin.single_threaded) void else ?std.Thread;
const Allocator = std.mem.Allocator;
const Runner = @import("../Runner.zig");
const Self = @This();

pub const Value = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    float: f64,
    boolean: bool,
    null: void,

    pub fn dupe(self: *const Value, alloc: Allocator) !Value {
        return switch (self.*) {
            .string => |value| .{ .string = try alloc.dupe(u8, value) },
            inline else => |v, t| @unionInit(Value, @tagName(t), v),
        };
    }

    pub fn deinit(self: *Value, alloc: Allocator) void {
        return switch (self.*) {
            .string => |value| alloc.free(value),
            inline else => {},
        };
    }
};

pub const ValueMap = std.StringHashMapUnmanaged(Value);

pub const Entry = struct {
    key: []const u8,
    value: Value,

    pub fn deinit(self: Entry, alloc: Allocator) void {
        alloc.free(self.key);
        self.value.deinit(alloc);
    }
};

map: ValueMap,

pub fn dupe(self: *const Self, alloc: Allocator) !Self {
    var map: ValueMap = .{};

    var iter = self.map.iterator();
    while (iter.next()) |entry| {
        const key = try alloc.dupe(u8, entry.key_ptr.*);
        errdefer alloc.free(key);

        var value = try entry.value_ptr.*.dupe(alloc);
        errdefer value.deinit(alloc);

        try map.put(alloc, key, value);
    }

    return .{ .map = map };
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    self.map.deinit(alloc);
    alloc.destroy(self);
}

pub const Stream = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    completed: ValueMap,
    thread: Thread,

    pub const VTable = struct {
        read: *const fn (*anyopaque, alloc: Allocator) anyerror!?Entry,
        dupe: *const fn (*anyopaque, alloc: Allocator) anyerror!*Stream,
        deinit: *const fn (*anyopaque, alloc: Allocator) void,
    };

    fn runThread(self: *Stream, alloc: Allocator) void {
        while (self.read(alloc) catch null) |_| {}
        self.thread = null;
    }

    pub fn initThread(self: *Stream, alloc: Allocator) !void {
        if (Thread == void) @compileError("Thread support is disabled");
        assert(self.thread == null);

        self.thread = try std.Thread.spawn(.{
            .allocator = alloc,
        }, runThread, .{ self, alloc });
    }

    pub fn read(self: *Stream, alloc: Allocator) !?Entry {
        if (self.vtable.read(self.ptr, alloc)) |entry| {
            errdefer entry.deinit(alloc);
            try self.competed.put(alloc, entry.key, entry.value);
            return entry;
        }
        return null;
    }

    pub fn dupe(self: *Stream, alloc: Allocator) !*Stream {
        return self.vtable.dupe(self.ptr, alloc);
    }

    pub fn deinit(self: *Stream, alloc: Allocator) void {
        var iter = self.completed.iterator();
        while (iter.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            entry.value_ptr.deinit(alloc);
        }

        self.vtable.deinit(self.ptr, alloc);
    }

    pub fn isThreaded(self: *const Stream) bool {
        if (Thread == void) return false;
        return self.thread != null;
    }

    /// Yields the current thread and waits for the value of the key to resolve.
    pub fn getSync(self: *Stream, alloc: Allocator, key: []const u8) !Value {
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
        self: *Stream,
        alloc: Allocator,
        runner: *Runner,
        key: []const u8,
        args: anytype,
        comptime f: fn (v: Runner.Job.Result.Value, a: @TypeOf(args)) Runner.Job.Result.Value,
        result: ?*?Runner.Job.Result,
    ) !void {
        try runner.pushJob(alloc, (struct {
            fn func(stream: *Stream, a: Allocator, k: []const u8, p: @TypeOf(args)) anyerror!Runner.Job.Result.Value {
                const value = try stream.getSync(a, k);
                return @call(.auto, f, .{ value, p });
            }
        }).func, .{ self, alloc, key, args }, result);
    } 

    pub const Iterator = struct {
        allocator: Allocator,
        stream: *Stream,

        pub fn next(self: *Iterator) !?Entry {
            return self.stream.read(self.allocator);
        }
    };
};

test {
    _ = Value;
    _ = Entry;
    _ = Stream;
}
