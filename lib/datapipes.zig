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

pub const outputs = @import("datapipes/outputs.zig");

pub const Runner = @import("datapipes/Runner.zig");
pub const Output = @import("datapipes/Output.zig");
pub const Source = @import("datapipes/Source.zig");
pub const Step = @import("datapipes/Step.zig");

test {
    _ = outputs;

    _ = Value;
    _ = Runner;
    _ = Output;
    _ = Source;
    _ = Step;
}
