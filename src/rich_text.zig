// Rich Text Parser and Renderer.
//
// Parses a specialized rich text string, i.e. "Hello {s:50}world{/s}!".
// This works in tandem with Nanovg (a vector graphics library) to render glyphs and bitmap.
//
// Example:
// const cursor: f32 = drawTextLine(vg, 200, 10, 40, .center, "{s:50}Big{/s} {c:#FF0000}red{/c}.");
//       |                          |    |      |
//       |                          The vector graphics instance.
//       |                               |      |
//       End x-position of cursor.       Max width of the line (also used for horizontal alignments).
//                                              |
//                                              (x, y) position to start the cursor.
//
// # Rendering inline bitmaps.
// This can also render bitmaps inline with text, you have to provide your own callback function
// to provide the bitmap texture and metadata, depending on the bitmap tag.
// For example: _ = drawTextLine(vg, 200, 10, 40, .left, "icon: {img:apple}");
// Will call your callback with the tag: "apple" ([]const u8).
// The callback will also be given an anyopaque userdata you previously defined.
//
// Example:
// setTextBitmapHandler(bitmapTextureProvider, &some_custom_texture_pool);
//
// fn bitmapTextureProvider(id: []const u8, userdata: ?*anyopaque) ?TextBitmap {
//     var texture_pool = SomeCustomTexturePool.fromUserdata(userdata);
//     var texture_handle: ?Nanovg.Image = null;
//     if (std.mem.eql(u8, id, "apple")) {
//         texture_handle = texture_pool.apple_icon;
//     }
//     if (texture_handle != null) {
//         return text_render.TextBitmap{
//             .texture_handle = texture_handle.?,
//             .offset_x = 0,
//             .offset_y = 0,
//             .width = 32,
//             .height = 32
//         };
//     }
//     return null;
// }
//
// # Memory.
// This doesn't allocate any memory, the parser uses memory on the stack by default and will
// return error.OutOfMemory if the internal arrays overflow. You can provide more memory
// by calling 'allocateMemoryPool(allocator, size_bytes)', passing in your own memory allocator.
// It is the callers responsibilty to also call 'freeMemoryPool(allocator)'.
//

const std = @import("std");
const Nanovg = @import("nanovg");

pub var g_draw_debug_shapes: bool = false;
pub var g_draw_debug_underlines: bool = false;

// Bitmap texture provide callback.
pub const fn_text_bitmap_t = *const fn (id: []const u8, userdata: ?*anyopaque) ?TextBitmap;
pub fn setTextBitmapHandler(handler: fn_text_bitmap_t, userdata: ?*anyopaque) void {
    g_text_bitmap_handler = handler;
    g_text_bitmap_userdata = userdata;
}
var g_text_bitmap_handler: fn_text_bitmap_t = nullTextBitmapHandler;
var g_text_bitmap_userdata: ?*anyopaque = null;
fn nullTextBitmapHandler(_: []const u8, _: ?*anyopaque) ?TextBitmap {
    return null;
}

// User custom style callback.
pub const fn_custom_style_callback_t = *const fn (Nanovg, ?*anyopaque, []const u8, []const u8, f32, f32) void;
var g_custom_style_callback: fn_custom_style_callback_t = nullCustomStyleCallback;
var g_custom_style_userdata: ?*anyopaque = null;
pub fn setCustomStyleCallback(callback: fn_custom_style_callback_t, userdata: ?*anyopaque) void {
    g_custom_style_callback = callback;
    g_custom_style_userdata = userdata;
}
fn nullCustomStyleCallback(_: Nanovg, _: ?*anyopaque, _: []const u8, _: []const u8, _: f32, _: f32) void {}

// Memory Pool.
const MemoryPool = struct {
    chunks: []RichTextChunk,
    tokens: []RichTextToken,
};
var g_default_memory_pool_chunks: [2048]RichTextChunk = undefined;
var g_default_memory_pool_tokens: [2048]RichTextToken = undefined;
var g_memory_pool: MemoryPool = .{ .chunks = &g_default_memory_pool_chunks, .tokens = &g_default_memory_pool_tokens };
pub fn allocateMemoryPool(allocator: std.mem.Allocator, size_bytes: usize) !void {
    const max_chunks = ((size_bytes / 2) / @sizeOf(RichTextChunk));
    const max_tokens = ((size_bytes / 2) / @sizeOf(RichTextToken));
    g_memory_pool = MemoryPool{ .chunks = try allocator.alloc(RichTextChunk, max_chunks), .tokens = try allocator.alloc(RichTextToken, max_tokens) };
}
pub fn freeMemoryPool(allocator: std.mem.Allocator) void {
    allocator.free(g_memory_pool.chunks);
    allocator.free(g_memory_pool.tokens);
    g_memory_pool = MemoryPool{ .chunks = &g_default_memory_pool_chunks, .tokens = &g_default_memory_pool_tokens };
}

