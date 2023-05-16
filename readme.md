# Zig Presentation
Create interactive presentations/slide decks with a simple markup text file.

![Example screenshot 1](images/zig-presentation-shot-01.png)
![Example screenshot 2](images/zig-presentation-shot-02.png)

# How to build and run.
Uses a build.zig as the build process. In your terminal use command `zig build`, then `zig-out/bin/zig-presentation presentation.md` to run.

Alternatively you can use command `zig build run -- presentation.md`.

Read `presentation.md` for how to create a presentation file.

# Dependencies
- Zig 0.11.x
- Glfw 3.x (included in lib)
- Nanovg-zig (included in lib)