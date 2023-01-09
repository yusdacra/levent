const std = @import("std");
const zstbi = @import("zstbi");
const img = @import("./gui/image.zig");

const FindCacheDirError = error{NotFound};

// it is up to the caller to destroy the resulting pointer
fn find_cache_dir(alloc: std.mem.Allocator) ![]const u8 {
    if (std.os.getenv("XDG_CACHE_HOME")) |cache_dir| {
        return try std.fmt.allocPrint(alloc, "{s}/levent", .{cache_dir});
    } else if (std.os.getenv("HOME")) |home_dir| {
        return try std.fmt.allocPrint(alloc, "{s}/.cache/levent", .{home_dir});
    } else {
        std.log.err("no cache dir found", .{});
        return FindCacheDirError.NotFound;
    }
}

// this function assumes zstbi is initialized.
pub inline fn read_image(image_path: [:0]const u8) !zstbi.Image {
    return try zstbi.Image.init(image_path, 4);
}

pub const FsState = struct {
    cache_dir: []const u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !*FsState {
        const state = try alloc.create(FsState);
        const cache_dir = try find_cache_dir(alloc);
        std.log.info("using cache directory: {s}", .{cache_dir});
        std.fs.makeDirAbsolute(cache_dir) catch |err| {
            if (err != std.os.MakeDirError.PathAlreadyExists) {
                std.log.err("could not create cache directory", .{});
                return err;
            } else {
                std.log.debug("cache dir already exists", .{});
            }
        };
        state.* = .{
            .alloc = alloc,
            .cache_dir = cache_dir,
        };
        return state;
    }

    pub fn write_thumbnail(self: *const FsState, image: *const zstbi.Image) !void {
        const image_id = img.id.hash(image.data);
        const path = try std.fmt.allocPrintZ(
            self.alloc,
            "{s}/{d}.jpg",
            .{ self.cache_dir, image_id },
        );
        defer self.alloc.destroy(path.ptr);
        try image.write_to_file(path, .{ .Jpeg = .{ .quality = 70 } });
    }

    pub fn deinit(self: *FsState) void {
        self.alloc.destroy(self.cache_dir.ptr);
        self.alloc.destroy(self);
    }
};
