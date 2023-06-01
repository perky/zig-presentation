const std = @import("std");
const c = @import("../c.zig");

const stylesheet_data = @embedFile("../res/stylesheet.css");
const html_template_data = @embedFile("../res/html_template.html");

pub const Ultralight = struct {
    allocator: std.mem.Allocator,
    renderer: c.ULRenderer,
    view: c.ULView,
    pixel_buffer: []u8,
    ready: bool,

    pub const BitmapData = struct {
        width: u32,
        height: u32,
        bytes_per_pixel: u32,
        pixel_data: []const u8,
        pub fn len(self: BitmapData) u32 { return self.width * self.height * self.bytes_per_pixel; }
        pub fn slice(self: BitmapData) []const u8 { return self.pixel_data[0..self.len()]; }
    };

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*Self {
        var config = c.ulCreateConfig();
        c.ulConfigSetDeviceScale(config, 1.0);

        var font_family = c.ulCreateString("Arial");
        c.ulConfigSetFontFamilyStandard(config, font_family);
        c.ulDestroyString(font_family);

        var resource_path = c.ulCreateString("./resources/");
        c.ulConfigSetResourcePath(config, resource_path);
        c.ulDestroyString(resource_path);

        c.ulConfigSetForceRepaint(config, true);
        c.ulConfigSetAnimationTimerDelay(config, 1.0 / 30.0);
        c.ulConfigSetUseGPURenderer(config, false);
        c.ulEnablePlatformFontLoader();

        var css_string = c.ulCreateString(stylesheet_data);
        c.ulConfigSetUserStylesheet(config, css_string);
        c.ulDestroyString(css_string);
        
        var base_dir = c.ulCreateString("./assets/");
        c.ulEnablePlatformFileSystem(base_dir);
        c.ulDestroyString(base_dir);

        var log_path = c.ulCreateString("./ultralight.log");
        c.ulEnableDefaultLogger(log_path);
        c.ulDestroyString(log_path);

        var renderer = c.ulCreateRenderer(config);
        c.ulDestroyConfig(config);

        var view = c.ulCreateView(renderer, width, height, true, null, false);

        var self_ptr = try allocator.create(Self);
        self_ptr.* = .{
            .allocator = allocator,
            .renderer = renderer,
            .view = view,
            .pixel_buffer = undefined,
            .ready = false,
        };
        c.ulViewSetFinishLoadingCallback(view, &ulOnFinishLoading, self_ptr);
        c.ulViewSetAddConsoleMessageCallback(view, &ulOnConsole, self_ptr);

        { // Create pixel buffer.
            var surface = c.ulViewGetSurface(view);
            var bitmap = c.ulBitmapSurfaceGetBitmap(surface);
            _ = c.ulBitmapLockPixels(bitmap);
            const bm_width: u32 = c.ulBitmapGetWidth(bitmap);
            const bm_height: u32 = c.ulBitmapGetHeight(bitmap);
            const bytes_per_pixel: u32 = c.ulBitmapGetBpp(bitmap);
            c.ulBitmapUnlockPixels(bitmap);
            const len = bm_width * bm_height * bytes_per_pixel;
            self_ptr.pixel_buffer = try allocator.alloc(u8, len);
        }

        return self_ptr;
    }

    pub fn deinit(self: *Self) void {
        c.ulDestroyView(self.view);
        c.ulDestroyRenderer(self.renderer);
        self.allocator.free(self.pixel_buffer);
        self.allocator.destroy(self);
    }

    pub fn loadHtml(self: *Self, bytes: [:0]const u8) void {
        self.ready = false;
        var html_string = c.ulCreateString(@ptrCast([*c]const u8, bytes));
        c.ulViewLoadHTML(self.view, html_string);
        c.ulDestroyString(html_string);
    }

    pub fn loadHtmlFromFile(self: *Self, path: []const u8) !void {
        var html_file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer html_file.close();
        const html_data = try html_file.readToEndAllocOptions(
            self.allocator, 
            10_000_000, 
            null, 
            @alignOf(u8),
            0,
        );
        defer self.allocator.free(html_data);
        self.loadHtml(html_data);
    }

    pub fn loadHtmlWithTemplate(self: *Self, bytes: [:0]const u8) !void {
        const html_data = try std.mem.replaceOwned(u8, self.allocator, html_template_data, "@fragment", bytes);
        defer self.allocator.free(html_data);
        const html_data_z = try self.allocator.dupeZ(u8, html_data);
        defer self.allocator.free(html_data_z);
        self.loadHtml(html_data_z);
    }

    pub fn tick(self: *Self) void {
        c.ulUpdate(self.renderer);
        c.ulRender(self.renderer);
    }

    pub fn tickUntilReady(self: *Self) void {
        while (!self.ready) {
            c.ulUpdate(self.renderer);
            c.ulRender(self.renderer);
        }
    }

    pub fn bitmapData(self: *Self) BitmapData {
        var surface = c.ulViewGetSurface(self.view);
        var bitmap = c.ulBitmapSurfaceGetBitmap(surface);
        var pixels = c.ulBitmapLockPixels(bitmap);
        const width: u32 = c.ulBitmapGetWidth(bitmap);
        const height: u32 = c.ulBitmapGetHeight(bitmap);
        const bytes_per_pixel: u32 = c.ulBitmapGetBpp(bitmap);
        var pixel_data = @ptrCast([*]u8, pixels);
        var len = width * height * bytes_per_pixel;
        for (0..(len/4)) |i| {
            self.pixel_buffer[i*4 + 0] = pixel_data[i*4 + 2];
            self.pixel_buffer[i*4 + 1] = pixel_data[i*4 + 1];
            self.pixel_buffer[i*4 + 2] = pixel_data[i*4 + 0];
            self.pixel_buffer[i*4 + 3] = pixel_data[i*4 + 3];
        }
        c.ulBitmapUnlockPixels(bitmap);

        return .{
            .width = width,
            .height = height,
            .bytes_per_pixel = bytes_per_pixel,
            .pixel_data = self.pixel_buffer,
        };
    }

    pub fn savePng(self: *Self, path: [*c]const u8) void {
        var surface = c.ulViewGetSurface(self.view);
        var bitmap = c.ulBitmapSurfaceGetBitmap(surface);
        c.ulBitmapSwapRedBlueChannels(bitmap);
        _ = c.ulBitmapWritePNG(bitmap, path);
    }

    fn onFinishLoadingHtml(self: *Self) void {
        self.ready = true;
    }
};

