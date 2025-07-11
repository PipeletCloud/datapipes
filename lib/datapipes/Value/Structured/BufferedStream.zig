const std = @import("std");
const Allocator = std.mem.Allocator;
const Structured = @import("../Structured.zig");
const Self = @This();

stream: Structured.Stream,
strct: Structured,
iter: ?Structured.ValueMap.Iterator,

pub fn create(alloc: Allocator, strct: *const Structured) !*Structured.Stream {
    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        .stream = .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .dupe = dupe,
                .deinit = deinit,
            },
        },
        .strct = try strct.dupe(alloc),
        .iter = null,
    };
    return &self.stream;
}

fn read(o: *anyopaque, _: Allocator) anyerror!?Structured.Entry {
    const self: *Self = @ptrCast(@alignCast(o));

    if (self.iter == null) {
        self.iter = self.strct.map.iterator();
    }

    const entry = self.iter.?.next() orelse return null;
    return .{
        .key = entry.key_ptr.*,
        .value = entry.value_ptr.*,
    };
}

fn dupe(o: *anyopaque, alloc: Allocator) anyerror!*Structured.Stream {
    const self: *Self = @ptrCast(@alignCast(o));
    return try create(alloc, &self.strct);
}

fn deinit(o: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(o));
    self.strct.deinit(alloc);
    alloc.destroy(self);
}
