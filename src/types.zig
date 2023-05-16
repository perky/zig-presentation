const std = @import("std");
const vg_lib = @import("vg.zig");
const Nanovg = vg_lib.Nanovg;
const TextEditor = @import("text_editor.zig");
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;
const Allocator = std.mem.Allocator;

pub const ImageHandle = Nanovg.Image;
pub const V4 = @Vector(4, f32);
const stdout = std.io.getStdOut().writer();

pub const AppState = struct {
    arena: std.heap.FixedBufferAllocator,
    vg: Nanovg,
    delta_time: f64 = 1,
    time: f64 = 0,
    cursor_x: f64 = 0,
    cursor_y: f64 = 0,
    compile_code_state: CompileCodeState = .{},
    presentation: ?Presentation = null,
    image_cache: vg_lib.ImageCache = undefined,
    color_presets: StringArrayHashMap([3]u8) = undefined,
    parse_err: ArrayList(u8) = undefined,

    pub const CompileCodeState = struct { 
        mutex: std.Thread.Mutex = .{}, 
        stdout: ?[]u8 = null, 
        stderr: ?[]u8 = null, 
        show_result: bool = false, 
        compiling: bool = false
    };

    pub fn init(arena: std.heap.FixedBufferAllocator, vg: Nanovg) AppState {
        var state: AppState = .{
            .arena = arena,
            .vg = vg,
        };
        return state;
    }
};

pub const Presentation = struct {
    slides: ArrayList(Slide),
    slots: StringArrayHashMap(Slide.Slot),
    code_editors: StringArrayHashMap(TextEditor) = undefined,
    slide_index: usize = 0,
    default_background: Slide.Background = .{ .color = .{ 0, 0, 0 } },
    show_notes: bool = false,
    pub fn init(arena: Allocator) Presentation {
        return .{ 
            .slides = ArrayList(Slide).init(arena), 
            .slots = StringArrayHashMap(Slide.Slot).init(arena),
            .code_editors = StringArrayHashMap(TextEditor).init(arena),
        };
    }
    pub fn nextSlide(self: *Presentation) void {
        self.slide_index +%= 1;
        self.printSlideInfo();
    }
    pub fn previousSlide(self: *Presentation) void {
        self.slide_index -%= 1;
        self.printSlideInfo();
    }
    pub fn printSlideInfo(self: *Presentation) void {
        const slide_idx = self.slide_index % self.slides.items.len;
        const slide = &self.slides.items[slide_idx];
        stdout.print("Slide {d}/{d} # {s}\n", .{slide_idx + 1, self.slides.items.len + 1, slide.title}) catch {};
        if (slide.notes.items.len > 0) {
            stdout.print("Notes: {s}\n", .{slide.notes.items}) catch {};
        }
        stdout.writeAll("\n") catch {};
    }
};

pub const Image = struct {
    handle: ImageHandle,
    slot: Slide.Slot,
    mode: Mode,
    pub const Mode = enum { fill, repeat, fit_w, fit_h };
};

pub const Slide = struct {
    title: []const u8,
    title_style: TextStyle = default_title_style,
    title_slot: Slot = default_title_slot,
    background: ?Background = null,
    code_editor: ?*TextEditor = null,
    code_editor_name: []const u8 = "",
    code_editor_slot: Slot = default_body_slot,
    code_editor_style: TextStyle = default_code_editor_style,
    notes: ArrayList(u8),

    bodies: ArrayList(Body),
    images: ArrayList(Image),

    pub const Background = union(enum) { color: [3]u8, image: ImageHandle };
    pub const Body = struct { text: ArrayList(u8), lines: usize = 0, slot: Slot = default_body_slot, style: TextStyle = default_body_style };
    pub const TextStyle = struct { size: f32, align_h: HAlign, color: [3]u8 };
    pub const Slot = struct { name: []const u8, x: f32, y: f32, w: f32, h: f32 };
    pub const HAlign = Nanovg.TextAlign.HorizontalAlign;

    pub const default_title_slot = Slot{ .name = "default_title", .x = 0.1, .y = 0.12, .w = 0.8, .h = 1 };
    pub const default_title_style = TextStyle{ .size = 80, .align_h = .left, .color = [_]u8{ 255, 255, 255 } };
    pub const default_body_slot = Slot{ .name = "default_body", .x = 0.1, .y = 0.23, .w = 0.8, .h = 0.6 };
    pub const default_body_style = TextStyle{ .size = 30, .align_h = .left, .color = [_]u8{ 255, 255, 255 } };
    pub const default_code_editor_style = TextStyle{ .size = 35, .align_h = .left, .color = [_]u8{ 255, 255, 255 } };
    pub const fullscreen_slot = Slot{ .name = "fullscreen", .x = 0, .y = 0, .w = 1, .h = 1 };

    pub fn init(arena: Allocator, title: []const u8) Slide {
        // zig fmt: off
        return .{ 
            .title = title, 
            .images = ArrayList(Image).init(arena),
            .bodies = ArrayList(Body).init(arena),
            .notes = ArrayList(u8).init(arena)
        };
        // zig fmt: on
    }
};

// zig fmt: off
pub const EditorCursorState = struct {};
pub const EditorRenderParams = struct { 
    vg: Nanovg, 
    x: f32, 
    y: f32, 
    cursor_color: Nanovg.Color, 
    text_color: Nanovg.Color, 
    blink_duration: f64 = 0.5,
    time: f32
};
// zig fmt: on
