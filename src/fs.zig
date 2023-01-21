const std = @import("std");
const zstbi = @import("zstbi");
const img = @import("./gui/image.zig");
const db = @import("./db.zig");

const FindDirError = error{NotFound};

// it is up to the caller to destroy the resulting pointer
fn find_cache_dir(alloc: std.mem.Allocator) ![]const u8 {
    if (std.os.getenv("XDG_CACHE_HOME")) |cache_dir| {
        return try std.fmt.allocPrint(alloc, "{s}/levent", .{cache_dir});
    } else if (std.os.getenv("HOME")) |home_dir| {
        return try std.fmt.allocPrint(alloc, "{s}/.cache/levent", .{home_dir});
    } else {
        std.log.err("no cache dir found", .{});
        return FindDirError.NotFound;
    }
}

// it is up to the caller to destroy the resulting pointer
fn find_data_dir(alloc: std.mem.Allocator) ![]const u8 {
    return try std.fs.getAppDataDir(alloc, "levent");
}

// this function assumes zstbi is initialized.
pub inline fn read_image(image_path: [:0]const u8) !zstbi.Image {
    return try zstbi.Image.init(image_path, 4);
}

pub const FsState = struct {
    cache_dir: []const u8,
    data_dir: []const u8,
    image_paths_db_path: [:0]const u8,
    image_tags_db_path: [:0]const u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !*FsState {
        const state = try alloc.create(FsState);

        const cache_dir = try find_cache_dir(alloc);
        errdefer alloc.free(cache_dir);
        std.log.info("using cache directory: {s}", .{cache_dir});
        std.fs.makeDirAbsolute(cache_dir) catch |err| {
            if (err != std.os.MakeDirError.PathAlreadyExists) {
                std.log.err("could not create cache directory", .{});
                return err;
            } else {
                std.log.debug("cache dir already exists", .{});
            }
        };

        const data_dir = try find_data_dir(alloc);
        errdefer alloc.free(data_dir);
        std.log.info("using data directory: {s}", .{data_dir});
        std.fs.makeDirAbsolute(data_dir) catch |err| {
            if (err != std.os.MakeDirError.PathAlreadyExists) {
                std.log.err("could not create data directory", .{});
                return err;
            } else {
                std.log.debug("data dir already exists", .{});
            }
        };

        const image_paths_db_path = try std.fmt.allocPrintZ(
            alloc,
            "{s}/image_paths.lvnt",
            .{data_dir},
        );
        errdefer alloc.free(image_paths_db_path);

        const image_tags_db_path = try std.fmt.allocPrintZ(
            alloc,
            "{s}/image_tags.lvnt",
            .{data_dir},
        );
        errdefer alloc.free(image_tags_db_path);

        state.* = .{
            .alloc = alloc,
            .cache_dir = cache_dir,
            .data_dir = data_dir,
            .image_paths_db_path = image_paths_db_path,
            .image_tags_db_path = image_tags_db_path,
        };

        return state;
    }

    pub fn write_thumbnail(
        self: *const FsState,
        og_image: *const zstbi.Image,
        thumbnail: *const zstbi.Image,
    ) !void {
        const image_id = img.id.hash(og_image.data);
        const path = try std.fmt.allocPrintZ(
            self.alloc,
            "{s}/{d}.jpg",
            .{ self.cache_dir, image_id },
        );
        defer self.alloc.free(path);
        try thumbnail.writeToFile(path, .{ .jpg = .{ .quality = 70 } });
    }

    fn get_db_filepath(self: *const FsState, comptime DbType: type) [:0]const u8 {
        // zig fmt: off
        if (DbType == db.Paths) return self.image_paths_db_path
        else if (DbType == db.Tags) return self.image_tags_db_path
        else @compileError("no filepath for this DB type");
        // zig fmt: on
    }

    pub fn read_db_file(self: *const FsState, comptime DbType: type) !DbType {
        const db_path = self.get_db_filepath(DbType);

        var maybe_db_file: ?std.fs.File = db: {
            break :db std.fs.openFileAbsoluteZ(db_path, .{}) catch |err| {
                if (err == std.fs.File.OpenError.FileNotFound) {
                    std.log.warn("no db file found at {s}", .{db_path});
                } else {
                    std.log.err("could not open db file: {}", .{err});
                }
                break :db null;
            };
        };

        if (maybe_db_file) |file| {
            defer file.close();
            std.log.info("reading db file from '{s}'", .{db_path});
            const metadata = try file.metadata();
            const data = try file.readToEndAlloc(self.alloc, @intCast(usize, metadata.size()));
            defer self.alloc.free(data);
            return try DbType.from_data(data, self.alloc);
        } else {
            std.log.info("creating a new db", .{});
            return DbType.init(self.alloc);
        }
    }

    pub fn write_db_file(
        self: *const FsState,
        comptime DbType: type,
        db_value: *const DbType,
    ) void {
        const db_path = self.get_db_filepath(DbType);

        // open or create the db file
        const db_file = std.fs.createFileAbsoluteZ(
            db_path,
            .{
                .truncate = true,
                .exclusive = false,
            },
        ) catch |err| {
            std.log.err(
                "could not create or open db file '{s}': {}",
                .{ db_path, err },
            );
            return;
        };
        defer db_file.close();
        std.log.info("saving db {s} ...", .{db_path});

        // save db file
        db_value.writeToFile(db_file) catch |err| {
            std.log.err("could not save to db file: {}", .{err});
        };
    }

    pub fn deinit(self: *FsState) void {
        self.alloc.free(self.cache_dir);
        self.alloc.free(self.data_dir);
        self.alloc.free(self.image_paths_db_path);
        self.alloc.free(self.image_tags_db_path);
        self.alloc.destroy(self);
    }
};
