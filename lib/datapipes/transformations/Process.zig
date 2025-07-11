const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Value = @import("../../datapipes.zig").Value;
const IoStream = @import("../outputs/IoStream.zig");
const Runner = @import("../Runner.zig");
const Step = @import("../Step.zig");
const Self = @This();

pub const Options = struct {
    cwd: ?[]const u8 = null,
    env_map: ?*const std.process.EnvMap = null,
    source_stream: Stream = .stdout,
    mode: std.meta.Tag(Value) = .buffered,

    pub const Stream = enum {
        stdout,
        stderr,
    };
};

step: Step,
argv: []const []const u8,
cwd: ?[]const u8,
env_map: ?*const std.process.EnvMap,
proc: ?std.process.Child,
input: ?Value,
output: ?Value,
source_stream: Options.Stream,
mode: std.meta.Tag(Value),

pub fn create(alloc: Allocator, argv: []const []const u8, options: Options) !*Step {
    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    self.* = .{
        .step = .init(@typeName(Self), .transformation, self, &.{
            .getInput = getInput,
            .getOutput = getOutput,
            .run = run,
            .deinit = deinit,
        }),
        .argv = argv,
        .cwd = options.cwd,
        .env_map = options.env_map,
        .proc = null,
        .input = null,
        .output = null,
        .source_stream = options.source_stream,
        .mode = options.mode,
    };
    return &self.step;
}

fn getInput(o: *anyopaque, alloc: Allocator, step: ?*Step, runner: *Runner) anyerror!*?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    assert(step != &self.step);
    self.input = if (step) |s| (try s.getOutput(alloc, runner)).* else null;
    return &self.input;
}

fn getOutput(o: *anyopaque, alloc: Allocator, step: ?*Step, runner: *Runner) anyerror!*?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    assert(step != &self.step);

    const proc, const needs_init = if (self.proc) |*proc| .{ proc, false } else blk: {
        self.proc = .init(self.argv, alloc);
        break :blk .{ &self.proc.?, true };
    };

    if (needs_init) {
        proc.cwd = self.cwd;
        proc.env_map = self.env_map;
        proc.stdin_behavior = .Pipe;
        proc.stdout_behavior = .Pipe;
        proc.stderr_behavior = .Pipe;

        try proc.spawn();
    }

    if ((try self.step.getInput(alloc, runner)).*) |input| {
        try runner.pushJob(alloc, writeStdin, .{ alloc, proc, input }, null);
    }

    const file = switch (self.source_stream) {
        inline else => |t| &@field(proc, @tagName(t)).?,
    };

    self.output = switch (self.mode) {
        .buffered => .{ .buffered = blk: {
            var buff = std.ArrayList(u8).init(alloc);
            defer buff.deinit();

            while (file.reader().any().readByte() catch |err| switch (err) {
                error.EndOfStream => null,
                else => return err,
            }) |byte| {
                try buff.append(byte);
            }

            break :blk .{ .unstructured = try buff.toOwnedSlice() };
        } },
        .streamed => .{ .streamed = .{ .unstructured = file.reader().any() } },
    };
    return &self.output;
}

fn run(o: *anyopaque, alloc: Allocator, _: ?*Step, runner: *Runner) !?Value {
    const self: *Self = @ptrCast(@alignCast(o));
    return (try self.step.getOutput(alloc, runner)).*;
}

fn deinit(o: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(o));
    if (self.proc) |*proc| {
        _ = proc.kill() catch undefined;
        _ = proc.wait() catch undefined;
    }
    if (self.output) |*out| out.deinit(alloc);
    alloc.destroy(self);
}

fn writeStdin(alloc: Allocator, proc: *std.process.Child, input: Value) anyerror!?Value {
    var stream = try input.asStream(alloc);
    defer {
        stream.deinit(alloc);
        proc.stdin.?.close();
        proc.stdin = null;
    }

    var reader = stream.reader() orelse return error.InvalidValue;

    while (reader.any().readByte() catch |err| switch (err) {
        error.EndOfStream => null,
        else => return err,
    }) |byte| {
        _ = try proc.stdin.?.write(&.{byte});
    }

    return null;
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
            const self = try create(a, &.{ "cat", "lib/" ++ @src().file }, .{});
            defer self.unref(a);

            const io_stream = try IoStream.create(a, o.writer().any());
            defer io_stream.unref(a);

            io_stream.pipe(a, self);

            return try io_stream.run(a, r);
        }
    }).func, .{ alloc, &output, &runner }, null);
    try runner.run();

    try std.testing.expectEqualStrings(@embedFile("Process.zig"), output.items);
}
