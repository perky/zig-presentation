// zig fmt: off
const std = @import("std");
const mecha = @import("mecha.zig");
const types = @import("types.zig");
const TextEditor = @import("text_editor.zig");
const ImageMode = types.Image.Mode;
const Slide = types.Slide;
const SlideSlot = types.Slide.Slot;
const Presentation = types.Presentation;

const use_html = @import("html_render.zig").use_ultralight;
const HtmlLoadInterface = @import("html_render.zig").HtmlLoadInterface;

const Allocator = std.mem.Allocator;
const NodeList = std.ArrayList(NodeWrap);
const Error = mecha.Error;
const JsonObject = std.json.ObjectMap;
const ImageCache = @import("vg.zig").ImageCache;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

pub const NodeWrap = struct {
    node: Node,
    original_str: []const u8
};

pub const Node = union(enum) {
    title: []const u8,
    body: []const u8,
    slide_param: SlideParam,
    global_param: GlobalParam,
    comment_line: void,
    pub const SlideParam = struct { label: SlideParamLabel, value: ParamValue };
    pub const GlobalParam = struct { label: GlobalParamLabel, value: ParamValue };
    pub const ParamValue = union(enum) { 
        string: []const u8,
        number: f32, 
        vec3: [3]u8, 
        make_slot: SlideSlot, 
        image: Image, 
        named_color: NamedColor 
    };
    pub const SlideParamLabel = enum { 
        background, image, append, note,
        bodySlot, bodySize, bodyAlign, bodyColor, 
        titleSlot, titleSize, titleAlign, titleColor,
        codeEditorSlot, codeEditorSize, codeEditorColor,
        codeEditor, 
        htmlFile, htmlBodyStart, htmlBodyEnd,
        jumpHere,
    };
    pub const GlobalParamLabel = enum {
        makeSlot, makeColor, defaultBackground, showNotes, debugMode
    };
    pub const Image = struct { path: []const u8, slot: []const u8, mode: ImageMode };
    pub const NamedColor = struct { name: []const u8, color: []u8 };
};

var g_current_parse_line: usize = undefined;
var g_current_parse_str: []const u8 = "";

fn logErr(comptime err_fmt: []const u8, args: anytype) void {
    std.log.err(err_fmt, args);
    std.log.err("Line {d}: {s}", .{ g_current_parse_line, g_current_parse_str });
}

pub fn parsePresentdownFile(
    arena: Allocator, 
    image_cache: *ImageCache, 
    color_presets: *StringArrayHashMap([3]u8), 
    html_loader: HtmlLoadInterface,
    path: []const u8,
) !Presentation {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader();
    var nodes = NodeList.init(arena);
    g_current_parse_line = 1;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const alloc_line = try arena.dupe(u8, line);
        g_current_parse_str = alloc_line;
        const parse_result = parseLine(arena, alloc_line) catch |err| {
            std.log.err("Error {} on line {d}.", .{err, g_current_parse_line});
            return err;
        };
        const node_wrap: NodeWrap = .{ .node = parse_result.value, .original_str = alloc_line };
        try nodes.append(node_wrap);
        g_current_parse_line += 1;
    }
    var presentation = initPresentation(arena, image_cache, color_presets, html_loader, nodes.items) catch |err| {
        std.log.err("Error {} on line {d}.", .{err, g_current_parse_line});
        return err;
    };
    return presentation;
}

