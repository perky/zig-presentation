const std = @import("std");

inline fn glfwDir() []const u8 {
    return thisDir() ++ "/glfw-3.3.8/";
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn buildLib(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.Build.CompileStep {
    const glfw_dir = glfwDir();
    const glfw_lib = b.addStaticLibrary(.{
        .name = "glfw",
        .target = target,
        .optimize = optimize,
    });
    glfw_lib.linkLibC();
    const glfw_src_dir = glfw_dir ++ "src/";
    const src_dir = thisDir() ++ "/src/";
    _ = src_dir;

    glfw_lib.addIncludePath(glfw_dir ++ "include/");
    glfw_lib.addIncludePath(glfw_dir ++ "deps/");

    const host = (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target;
    switch (host.os.tag) {
        .macos => {
            glfw_lib.linkFramework("IOKit");
            glfw_lib.linkFramework("CoreFoundation");
            glfw_lib.linkFramework("Cocoa");
            glfw_lib.linkFramework("OpenGL");
            glfw_lib.addCSourceFiles(&.{
                glfw_src_dir ++ "monitor.c",
                glfw_src_dir ++ "init.c",
                glfw_src_dir ++ "vulkan.c",
                glfw_src_dir ++ "input.c",
                glfw_src_dir ++ "context.c",
                glfw_src_dir ++ "window.c",
                glfw_src_dir ++ "osmesa_context.c",
                glfw_src_dir ++ "egl_context.c",
                glfw_src_dir ++ "nsgl_context.m",
                glfw_src_dir ++ "posix_thread.c",
                glfw_src_dir ++ "cocoa_time.c",
                glfw_src_dir ++ "cocoa_joystick.m",
                glfw_src_dir ++ "cocoa_init.m",
                glfw_src_dir ++ "cocoa_window.m",
                glfw_src_dir ++ "cocoa_monitor.m",
                glfw_dir ++ "deps/glad_gl.c",
            }, &.{"-D_GLFW_COCOA"});
        },
        else => unreachable,
    }

    return glfw_lib;
}

pub fn addCSource(exe: anytype) void {
    exe.addIncludePath(glfwDir() ++ "include/");
}
