const b_use_ultralight = @import("build_options").ultralight;
pub usingnamespace @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    if (b_use_ultralight) {
        @cInclude("AppCore/CAPI.h");
        @cInclude("Ultralight/CAPI.h");
    }
});