// Types.
// zig fmt: off
pub const TextHorizontalAlign = enum(u8) { left, center, right };
pub const TextVerticalAlign = enum(u8) { bottom, middle, top };
pub const Point = struct { x: f32, y: f32 };
pub const Size = struct { w: f32, h: f32 };
pub const Rect = struct { size: Size, top_left: Point };
pub const TextWrap = enum(u8) { none, word, character };
pub const TextBitmap = struct { 
    texture_handle: Nanovg.Image, 
    offset_x: f32, 
    offset_y: f32, 
    width: f32, 
    height: f32, 
    scale: f32 = 1.0
};
const RichTextTagType = enum {
    none,
    eof,
    text,
    bitmap,
    size,
    color,
    font,
    kerning,
    user_custom,
    pub const string_to_type = std.ComptimeStringMap(RichTextTagType, .{ 
        .{ "img", .bitmap }, 
        .{ "s", .size }, 
        .{ "c", .color }, 
        .{ "f", .font }, 
        .{ "k", .kerning },
        .{ "custom", .user_custom } 
    });
};
const RichTextTagPayload = union(enum) { 
    none: void, 
    numeric: f32, 
    color: [4]f32, 
    bitmap: TextBitmap, 
    text: []const u8,
    user_custom: UserCustomStyle,
    pub const UserCustomStyle = struct { enabled: bool, style_name: []const u8 };
};
const RichTextChunk = struct { 
    x_cursor: f32 = 0, 
    y_cursor: f32 = 0, 
    line: usize = 0, 
    width: f32 = 0, 
    bounds: [4]f32, 
    tag_type: RichTextTagType = .none, 
    tag_payload: RichTextTagPayload = .{ .none = {} } 
};
const RichTextChunksResult = struct { chunks_len: usize, final_cursor_pos: Point };
const TextMetrics = struct { ascender: f32, descender: f32, line_height: f32 };
const Result = struct { x_cursor: f32, y_cursor: f32, line_height: f32, rect: [4]f32 };
// zig fmt: on

pub fn drawTextLine(vg: Nanovg, line_width: f32, x: f32, y: f32, h_align: TextHorizontalAlign, txt: []const u8) ?Result {
    return drawText(vg, line_width, x, y, h_align, TextWrap.none, true, txt);
}

pub fn drawTextMultiline(vg: Nanovg, line_width: f32, x: f32, y: f32, h_align: TextHorizontalAlign, wrap_mode: TextWrap, txt: []const u8) ?Result {
    return drawText(vg, line_width, x, y, h_align, wrap_mode, false, txt);
}

/// Draws a single line of rich text.
/// Returns the final cursor x position (where the pen ends after writing text).
pub fn drawText(vg: Nanovg, line_width: f32, x: f32, y: f32, h_align: TextHorizontalAlign, wrap_mode: TextWrap, ignore_newlines: bool, txt: []const u8) ?Result {
    vg.save();
    defer vg.restore();
    vg.translate(x, y);
    vg.textAlign(.{ .horizontal = .left, .vertical = .baseline });
    vg.beginPath();

    const default_text_metrics = getTextMetrics(vg);

    if (g_draw_debug_shapes or g_draw_debug_underlines) {
        vg.strokeColor(Nanovg.rgba(140, 255, 0, 255));
        vg.moveTo(0, 0);
        vg.lineTo(line_width, 0);
        vg.stroke();
    }

    // Parse the rich text into chunks.
    // zig fmt: off
    const chunks_result = parseRichText(
        vg, 
        txt,
        line_width, 
        h_align, 
        wrap_mode, 
        ignore_newlines, 
        g_memory_pool.chunks) catch |err| 
    {
        std.log.err("{any}, {s}", .{ err, "failed to to parse rich text." });
        _ = vg.text(x, y, "FAILED TO PARSE");
        return null;
    };
    // zig fmt: on
    const chunks_len = chunks_result.chunks_len;
    if (chunks_len == 0) return null;

    // Indices for text bounds array.
    const X1 = 0;
    const Y1 = 1;
    const X2 = 2;
    const Y2 = 3;

    // Find the max chunk height.
    var line_height: f32 = 0;
    var out_rect: [4]f32 = .{
        0, 0, 0, default_text_metrics.line_height
    };
    for (0..chunks_len) |chunk_i| {
        const chunk = g_memory_pool.chunks[chunk_i];
        if (chunk.tag_type != .text) continue;
        out_rect[X1] = @min(out_rect[X1], chunk.bounds[X1]);
        out_rect[Y1] = @min(out_rect[Y1], chunk.bounds[Y1]);
    } 
    out_rect[X1] += x;
    out_rect[Y1] += y;
    for (0..chunks_len) |chunk_i| {
        const chunk = g_memory_pool.chunks[chunk_i];
        if (chunk.tag_type != .text) continue;
        const height = chunk.bounds[Y2] - chunk.bounds[Y1];
        const width = chunk.bounds[X2] - chunk.bounds[X1];
        line_height = @max(line_height, height);
        out_rect[2] = @max(out_rect[2], width);
        out_rect[3] = @max(out_rect[3], chunk.y_cursor - chunk.bounds[Y1]);  
    }
    
    var x_cursor: f32 = x;
    var y_cursor: f32 = y + (line_height - default_text_metrics.line_height);
    var user_custom_style: RichTextTagPayload.UserCustomStyle = .{ .enabled = false, .style_name = &[_]u8{} };

    if (g_draw_debug_shapes) {
        vg.translate(-x, -y);
        vg.beginPath();
        vg.strokeColor(Nanovg.rgba(255, 0, 0, 200));
        vg.rect(out_rect[0], out_rect[1], out_rect[2], out_rect[3]);
        vg.stroke();

        for (0..chunks_len) |chunk_i| {
            const chunk = g_memory_pool.chunks[chunk_i];
            if (chunk.tag_type != .text) continue;
            vg.beginPath();
            vg.strokeColor(Nanovg.rgba(255, 192, 0, 255));
            vg.rect(x + chunk.x_cursor, y + chunk.y_cursor, chunk.width, 1);
            vg.stroke();
        }
        vg.translate(x, y);
    }

    // Iterate over each chunk and draw it.
    for (0..chunks_len) |chunk_i| for_loop: {
        const chunk = g_memory_pool.chunks[chunk_i];
        const bounds = chunk.bounds;
        x_cursor = chunk.x_cursor;
        y_cursor = chunk.y_cursor + (line_height - default_text_metrics.line_height);
        switch (chunk.tag_type) {
            .none => unreachable, // If execution reaches here it will trigger a panic.
            // We could return an error instead, but this better signifies
            // that reaching here is a bug and not a possible runtime error.
            .eof => break :for_loop,
            .text => {
                if (user_custom_style.enabled) {
                    vg.translate(-x, -y);
                    g_custom_style_callback(vg, g_custom_style_userdata, user_custom_style.style_name, chunk.tag_payload.text, x + x_cursor, y + y_cursor);
                    vg.translate(x, y);
                } else {
                    _ = vg.text(x_cursor, y_cursor, chunk.tag_payload.text);
                }
            },
            .bitmap => {
                const text_bitmap = chunk.tag_payload.bitmap;
                const img_w = text_bitmap.width * text_bitmap.scale;
                const img_h = (bounds[Y2] - bounds[Y1]);
                const min_dim = @min(img_w, img_h);
                const max_dim = @max(img_w, img_h);
                const img_x = x_cursor + text_bitmap.offset_x + ((max_dim - min_dim) / 2);
                const img_y = y_cursor + text_bitmap.offset_y + bounds[Y1];
                const imgPaint = vg.imagePattern(img_x, img_y, min_dim, min_dim, 0.0, text_bitmap.texture_handle, 1.0);
                vg.beginPath();
                vg.rect(img_x, img_y, min_dim, min_dim);
                vg.fillPaint(imgPaint);
                vg.fill();
                if (g_draw_debug_shapes) {
                    vg.beginPath();
                    vg.rect(x_cursor + text_bitmap.offset_x, img_y, img_w, img_h);
                    vg.strokeColor(Nanovg.rgba(200, 192, 60, 255));
                    vg.stroke();
                }
            },
            // The rest of the chunk cases are "style" chunks and do not render anything onscreen.
            // Instead they mutate the vector graphics state.
            .size => {
                const size = chunk.tag_payload.numeric;
                vg.fontSize(size);
            },
            .color => {
                const color = chunk.tag_payload.color;
                vg.fillColor(Nanovg.rgbaf(color[0], color[1], color[2], color[3]));
            },
            .font => {
                setFontFace(vg, chunk.tag_payload.text);
            },
            .kerning => {
                vg.textLetterSpacing(chunk.tag_payload.numeric);
            },
            .user_custom => {
                user_custom_style = chunk.tag_payload.user_custom;
            },
        }
    }
    return Result{ .x_cursor = x_cursor, .y_cursor = y_cursor, .line_height = line_height, .rect = out_rect };
}

