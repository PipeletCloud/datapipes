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
        try a.streamUntilDelimiter(self.stream, 0, null);
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

    try runner.pushJob(alloc, (struct {
        fn func(a: Allocator, o: *std.ArrayList(u8), r: *Runner) !?Value {
            const seq = try ValueSequence.create(a, &.{
                .{ .buffered = .{ .unstructured = "Hello, world" } }
            });
            defer seq.unref(a);

            const self = try create(a, o.writer().any());
            defer self.unref(a);

            try self.pipe(a, seq);

            try self.run(a, r);
            return null;
        }
    }).func, .{ alloc, &output, &runner }, null);
    try runner.run();

    try std.testing.expectEqualStrings("Hello, world", output.items);
}
