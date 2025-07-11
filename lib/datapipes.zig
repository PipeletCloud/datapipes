const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    buffered: Buffered,
    streamed: Streamed,

    pub const Structured = @import("datapipes/Value/Structured.zig");

    pub const Buffered = union(enum) {
        structured: Structured,
        unstructured: []const u8,

        pub fn deinit(self: *Buffered, alloc: Allocator) void {
            return switch (self.*) {
                .structured => |*v| v.deinit(alloc),
                .unstructured => |v| alloc.free(v),
            };
        }
    };

    pub const Streamed = union(enum) {
        structured: Structured.Stream,
        unstructured: std.io.AnyReader,

        pub fn deinit(self: *Streamed, alloc: Allocator) void {
            return switch (self.*) {
                .structured => |*v| v.deinit(alloc),
                .unstructured => {},
            };
        }
    };

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