fn initPresentation(
    arena: Allocator, 
    image_cache: *ImageCache, 
    color_presets: *StringArrayHashMap([3]u8), 
    html_loader: HtmlLoadInterface,
    nodes: []const NodeWrap,
) !Presentation {
    var presentation = Presentation.init(arena, html_loader);
    try presentation.slots.put("default_body", Slide.default_body_slot);
    try presentation.slots.put("default_title", Slide.default_title_slot);
    try presentation.slots.put("fullscreen", Slide.fullscreen_slot);

    // BEGIN inline getter struct. 
    // Helps with getting commonly re-used data, such as colors, images, and slots.
    var getter = struct {
        _image_cache: *ImageCache,
        _color_presets: *StringArrayHashMap([3]u8),
        _presentation: *Presentation,

        fn background(self: @This(), value: Node.ParamValue) !Slide.Background {
            switch (value) {
                .vec3 => |v| return .{ .color = v },
                .string => |name| {
                    const m_img = self._image_cache.getOrCreateImage(name) catch null;
                    if (m_img) |img| {
                        return .{ .image = img };
                    } else {
                        const col = self._color_presets.get(name);
                        if (col == null) {
                            logErr("Could not find image or named color: {s}.", .{name});
                            return error.InvalidBackgroundName;
                        }
                        return .{ .color = col.? };
                    }
                },
                else => {
                    logErr("Invalid background parameter.", .{});
                    return error.InvalidBackgroundParam;
                }
            }
        }

        fn color(self: @This(), value: Node.ParamValue) ![3]u8 {
            switch (value) {
                .vec3 => |v| return v,
                .string => |name| {
                    const col = self._color_presets.get(name);
                    if (col == null) {
                        logErr("Could not find named color: {s}.", .{name});
                        return error.InvalidNamedColor;
                    }
                    return col.?;
                },
                else => {
                    logErr("Invalid color parameter.", .{});
                    return error.InvalidColorParam;
                }
            }
        }

        fn slot(self: @This(), name: []const u8) !Slide.Slot {
            const m_slot = self._presentation.slots.get(name);
            if (m_slot == null) {
                logErr("Could not find slot {s}", .{name});
                return error.SlotNotFound;
            }
            return m_slot.?;
        }

        fn editor(self: @This(), _arena: Allocator, name: []const u8) !*TextEditor {
            var m_editor = self._presentation.code_editors.getPtr(name);
            if (m_editor == null) {
                try self._presentation.code_editors.put(name, try TextEditor.init(_arena, 10_000));
                return self._presentation.code_editors.getPtr(name).?;
            } else {
                return m_editor.?;
            }
        }
    }{ ._image_cache = image_cache, ._color_presets = color_presets, ._presentation = &presentation };
    // END inline getter struct.

    var next_body_slot_name: ?[]const u8 = null;
    var next_body_style: Slide.TextStyle = Slide.default_body_style;
    var wants_new_body: bool = false;
    var do_not_show_next_body: bool = false;
    var read_html_body: bool = false;
    var html_body_arr = ArrayList(u8).init(arena);
    g_current_parse_line = 1;
    for (nodes) |node_wrap| {
        const node = node_wrap.node;
        defer g_current_parse_line += 1;
        g_current_parse_str = node_wrap.original_str;
        switch (node) {
            .comment_line => {}, // ignore.
            .global_param => |param| switch (param.label) {
                .makeSlot => try presentation.slots.put(param.value.make_slot.name, param.value.make_slot),
                .makeColor => {
                    const color = try color_lit(arena, param.value.named_color.color);
                    try color_presets.put(param.value.named_color.name, color.value);
                },
                .defaultBackground => presentation.default_background = try getter.background(param.value),
                .showNotes => presentation.show_notes = (param.value.number >= 1),
                .debugMode => presentation.debug_mode = (param.value.number >= 1),
            },
            .title => |_title| {
                var slide = Slide.init(arena, _title);
                try presentation.slides.append(slide);
                next_body_slot_name = null;
                next_body_style = Slide.default_body_style;
            },
            .body => {
                if (presentation.slides.items.len == 0) {
                    if (node.body.len == 0 or node.body[0] == '\n') continue;
                    std.log.err("Body must come after title.\nLine {d}: {s}", .{g_current_parse_line, node.body});
                    return error.InvalidBody;
                }
                var current_slide: *Slide = getLastItemPtr(Slide, presentation.slides).?;
                
                if (read_html_body) {
                    try html_body_arr.appendSlice(node.body);
                    continue;
                }

                if (do_not_show_next_body) {
                    do_not_show_next_body = false;
                    var append_slide = Slide.init(arena, current_slide.title);
                    append_slide.background = current_slide.background;
                    append_slide.images = current_slide.images;
                    for (current_slide.bodies.items) |body| {
                        var body_copy = body;
                        body_copy.text = try body.text.clone();
                        try append_slide.bodies.append(body_copy);
                    }
                    try presentation.slides.append(append_slide);
                }

                current_slide = getLastItemPtr(Slide, presentation.slides).?;
                const slide_body_len = current_slide.bodies.items.len;
                const b_create_new_body: bool = (next_body_slot_name != null or slide_body_len == 0 or wants_new_body);
                var current_body: *Slide.Body = undefined;
                if (b_create_new_body) { // Create new body.
                    const slot = blk: {
                        if (next_body_slot_name) |slot_name| {
                            break :blk try getter.slot(slot_name);
                        } else {
                            break :blk Slide.default_body_slot;
                        }
                    };
                    var body = Slide.Body{ .text = ArrayList(u8).init(arena), .slot = slot, .style = next_body_style };
                    try current_slide.bodies.append(body);
                    next_body_slot_name = null;
                    current_body = getLastItemPtr(Slide.Body, current_slide.bodies).?;
                    wants_new_body = false;
                } else { // Get last created body.
                    current_body = getLastItemPtr(Slide.Body, current_slide.bodies).?;
                }

                if (current_slide.code_editor) |code_editor| {
                    const pre_eof = code_editor.eof;
                    code_editor.insertBytesKeepCursor(node.body);
                    code_editor.insertByteKeepCursor('\n');
                    const cursor_literal = "#cursor";
                    if (std.mem.indexOf(u8, node.body, cursor_literal)) |cursor_col| {
                        code_editor.setCursorIdx(pre_eof + cursor_col);
                        for (0..cursor_literal.len) |_| {
                            code_editor.deleteForward();
                        }
                    }
                } else {
                    var writer = current_body.text.writer();
                    if (node.body.len > 0) {
                        try writer.writeAll(node.body);
                    }
                    try writer.writeAll("\n");
                }
                current_body.lines += 1;
            },
            .slide_param => |param| {
                if (presentation.slides.items.len == 0) {
                    std.log.err("Param must come after title.\nParam: {any}", .{param.label});
                    return error.InvalidParam;
                }
                var current_slide: *Slide = getLastItemPtr(Slide, presentation.slides).?;
                switch (param.label) {
                    .background => current_slide.background = try getter.background(param.value),
                    .image => {
                        const image_meta: Node.Image = param.value.image;
                        const slot = try getter.slot(image_meta.slot);
                        var image = types.Image{ .handle = try image_cache.getOrCreateImage(image_meta.path), .slot = slot, .mode = image_meta.mode };
                        try current_slide.images.append(image);
                    },
                    .bodySlot => next_body_slot_name = param.value.string,
                    .bodySize => next_body_style.size = param.value.number,
                    .bodyAlign => next_body_style.align_h = std.meta.stringToEnum(Slide.HAlign, param.value.string).?,
                    .bodyColor => next_body_style.color = try getter.color(param.value),
                    .titleSlot => current_slide.title_slot = try getter.slot(param.value.string),
                    .titleSize => current_slide.title_style.size = param.value.number,
                    .titleAlign => {
                        const m_tag = std.meta.stringToEnum(Slide.HAlign, param.value.string);
                        if (m_tag == null) {
                            std.log.err("Invalid align tag {s}", .{param.value.string});
                            return error.InvalidAlignTag;
                        }
                        current_slide.title_style.align_h = m_tag.?;
                    },
                    .titleColor => current_slide.title_style.color = try getter.color(param.value),
                    .codeEditor => {
                        const editor_name = param.value.string;
                        var editor: *TextEditor = try getter.editor(arena, editor_name);
                        current_slide.code_editor = editor;
                        current_slide.code_editor_slot = Slide.default_body_slot;
                        current_slide.code_editor_name = editor_name;
                    },
                    .codeEditorSlot => current_slide.code_editor_slot = try getter.slot(param.value.string),
                    .codeEditorSize => current_slide.code_editor_style.size = param.value.number,
                    .codeEditorColor => current_slide.code_editor_style.color = try getter.color(param.value),
                    .append => do_not_show_next_body = true,
                    .note => try current_slide.notes.appendSlice(param.value.string),
                    .htmlFile => {
                        if (!use_html) {
                            std.log.err("Cannot use @htmlFile, no html renderer compiled.", .{});
                            return error.InvalidParam;
                        }

                        const path = param.value.string;
                        var html_file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
                        defer html_file.close();
                        const html_data = try html_file.readToEndAllocOptions(
                            arena, 
                            10_000_000, 
                            null, 
                            @alignOf(u8),
                            0,
                        );
                        current_slide.html_body = html_data;
                    },
                    .htmlBodyStart => {
                        if (!use_html) {
                            std.log.err("Cannot use @htmlBodyStart, no html renderer compiled.", .{});
                            return error.InvalidParam;
                        }
                        read_html_body = true;
                    },
                    .htmlBodyEnd => {
                        if (!use_html) {
                            std.log.err("Cannot use @htmlBodyEnd, no html renderer compiled.", .{});
                            return error.InvalidParam;
                        }
                        read_html_body = false;
                        current_slide.html_body = try html_body_arr.toOwnedSliceSentinel(0);
                    },
                    .jumpHere => presentation.slide_index = presentation.slides.items.len - 1,
                }
            },
        }
    }

    return presentation;
}

