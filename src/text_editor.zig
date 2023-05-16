///! A text editor with basic actions: move cursor, home/end, backspace and delete.
///! Note: this does not have any text-range selection implemented.
const std = @import("std");
const Editor = @This();

pub const Cursor = struct { idx: usize = 0, row: usize = 0, col: usize = 0 };
pub const RectangleInt = struct { x: i32, y: i32, width: i32, height: i32 };

/// Fields
buf: []u8,
cursor: Cursor = Cursor{},
allocator: std.mem.Allocator,
eof: usize = 0,

pub fn init(in_allocator: std.mem.Allocator, comptime max_buffer_size: usize) !Editor {
    var editor = Editor{
        .allocator = in_allocator,
        .buf = try in_allocator.alloc(u8, max_buffer_size),
    };
    editor.buf[0] = 0;
    return editor;
}

pub fn initC(in_allocator: std.mem.Allocator, comptime max_buffer_size: usize) !*Editor {
    var editor = try in_allocator.create(Editor);
    editor.allocator = in_allocator;
    editor.buf = try in_allocator.alloc(u8, max_buffer_size);
    editor.buf[0] = 0;
    editor.eof = 0;
    editor.cursor = Cursor{ .idx = 0, .row = 0, .col = 0 };
    return editor;
}

pub fn deinit(self: *Editor) void {
    self.allocator.free(self.buf);
}

pub fn setCursorIdx(self: *Editor, idx: usize) void {
    self.cursor.idx = idx;
    var col: usize = 0;
    var row: usize = 0;
    for (0..self.eof) |i| {
        if (self.buf[i] == '\n') {
            row += 1;
            col = 0;
        }
        if (i == idx) {
            break;
        }
        col += 1;
    }
    self.cursor.col = col - 1;
    self.cursor.row = row;
}

pub fn insertBytes(self: *Editor, bytes: []const u8) void {
    for (bytes) |byte| {
        self.insertByte(byte);
    }
}

pub fn insertBytesKeepCursor(self: *Editor, bytes: []const u8) void {
    for (bytes) |byte| {
        self.insertByteKeepCursor(byte);
    }
}

pub fn insertByteKeepCursor(self: *Editor, byte: u8) void {
    self.buf[self.eof] = byte;
    self.eof += 1;
}

pub fn insertByte(self: *Editor, byte: u8) void {
    if (self.cursor.idx != self.eof) {
        std.mem.copyBackwards(u8, self.bufCursorToBufEnd(1), self.bufCursorToEof(0));
    }
    self.buf[self.cursor.idx] = byte;
    self.eof += 1;
    self.cursor.idx += 1;
    self.cursor.col += 1;
    if (byte == '\n') {
        self.cursor.row += 1;
        self.cursor.col = 0;
    }
}

pub fn replaceBytes(self: *Editor, bytes: []const u8) void {
    std.mem.copy(u8, self.buf, bytes);
    self.eof = bytes.len;
    self.cursor.idx = 0;
    self.cursor.col = 0;
    self.cursor.row = 0;
}

pub fn deleteBackward(self: *Editor) void {
    if (self.cursor.idx != 0 and self.eof != 0) {
        const delete_pos = self.cursor.idx -| 1;
        const deleted_char: u8 = self.buf[delete_pos];
        if (self.cursor.idx != self.eof) {
            std.mem.copy(u8, self.buf[delete_pos..], self.bufCursorToEof(0));
            self.buf[self.eof - 1] = 0;
        } else {
            self.buf[self.cursor.idx - 1] = 0;
        }
        self.cursor.idx = delete_pos;
        self.cursor.col -|= 1;
        self.eof -= 1;
        if (deleted_char == '\n') {
            self.cursor.row -= 1;
            const line_len = self.distToLineStart(self.cursor.idx);
            self.cursor.col = line_len;
        }
    }
}

