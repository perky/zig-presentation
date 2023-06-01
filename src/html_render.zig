const Nanovg = @import("vg.zig").Nanovg;
const std = @import("std");
pub const use_ultralight = @import("build_options").ultralight;
pub const Renderer = if (use_ultralight) @import("html_render/ultralight.zig").Ultralight else void;

pub fn loaderInterface(renderer: ?*Renderer) HtmlLoadInterface {
    if (use_ultralight) {
        return .{
            .context = renderer,
            .load = Renderer.loadHtml,
            .loadFromFile = Renderer.loadHtmlFromFile,
            .loadWithTemplate = Renderer.loadHtmlWithTemplate,
        };
    } else {
        return .{};
    }
}

pub fn rendererInit(allocator: std.mem.Allocator, width: u32, height: u32) ?*Renderer {
    if (use_ultralight) {
        return Renderer.init(allocator, width, height) catch @panic("Error when init html renderer.");
    } else {
        return null;
    }
}

pub fn rendererMakeImage(renderer: ?*Renderer, vg: Nanovg) ?Nanovg.Image {
    if (use_ultralight) {
        var html_bitmap = renderer.?.bitmapData();
        return vg.createImageRGBA(
            html_bitmap.width, 
            html_bitmap.height, 
            .{}, 
            html_bitmap.pixel_data,
        );
    } else {
        return null;
    }
}

pub fn rendererUpdate(renderer: ?*Renderer, vg: Nanovg, image: ?Nanovg.Image) void {
    if (use_ultralight) {
        renderer.?.tick();
        if (image) |_image| {
            var html_bitmap = renderer.?.bitmapData();
            vg.updateImage(_image, html_bitmap.pixel_data);
        }
    }
}

pub const HtmlLoadInterface = struct {
    context: ?*Renderer = null,
    load: ?*const html_load_noerr_fn_t = null,
    loadFromFile: ?*const html_load_from_file_fn_t = null,
    loadWithTemplate: ?*const html_load_fn_t = null,

    pub const HtmlLoadError = error { CouldNotLoadHtml };
    pub const html_load_noerr_fn_t = fn (renderer: *Renderer, bytes: [:0]const u8) void;
    pub const html_load_from_file_fn_t = fn (renderer: *Renderer, path: []const u8) anyerror!void;
    pub const html_load_fn_t = fn (renderer: *Renderer, bytes: [:0]const u8) anyerror!void;
};