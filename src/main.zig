const graphics = @import("./gui/graphics.zig");
const ui = @import("./gui/ui.zig");
const fs = @import("./fs.zig");

const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zstbi = @import("zstbi");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const fs_state = fs.FsState.init(allocator) catch |err| {
        std.log.err("Failed to initialize FS state: {}", .{err});
        return;
    };
    defer fs_state.deinit();

    zstbi.init(allocator);
    defer zstbi.deinit();

    zglfw.init() catch |err| {
        std.log.err("Failed to initialize GLFW library: {}", .{err});
        return;
    };
    defer zglfw.terminate();

    const window = zglfw.Window.create(1600, 1000, ui.window_title, null) catch |err| {
        std.log.err("Failed to create the window: {}", .{err});
        return;
    };
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    const graphics_state = graphics.create(allocator, window) catch |err| {
        std.log.err("Failed to initialize the graphics state: {}", .{err});
        return;
    };
    defer graphics_state.deinit(allocator);

    const ui_state = ui.create(allocator, graphics_state, fs_state) catch |err| {
        std.log.err("Failed to initialize the UI state: {}", .{err});
        return;
    };
    defer ui_state.deinit(allocator);

    // we should be initialized here

    zgui.io.setIniFilename(null);

    while (!window.shouldClose() and !ui_state.quit) {
        zglfw.pollEvents();
        graphics_state.new_frame();
        ui_state.draw();
        graphics_state.draw();
    }
}