pub fn drawTextInRect(vg: Nanovg, rect: Rect, h_align: TextHorizontalAlign, v_align: TextVerticalAlign, wrap_mode: TextWrap, txt: []const u8) Point {
    vg.save();
    defer vg.restore();
    vg.translate(rect.top_left.x, rect.top_left.y);
    vg.textAlign(.{ .horizontal = .left, .vertical = .top });

    // Parse the rich text into chunks.
    // zig fmt: off
    const chunks_result = parseRichText(
        vg, 
        txt, 
        rect.size.w, 
        h_align, 
        wrap_mode,
        false, 
        g_memory_pool.chunks) catch |err| 
    {
        std.log.err("{any}, {s}", .{ err, "failed to to parse rich text." });
        _ = vg.text(rect.top_left.x, rect.top_left.y, "FAILED TO PARSE");
        return rect.top_left;
    };
    const chunks_len = chunks_result.chunks_len;
    // zig fmt: on

    const tm = getTextMetrics(vg);
    const y_align_offset = switch (v_align) {
        .top => 0,
        .middle => (rect.size.h - (chunks_result.final_cursor_pos.y + tm.line_height)) / 2,
        .bottom => rect.size.h - (chunks_result.final_cursor_pos.y + tm.line_height),
    };
    vg.translate(0, y_align_offset);

    var user_custom_style: RichTextTagPayload.UserCustomStyle = .{ .enabled = false, .style_name = &[_]u8{} };

    // TODO: refactor this out to function.
    // Iterate over each chunk and draw it.
    // const X1 = 0;
    const Y1 = 1;
    // const X2 = 2;
    const Y2 = 3;
    for (0..chunks_len) |chunk_i| for_loop: {
        const chunk = g_memory_pool.chunks[chunk_i];
        const bounds = chunk.bounds;
        switch (chunk.tag_type) {
            .none => unreachable,
            .eof => break :for_loop,
            .text => {
                if (user_custom_style.enabled) {
                    vg.translate(0, -y_align_offset);
                    vg.translate(-rect.top_left.x, -rect.top_left.y);
                    // zig fmt: off
                    g_custom_style_callback(
                        vg, 
                        g_custom_style_userdata, 
                        user_custom_style.style_name, 
                        chunk.tag_payload.text, 
                        chunk.x_cursor + rect.top_left.x, 
                        chunk.y_cursor + rect.top_left.y + y_align_offset);
                    // zig fmt: on
                    vg.translate(rect.top_left.x, rect.top_left.y);
                    vg.translate(0, y_align_offset);
                } else {
                    _ = vg.text(chunk.x_cursor, chunk.y_cursor, chunk.tag_payload.text);
                }
            },
            .bitmap => {
                const text_bitmap = chunk.tag_payload.bitmap;
                const img_w = text_bitmap.width * text_bitmap.scale;
                const img_h = (bounds[Y2] - bounds[Y1]);
                const min_dim = @min(img_w, img_h);
                const max_dim = @max(img_w, img_h);
                const img_x = chunk.x_cursor + text_bitmap.offset_x + ((max_dim - min_dim) / 2);
                const img_y = chunk.y_cursor + text_bitmap.offset_y + bounds[Y1];
                const imgPaint = vg.imagePattern(img_x, img_y, min_dim, min_dim, 0.0, text_bitmap.texture_handle, 1.0);
                vg.beginPath();
                vg.rect(img_x, img_y, min_dim, min_dim);
                vg.fillPaint(imgPaint);
                vg.fill();
                if (g_draw_debug_shapes) {
                    vg.beginPath();
                    vg.rect(chunk.x_cursor + text_bitmap.offset_x, img_y, img_w, img_h);
                    vg.strokeColor(Nanovg.rgba(200, 192, 60, 255));
                    vg.stroke();
                }
            },
            // The rest of the chunk cases are "style" chunks and do not render anything onscreen.
            // Instead they mutate the vector graphics state.
            .size => {
                const size = chunk.tag_payload.numeric;
                vg.fontSize(size);
            },
            .color => {
                const color = chunk.tag_payload.color;
                vg.fillColor(Nanovg.rgbaf(color[0], color[1], color[2], color[3]));
            },
            .font => {
                setFontFace(vg, chunk.tag_payload.text);
            },
            .kerning => {
                vg.textLetterSpacing(chunk.tag_payload.numeric);
            },
            .user_custom => {
                user_custom_style = chunk.tag_payload.user_custom;
            },
        }
    }
    return rect.top_left;
}

