const std = @import("std");
const c = @import("c.zig");
const vg_lib = @import("vg.zig");
const Nanovg = vg_lib.Nanovg;
const rich_text = @import("rich_text.zig");
const parse = @import("parse.zig");
const TextEditor = @import("text_editor.zig");
const html_render = @import("html_render.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const AppState = types.AppState;
const Node = parse.Node;
const Slide = types.Slide;
const Presentation = types.Presentation;

var g_presentation_window: ?*c.GLFWwindow = undefined;
var g_app_state: AppState = undefined;
var g_redirect_stderr: ?*ArrayList(u8) = null;
var g_file_mtime: i128 = 0;
var g_presentation_path: [:0]const u8 = "presentation.md";

pub const std_options = struct {
    pub const logFn = myLogFn;
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = level;
    _ = scope;
    if (g_redirect_stderr) |redirect| {
        nosuspend redirect.writer().print(format ++ "\n", args) catch return;
    } else {
        // Print the message to stderr, silently ignoring any errors
        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();
        const stderr = std.io.getStdErr().writer();
        nosuspend stderr.print(format ++ "\n", args) catch return;
    }
}

fn loadPresentation() void {
    _ = g_app_state.arena.reset();

    const pre_slide_index: usize = if (g_app_state.presentation) |p| p.slide_index else 0;

    // Make a source to redirect stderr to.
    g_app_state.parse_err = ArrayList(u8).init(g_app_state.arena.allocator());
    g_app_state.parse_err.writer().print("Failed to parse {s}.\n", .{g_presentation_path}) catch unreachable;
    g_redirect_stderr = &g_app_state.parse_err;
    // Do the parsing magic.
    g_app_state.presentation = parse.parsePresentdownFile(
        g_app_state.arena.allocator(), 
        &g_app_state.image_cache, 
        &g_app_state.color_presets,
        html_render.loaderInterface(g_app_state.html_renderer), 
        g_presentation_path) catch null;
    // Unlink the stderr redirect.
    g_redirect_stderr = null;
    // Output the stuff that was redirected, to stderr.
    if (g_app_state.presentation) |*p| {
        if (pre_slide_index != 0) {
            p.slide_index = pre_slide_index;
        }
        p.onSlideChange();
    } else {
        std.log.err("{s}", .{g_app_state.parse_err.items});
    }
}

fn toggleFullscreen() void {
    var monitor: ?*c.GLFWmonitor = c.glfwGetWindowMonitor(g_presentation_window);
    if (monitor != null) {
        c.glfwSetWindowMonitor(g_presentation_window, null, 50, 50, 1024, 768, 0);
    } else {
        const primary_monitor: ?*c.GLFWmonitor = c.glfwGetPrimaryMonitor();
        const mode: [*c]const c.GLFWvidmode = c.glfwGetVideoMode(primary_monitor);
        c.glfwSetWindowMonitor(g_presentation_window, primary_monitor, 0, 0, mode.*.width, mode.*.height, mode.*.refreshRate);
    }
}

fn initFixedArenaAllocator(allocator: Allocator, comptime bytes: usize) !std.heap.FixedBufferAllocator {
    var buffer = try allocator.alloc(u8, bytes);
    return std.heap.FixedBufferAllocator.init(buffer);
}

pub fn main() !void {
    var allocator = std.heap.c_allocator;
    var args = try std.process.argsAlloc(allocator);
    if (args.len >= 2) {
        g_presentation_path = args[1];
    }

    var parsing_arena = try initFixedArenaAllocator(allocator, 10_000_000);
    var image_cache_arena = try initFixedArenaAllocator(allocator, 50_000_000);
    var frame_arena = try initFixedArenaAllocator(allocator, 1_000_000);

    _ = c.glfwSetErrorCallback(glfwErrorCallback);
    if (c.glfwInit() == 0) {
        std.log.err("Unable to init GLFW.", .{});
        return error.Glfw;
    }

    var monitor: ?*c.GLFWmonitor = c.glfwGetPrimaryMonitor();
    var video_mode: [*c]const c.GLFWvidmode = c.glfwGetVideoMode(monitor);
    const screen_w = video_mode[0].width;
    const screen_h = video_mode[0].height;
    var window: ?*c.GLFWwindow = c.glfwCreateWindow(screen_w, screen_h, "presentation", c.glfwGetPrimaryMonitor(), null);
    g_presentation_window = window;
    
    if (window == null) {
        c.glfwTerminate();
        std.log.err("Failed to create window.", .{});
        return error.Glfw;
    }
    defer {
        c.glfwDestroyWindow(window);
        c.glfwTerminate();
    }

    _ = c.glfwSetKeyCallback(window, glfwKeyCallback);
    _ = c.glfwSetCharCallback(window, glfwCharInputCallback);
    c.glfwMakeContextCurrent(window);
    if (c.gladLoadGL() == 0) {
        return error.GLADInitFailed;
    }
    c.glfwSwapInterval(1);

    const vg = vg_lib.initNanovg(allocator) catch {
        std.log.err("Failed to init nanovg.", .{});
        return error.Nanovg;
    };
    g_app_state = AppState.init(parsing_arena, vg);
    g_app_state.image_cache = vg_lib.ImageCache.init(image_cache_arena.allocator(), vg);
    g_app_state.color_presets = std.StringArrayHashMap([3]u8).init(image_cache_arena.allocator());
    rich_text.setCustomStyleCallback(vg_lib.customStyleCallback, &g_app_state);
    
    g_app_state.html_renderer = html_render.rendererInit(allocator, @intCast(u32, screen_w), @intCast(u32, screen_h));
    var html_render_image: ?Nanovg.Image = html_render.rendererMakeImage(g_app_state.html_renderer, vg);

    loadPresentation();

    var presentation_file = try std.fs.cwd().openFile(g_presentation_path, .{ .mode = .read_only });
    defer presentation_file.close();
    g_file_mtime = (try presentation_file.stat()).mtime;

    var time_prev_frame: f64 = 0;
    var frame_counter: u64 = 0;
    while (c.glfwWindowShouldClose(window) == 0) {
        const delta_time: f64 = blk: {
            const time_this_frame: f64 = c.glfwGetTime();
            const dt = time_this_frame - time_prev_frame;
            time_prev_frame = time_this_frame;
            break :blk dt;
        };
        g_app_state.delta_time = delta_time;
        g_app_state.time += delta_time;

        c.glfwGetCursorPos(window, &g_app_state.cursor_x, &g_app_state.cursor_y);
        const win_size = getWindowSize(window);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);
        vg.beginFrame(win_size[0], win_size[1], 1.0);

        if (g_app_state.presentation) |presentation| {
            try vg_lib.drawPresentation(vg, presentation, @floatCast(f32, g_app_state.time), win_size);
            try vg_lib.drawCompileCodeOutput(vg, frame_arena.allocator(), &g_app_state.compile_code_state, @floatCast(f32, g_app_state.time), win_size);

            const slide = presentation.activeSlidePtr();
            if (slide.html_body != null) {
                html_render.rendererUpdate(g_app_state.html_renderer, vg, html_render_image);
                if (html_render_image) |ri| {
                    vg_lib.vgImage(vg, 0, 0, win_size[0], win_size[1], ri, .fill);
                }
            }
        } else {
            var x_off = @floatCast(f32, g_app_state.time*20);
            vg_lib.vgImage(vg, -x_off, win_size[1] / 2, win_size[0] + x_off, win_size[1] / 2, vg_lib.sad_img, .fit_h);
            vg.fontSize(20);
            vg.fontFace("mono");
            vg.textAlign(.{ .horizontal = .left, .vertical = .top });
            vg.fillColor(Nanovg.rgb(255, 255, 255));
            vg.textBox(50, 50, win_size[0] - 100, g_app_state.parse_err.items);
        }

        _ = frame_arena.reset();
        vg.endFrame();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();

        frame_counter += 1;

        if (frame_counter % 10 == 0) {
            const new_mtime = (try presentation_file.stat()).mtime;
            if (new_mtime != g_file_mtime) {
                g_file_mtime = new_mtime;
                loadPresentation();
            }
        }
    }
}

