const graphics = @import("./gui/graphics.zig");
const ui = @import("./gui/ui.zig");
const fs = @import("./fs.zig");
const db = @import("./db.zig");

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
    defer ui_state.deinit();

    // we should be initialized here

    zgui.io.setIniFilename(null);

    while (!window.shouldClose() and !ui_state.quit) {
        zglfw.pollEvents();
        graphics_state.new_frame();
        ui_state.draw();
        graphics_state.draw();
    }

    // open or create the db file
    const db_file = std.fs.createFileAbsoluteZ(
        fs_state.images_db_path,
        .{
            .truncate = true,
            .exclusive = false,
        },
    ) catch |err| {
        std.log.err(
            "could not create or open db file '{s}': {}",
            .{ fs_state.images_db_path, err },
        );
        return;
    };
    defer db_file.close();
    std.log.info("saving db...", .{});
    // save db file
    ui_state.images_state.image_paths.writeToFile(db_file) catch |err| {
        std.log.err("could not save to db file: {}", .{err});
    };
}
