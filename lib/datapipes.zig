const std = @import("std");

pub const Value = union(enum) {
    buffered: Buffered,
    streamed: Streamed,

    pub const Structured = @import("datapipes/Value/Structured.zig");

    pub const Buffered = union(enum) {
        structured: Structured,
        unstructured: []const u8,
    };

    pub const Streamed = union(enum) {
        structured: Structured.Stream,
        unstructured: std.io.AnyReader,
    };

    test {
        _ = Structured;
        _ = Buffered;
        _ = Streamed;
    }
};

pub const Runner = @import("datapipes/Runner.zig");

test {
    _ = Value;
    _ = Runner;
}