fn getWindowSize(window: ?*c.GLFWwindow) [2]f32 {
    var win_width: i32 = undefined;
    var win_height: i32 = undefined;
    c.glfwGetWindowSize(window, &win_width, &win_height);
    return .{ @intToFloat(f32, win_width), @intToFloat(f32, win_height) };
}

fn getActiveSlide() ?*Slide {
    if (g_app_state.presentation) |*presentation| {
        const i = presentation.slide_index;
        const len = presentation.slides.items.len;
        return &(presentation.slides.items[i % len]);
    }
    return null;
}

export fn glfwErrorCallback(_: c_int, description: [*c]const u8) void {
    std.debug.panic("GLFW Error: {s}\n", .{description});
}

export fn glfwKeyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
    _ = scancode;
    if (action == c.GLFW_REPEAT) {
        var m_slide = getActiveSlide();
        if (m_slide != null and m_slide.?.code_editor != null) {
            var editor: *TextEditor = m_slide.?.code_editor.?;
            switch (key) {
                c.GLFW_KEY_ENTER => editor.insertByte('\n'),
                c.GLFW_KEY_BACKSPACE => editor.deleteBackward(),
                c.GLFW_KEY_DELETE => editor.deleteForward(),
                c.GLFW_KEY_RIGHT => editor.moveCursorRight(&editor.cursor),
                c.GLFW_KEY_LEFT => editor.moveCursorLeft(&editor.cursor),
                c.GLFW_KEY_UP => editor.moveCursorUp(&editor.cursor),
                c.GLFW_KEY_DOWN => editor.moveCursorDown(&editor.cursor),
                c.GLFW_KEY_TAB => editor.insertBytes("  "),
                else => {},
            }
            if (mods & c.GLFW_MOD_ALT != 0) {
                switch (key) {
                    c.GLFW_KEY_RIGHT => editor.moveCursorToNextWord(&editor.cursor),
                    c.GLFW_KEY_LEFT => editor.moveCursorToPreviousWord(&editor.cursor),
                    else => {},
                }
            }
        }
    } else if (action == c.GLFW_PRESS) {
        switch (key) {
            c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(window, c.GLFW_TRUE),
            c.GLFW_KEY_F2 => loadPresentation(),
            c.GLFW_KEY_F3 => toggleFullscreen(),
            else => {},
        }

        if (g_app_state.presentation == null) return;
        var m_slide = getActiveSlide();
        if (m_slide == null) return;
        if (m_slide.?.code_editor) |editor| {
            switch (key) {
                c.GLFW_KEY_ENTER => editor.insertByte('\n'),
                c.GLFW_KEY_BACKSPACE => editor.deleteBackward(),
                c.GLFW_KEY_DELETE => editor.deleteForward(),
                c.GLFW_KEY_RIGHT => editor.moveCursorRight(&editor.cursor),
                c.GLFW_KEY_LEFT => editor.moveCursorLeft(&editor.cursor),
                c.GLFW_KEY_UP => editor.moveCursorUp(&editor.cursor),
                c.GLFW_KEY_DOWN => editor.moveCursorDown(&editor.cursor),
                c.GLFW_KEY_TAB => editor.insertBytes("  "),
                c.GLFW_KEY_HOME => editor.moveCursorToLineStart(&editor.cursor),
                c.GLFW_KEY_END => editor.moveCursorToLineEnd(&editor.cursor),
                c.GLFW_KEY_F1 => {
                    compileCode() catch |err| {
                        std.log.err("{} failed to compile presentation editor code,", .{err});
                        @panic("code runtime-compile error");
                    };
                },
                else => {},
            }
            if (mods & c.GLFW_MOD_ALT != 0) {
                switch (key) {
                    c.GLFW_KEY_RIGHT => editor.moveCursorToNextWord(&editor.cursor),
                    c.GLFW_KEY_LEFT => editor.moveCursorToPreviousWord(&editor.cursor),
                    else => {},
                }
            } else if (mods & c.GLFW_MOD_SUPER != 0) {
                switch (key) {
                    c.GLFW_KEY_RIGHT => g_app_state.presentation.?.nextSlide(),
                    c.GLFW_KEY_LEFT => g_app_state.presentation.?.previousSlide(),
                    else => {},
                }
            }
        } else {
            switch (key) {
                c.GLFW_KEY_RIGHT => g_app_state.presentation.?.nextSlide(),
                c.GLFW_KEY_LEFT => g_app_state.presentation.?.previousSlide(),
                else => {},
            }
        }
    }
}