fn getLastItemPtr(comptime T: type, list: anytype) ?*T {
    if (list.items.len > 0) {
        return &list.items[list.items.len - 1];
    }
    return null;
}

pub fn toNode(comptime tag: []const u8) *const fn (Allocator, anytype) Error!Node {
    return toUnion(Node, tag);
}

pub fn toParamValue(comptime tag: []const u8) *const fn (Allocator, anytype) Error!Node.ParamValue {
    return toUnion(Node.ParamValue, tag);
}

pub fn toUnion(comptime T: type, comptime tag: []const u8) *const fn (Allocator, anytype) Error!T {
    return struct {
        fn func(_: Allocator, data: anytype) Error!T {
            return @unionInit(T, tag, data);
        }
    }.func;
}

pub fn toJsonObject(comptime T: type) *const fn (Allocator, anytype) Error!T {
    const json = std.json;
    return struct {
        fn func(allocator: Allocator, data: anytype) Error!T {
            const trim_data = std.mem.trimRight(u8, data, "\n");
            // var stream = json.TokenStream.init(trim_data);
            // var result = json.parse(T, &stream, .{ .allocator = allocator }) catch |err| {
            var result = json.parseFromSlice(T, allocator, trim_data, .{ .ignore_unknown_fields = true }) catch |err| {
                std.log.err("Failed to parse JSON into type {s} {} => {s}", .{@typeName(T), err, data});
                return Error.OtherError;
            };
            return result;
        }
    }.func;
}