/// First tokenizes the input text and then fills an array of RichTextChunk with
/// information about each chunk of text to draw, returns number of chunks filled and the
/// final cursor x position.
/// Note that this doesn't allocate any memory, you pass in a pre-allocated array.
fn parseRichText(vg: Nanovg, txt: []const u8, line_width: f32, h_align: TextHorizontalAlign, wrap_mode: TextWrap, ignore_newlines: bool, chunks: []RichTextChunk) !RichTextChunksResult {
    const token_count = tokenizeRichText(txt, g_memory_pool.tokens) catch |err| {
        std.log.err("{},  failed to tokenize rich text.", .{err});
        return err;
    };
    // A function local struct, this is used to simplify state management
    // just inside this function.
    const LocalContext = struct {
        chunks: []RichTextChunk,
        tokens: []RichTextToken,
        newline_chunk_i: usize = 0,
        len: usize = 0,
        line_count: usize = 0,
        token_i: usize = 0,
        x_cursor: f32 = 0,
        y_cursor: f32 = 0,
        const Self = @This(); // @This() returns the type of the struct its in.
        pub fn nextToken(self: *Self) ?RichTextToken {
            if (self.token_i >= self.tokens.len) {
                return null;
            }
            const token = self.tokens[self.token_i];
            self.token_i += 1;
            return token;
        }
        pub fn addChunk(self: *Self, chunk: RichTextChunk, width: f32) !void {
            if (self.len >= self.chunks.len) {
                return error.OutOfMemory;
            }
            self.chunks[self.len] = chunk;
            self.chunks[self.len].x_cursor = self.x_cursor;
            self.chunks[self.len].y_cursor = 0.0;
            self.chunks[self.len].width = width;
            self.chunks[self.len].line = self.line_count;
            self.len += 1;
            self.x_cursor += width;
        }
        pub fn addStyleChunk(self: *Self, tag_type: RichTextTagType, payload: RichTextTagPayload) !void {
            if (self.len >= self.chunks.len) {
                return error.OutOfMemory;
            }
            self.chunks[self.len] = RichTextChunk{ .bounds = .{ 0, 0, 0, 0 }, .tag_type = tag_type, .tag_payload = payload };
            self.chunks[self.len].x_cursor = self.x_cursor;
            self.chunks[self.len].y_cursor = self.y_cursor;
            self.chunks[self.len].line = self.line_count;
            self.len += 1;
        }
        pub fn newline(self: *Self, line_height: f32) void {
            self.backfillYCursor(line_height);
            self.x_cursor = 0.0;
            self.newline_chunk_i = self.len - 1;
            self.line_count += 1;
        }
        pub fn backfillYCursor(self: *Self, line_height: f32) void {
            if (self.line_count == 0) return;
            self.y_cursor += line_height;
            var i: usize = self.len - 1;
            while (i > self.newline_chunk_i) : (i -= 1) {
                self.chunks[i].y_cursor += self.y_cursor;
            }
        }
        pub fn wrap(self: *Self, wrap_iter: anytype, line_height: f32) !void {
            comptime {
                const trait = std.meta.trait;
                const TPtr = @TypeOf(wrap_iter);
                if (!trait.isPtrTo(.Struct)(TPtr)) {
                    @compileError("Invalid Wrap Iterator, expected ptr to struct.");
                }
                const T = @TypeOf(wrap_iter.*);
                if (!trait.hasFn("next")(T)) {
                    @compileError("Invalid Wrap Iterator, expected struct to have next() function.");
                }
            }

            var wrap_count: usize = 0;
            while (wrap_iter.next()) |result| {
                var subtext = result.subtext;
                if (wrap_count > 0) {
                    self.newline(line_height);
                    subtext = std.mem.trimLeft(u8, subtext, " \t");
                }   
                try self.addChunk(.{ .tag_type = .text, .tag_payload = .{ .text = subtext }, .bounds = result.bounds }, result.width);
                wrap_count += 1;
            }
        }
    };
    var context = LocalContext{ .chunks = chunks, .tokens = g_memory_pool.tokens[0..token_count] };

    const vg_state = vg.ctx.getState();
    // TODO: Make these chached states a stack.
    var cached_color: Nanovg.Color = vg_state.fill.inner_color;
    var cached_font_size: f32 = vg_state.font_size;
    var cached_font: [:0]const u8 = getCurrentFontFaceName(vg);
    var cached_kerning: f32 = vg_state.letter_spacing;
    var bounds: [4]f32 = undefined;
    var current_tag_type: RichTextTagType = .none;
    var max_line_height: f32 = 0.0;
    var max_descender: f32 = 0.0;
    var next_line_descender: f32 = 0.0;

    // Pushes the current vector graphics state onto a stack.
    // The defer line will pop it off the stack and restore it once
    // execution exits this scope.
    vg.save();
    defer vg.restore();

    // Now that we have the rich text "tokens", we iterate through those
    // and convert them to "chunks". Chunks are different from tokens in that they provide
    // information about the bounds and width of the text regions/bitmaps to draw and
    // they have the tag body text converted into types (float, int, etc).
    while (context.nextToken()) |token| {
        switch (token.kind) {
            .none => return error.InvalidRichTextToken,
            .text => {
                // Update max line height and descender for newlines.
                const tm = getTextMetrics(vg);
                if (tm.line_height > max_line_height) {
                    max_line_height = tm.line_height;
                }
                if (tm.descender < max_descender) {
                    max_descender = tm.descender;
                }
                // Add text chunk.
                const text = token.token[0..];
                switch (wrap_mode) {
                    .none => {
                        const width = vg.textBounds(0, 0, text, &bounds);
                        try context.addChunk(.{ .tag_type = .text, .tag_payload = .{ .text = text }, .bounds = bounds }, width);
                    },
                    .character => {
                        var char_wrap_it = WrapCharacterIterator{ .vg = vg, .line_width = line_width, .text = text };
                        try context.wrap(&char_wrap_it, max_line_height + next_line_descender);
                    },
                    .word => {
                        var word_wrap_it = WrapWordIterator{ .vg = vg, .line_width = line_width, .initial_line_width = line_width - context.x_cursor, .text = text };
                        try context.wrap(&word_wrap_it, max_line_height + next_line_descender);
                    },
                }
            },
            .newline => {
                if (ignore_newlines) continue;
                // Any previous newline chunks now need to be updated with the correct
                // line height.
                context.newline(max_line_height + next_line_descender);
                max_line_height = 0.0;
                next_line_descender = max_descender * -1.0;
                max_descender = 0.0;
            },
            .tag_prefix => current_tag_type = token.tag_type,
            .tag_body => switch (current_tag_type) {
                .none, .text, .eof => return error.InvalidTagPrefix,
                .size => {
                    cached_font_size = vg.ctx.getState().font_size;
                    const font_size = std.fmt.parseFloat(f32, token.token) catch {
                        return error.InvalidFontSize;
                    };
                    vg.fontSize(font_size);
                    try context.addStyleChunk(.size, .{ .numeric = font_size });
                },
                .color => {
                    cached_color = vg.ctx.getState().fill.inner_color;
                    const color_str = token.token;
                    if (color_str.len != 7) return error.InvalidColor;
                    if (color_str[0] == '#') {
                        const color_int: u32 = std.fmt.parseInt(u32, color_str[1..], 16) catch {
                            std.log.err("Unable to parse color value: {s}", .{color_str[1..]});
                            return error.InvalidColor;
                        };
                        const b: f32 = @intToFloat(f32, @truncate(u8, (color_int & 0xFF))) / 255.0;
                        const g: f32 = @intToFloat(f32, @truncate(u8, (color_int >> 8) & 0xFF)) / 255.0;
                        const r: f32 = @intToFloat(f32, @truncate(u8, (color_int >> 16) & 0xFF)) / 255.0;
                        try context.addStyleChunk(.color, .{ .color = .{ r, g, b, 1.0 } });
                    }
                },
                .font => {
                    cached_font = getCurrentFontFaceName(vg);
                    setFontFace(vg, token.token);
                    try context.addStyleChunk(.font, .{ .text = token.token });
                },
                .kerning => {
                    cached_kerning = vg.ctx.getState().letter_spacing;
                    const kerning = std.fmt.parseFloat(f32, token.token) catch {
                        return error.InvalidKerning;
                    };
                    vg.textLetterSpacing(kerning);
                    try context.addStyleChunk(.kerning, .{ .numeric = kerning });
                },
                .bitmap => {
                    var maybe_text_bitmap = g_text_bitmap_handler(token.token, g_text_bitmap_userdata);
                    var bitmap_width: f32 = 0;
                    if (maybe_text_bitmap) |text_bitmap| {
                        bitmap_width += text_bitmap.width;
                    } else {
                        std.log.err("Could not find text bitmap for id: {s}", .{token.token});
                        return error.BitmapNotFound;
                    }
                    const font_size: f32 = vg.ctx.getState().font_size;
                    const scale: f32 = (font_size / 30.0);
                    maybe_text_bitmap.?.scale = scale;
                    bitmap_width *= scale;
                    const tm = getTextMetrics(vg);
                    const letter_spacing: f32 = vg.ctx.getState().letter_spacing;
                    context.x_cursor += (letter_spacing / 2);
                    try context.addChunk(.{ .tag_type = .bitmap, .tag_payload = .{ .bitmap = maybe_text_bitmap.? }, .bounds = .{ 0, -tm.ascender, bitmap_width, 0 } }, bitmap_width + (letter_spacing / 2));
                },
                .user_custom => {
                    try context.addStyleChunk(.user_custom, .{ .user_custom = .{ .enabled = true, .style_name = token.token } });
                },
            },
            .tag_close => switch (token.tag_type) {
                .none, .text, .eof => return error.InvalidTagPrefix,
                .size => {
                    vg.fontSize(cached_font_size);
                    try context.addStyleChunk(.size, .{ .numeric = cached_font_size });
                },
                .color => {
                    const r: f32 = cached_color.r;
                    const g: f32 = cached_color.g;
                    const b: f32 = cached_color.b;
                    const a: f32 = cached_color.a;
                    try context.addStyleChunk(.color, .{ .color = .{ r, g, b, a } });
                },
                .font => {
                    setFontFace(vg, cached_font);
                    try context.addStyleChunk(.font, .{ .text = cached_font });
                },
                .kerning => {
                    vg.textLetterSpacing(cached_kerning);
                    try context.addStyleChunk(.kerning, .{ .numeric = cached_kerning });
                },
                .bitmap => {},
                .user_custom => {
                    try context.addStyleChunk(.user_custom, .{ .user_custom = .{ .enabled = false, .style_name = &[_]u8{} } });
                },
            },
        }
    }

    // Add End-Of-File chunk and update the y-cursor values for chunks in the final line.
    try context.addStyleChunk(.eof, .{ .none = {} });
    context.backfillYCursor(max_line_height + next_line_descender);

    { // Calculate and store the horizontal alignment offset for each line.
        var line_start_i: usize = 0;
        var line_i: usize = 0;
        for (0..context.len) |i| {
            var chunk: *const RichTextChunk = &context.chunks[i];
            const is_new_line = (chunk.line != line_i) and i > 0;
            const is_last_chunk = (chunk.tag_type == .eof);
            if (is_new_line or is_last_chunk) {
                line_i = chunk.line;
                const last_chunk: *const RichTextChunk = if (i == 0) chunk else &context.chunks[i - 1];
                const draw_width = last_chunk.x_cursor + last_chunk.width;
                const align_offset = switch (h_align) {
                    .left => 0,
                    .center => (line_width - draw_width) / 2,
                    .right => (line_width - draw_width),
                };
                for (line_start_i..i) |j| {
                    context.chunks[j].x_cursor += align_offset;
                }
                line_start_i = i;
            }
        }
    }

    return .{ .chunks_len = context.len, .final_cursor_pos = .{ .x = context.x_cursor, .y = context.y_cursor } };
}