pub fn deleteForward(self: *Editor) void {
    if (self.cursor.idx != self.eof and self.eof != 0) {
        const delete_pos = self.cursor.idx;
        if (self.cursor.idx != self.eof) {
            std.mem.copy(u8, self.buf[delete_pos..], self.bufCursorToEof(1));
            self.buf[self.eof - 1] = 0;
        } else {
            self.buf[self.cursor.idx - 1] = 0;
        }
        self.cursor.idx = delete_pos;
        self.eof -= 1;
    }
}

pub fn moveCursorLeft(self: *const Editor, cursor: *Cursor) void {
    if (cursor.idx == 0) return;
    const line_start = cursor.idx - self.distToLineStart(cursor.idx);
    if (cursor.idx == line_start) {
        cursor.idx -= 1;
        cursor.row -|= 1;
        cursor.col = self.distToLineStart(cursor.idx);
    } else {
        cursor.idx -= 1;
        cursor.col -|= 1;
    }
}

pub fn moveCursorRight(self: *const Editor, cursor: *Cursor) void {
    const char = self.buf[cursor.idx];
    if (char == '\n') {
        cursor.idx += 1;
        cursor.col = 0;
        cursor.row += 1;
    } else if (char != 0 and cursor.idx != self.eof) {
        cursor.idx += 1;
        cursor.col += 1;
    }
}

pub fn moveCursorUp(self: *const Editor, cursor: *Cursor) void {
    if (cursor.idx == 0) return;
    const old_cursor_col = cursor.col;
    const was_at_end_of_line = self.isCursorAtEndOfLine(cursor);
    self.moveCursorToLineStart(cursor);
    if (cursor.idx > 0) {
        cursor.idx -|= 1;
        cursor.row -|= 1;
        cursor.col = self.distToLineStart(cursor.idx);
        // ^ Cursor now at line end of previous line up.
        if (!was_at_end_of_line and old_cursor_col < cursor.col) {
            cursor.idx -= (cursor.col - old_cursor_col);
            cursor.col = old_cursor_col;
        }
    }
}

pub fn moveCursorDown(self: *const Editor, cursor: *Cursor) void {
    const old_cursor_col = cursor.col;
    const was_at_end_of_line = self.isCursorAtEndOfLine(cursor);
    self.moveCursorToLineEnd(cursor);
    if (cursor.idx != self.eof) {
        cursor.idx += 1;
        cursor.row += 1;
        cursor.col = 0;
        // ^ Cursor now at line start of next line down.
        self.moveCursorToLineEnd(cursor);
        // ^ Cursor now at line end of next line down.
        if (!was_at_end_of_line and old_cursor_col < cursor.col) {
            cursor.idx -= (cursor.col - old_cursor_col);
            cursor.col = old_cursor_col;
        }
    }
}

pub fn moveCursorToLineStart(self: *const Editor, cursor: *Cursor) void {
    if (cursor.idx == 0) return;
    const dist = self.distToLineStart(cursor.idx);
    cursor.idx -= dist;
    cursor.col = 0;
}

pub fn moveCursorToLineEnd(self: *const Editor, cursor: *Cursor) void {
    if (self.isCursorAtEndOfLine(cursor)) return;
    const dist = self.distToLineEnd(cursor.idx);
    cursor.idx += dist;
    cursor.col += dist;
}

pub fn moveCursorToPreviousWord(self: *const Editor, cursor: *Cursor) void {
    if (self.isCursorAtStartOfLine(cursor)) return;
    var skip_whitespace: bool = std.ascii.isWhitespace(self.buf[cursor.idx]);
    while (true) {
        cursor.idx -= 1;
        cursor.col -= 1;
        if (self.isCursorAtStartOfLine(cursor)) return;
        if (skip_whitespace) {
            if (!std.ascii.isWhitespace(self.buf[cursor.idx])) return;
        } else {
            if (std.ascii.isWhitespace(self.buf[cursor.idx])) return;
        }
    }
}

pub fn moveCursorToNextWord(self: *const Editor, cursor: *Cursor) void {
    if (self.isCursorAtEndOfLine(cursor)) return;
    var skip_whitespace: bool = std.ascii.isWhitespace(self.buf[cursor.idx]);
    while (true) {
        cursor.idx += 1;
        cursor.col += 1;
        if (self.isCursorAtEndOfLine(cursor)) return;
        if (skip_whitespace) {
            if (!std.ascii.isWhitespace(self.buf[cursor.idx])) return;
        } else {
            if (std.ascii.isWhitespace(self.buf[cursor.idx])) return;
        }
    }
}

