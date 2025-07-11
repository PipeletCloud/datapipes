const std = @import("std");
const Allocator = std.mem.Allocator;
const Output = @import("../Output.zig");
const Step = @import("../Step.zig");
const Runner = @import("../Runner.zig");
const Value = @import("../../datapipes.zig").Value;
const ValueSequence = @import("../sources/ValueSequence.zig");
const Self = @This();

output: Output,
stream: std.io.AnyWriter,

pub fn create(alloc: Allocator, stream: std.io.AnyWriter) !*Step {
    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        .output = .init(@typeName(Self), &self.output, self, &.{
            .run = run,
            .deinit = deinit,
        }),
        .stream = stream,
    };
    return &self.output.step;
}

fn run(o: *anyopaque, alloc: Allocator, value: Value, _: *Runner) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(o));

    var stream = try value.asStream(alloc);
    defer stream.deinit(alloc);

    if (stream.reader()) |*reader| {
        const a = @constCast(reader).any();
        while (a.readByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => return err,
        }) |byte| try self.stream.writeByte(byte);
    } else {
        return error.NotImplemented;
    }
}

fn deinit(o: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(o));
    alloc.destroy(self);
}

test {
    const alloc = std.testing.allocator;

    var runner: Runner = undefined;
    try runner.init(alloc, .{});
    defer runner.deinit(alloc);

    var output = std.ArrayList(u8).init(alloc);
    defer output.deinit();

    const seq = try ValueSequence.create(alloc, &.{
        .{ .buffered = .{ .unstructured = "Hello, world" } },
    });
    defer seq.unref(alloc);

    const self = try create(alloc, output.writer().any());
    defer self.unref(alloc);

    self.pipe(alloc, seq);

    _ = try self.run(alloc, &runner);
    try runner.runSync();

    try std.testing.expectEqualStrings("Hello, world", output.items);
}
