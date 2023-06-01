@c This is a presentation file. You first define presentation-global parameters, then a slide title,
@c then a slide body (which can contain slide parameters), then another slide title and so on.
@c Presentation-global parameters start with @!
@c By now you might have guessed that lines starting with @c are comments, and are ignored by the application.

@c The @!makeSlot parameter defines a rectangle in which you can put text and images inside.
@c The rectangle co-ordinates are in screen-space, with the top-left being 0,0 and bottom-right being 1,1.
@!makeSlot {"name": "right", "x": 0.5, "y": 0, "w": 0.5, "h": 1}
@!makeSlot {"name": "left", "x": 0, "y": 0, "w": 0.5, "h": 1}
@!makeSlot {"name": "bottom", "x": 0, "y": 0.5, "w": 1, "h": 0.5}
@!makeSlot {"name": "bottom_body", "x": 0.1, "y": 0.5, "w": 0.8, "h": 0.5}
@!makeSlot {"name": "left_body", "x": 0.15, "y": 0.25, "w": 0.25, "h": 0.75}
@!makeSlot {"name": "right_body", "x": 0.65, "y": 0.25, "w": 0.25, "h": 0.75}

@c The @!makeColor defines a color preset, that you can refer back to with it's name.
@c The color value is six character hexadecimal, in the format #rrggbb.
@!makeColor {"name": "red", "color": "#ff0000" }

@c This defines the default background for all slides.
@!defaultBackground #111211

@c Below is how a new slide is started, the text following the '#' will be used as the title.
# Controls
Lets get the controls first:

- Left/Right arrow keys to change slide.
- Cmd-Left/Cmd-Right also works to change slide.
- Esc to quit.
- F3 to toggle fullscreen.
- F2 to force reload the presentation file (but this is automatically reloaded when you save).
- F1 to compile and run zig code (if there's a code editor slide showing).
- F1 to compile and run zig code (if there's a code editor slide showing).

# Zig Presentation is easy
- Everything following a slide's tile is part of the slide's body.

- The body text is automatically put into a slot named "defaultBody".

- Until another slide title or @append is declared (see below).

@append
- The @append param will create a duplicate slide that... 

@append
- ...contains everything up until the next @append.

@append
- This creates the illusion of bullet points...

@append
- ...appearing one by one.

@append
- Presentations are automatically reloaded when you edit the file, try it.

# Per-slide parameters
@background #117071
@titleAlign "center"
@bodyAlign "center"
@bodySize 30
Each slide can have custom parameters, overriding the default ones:
- @background
- @titleSlot
- @titleAlign
- @titleSize
- @titleColor
- @bodySlot
- @bodyAlign
- @bodySize
- @bodyColor

# Multiple slots
@titleAlign "center"
@bodySlot "left_body"
This text will appear in the "left_body" slot.

@bodySlot "right_body"
This text will appear in the "right_body" slot.

# Images
@background "assets/img/ribbon.jpg"
@bodySlot "left_body"
@image {"path": "assets/img/bricks.jpg", "slot": "right", "mode": "fill"}
{c:#00ff00}The background can also be set to an image. Most well known image formats are supported.{/c}

You can also put images into the body.

The possible image modes are: "fill", "fit_w", "fit_h", and "repeat".

# Rich Text
@note "Notes are shown to stdout when slide is opened, which means you can have the console open on"
@note " a seperate monitor. But you can also make notes appear at the bottom of the slide with @!showNotes 1"
Text can be {s:10}small{/s} or it can be {s:50}big{/s}.
It can be {c:#ff0000}red{/c} or it could be {c:#0000ff}blue{/c}.
The font {f:mono}can be changed{/f}.

{custom:wiggle}Custom formatters{/custom} can {custom:flash_red}be made{/custom}.

# A simple but useless program.
@c You can make slides into interactive code editors!
@c If the code is Zig, you can press F1 to compile and run it! Stdout and Stderr will be shown on the slide.
@c Put "#cursor" in the text to mark where the editor's cursor should start.
@codeEditor "hello_world"
const std = @import("std");
const output = std.io.getStdOut().writer();
pub fn main() !void {
    try output.writeAll("Hello world.\n");
    #cursor
}

# A simple and useful program.
@c Make the first line a //! comment to pass arguments to the process.
@codeEditor "calc_slope"
//! 5 3 1
const std = @import("std");
const output = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    if (args.len == 4) {
        const parseInt = std.fmt.parseInt;
        const m = try parseInt(i32, args[1], 10);
        const x = try parseInt(i32, args[2], 10);
        const b = try parseInt(i32, args[3], 10);
        const answer = m * x + b;
        try output.print("{d}*{d}+{d} = {d}\n", .{m, x, b, answer});
    } else {
        try stderr.writeAll("Expected three integer arguments.");
    }
}

# Hello, again
@c Code editors are given a name, you can reuse the name in multiple slides to come back to the same
@c text buffer.
@codeEditor "hello_world"

# The end.
{s:70}{custom:wiggle}That's all for now!{/custom}{/s}