pub fn getText(self: *const Editor) []const u8 {
    return self.buf[0..self.eof];
}

fn bufCursorToX(self: *Editor, end_exclusive: usize) []u8 {
    return self.buf[self.cursor.idx..end_exclusive];
}

fn bufXToCursor(self: *Editor, start: usize) []u8 {
    return self.buf[start..self.cursor.idx];
}

fn bufCursorToBufEnd(self: *Editor, comptime start_offset: usize) []u8 {
    return self.buf[(self.cursor.idx + start_offset)..];
}

fn bufCursorToEof(self: *Editor, comptime start_offset: usize) []u8 {
    return self.buf[(self.cursor.idx + start_offset)..self.eof];
}

fn distToLineStart(self: *const Editor, pos: usize) usize {
    if (pos == 0) return 0;
    // find start of text or previous newline.
    var i: usize = 1;
    while (pos - i > 0) : (i += 1) {
        if (self.buf[pos - i] == '\n') {
            i -= 1;
            break;
        }
    }
    return i;
}

fn distToLineEnd(self: *const Editor, pos: usize) usize {
    if (pos == self.eof) return 0;
    // find end of text or next newline.
    var i: usize = 0;
    while (pos + i < self.eof) : (i += 1) {
        if (self.buf[pos + i] == '\n') break;
    }
    return i;
}

fn isCursorAtStartOfLine(_: *const Editor, cursor: *Cursor) bool {
    return cursor.col == 0;
}

fn isCursorAtEndOfLine(self: *const Editor, cursor: *Cursor) bool {
    return cursor.col != 0 and (self.buf[cursor.idx] == '\n' or cursor.idx == self.eof);
}

///! Rendering Interface.
pub const DrawGlyphSignature = *const fn (char: u8, x: i32, y: i32, userdata: *const anyopaque) void;
pub const CursorRectSignature = *const fn (col: i32, row: i32, userdata: *const anyopaque) RectangleInt;
pub const DrawCursorRectSignature = *const fn (rect: RectangleInt, mutable_userdata: ?*anyopaque, userdata: *const anyopaque) void;
pub const RendererInterface = struct { draw_glyph_fn: DrawGlyphSignature, cursor_rect_fn: CursorRectSignature, draw_cursor_rect_fn: DrawCursorRectSignature, mutable_userdata: ?*anyopaque, userdata: *const anyopaque };

pub fn drawCursor(self: *const Editor, renderer: RendererInterface) void {
    const rect = renderer.cursor_rect_fn(@intCast(i32, self.cursor.col), @intCast(i32, self.cursor.row), renderer.userdata);
    renderer.draw_cursor_rect_fn(rect, renderer.mutable_userdata, renderer.userdata);
}

pub fn drawBuffer(self: *const Editor, renderer: RendererInterface) void {
    var draw_cursor = Cursor{};
    for (self.buf, 0..) |char, i| {
        draw_cursor.idx = i;
        if (char == 0 or i == self.eof) break;
        if (char == '\n') {
            draw_cursor.row += 1;
            draw_cursor.col = 0;
            continue;
        }
        const rect = renderer.cursor_rect_fn(@intCast(i32, draw_cursor.col), @intCast(i32, draw_cursor.row), renderer.userdata);
        renderer.draw_glyph_fn(char, rect.x, rect.y, renderer.userdata);
        draw_cursor.col += 1;
    }
}

pub fn castUserdata(comptime T: type, userdata: *const anyopaque) *const T {
    @setRuntimeSafety(false);
    return @ptrCast(*const T, @alignCast(@alignOf(*const T), userdata));
}

pub fn castMutableUserdata(comptime T: type, mutable_userdata: *anyopaque) *T {
    @setRuntimeSafety(false);
    return @ptrCast(*T, @alignCast(@alignOf(*T), mutable_userdata));
}