// Utility functions for text.
fn getTextMetrics(vg: Nanovg) TextMetrics {
    var text_metrics: TextMetrics = undefined;
    vg.textMetrics(&text_metrics.ascender, &text_metrics.descender, &text_metrics.line_height);
    return text_metrics;
}

const WrapResult = struct { subtext: []const u8, width: f32, bounds: [4]f32 };

const WrapWordIterator = struct {
    // Input.
    vg: Nanovg,
    text: []const u8,
    line_width: f32,
    initial_line_width: f32,
    // State.
    index: usize = 0,
    end_wb_index: usize = 0,
    word_boundaries_arr: [4096]usize = undefined,
    word_boundaries: ?[]usize = null,
    current_line_width: f32 = 0,
    const Self = @This();

    fn cacheWordBoundaries(self: *Self) []usize {
        var word_boundaries_len: usize = 0;
        var last_char = self.text[0];
        for (self.text, 0..) |char, i| {
            if ((last_char != char and char == ' ')) {
                self.word_boundaries_arr[word_boundaries_len] = i;
                word_boundaries_len += 1;
            }
            last_char = char;
        }
        self.word_boundaries_arr[word_boundaries_len] = self.text.len;
        word_boundaries_len += 1;
        return self.word_boundaries_arr[0..word_boundaries_len];
    }

    pub fn next(self: *Self) ?WrapResult {
        if (self.index >= self.text.len) return null;
        if (self.word_boundaries == null) {
            self.word_boundaries = self.cacheWordBoundaries();
            self.end_wb_index = self.word_boundaries.?.len;
            self.current_line_width = self.initial_line_width;
        }
        const word_boundaries = self.word_boundaries.?;
        var part: []const u8 = undefined;
        var part_width: f32 = undefined;
        var bounds: [4]f32 = undefined;
        for (0..self.end_wb_index) |wb_i| {
            var end_i = word_boundaries[word_boundaries.len - wb_i - 1];
            part = self.text[self.index..end_i];
            part_width = self.vg.textBounds(0, 0, part, &bounds);
            if (part_width <= self.current_line_width) {
                self.index = end_i;
                self.end_wb_index = wb_i;
                self.current_line_width = self.line_width;
                return .{ .subtext = part, .width = part_width, .bounds = bounds };
            } else if (wb_i == self.end_wb_index - 1) {
                while (end_i > self.index) : (end_i -= 1) {
                    part = self.text[self.index..end_i];
                    part_width = self.vg.textBounds(0, 0, part, &bounds);
                    if (part_width <= self.current_line_width) {
                        self.index = end_i;
                        self.current_line_width = self.line_width;
                        return .{ .subtext = part, .width = part_width, .bounds = bounds };
                    }
                }
            }
        }
        return null;
    }
};

