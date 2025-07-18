const std = @import("std");
const Allocator = std.mem.Allocator;
const scalarcore = @import("scalarcore");
const Pipe = @import("../Pipe.zig");
const Step = @import("../Step.zig");
const BufferedReader = @import("BufferedReader.zig");
const Self = @This();

const Data = struct {
    stream: std.io.AnyWriter,

    fn cast(ptr: ?*anyopaque) *Data {
        return @ptrCast(@alignCast(ptr orelse unreachable));
    }

    fn deinit(self: *Data, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

pub fn create(alloc: Allocator, writer: std.io.AnyWriter) !Step {
    const data = try alloc.create(Data);
    errdefer alloc.destroy(data);

    data.* = .{
        .stream = writer,
    };

    return .init(@typeName(Self), workCallback, data, deinitCallback);
}

fn workCallback(
    step: *Step,
    parents: []const *Step,
    pipe: *Pipe,
    alloc: Allocator,
    runner: *scalarcore.Runner,
    userdata: ?*anyopaque,
) anyerror!bool {
    const data = Data.cast(userdata);
    return !(try pipe.streamWriteAsync(step, parents, alloc, runner, data.stream));
}

fn deinitCallback(userdata: ?*anyopaque, alloc: Allocator) void {
    return Data.cast(userdata).deinit(alloc);
}

test {
    std.testing.refAllDecls(@This());
}

test "Buffered reader to stream writer" {
    const alloc = std.testing.allocator;

    var output = std.ArrayList(u8).init(alloc);
    defer output.deinit();

    var breader = try BufferedReader.create(alloc, "Hello, world!");
    defer breader.deinit(alloc);

    var swriter = try create(alloc, output.writer().any());
    defer swriter.deinit(alloc);

    var pipe = try Pipe.init(alloc, 1, &.{
        &breader,
        &swriter,
    });
    defer pipe.deinit(alloc);

    var runner = try scalarcore.Runner.create(alloc, .{});
    defer runner.deinit(alloc);

    try pipe.runAsync(alloc, runner);
    try runner.runSync(null);

    try std.testing.expectEqualStrings("Hello, world!", output.items);
}
