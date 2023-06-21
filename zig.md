@!debugMode 0
@!showNotes 1
@!defaultBackground #111211
@!makeSlot {"name": "right_body", "x": 0.6, "y": 0.23, "w": 0.3, "h": 0.6}
@!makeSlot {"name": "left_body", "x": 0.1, "y": 0.23, "w": 0.3, "h": 0.6}
@!makeSlot {"name": "left_image", "x": 0.1, "y": 0.23, "w": 0.45, "h": 0.6}
@!makeSlot {"name": "right_image", "x": 0.4, "y": 0.23, "w": 0.5, "h": 0.6}
@!makeSlot {"name": "fullscreen_padding", "x": 0.02, "y": 0.02, "w": 0.96, "h": 0.96}
@!makeColor {"name": "secondary", "color": "#F0544F" }
# -

# 
@htmlFile "assets/zig_intro.html"

# ziglang.org
@image {"path": "assets/img/zigwebsite.png", "slot": "default_body", "mode": "fit_h"}
@note "Started in 2016 by Andrew Kelley, became a non-profit org in 2020."

# Overview
@bodySize 50
@bodyColor "secondary"
- {custom:highlight}How I discovered Zig.{/custom}
- {custom:highlight}What it does and doesn't have.{/custom}
- {custom:highlight}Using Zig as a toolchain.{/custom}
- {custom:highlight}Code examples.{/custom}
- {custom:highlight}Gamedev.{/custom}

# How I Discovered Zig
@titleColor "secondary"
@image {"path": "assets/img/aoc_example.png", "slot": "left_image", "mode": "fit_w"}
@bodySlot "right_body"
@note "Example of an Advent of Code puzzle. This one is about validating a big list of passwords according to some arbitrary rules."
{s:50}Advent of Code{/s}

A series of programming puzzles, that you can solve with a language of your choice.

Each puzzle gives you an "input" text file, which you then compute into a single numeric answer.

@append
In 2019 I tried a bunch of puzzles in C99, Rust, and Zig.

@append
I alread knew C pretty well and I found Rust to be just as complicated, if not more, as C++ and compile times annoyingly slow.

@append
I ended up enjoying Zig the most. It was simple and elegant.


# Small Size
@image {"path": "assets/img/zigdownload.png", "slot": "right_image", "mode": "fit_w"}
@bodySlot "left_body"
All you need to get started is a 70mb compiler.

@append
You can compile Zig, C, and C++...

@append
To machine code for almost any platform, from any platform!