fn ulOnFinishLoading(
    user_data: ?*anyopaque, 
    caller: c.ULView,
    frame_id: c_ulonglong, 
    is_main_frame: bool,
    url: c.ULString,
) callconv(.C) void {
    _ = caller;
    _ = frame_id;
    _ = url; 
    var ul_ptr = @ptrCast(*Ultralight, @alignCast(@alignOf(Ultralight), user_data));
    if (is_main_frame) {
        ul_ptr.onFinishLoadingHtml();
    }
}

fn ulOnConsole(
    user_data: ?*anyopaque,
    caller: c.ULView,
    source: c.ULMessageSource,
    level: c.ULMessageLevel,
    message: c.ULString,
    line_number: c_uint,
    column_number: c_uint,
    source_id: c.ULString,
) callconv(.C) void {
    _ = caller;
    _ = source;
    _ = level;
    _ = line_number;
    _ = column_number;
    _ = source_id;
    var ul_ptr = @ptrCast(*Ultralight, @alignCast(@alignOf(Ultralight), user_data));
    
    const message_c_data: [*c]c_ushort = c.ulStringGetData(message);
    const message_len: usize = c.ulStringGetLength(message);
    const message_data = @ptrCast([*]u16, message_c_data);
    const m = std.unicode.utf16leToUtf8Alloc(ul_ptr.allocator, message_data[0..message_len]) catch unreachable;
    defer ul_ptr.allocator.free(m);
    std.log.info("[UL] {s}", .{ m });
}