const WrapCharacterIterator = struct {
    // Input.
    vg: Nanovg,
    text: []const u8,
    line_width: f32,
    // State.
    index: usize = 0,
    const Self = @This();

    pub fn next(self: *Self) ?WrapResult {
        if (self.index >= self.text.len) return null;
        var end_i: usize = self.text.len;
        var part: []const u8 = undefined;
        var part_width: f32 = undefined;
        var bounds: [4]f32 = undefined;
        while (end_i > self.index) : (end_i -= 1) {
            part = self.text[self.index..end_i];
            part_width = self.vg.textBounds(0, 0, part, &bounds);
            if (part_width <= self.line_width) {
                self.index = end_i;
                return .{ .subtext = part, .width = part_width, .bounds = bounds };
            }
        }
        return null;
    }
};

const AnyWrapIterator = struct {
    pub fn next(iter: anytype) ?WrapResult {
        return iter.next();
    }
};

// Utility functions for managing fonts.
fn setFontFace(vg: Nanovg, font_face: []const u8) void {
    var buf: [128]u8 = undefined;
    const font_faceZ = std.fmt.bufPrintZ(&buf, "{s}", .{font_face}) catch unreachable;
    vg.fontFace(font_faceZ);
}
fn getCurrentFontFaceName(vg: Nanovg) [:0]const u8 {
    return vg.ctx.currentFontFaceName();
}

