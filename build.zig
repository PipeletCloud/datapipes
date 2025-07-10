const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single_threaded = b.option(bool, "single-threaded", "Enable or disable threading support");

    const xev = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("datapipes", .{
        .root_source_file = b.path("lib/datapipes.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .imports = &.{
            .{
                .name = "xev",
                .module = xev.module("xev"),
            },
        },
    });

    const module_tests = b.addTest(.{
        .root_module = module,
    });

    const run_module_tests = b.addRunArtifact(module_tests);

    const doc_step = b.step("docs", "Generate documentation");

    doc_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = module_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/datapipes",
    }).step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_module_tests.step);
}