pub fn toUnionViaJson(comptime U: type, comptime T: type, comptime tag: []const u8) *const fn (Allocator, anytype) Error!T {
    const json = std.json;
    return struct {
        fn func(allocator: Allocator, data: anytype) Error!T {
            const trim_data = std.mem.trimRight(u8, data, "\n");
            var result = json.parseFromSlice(T, allocator, trim_data, .{ .ignore_unknown_fields = true }) catch |err| {
                std.log.err("Failed to parse JSON into type {s} {} => {s}", .{@typeName(T), err, data});
                return Error.OtherError;
            };
            return @unionInit(U, tag, result);
        }
    }.func;
}


const ascii = mecha.ascii;
const utf8 = mecha.utf8;
const combine = mecha.combine;
const discard = mecha.discard;
const many = mecha.many;
const oneOf = mecha.oneOf;
const convert = mecha.convert;
const withErr = mecha.withError;

const quote_lit = ascii.char('"');
const hash_lit = ascii.char('#');
const at_lit = ascii.char('@');
const bang_lit = ascii.char('!');
const open_brace_lit = ascii.char('{');
const close_brace_lit = ascii.char('}');
const space_lit = ascii.char(' ');
const quoted_string = combine(.{
    discard(quote_lit),
    many(mecha.ascii.not(quote_lit), .{}), 
    discard(quote_lit)
});
const braced_object = mecha.asStr(combine(.{
    open_brace_lit,
    many(mecha.ascii.not(close_brace_lit), .{}),
    close_brace_lit
}));
const label = mecha.asStr(combine(.{
    ascii.alphabetic,
    many(ascii.alphanumeric, .{})
}));
const float_lit = convert(mecha.toFloat(f32), mecha.rest);

const comment_line = combine(.{
    discard(at_lit),
    discard(mecha.ascii.char('c')),
    discard(mecha.ascii.char(' ')),
    skip_whitespace,
    discard(mecha.rest)
});

fn globalParamParser(comptime id: []const u8, comptime param_parser: anytype) mecha.Parser(Node.GlobalParam) {
    return mecha.map(mecha.toStruct(Node.GlobalParam), combine(.{
        convert(mecha.toEnum(Node.GlobalParamLabel), mecha.asStr(mecha.string(id))),
        skip_whitespace,
        param_parser,
    }));
}

fn globalParamParserOneOf(comptime id: []const u8, comptime parser_list: anytype) mecha.Parser(Node.GlobalParam) {
    return mecha.map(mecha.toStruct(Node.GlobalParam), combine(.{
        convert(mecha.toEnum(Node.GlobalParamLabel), mecha.asStr(mecha.string(id))),
        skip_whitespace,
        oneOf(parser_list),
    }));
}

