const graphics = @import("./gui/graphics.zig");
const ui = @import("./gui/ui.zig");

const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zstbi = @import("zstbi");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    zstbi.init(arena);
    defer zstbi.deinit();

    zglfw.init() catch {
        std.log.err("Failed to initialize GLFW library.", .{});
        return;
    };
    defer zglfw.terminate();

    const window = zglfw.Window.create(1600, 1000, ui.window_title, null) catch {
        std.log.err("Failed to create the window.", .{});
        return;
    };
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    const graphics_state = graphics.create(allocator, window) catch {
        std.log.err("Failed to initialize the graphics state.", .{});
        return;
    };
    defer graphics_state.deinit(allocator);

    const ui_state = ui.create(allocator, graphics_state) catch {
        std.log.err("Failed to initialize the UI state.", .{});
        return;
    };
    defer ui_state.deinit(allocator);

    // we should be initialized here
    zgui.io.setIniFilename(null);

    while (!window.shouldClose() and window.getKey(.escape) != .press and !ui_state.quit) {
        zglfw.pollEvents();
        graphics_state.new_frame();
        ui_state.draw();
        graphics_state.draw();
    }
}
