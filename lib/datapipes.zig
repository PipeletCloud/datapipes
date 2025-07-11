const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    buffered: Buffered,
    streamed: Streamed,

    pub const Structured = @import("datapipes/Value/Structured.zig");

    pub const Buffered = union(enum) {
        structured: Structured,
        unstructured: []const u8,

        pub fn toStream(self: *const Buffered, alloc: Allocator) !Streamed {
            return switch (self.*) {
                .structured => |*v| .{ .structured = try v.toStream(alloc) },
                .unstructured => |v| .{ .unstructured_fb = std.io.fixedBufferStream(v) },
            };
        }

        pub fn dupe(self: *const Buffered, alloc: Allocator) !Buffered {
            return switch (self.*) {
                .structured => |*v| .{ .structured = try v.dupe(alloc) },
                .unstructured => |v| .{ .unstructured = try alloc.dupe(u8, v) },
            };
        }

        pub fn deinit(self: *Buffered, alloc: Allocator) void {
            return switch (self.*) {
                .structured => |*v| v.deinit(alloc),
                .unstructured => |v| alloc.free(v),
            };
        }
    };

    pub const Streamed = union(enum) {
        structured: *Structured.Stream,
        unstructured_fb: std.io.FixedBufferStream([]const u8),
        unstructured: std.io.AnyReader,

        pub const Reader = union(enum) {
            fbs: std.io.FixedBufferStream([]const u8).Reader,
            _any: std.io.AnyReader,

            pub fn read(self: *Reader, buff: []u8) !usize {
                return switch (self.*) {
                    inline else => |*v| v.read(buff),
                };
            }

            pub fn any(self: *Reader) std.io.GenericReader(*Reader, anyerror, read) {
                return .{ .context = self };
            }
        };

        pub fn reader(self: *Streamed) ?Reader {
            return switch (self.*) {
                .structured => null,
                .unstructured_fb => |*fb| .{ .fbs = fb.reader() },
                .unstructured => |r| .{ ._any = r },
            };
        }

        pub fn dupe(self: *const Streamed, alloc: Allocator) !Streamed {
            return switch (self.*) {
                .structured => |v| .{ .structured = try v.dupe(alloc) },
                .unstructured_fb => |v| .{ .unstructured_fb = v },
                .unstructured => |v| .{ .unstructured = v },
            };
        }

        pub fn deinit(self: *Streamed, alloc: Allocator) void {
            return switch (self.*) {
                .structured => |v| v.deinit(alloc),
                .unstructured_fb => {},
                .unstructured => {},
            };
        }
    };

    pub fn asStream(self: *const Value, alloc: Allocator) !Streamed {
        return switch (self.*) {
            .buffered => |*v| try v.toStream(alloc),
            .streamed => |*v| try v.dupe(alloc),
        };
    }

    pub fn dupe(self: *const Value, alloc: Allocator) !Value {
        return switch (self.*) {
            inline else => |*v, t| @unionInit(Value, @tagName(t), try v.dupe(alloc)),
        };
    }

    pub fn deinit(self: *Value, alloc: Allocator) void {
        return switch (self.*) {
            inline else => |*v| v.deinit(alloc),
        };
    }

    test {
        _ = Structured;
        _ = Buffered;
        _ = Streamed;
    }
};

pub const outputs = @import("datapipes/outputs.zig");
pub const sources = @import("datapipes/sources.zig");

pub const Runner = @import("datapipes/Runner.zig");
pub const Output = @import("datapipes/Output.zig");
pub const Source = @import("datapipes/Source.zig");
pub const Step = @import("datapipes/Step.zig");

test {
    _ = outputs;
    _ = sources;

    _ = Value;
    _ = Runner;
    _ = Output;
    _ = Source;
    _ = Step;
}