# Low Complexity
@note "You can learn Zig in a day."
Took me a few hours to read the language reference, maybe a day to "grok" it.
{s:40}47 Keywords{/s}
{c:#F0544F}{f:mono}addrspace, align, allowzero, and, anyframe, anytype, asm, async, await, break, catch, comptime, const, continue, defer, else, enum, errdefer, error, export, extern, fn, for, if, inline, linksection, noalias, noinline, nosuspend, or, orelse, packed, pub, resume, return, struct, suspend, switch, test, threadlocal, try, union, unreachable, usingnamespace, var, volatile, while{/f}{/c}

# C++ has 125!
@image {"path": "assets/img/cppkeyword1.png", "slot": "right_image", "mode": "fit_w"}
@image {"path": "assets/img/cppkeyword2.png", "slot": "left_image", "mode": "fit_w"}
@image {"path": "assets/img/cppkeyword3.png", "slot": "right_image", "mode": "fit_w"}

# What it does and doesn't have
@titleColor "secondary"

# What it doesn't have
- {c:#5050f0}No {custom:flash_red}hidden{/custom} control flow.{/c}
@append
    - Favours explicit and verbose rather than terse and magic syntax.
    - A codebase should be easy to read.
@append
- {c:#5050f0}No operator overloading, or function overloading.{/c}
@append
    - In {c:#a5a555}C++{/c} the "+" operator could be calling lots of instructions.
@append
- {c:#5050f0}No hidden allocations.{/c}
@append
    - {f:mono}allocPrint(allocator, "cost: £{{d}}", .{{ 42 }});{/f}
    - No hidden constructors/destructors.
    - Destroy resources with {f:mono}defer{/f}.
@append
- {c:#5050f0}No macros.{/c}
@append
    - I hate macros, you hate macros.
@append
    - Zig code can be run at compile time though which we'll see more of later.
@append
- {c:#5050f0}No OOP-isms.{/c}
@append
    - Use plain old data structures.
    - Tagged Unions, Enums, and exhaustive switch.
    - Bring your own virtual tables.

# What is does have
- {c:#50f050}Nice pointers{/c} {s:20}{c:#cccccc}(with safety features in a Debug build){/c}{/s}.
@append
    - {f:mono}*i32{/f} {c:#909090}<- ptr to single int, cannot be nullptr.{/c}
@append
    - {f:mono}?*i32{/f} {c:#909090}<- could be nullptr.{/c}
@append
    - {f:mono}*const i32{/f} {c:#909090}<- immutable ptr to a single int.{/c}
@append
    - {f:mono}[*]i32{/f} {c:#909090}<- ptr to zero or more ints.{/c}

@append
- {c:#50f050}Slices.{/c}
@append
    - {f:mono}[]i32{/f} {c:#909090}<- "fat" ptr, with length included.{/c}
@append
    - {f:mono}[]const i32{/f} {c:#909090}<- immutable slice.{/c}
@append
    - {f:mono}var slice = arr[3..5];{/f}
@append
    - Slice/Array bounds checking (in Debug build).

@append
- {c:#50f050}{custom:wiggle}Comptime.{/custom}{/c}
@append
    - {f:mono}comptime blah(42);{/f} {c:#909090}<- executed at compile-time.{/c}
@append
    - {f:mono}fn Blah(comptime T: type) T{/f} {c:#909090}<- argument is compile-time known{/c}
@append
    - {f:mono}var list = ArrayList(*f32).init();{/f} {c:#909090}<- generic data structure.{/c}

# What is does have
- {c:#50f050}{custom:wiggle}Composable{/custom} Allocators:{/c}
@append
    - Get malloc/free style allocation with {f:mono}c_allocator{/f} {s:20}(If libc linked){/s}
@append
    - {f:mono}GeneralPurposeAllocator{/f}: slightly slower than above but will detect memory leaks and use-after-free.
@append
    - {f:mono}FixedBufferAllocator{/f}: provide your own backing byte buffer.
@append
    - {f:mono}TestAllocator{/f} specifically made for running unit tests.
@append
    - Wrap any of the above in an {f:mono}ArenaAllocator{/f} to get a memory arena/bump allocator.
@append

- {c:#50f050}Lazy compilation.{/c}
@append
    - You only compile the functions you use.
    - No need for pre-processor defines, dead branches are eliminated during compilation.
@append

- {c:#50f050}Interops nicely with C{/c}
@append
    - No need for FFI.
    - Can make data structures and function conform to C ABI.


# Zig is better at C than C
@image {"path": "assets/img/zig_c_example.png", "slot": "default_body", "mode": "fit_w"}

# Using Zig as a Toolchain
@titleColor "secondary"
@image {"path": "assets/img/chrome_avTzyWdHi1.png", "slot": "default_body", "mode": "fit_h"}

# Cross Compilation
{c:#5050f0}Supported Architecture{/c}:
- x86_64
- x86
- aarch64
- arm
- mips
- riscv64
- sparc64
- powerpc64
- wasm32
(As of Zig 0.10)
@bodySlot "right_body"
{c:#50f050}Supported OS{/c}:
- freestanding
- Linux 3.16+
- macOS 11+
- Windows 8.1+
- WASI
@note "Tier 1 = entire std library works and libc available."

# Cross Compilation
Build commands:
{c:#C6D8D3}{f:mono}zig build-exe main.zig -O Debug -target x86_64-windows{/f}{/c}
{c:#FDF0D5}{f:mono}zig build-lib library.zig -O ReleaseFast -target aarch64-linux-gnu{/f}{/c}
@append
Drop-in C compiler:
{c:#C6D8D3}{f:mono}zig cc -o hello.exe hello.c{/f}{/c}
@append
Build system (begone cmake, ninja, makefiles):
{c:#FDF0D5}{f:mono}zig build{/f}{/c}

# build.zig
@image {"path": "assets/img/build_example.png", "slot": "default_body", "mode": "fit_h"}

# 
@bodyAlign "center"
@bodySize 72
@bodyColor "secondary"
{custom:wiggle}Example Time{/custom}

# Useless Example
@codeEditor "hello_world"
@codeEditorSize 24
const std = @import("std");

pub fn main() void {
    const stdout = std.io.getStdOut().writer();
    #cursorstdout.writeAll("Hello world.\n");
}

# Slightly useful example
@jumpHere
@codeEditor "calc_slope"
@codeEditorSize 24
//! 5 3 1
const std = @import("std");
const parseInt = std.fmt.parseInt;
// fn parseInt(comptime T: type, buf: []const u8, radix: u8) ParseIntError!T

pub fn main() !void { #cursor
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len == 4) {
        const m = parseInt(i32, args[1], 10);
        const x = parseInt(i32, args[2], 10);
        const b = parseInt(i32, args[3], 10);
        const slope = m * x + b;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{d}*{d}+{d} = {d}\n", .{m, x, b, slope});
    } else {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("Expected three integer arguments.");
    }
}

# Comptime
@codeEditor "comptime1"
const std = @import("std");

const Node = struct {
    payload: [3]u32,
    next: ?*Node = null,
};

pub fn main() void {
    var node0 = Node{ .payload = [3]u32{1,2,3} };
    var node1 = Node{ .payload = [3]u32{4,5,6} };
    node0.next = &node1;
    std.debug.print("{any}, {any}\n", .{node0, node1});#cursor
}

# Comptime
@codeEditor "comptime2"
const std = @import("std");

fn Node(comptime PayloadT: type) type {
    return struct {
        payload: PayloadT,
        next: ?*@This() = null,
    };
}

pub fn main() void {
    const BoolNode = Node(bool);
    var node0 = BoolNode{ .payload = true };
    var node1 = BoolNode{ .payload = false };
    node0.next = &node1;
    std.debug.print("{any}, {any}\n", .{node0, node1});#cursor
}

# Gamedev
@titleColor "secondary"
@titleAlign "center"

# zig-gamedev
@titleAlign "right"
@image {"path": "assets/img/chrome_gFEcaelZR2.png", "slot": "fullscreen_padding", "mode": "fit_h" }

# examples
@titleAlign "right"
@image {"path": "assets/img/chrome_6hZOjSClfE.png", "slot": "fullscreen_padding", "mode": "fit_h" }

# modules
@titleAlign "right"
@image {"path": "assets/img/chrome_tZ0PVqO4nt.png", "slot": "fullscreen_padding", "mode": "fit_h" }

# Mach Engine
@titleAlign "right"
@image {"path": "assets/img/chrome_KedAzlNvx6.png", "slot": "fullscreen_padding", "mode": "fit_h" }

# Examples
@titleAlign "right"
@image {"path": "assets/img/chrome_ZnsyPLByd5.png", "slot": "fullscreen_padding", "mode": "fit_h" }

# Raylib
@titleAlign "right"
@image {"path": "assets/img/chrome_XIkvx08gQr.png", "slot": "fullscreen_padding", "mode": "fit_h" }

# Further Reading

{custom:wiggle}{c:#5050f0}Learning{/c}{/custom}
- {custom:highlight}ziglang.org{/custom}      {c:#ffa0b0}Download & Docs{/c}
- {custom:highlight}ziglearn.org{/custom}     {c:#ffa0b0}Really nice tutorials on getting started{/c}
- {custom:highlight}github.com/ratfactor/ziglings{/custom}    {c:#ffa0b0}Learn by fixing tiny broken programs{/c}
- {custom:highlight}"Intro to the Zig Programming Language • Andrew Kelley • GOTO 2022"{/custom}

{custom:wiggle}{c:#50f050}Community{/c}{/custom}
- {custom:highlight}zig.news{/custom}         {c:#ffa0b0}Community blog site for zig articles{/c}
- {custom:highlight}ziggit.dev{/custom}        {c:#ffa0b0}Forums{/c}
- {custom:highlight}Discord "Zig Programming Language"{/custom}   {c:#ffa0b0}Help and compiler discussion{/c}
