const graphics = @import("./gui/graphics.zig");
const ui = @import("./gui/ui.zig");
const fs = @import("./fs.zig");
const db = @import("./db.zig");

const builtin = @import("builtin");
const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zstbi = @import("zstbi");
const clap = @import("clap");

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    },
};

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-v, --version  Output version information and exit.
        \\
    );

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = allocator,
    }) catch |err| {
        switch (err) {
            clap.streaming.Error.InvalidArgument => {
                std.log.err("invalid flag passed", .{});
            },
            else => std.log.err("{}", .{err}),
        }
        return;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{}) catch |err| {
            std.log.err("failed to show help text: {}", .{err});
            return;
        };
        return;
    }
    if (res.args.version != 0) {
        std.debug.print("0.0.0", .{});
        return;
    }

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

    var thread_pool = allocator.create(std.Thread.Pool) catch |err| {
        std.log.err("failed to create thread pool: {}", .{err});
        return;
    };
    thread_pool.init(.{
        .allocator = allocator,
        .n_jobs = std.Thread.getCpuCount() catch |err| {
            std.log.err("failed to initialize thread pool: {}", .{err});
            return;
        },
    }) catch |err| {
        std.log.err("failed to initialize thread pool: {}", .{err});
        return;
    };
    defer thread_pool.deinit();
    defer allocator.destroy(thread_pool);

    const ui_state = ui.create(allocator, graphics_state, fs_state, thread_pool) catch |err| {
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
        std.atomic.spinLoopHint();
    }

    fs_state.write_db_file(db.Paths, &ui_state.images_state.image_paths);
    fs_state.write_db_file(db.Tags, &ui_state.images_state.image_tags);
}