// Tokenizing.
const RichTextToken = struct {
    token: []const u8,
    kind: TokenKind,
    tag_type: RichTextTagType = .none,

    pub const TokenKind = enum { none, text, newline, tag_prefix, tag_body, tag_close };
};

/// Possible errors the tokenize function could return.
const TokenizeError = error{ OutOfMemory, UnexpectedCharacter, InvalidTagPrefix, InvalidCloseTag };

/// Tokenizes the input rich text string. You are expected to pass in a pre-allocated array of tokens.
/// Returns an error or the count of tokens emitted.
pub fn tokenizeRichText(text: []const u8, tokens: []RichTextToken) TokenizeError!usize {
    const TokenizeState = enum { start, open_brace, inside_tag, close_tag, close_brace };
    const open_brace_char = '{';
    const close_brace_char = '}';
    const tag_prefix_char = ':';
    const tag_close_char = '/';
    const newline_char = '\n';
    // A function local struct, this is used to simplify state management
    // just inside this function.
    const LocalContext = struct {
        token_count: usize = 0,
        tokens: []RichTextToken,
        pub fn emitToken(self: *@This(), kind: RichTextToken.TokenKind, token: []const u8) !*RichTextToken {
            if (self.token_count >= self.tokens.len) {
                return error.OutOfMemory;
            }
            self.tokens[self.token_count] = .{ .token = token, .kind = kind };
            self.token_count += 1;
            return &self.tokens[self.token_count - 1];
        }
    };
    var context = LocalContext{ .tokens = tokens };
    var state = TokenizeState.start;
    var text_start: usize = 0;
    var tag_start: usize = 0;
    var tag_end: usize = 0;

    // The actual tokenizing logic. It loops through each character in the text,
    // and transitions the state machine and/or emits a token.
    for (text, 0..) |char, i| {
        try switch (state) {
            .start => switch (char) {
                open_brace_char => { // "...{"
                    state = .open_brace;
                    tag_start = i + 1;
                },
                close_brace_char => { // "...}"
                    state = .close_brace;
                },
                newline_char => {
                    _ = try context.emitToken(.text, text[text_start..i]);
                    _ = try context.emitToken(.newline, text[i .. i + 1]);
                    text_start = i + 1;
                },
                else => continue,
            },
            .open_brace => switch (char) {
                close_brace_char, tag_prefix_char, newline_char => return error.UnexpectedCharacter,
                open_brace_char => { // Escape brace: "{{..."
                    state = .start;
                    continue;
                },
                tag_close_char => { // "{/..."
                    tag_end = tag_start - 1;
                    if (tag_end > text_start) {
                        _ = try context.emitToken(.text, text[text_start..tag_end]);
                    }
                    state = .close_tag;
                },
                else => { // "{..."
                    tag_end = tag_start - 1;
                    if (tag_end > text_start) {
                        _ = try context.emitToken(.text, text[text_start..tag_end]);
                    }
                    state = .inside_tag;
                },
            },
            .inside_tag => switch (char) {
                open_brace_char, newline_char => error.UnexpectedCharacter,
                close_brace_char => { // "{...}..."
                    state = .close_brace;
                    tag_end = i;
                },
                tag_prefix_char => { // "{...:..."
                    var token: *RichTextToken = try context.emitToken(.tag_prefix, text[tag_start..i]);
                    if (RichTextTagType.string_to_type.get(token.token)) |prefix_kind| {
                        token.tag_type = prefix_kind;
                    } else {
                        return error.InvalidTagPrefix;
                    }
                    tag_start = i + 1;
                },
                else => continue,
            },
            .close_tag => switch (char) {
                open_brace_char, tag_prefix_char, tag_close_char, newline_char => return error.UnexpectedCharacter,
                close_brace_char => { // "{/...}..."
                    var token: *RichTextToken = try context.emitToken(.tag_close, text[tag_start..i]);
                    if (RichTextTagType.string_to_type.get(token.token[1..])) |prefix_kind| {
                        token.tag_type = prefix_kind;
                    } else {
                        return error.InvalidCloseTag;
                    }
                    state = .start;
                    text_start = i + 1;
                },
                else => continue,
            },
            .close_brace => switch (char) {
                close_brace_char => { // Escape brace: "}}..."
                    state = .start;
                    continue;
                },
                open_brace_char => { // "}{..."
                    _ = try context.emitToken(.tag_body, text[tag_start..tag_end]);
                    state = .open_brace;
                    tag_start = (i + 1);
                    text_start = tag_end + 1;
                },
                else => { // "}..."
                    _ = try context.emitToken(.tag_body, text[tag_start..tag_end]);
                    state = .start;
                    text_start = (tag_end + 1);
                },
            },
        };
    }

    if (state == .start and text_start < text.len) {
        _ = try context.emitToken(.text, text[text_start..]);
    }
    return context.token_count;
}

