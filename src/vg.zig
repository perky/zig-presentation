pub const Nanovg = @import("nanovg");
const std = @import("std");
const types = @import("types.zig");
const TextEditor = @import("text_editor.zig");
const rich_text = @import("rich_text.zig");
const ImageMode = types.Image.Mode;
const Slide = types.Slide;
const Presentation = types.Presentation;
const AppState = types.AppState;
const Allocator = std.mem.Allocator;
const c = @import("c.zig");

pub const sad_img_data = @embedFile("res/sad.jpg");
pub var sad_img: Nanovg.Image = undefined;

const fonts = struct {
    pub const bold = @embedFile("res/Roboto-Bold.ttf");
    pub const mono = @embedFile("res/DejaVuSansMono.ttf");
    pub fn init(vg: Nanovg) void {
        _ = vg.createFontMem("sans-bold", bold);
        _ = vg.createFontMem("mono", mono);
    }
};

pub fn initNanovg(allocator: std.mem.Allocator) !Nanovg {
    const vg = try Nanovg.gl.init(allocator, .{ .antialias = true, .stencil_strokes = false, .debug = true });
    fonts.init(vg);
    sad_img = vg.createImageMem(sad_img_data, .{ .repeat_x = true, .repeat_y = true });
    return vg;
}

pub fn drawPresentation(vg: Nanovg, presentation: Presentation, time: f32, size: [2]f32) !void {
    const f_win_width = size[0];
    const f_win_height = size[1];
    if (presentation.slides.items.len == 0) {
        return;
    }
    var slide = &presentation.slides.items[presentation.slide_index % presentation.slides.items.len];

    const background = if (slide.background) |b| b else presentation.default_background;
    switch (background) {
        .color => |color| {
            vg.beginPath();
            vg.rect(0, 0, f_win_width, f_win_height);
            vg.fillColor(Nanovg.rgb(color[0], color[1], color[2]));
            vg.fill();
        },
        .image => |img| {
            vgImage(vg, 0, 0, f_win_width, f_win_height, img, .fill);
        },
    }

    for (slide.images.items) |image| {
        const x = f_win_width * image.slot.x;
        const y = f_win_height * image.slot.y;
        const w = f_win_width * image.slot.w;
        const h = f_win_height * image.slot.h;
        vgImage(vg, x, y, w, h, image.handle, image.mode);
    }

    // Draw title.
    vg.fontSize(slide.title_style.size);
    vg.fontFace("sans-bold");
    vg.textAlign(.{ .horizontal = slide.title_style.align_h, .vertical = .middle });
    vg.fillColor(colorFrom3u8(slide.title_style.color));
    const title_rect = getRectFromSlot(slide.title_slot, size);
    vgTextBoxRect(vg, title_rect, slide.title);

    if (slide.code_editor) |editor| {
        const editor_slot = getRectFromSlot(Slide.default_body_slot, size);
        editorDraw(vg, editor, time, editor_slot);
    } else {
        // Draw bodies.
        for (slide.bodies.items) |body| {
            vg.fontSize(body.style.size);
            vg.textAlign(.{ .horizontal = .left, .vertical = .baseline });
            vg.fillColor(colorFrom3u8(body.style.color));
            var fbs = std.io.fixedBufferStream(body.text.items);
            var body_reader = fbs.reader();
            var body_line_buf: [2048]u8 = undefined;
            const rect = getRectFromSlot(body.slot, size);
            var y: f32 = 0;
            while (try body_reader.readUntilDelimiterOrEof(&body_line_buf, '\n')) |line| {
                if (line.len == 0) {
                    y += body.style.size;
                    continue;
                }
                const align_h: rich_text.TextHorizontalAlign = switch (body.style.align_h) {
                    .left => .left,
                    .center => .center,
                    .right => .right,
                    else => .left,
                };
                const m_result = rich_text.drawTextMultiline(vg, rect[2], rect[0], rect[1] + y, align_h, .word, line);
                if (m_result) |result| {
                    y += (result.rect[3] * 1.0) + (result.line_height * 0.2);
                }
                
            }
        }
    }

    if (presentation.show_notes and slide.notes.items.len > 0) {
        const x = f_win_width * 0.05;
        const w = f_win_width * 0.9;
        const y = f_win_height * 0.9;
        const noteSize = 20;
        vg.fontSize(noteSize);
        vg.textAlign(.{ .horizontal = .left, .vertical = .baseline });
        vg.fillColor(Nanovg.rgb(0,0,0));
        _ = rich_text.drawTextMultiline(vg, w, x+3, y+3, .center, .word, slide.notes.items);
        vg.fillColor(Nanovg.rgb(255, 255, 255));
        _ = rich_text.drawTextMultiline(vg, w, x, y, .center, .word, slide.notes.items);
    }
}

