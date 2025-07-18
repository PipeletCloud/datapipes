const std = @import("std");
const Allocator = std.mem.Allocator;
const scalecore = @import("scalarcore");
const Pipe = @import("../Pipe.zig");
const Step = @import("../Step.zig");
const Self = @This();

const Data = struct {
    buff: []const u8,

    fn cast(ptr: ?*anyopaque) *Data {
        return @ptrCast(@alignCast(ptr orelse unreachable));
    }

    fn deinit(self: *Data, alloc: Allocator) void {
        alloc.free(self.buff);
        alloc.destroy(self);
    }
};

pub fn create(alloc: Allocator, buff: []const u8) !Step {
    const data = try alloc.create(Data);
    errdefer alloc.destroy(data);

    const owned_buff = try alloc.dupe(u8, buff);
    errdefer alloc.free(owned_buff);

    data.* = .{
        .buff = owned_buff,
    };

    return .init(@typeName(Self), workCallback, data, deinitCallback);
}

fn workCallback(
    step: *Step,
    _: []const *Step,
    pipe: *Pipe,
    alloc: Allocator,
    _: *scalecore.Runner,
    userdata: ?*anyopaque,
) anyerror!bool {
    _ = try pipe.writeSync(step, alloc, Data.cast(userdata).buff);
    return false;
}

fn deinitCallback(userdata: ?*anyopaque, alloc: Allocator) void {
    return Data.cast(userdata).deinit(alloc);
}
