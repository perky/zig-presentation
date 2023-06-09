const std = @import("std");
const build_glfw = @import("lib/build_glfw.zig");
const build_nanovg = @import("lib/build_nanovg.zig");

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-presentation",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add custom build options.
    const build_with_ultralight = b.option(bool, "ultralight", "Build with Ultralight to render HTML") orelse false;
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption(bool, "ultralight", build_with_ultralight);

    const nanovg_module = build_nanovg.module(b);
    exe.addModule("nanovg", nanovg_module);
    build_nanovg.addCSource(exe);

    const glfw_lib = build_glfw.buildLib(b, target, optimize);
    exe.linkLibrary(glfw_lib);
    build_glfw.addCSource(exe);

    if (build_with_ultralight) {
        exe.addIncludePath(thisDir() ++ "/lib/ultralight/include");
        exe.addLibraryPath(thisDir() ++ "/lib/ultralight");
        exe.addRPath(thisDir() ++ "/lib/ultralight");
        exe.linkSystemLibrary("Ultralight");
        exe.linkSystemLibrary("UltralightCore");
        exe.linkSystemLibrary("WebCore");
        exe.linkSystemLibrary("AppCore");
    }

    // exe.addIncludePath(thisDir() ++ "/lib/harfbuzz/zig-out/include");
    // exe.addLibraryPath(thisDir() ++ "/lib/harfbuzz/zig-out/lib");
    // exe.linkSystemLibrary("harfbuzz");

    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    // exe.install(); // zig 0.11.0-dev.1914
    b.installArtifact(exe); // zig 0.11.0-dev.3301

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    // const run_cmd = exe.run();  // zig 0.11.0-dev.1914
    const run_cmd = b.addRunArtifact(exe);  // zig 0.11.0-dev.3301

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