pub fn drawCompileCodeOutput(vg: Nanovg, frame_arena: Allocator, compile_code_state: *AppState.CompileCodeState, time: f32, size: [2]f32) !void {
    // Draw editor stdout/err.
    const m_message = blk: {
        if (compile_code_state.mutex.tryLock()) {
            defer compile_code_state.mutex.unlock();
            if (!compile_code_state.show_result) break :blk null;

            if (compile_code_state.stderr) |editor_stderr| {
                if (editor_stderr.len > 0) {
                    const text = frame_arena.dupe(u8, editor_stderr) catch "error";
                    break :blk .{ .text = text, .color = Nanovg.rgba(255, 50, 50, 255) };
                }
            }

            if (compile_code_state.stdout) |editor_stdout| {
                if (editor_stdout.len > 0) {
                    const text = frame_arena.dupe(u8, editor_stdout) catch "error";
                    break :blk .{ .text = text, .color = Nanovg.rgba(255, 255, 255, 255) };
                }
            }
        }
        break :blk null;
    };

    if (m_message) |message| {
        const box_rect = getRectFromSlot(Slide.default_body_slot, size);
        vg.beginPath();
        vgRect(vg, box_rect);
        vg.fillColor(Nanovg.rgba(0, 0, 0, 240));
        vg.fill();

        const text_rect = rectPadding(box_rect, 50);
        vg.fontFace("mono");
        vg.fontSize(18);
        vg.textAlign(.{ .horizontal = .left, .vertical = .top });
        vg.fillColor(message.color);
        vgTextBoxRect(vg, text_rect, message.text);
    } else if (compile_code_state.compiling) {
        const box_rect = getRectFromSlot(Slide.default_body_slot, size);
        vg.beginPath();
        vgRect(vg, box_rect);
        vg.fillColor(Nanovg.rgba(0, 0, 0, 150));
        vg.fill();
        vgSpinner(vg, size[0] * 0.5, size[1] * 0.5, 40, @floatCast(f32, time));
    }
}

const CustomStyle = enum { wiggle, pulse, highlight, flash_blue, flash_red, flash_green };

pub fn customStyleCallback(vg: Nanovg, userdata: ?*anyopaque, style_name: []const u8, text: []const u8, x_cursor: f32, y_cursor: f32) void {
    var app_state = @ptrCast(*AppState, @alignCast(@alignOf(AppState), userdata));

    vg.save();
    defer vg.restore();
    const time: f32 = @floatCast(f32, app_state.time);
    const cursor_x = @floatCast(f32, app_state.cursor_x);
    const cursor_y = @floatCast(f32, app_state.cursor_y);

    const style_tag = std.meta.stringToEnum(CustomStyle, style_name);
    if (style_tag == null) {
        std.debug.panic("Unknown style tag {s}", .{style_name});
    }
    switch (style_tag.?) {
        .wiggle => {
            const speed: f32 = 4.0;
            const freq: f32 = 0.7;
            const amp: f32 = 0.4;
            var x: f32 = x_cursor;
            for (text, 0..) |char, i| {
                const phase = @intToFloat(f32, i);
                const str = &[_]u8{char};
                var char_bounds: [4]f32 = undefined;
                const char_width = vg.textBounds(0, 0, str, &char_bounds);
                const y_offset: f32 = @sin(time * speed + (phase * freq)) * char_bounds[3] * amp;

                vg.translate(0, y_offset);
                _ = vg.text(x, y_cursor, str);
                x += char_width;
                vg.translate(0, -y_offset);
            }
        },

        .pulse => {
            const speed: f32 = 4.0;
            const scale: f32 = ((@sin(time * speed) + 1.0 * 0.5) * 0.1) + 0.9;
            var bounds: [4]f32 = undefined;
            _ = vg.textBounds(0, 0, text, &bounds);
            const width = bounds[2] - bounds[0];
            const height = 0;
            vg.translate(x_cursor + (width / 2.0), y_cursor + (height / 2.0));
            vg.scale(scale, scale);
            vg.translate(-(width / 2.0), -(height / 2.0));
            _ = vg.text(0, 0, text);
        },

        .highlight => {
            var bounds: [4]f32 = undefined;
            _ = vg.textBounds(x_cursor, y_cursor, text, &bounds);
            const expansion: f32 = 10;
            bounds[0] -= expansion;
            bounds[1] -= expansion;
            bounds[2] += expansion;
            bounds[3] += expansion;
            if (cursor_x > bounds[0] and cursor_x < bounds[2] and cursor_y > bounds[1] and cursor_y < bounds[3]) {
                vg.strokeColor(Nanovg.hsl(0.5, 0.0, 1.0));
                vg.beginPath();
                vg.rect(bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1]);
                vg.stroke();
                vg.fillColor(Nanovg.hsl(0.4, 1.0, 0.8));
                _ = vg.text(x_cursor, y_cursor, text);
            } else {
                _ = vg.text(x_cursor, y_cursor, text);
            }
        },

        .flash_blue, .flash_red, .flash_green => {
            const eql = std.mem.eql;
            const flash_color = blk: {
                if (eql(u8, style_name, "flash_blue")) {
                    break :blk Nanovg.hsl(0.6, 0.9, 0.6);
                } else if (eql(u8, style_name, "flash_red")) {
                    break :blk Nanovg.hsl(0.0, 0.9, 0.6);
                } else if (eql(u8, style_name, "flash_green")) {
                    break :blk Nanovg.hsl(0.4, 0.9, 0.6);
                }
                break :blk Nanovg.hsl(0.0, 0.0, 0.0);
            };
            const current_color = vg.ctx.getState().fill.inner_color;
            const theta: f32 = @sin(time * 2.25) + 1.0 * 0.5;

            vg.fillColor(Nanovg.lerpRGBA(current_color, flash_color, theta));
            _ = vg.text(x_cursor, y_cursor, text);
        },
    }
}