fn slideParamParser(comptime id: []const u8, comptime param_parser: anytype) mecha.Parser(Node.SlideParam) {
    return mecha.map(mecha.toStruct(Node.SlideParam), combine(.{
        convert(mecha.toEnum(Node.SlideParamLabel), mecha.asStr(mecha.string(id))),
        skip_whitespace,
        param_parser,
    }));
}

fn slideParamParserOneOf(comptime id: []const u8, comptime param_list: anytype) mecha.Parser(Node.SlideParam) {
    return mecha.map(mecha.toStruct(Node.SlideParam), combine(.{
        convert(mecha.toEnum(Node.SlideParamLabel), mecha.asStr(mecha.string(id))),
        skip_whitespace,
        oneOf(param_list),
    }));
}

fn jsonParser(comptime T: type) mecha.Parser(T) {
    return convert(toJsonObject(T), braced_object);
}

fn paramValueParser(comptime tag: []const u8, comptime parser: anytype) mecha.Parser(Node.ParamValue) {
    return convert(toParamValue(tag), parser);
}

const empty_param_value = paramValueParser("string", eos);
const number_param_value = paramValueParser("number", float_lit);
const color_param_value = paramValueParser("vec3", color_lit);
const image_param_value = paramValueParser("image", jsonParser(Node.Image));
const string_param_value = paramValueParser("string", quoted_string);

const bangat_param = combine(.{
    discard(at_lit),
    discard(bang_lit),
    oneOf(.{
        globalParamParser("makeSlot", paramValueParser("make_slot", jsonParser(SlideSlot))),
        globalParamParser("makeColor", paramValueParser("named_color", jsonParser(Node.NamedColor))),
        globalParamParserOneOf("defaultBackground", .{ color_param_value, string_param_value }),
        globalParamParser("showNotes", number_param_value),
        globalParamParser("debugMode", number_param_value),
    }),
});

const at_param = combine(.{
    discard(at_lit),
    oneOf(.{
        slideParamParser("image", image_param_value),
        slideParamParser("append", empty_param_value),
        slideParamParserOneOf("background", .{ color_param_value, string_param_value }),
        slideParamParser("note", string_param_value),
        slideParamParser("bodySlot", string_param_value),
        slideParamParser("bodySize", number_param_value),
        slideParamParser("bodyAlign", string_param_value),
        slideParamParser("bodyColor", color_param_value),
        slideParamParser("titleSlot", string_param_value),
        slideParamParser("titleSize", number_param_value),
        slideParamParser("titleAlign", string_param_value),
        slideParamParser("titleColor", color_param_value),
        slideParamParser("codeEditorSlot", string_param_value),
        slideParamParser("codeEditorSize", number_param_value),
        slideParamParser("codeEditorColor", color_param_value),
        slideParamParser("codeEditor", string_param_value),
        slideParamParser("htmlFile", string_param_value),
        slideParamParser("htmlBodyStart", empty_param_value),
        slideParamParser("htmlBodyEnd", empty_param_value),
        slideParamParser("jumpHere", empty_param_value),
    }),
});

const hex_byte = mecha.int(u8, .{
    .parse_sign = false,
    .base = 16,
    .max_digits = 2,
});
const hex_vec3 = mecha.manyN(hex_byte, 3, .{});
const color_lit = combine(.{ discard(hash_lit), hex_vec3 });

const skip_whitespace = discard(many(ascii.whitespace, .{ .collect = false }));
const whitespace = many(ascii.whitespace, .{ .collect = true });
const text_line = combine(.{ skip_whitespace, mecha.rest });
const title = mecha.combine(.{ discard(hash_lit), text_line });

const body_line = mecha.asStr(combine(.{
    mecha.ascii.not(at_lit), 
    mecha.rest,
}));

/// A parser that only succeeds on the end of the string.
pub fn eos(_: Allocator, str: []const u8) Error!mecha.Result([]const u8) {
    if (str.len != 0)
        return error.ParserFailed;
    return .{ .value = str, .rest = str };
}

// Root of the the parsing tree.
pub const parseLine = oneOf(.{
    convert(toNode("title"), title), 
    convert(toNode("comment_line"), comment_line),
    convert(toNode("global_param"), bangat_param),
    convert(toNode("slide_param"), at_param),
    convert(toNode("body"), oneOf(.{body_line, eos})),
});