export fn glfwCharInputCallback(window: ?*c.GLFWwindow, char: c_uint) void {
    _ = window;
    var m_slide = getActiveSlide();
    if (m_slide != null and m_slide.?.code_editor != null) {
        m_slide.?.code_editor.?.insertByte(@intCast(u8, char));
    }
}

fn compileCode() !void {
    {
        g_app_state.compile_code_state.mutex.lock();
        defer g_app_state.compile_code_state.mutex.unlock();
        if (g_app_state.compile_code_state.show_result) {
            g_app_state.compile_code_state.show_result = false;
            g_app_state.compile_code_state.compiling = false;
            return;
        }
    }

    var m_slide = getActiveSlide();
    if (m_slide) |slide| {
        if (slide.code_editor) |editor| {
            g_app_state.compile_code_state.compiling = true;
            const code = editor.getText();
            var thread = try std.Thread.spawn(.{}, compileCodeThread, .{code, slide.code_editor_name});
            thread.detach();
        }
    }
}

fn compileCodeThread(code: []const u8, name: []const u8) !void {
    var allocator = std.heap.page_allocator;
    const temp_file_path = try std.fmt.allocPrint(allocator, "./temp_{s}.zig", .{name});
    defer allocator.free(temp_file_path);
    var file = try std.fs.cwd().createFile(temp_file_path, .{});
    defer file.close();
    try file.writeAll(code);

    var args = ArrayList([]const u8).init(allocator);
    defer args.deinit();
    const arg_line_start = "//! ";
    if (std.mem.startsWith(u8, code, arg_line_start)) {
        if (std.mem.indexOf(u8, code, "\n")) |end_arg_line_i| {
            const arg_line = code[arg_line_start.len..end_arg_line_i];
            var split_iter = std.mem.split(u8, arg_line, " ");
            while (split_iter.next()) |arg_str| {
                try args.append(arg_str);
            }
        }
    }

    {
        g_app_state.compile_code_state.mutex.lock();
        defer g_app_state.compile_code_state.mutex.unlock();
        if (g_app_state.compile_code_state.stdout != null) {
            allocator.free(g_app_state.compile_code_state.stdout.?);
            g_app_state.compile_code_state.stdout = null;
        }
        if (g_app_state.compile_code_state.stderr != null) {
            allocator.free(g_app_state.compile_code_state.stderr.?);
            g_app_state.compile_code_state.stderr = null;
        }
    }

    var exec_args = ArrayList([]const u8).init(allocator);
    defer exec_args.deinit();
    try exec_args.appendSlice(&[_][]const u8{ "zig", "run", "--color", "off", temp_file_path, "--" });
    try exec_args.appendSlice(args.items);

    var result = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = exec_args.items });
    {
        g_app_state.compile_code_state.mutex.lock();
        defer g_app_state.compile_code_state.mutex.unlock();
        g_app_state.compile_code_state.stdout = result.stdout;
        g_app_state.compile_code_state.stderr = result.stderr;
        g_app_state.compile_code_state.show_result = true;
        g_app_state.compile_code_state.compiling = false;
    }
}
