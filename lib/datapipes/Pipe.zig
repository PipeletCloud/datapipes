const std = @import("std");
const Allocator = std.mem.Allocator;
const closure = @import("closure");
const scalecore = @import("scalarcore");
const Step = @import("Step.zig");
const Self = @This();

write_buffer_lock: std.Thread.Mutex,
read_buffer_lock: std.Thread.Mutex,
ring_buffer: std.RingBuffer,
steps: []const *Step,

pub fn init(alloc: Allocator, min_size: usize, steps: []const *Step) !Self {
    return .{
        .write_buffer_lock = .{},
        .read_buffer_lock = .{},
        .ring_buffer = try .init(alloc, @min(min_size, 1)),
        .steps = steps,
    };
}

pub fn runSync(self: *Self, alloc: Allocator, runner: *scalecore.Runner) !void {
    const i = self.steps.len - 1;
    const root_step = self.steps[i];
    _ = try root_step.runSync(self, self.steps[0..i], alloc, runner);
}

pub fn runAsync(self: *Self, alloc: Allocator, runner: *scalecore.Runner) !void {
    const i = self.steps.len - 1;
    const root_step = self.steps[i];
    try root_step.runAsync(self, self.steps[0..i], alloc, runner);
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    self.ring_buffer.deinit(alloc);
}

pub fn writeSync(self: *Self, step: *Step, alloc: Allocator, slice: []const u8) !usize {
    self.write_buffer_lock.lock();
    defer self.write_buffer_lock.unlock();

    if (self.ring_buffer.len() + slice.len > self.ring_buffer.data.len) {
        self.ring_buffer.data = try alloc.realloc(self.ring_buffer.data, self.ring_buffer.data.len + slice.len);
    }

    try self.ring_buffer.writeSlice(slice);
    return step.atomic_tx.fetchAdd(slice.len, .acq_rel);
}

pub fn readSync(self: *Self, step: *Step, alloc: Allocator, size: usize) ![]const u8 {
    self.read_buffer_lock.lock();
    defer self.read_buffer_lock.unlock();

    const slice = try alloc.alloc(u8, size);
    errdefer alloc.free(slice);

    const init_rx = step.atomic_rx.load(.acquire);
    const total_rx = init_rx + size;

    var i: usize = 0;
    while ((init_rx + i) < total_rx) {
        if (self.ring_buffer.read()) |byte| {
            slice[i] = byte;
            i += 1;
        }
    }

    step.atomic_rx.store(total_rx, .release);
    return slice;
}

pub fn streamWriteAsync(self: *Self, step: *Step, parents: []const *Step, alloc: Allocator, runner: *scalecore.Runner, writer: std.io.AnyWriter) !bool {
    self.read_buffer_lock.lock();
    defer self.read_buffer_lock.unlock();

    const source_step = parents[parents.len - 1];

    if (source_step.state() == .waiting) {
        _ = try source_step.runSync(self, parents[0..(parents.len - 1)], alloc, runner);
    }

    while (self.ring_buffer.read()) |byte| {
        _ = step.atomic_rx.fetchAdd(1, .acq_rel);
        _ = step.atomic_tx.fetchAdd(1, .acq_rel);
        try writer.writeByte(byte);
    }

    return source_step.state() == .done;
}

test {
    std.testing.refAllDecls(@This());
}
