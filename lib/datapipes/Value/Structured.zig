const std = @import("std");
const Allocator = std.mem.Allocator;
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

pub fn toStream(self: *const Self, alloc: Allocator) !*Stream {
    return try BufferedStream.create(alloc, self);
}

pub const BufferedStream = @import("Structured/BufferedStream.zig");
pub const Stream = @import("Structured/Stream.zig");

test {
    _ = Value;
    _ = Entry;
    _ = BufferedStream;
    _ = Stream;
}