const EditorRenderParams = types.EditorRenderParams;
const EditorCursorState = types.EditorCursorState;

/// Returns the rendering interface to pass to TextEditor draw functions.
pub fn editorInterface(draw_params: *const EditorRenderParams, cursor_state: ?*EditorCursorState) TextEditor.RendererInterface {
    // zig fmt: off
    return .{
        .draw_glyph_fn = editorDrawGlyph,
        .cursor_rect_fn = editorCursorRect,
        .draw_cursor_rect_fn = editorDrawCursorRect,
        .mutable_userdata = cursor_state,
        .userdata = draw_params
    };
    // zig fmt: on
}

pub fn editorDraw(vg: Nanovg, code_editor: *TextEditor, time: f32, bounds: [4]f32) void {
    // Setup parameters for text editor renderer.
    const params = EditorRenderParams{ .vg = vg, .x = bounds[0], .y = bounds[1], .cursor_color = Nanovg.rgba(111, 111, 111, 128), .text_color = Nanovg.rgb(255, 255, 255), .time = time };
    const code_editor_renderer = editorInterface(&params, null);
    vg.save();
    defer vg.restore();
    vg.fontSize(25.0);
    vg.fontFace("mono");
    vg.textAlign(.{ .horizontal = .left, .vertical = .top });
    vg.translate(params.x, params.y);
    vg.fillColor(params.text_color);
    code_editor.drawBuffer(code_editor_renderer);
    code_editor.drawCursor(code_editor_renderer);
}

pub fn editorDrawGlyph(char: u8, x: i32, y: i32, userdata: *const anyopaque) void {
    const params = TextEditor.castUserdata(EditorRenderParams, userdata);
    const pos = .{
        .x = @intToFloat(f32, x),
        .y = @intToFloat(f32, y),
    };
    _ = params.vg.text(pos.x, pos.y, &[1]u8{char});
}

pub fn editorCursorRect(col: i32, row: i32, userdata: *const anyopaque) TextEditor.RectangleInt {
    const params = TextEditor.castUserdata(EditorRenderParams, userdata);
    var bounds: [4]f32 = undefined;
    _ = params.vg.textBounds(0, 0, "X", &bounds);
    const col_f = @intToFloat(f32, col);
    const row_f = @intToFloat(f32, row);
    const w = bounds[2] + 0;
    const h = bounds[3] * 1.2;
    const x = col_f * (w);
    const y = row_f * (h);
    // zig fmt: off
    return TextEditor.RectangleInt{
        .x = @floatToInt(i32, x),
        .y = @floatToInt(i32, y),
        .width = @floatToInt(i32, bounds[2]),
        .height = @floatToInt(i32, bounds[3])
    };
    // zig fmt: on
}

pub fn editorDrawCursorRect(rect: TextEditor.RectangleInt, mutable_userdata: ?*anyopaque, userdata: *const anyopaque) void {
    _ = mutable_userdata;
    const params = TextEditor.castUserdata(EditorRenderParams, userdata);
    params.vg.beginPath();
    // zig fmt: off
    params.vg.rect(
        @intToFloat(f32, rect.x), 
        @intToFloat(f32, rect.y), 
        @intToFloat(f32, rect.width), 
        @intToFloat(f32, rect.height));
    // zig fmt: on
    var alpha: u8 = if (@mod(params.time, params.blink_duration) < params.blink_duration * 0.5)
        50
    else
        230;
    params.vg.fillColor(Nanovg.transRGBA(params.cursor_color, alpha));
    params.vg.fill();
}

