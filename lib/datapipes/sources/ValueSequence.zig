const std = @import("std");
const Allocator = std.mem.Allocator;
const Source = @import("../Source.zig");
const Step = @import("../Step.zig");
const Runner = @import("../Runner.zig");
const Value = @import("../../datapipes.zig").Value;
const Self = @This();

source: Source,
seq: std.ArrayListUnmanaged(Value),
index: usize,

pub fn create(alloc: Allocator, seq: []const Value) !*Step {
    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        .source = .init(@typeName(Self), &self.source, self, &.{
            .run = run,
            .deinit = deinit,
        }),
        .seq = .{},
        .index = 0,
    };

    for (seq) |item| {
        try self.seq.append(alloc, try item.dupe(alloc));
    }

    return &self.source.step;
}

fn run(o: *anyopaque, alloc: Allocator, _: ?*Step, _: *Runner) anyerror!?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    if (self.index < self.seq.items.len) {
        const value = self.seq.items[self.index];
        self.index += 1;
        return try value.dupe(alloc);
    }
    return null;
}

fn deinit(o: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(o));
    for (self.seq.items) |*item| item.deinit(alloc);
    self.seq.deinit(alloc);
    alloc.destroy(self);
}
