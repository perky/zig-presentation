const std = @import("std");

inline fn nanovgDir() []const u8 {
    return thisDir() ++ "/nanovg-zig";
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn module(b: *std.Build) *std.Build.Module {
    const nanovg_path = nanovgDir();
    const nanovg_module = b.createModule(.{
        .source_file = .{ .path = nanovg_path ++ "/src/nanovg.zig" },
    });
    return nanovg_module;
}

pub fn addCSource(exe: anytype) void {
    const nanovg_dir = nanovgDir();
    exe.addIncludePath(nanovg_dir ++ "/src");
    exe.addIncludePath(nanovg_dir ++ "/lib/gl2/include");
    exe.addCSourceFile(nanovg_dir ++ "/src/fontstash.c", &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" });
    exe.addCSourceFile(nanovg_dir ++ "/src/stb_image.c", &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" });
    exe.addCSourceFile(nanovg_dir ++ "/lib/gl2/src/glad.c", &.{});
}