// This is the test suite.
// Zig provides built in testing with the "test" keyword, and also
// has a bunch of equality helpers inside the std.testing namespace.
// To run the tests use the following CLI: zig test rich_text.zig
const testing = std.testing;
test "tokezine simple text, no tags" {
    const text = "Simple line of text.";
    var tokens: [4]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 1), token_count);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[0].kind);
    try testing.expect(std.mem.eql(u8, text[0..], tokens[0].token));
}

test "tokezine simple text with newline" {
    const text = "Simple line of text,\nsecond line of text.";
    var tokens: [4]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 3), token_count);
    try testing.expectEqual(RichTextToken.TokenKind.newline, tokens[1].kind);
    try testing.expect(std.mem.eql(u8, "Simple line of text,", tokens[0].token));
    try testing.expect(std.mem.eql(u8, "\n", tokens[1].token));
    try testing.expect(std.mem.eql(u8, "second line of text.", tokens[2].token));
}

test "tokenize text with one self-closing tag" {
    const text = "test {img:name} end.";
    var tokens: [4]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 4), token_count);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[0].kind);
    try testing.expectEqual(RichTextToken.TokenKind.tag_prefix, tokens[1].kind);
    try testing.expectEqual(RichTextToken.TokenKind.tag_body, tokens[2].kind);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[3].kind);
    try testing.expect(std.mem.eql(u8, "test ", tokens[0].token));
    try testing.expect(std.mem.eql(u8, "img", tokens[1].token));
    try testing.expect(std.mem.eql(u8, "name", tokens[2].token));
    try testing.expect(std.mem.eql(u8, " end.", tokens[3].token));
}

test "tokenize text with one closing tag" {
    const text = "test {s:50}size{/s} end.";
    var tokens: [8]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 6), token_count);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[0].kind);
    try testing.expectEqual(RichTextToken.TokenKind.tag_prefix, tokens[1].kind);
    try testing.expectEqual(RichTextToken.TokenKind.tag_body, tokens[2].kind);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[3].kind);
    try testing.expectEqual(RichTextToken.TokenKind.tag_close, tokens[4].kind);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[5].kind);
    try testing.expect(std.mem.eql(u8, "test ", tokens[0].token));
    try testing.expect(std.mem.eql(u8, "s", tokens[1].token));
    try testing.expect(std.mem.eql(u8, "50", tokens[2].token));
    try testing.expect(std.mem.eql(u8, "size", tokens[3].token));
    try testing.expect(std.mem.eql(u8, "/s", tokens[4].token));
    try testing.expect(std.mem.eql(u8, " end.", tokens[5].token));
}

test "tokenize text with two closing tags" {
    const text = "test {s:50}size{/s} and {c:#FF0011}color{/c} end.";
    var tokens: [16]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 11), token_count);
}

test "tokenize text with contigous closing tags" {
    const text = "{k:4}{s:50}size and kerning{/s}{/k} end.";
    var tokens: [16]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 8), token_count);
    try testing.expectEqual(RichTextToken.TokenKind.tag_prefix, tokens[0].kind);
    try testing.expectEqual(RichTextTagType.kerning, tokens[0].tag_type);
    try testing.expectEqual(RichTextToken.TokenKind.tag_prefix, tokens[2].kind);
    try testing.expectEqual(RichTextTagType.size, tokens[2].tag_type);
    try testing.expectEqual(RichTextToken.TokenKind.tag_close, tokens[5].kind);
    try testing.expectEqual(RichTextToken.TokenKind.tag_close, tokens[6].kind);
    try testing.expectEqual(RichTextToken.TokenKind.text, tokens[7].kind);
}

test "tokenize with not enough token memory" {
    const text = "test {img:icon} end.";
    var tokens: [2]RichTextToken = undefined;
    const err = tokenizeRichText(text, &tokens);
    try testing.expectError(error.OutOfMemory, err);
}

test "tokenize with invalid tag prefix" {
    const text = "test {&:icon} end.";
    var tokens: [4]RichTextToken = undefined;
    const err = tokenizeRichText(text, &tokens);
    try testing.expectError(error.InvalidTagPrefix, err);
}

test "tokenize with invalid close tag" {
    const text = "test {s:20}test{/&} end.";
    var tokens: [8]RichTextToken = undefined;
    const err = tokenizeRichText(text, &tokens);
    try testing.expectError(error.InvalidCloseTag, err);
}

test "tokenize bad text" {
    const text = "test {img{:name} end.";
    var tokens: [4]RichTextToken = undefined;
    const err = tokenizeRichText(text, &tokens);
    try testing.expectError(error.UnexpectedCharacter, err);
}

test "tokenize text with escaped braces" {
    const text = "test {{iname}} }}end{{";
    var tokens: [4]RichTextToken = undefined;
    const token_count = try tokenizeRichText(text, &tokens);
    try testing.expectEqual(@as(usize, 1), token_count);
    try testing.expect(std.mem.eql(u8, text[0..], tokens[0].token));
}