pub fn rectPadding(rect: [4]f32, padding: f32) [4]f32 {
    var result = rect;
    result[0] += padding;
    result[1] += padding;
    result[2] -= padding * 2;
    result[3] -= padding * 2;
    return result;
}

fn getRectFromSlot(slot: Slide.Slot, slide_size: [2]f32) [4]f32 {
    const f_win_width: f32 = slide_size[0];
    const f_win_height: f32 = slide_size[1];
    return .{ f_win_width * slot.x, f_win_height * slot.y, f_win_width * slot.w, f_win_height * slot.h };
}

pub fn colorFrom3u8(rgb: [3]u8) Nanovg.Color {
    return Nanovg.rgb(rgb[0], rgb[1], rgb[2]);
}

pub fn vgRect(vg: Nanovg, rect: [4]f32) void {
    vg.rect(rect[0], rect[1], rect[2], rect[3]);
}

pub fn vgTextBoxRect(vg: Nanovg, rect: [4]f32, text: []const u8) void {
    vg.textBox(rect[0], rect[1], rect[2], text);
}

pub fn vgImage(vg: Nanovg, x: f32, y: f32, w: f32, h: f32, image: Nanovg.Image, mode: ImageMode) void {
    const img_size: [2]f32 = blk: {
        var img_w: i32 = undefined;
        var img_h: i32 = undefined;
        vg.imageSize(image, &img_w, &img_h);
        break :blk [2]f32{ @intToFloat(f32, img_w), @intToFloat(f32, img_h) };
    };

    const is_landscape = (img_size[0] > img_size[1]);
    const aspect = if (is_landscape)
        img_size[0] / img_size[1]
    else
        img_size[1] / img_size[0];

    const ptn_size: [2]f32 = blk: {
        switch (mode) {
            .repeat => break :blk .{ img_size[0], img_size[1] },
            .fit_w => {
                const aspect_ = if (is_landscape) (1 / aspect) else aspect;
                break :blk .{ w, w * aspect_ };
            },
            .fit_h => {
                const aspect_ = if (is_landscape) aspect else (1 / aspect);
                break :blk .{ h * aspect_, h };
            },
            .fill => {
                if (!is_landscape) {
                    if (w * aspect < h) {
                        break :blk .{ h * (1 / aspect), h };
                    } else {
                        break :blk .{ w, w * aspect };
                    }
                } else {
                    if (h * aspect < w) {
                        break :blk .{ w, w * (1 / aspect) };
                    } else {
                        break :blk .{ h * aspect, h };
                    }
                }
            },
        }
    };
    var img_pattern = vg.imagePattern(x, y, ptn_size[0], ptn_size[1], 0, image, 1.0);
    vg.beginPath();
    vg.rect(x, y, w, h);
    vg.fillPaint(img_pattern);
    vg.fill();
}

pub fn vgSpinner(vg: Nanovg, cx: f32, cy: f32, r: f32, t: f32) void {
    const a0 = 0.0 + t * 6;
    const a1 = std.math.pi + t * 6;
    const r0 = r;
    const r1 = r * 0.75;

    vg.save();
    defer vg.restore();

    vg.beginPath();
    vg.arc(cx, cy, r0, a0, a1, .cw);
    vg.arc(cx, cy, r1, a1, a0, .ccw);
    vg.closePath();
    const ax = cx + @cos(a0) * (r0 + r1) * 0.5;
    const ay = cy + @sin(a0) * (r0 + r1) * 0.5;
    const bx = cx + @cos(a1) * (r0 + r1) * 0.5;
    const by = cy + @sin(a1) * (r0 + r1) * 0.5;
    const paint = vg.linearGradient(ax, ay, bx, by, Nanovg.rgba(255, 255, 255, 0), Nanovg.rgba(255, 255, 255, 128));
    vg.fillPaint(paint);
    vg.fill();
}

pub const ImageCache = struct {
    allocator: std.mem.Allocator,
    images: std.StringArrayHashMap(Nanovg.Image),
    vg: Nanovg,

    pub fn init(allocator: std.mem.Allocator, vg: Nanovg) ImageCache {
        return .{ .allocator = allocator, .images = std.StringArrayHashMap(Nanovg.Image).init(allocator), .vg = vg };
    }

    pub fn deinit(self: *ImageCache) void {
        for (self.images) |img| {
            self.vg.deleteImage(img);
        }
        self.images.deinit();
        self.* = undefined;
    }

    pub fn getOrCreateImage(self: *ImageCache, path: []const u8) !Nanovg.Image {
        if (self.images.get(path)) |img| {
            return img;
        } else {
            const img = try self.vg.createImageFile(self.allocator, path, .{ .repeat_x = true, .repeat_y = true });
            try self.images.put(path, img);
            return img;
        }
    }
};
