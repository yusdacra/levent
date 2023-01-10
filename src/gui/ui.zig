const graphics = @import("./graphics.zig");
const img = @import("./image.zig");
const uitils = @import("./ui/utils.zig");
const utils = @import("../utils.zig");
const fs = @import("../fs.zig");
const db = @import("../db.zig");

const std = @import("std");
const zgui = @import("zgui");
const zstbi = @import("zstbi");
const nfd = @import("nfd");
const ring_buffer = @import("zig-ring-buffer");

const print = std.debug.print;

pub const window_title = "levent";

const RingBuffer = ring_buffer.RingBuffer;
const Image = zstbi.Image;

const DecodedImage = struct {
    destroy_path: bool,
    do_add: bool,
    id: ?img.ImageId,
    image: ?Image,
    thumbnail: ?Image,
    path: [:0]const u8,
};

const ImageState = struct {
    is_open: bool = false,
};
const ImageStates = std.AutoArrayHashMap(img.ImageId, ImageState);

const ImagesState = struct {
    image_paths: db.Images,
    // loaded images
    images: img.ImageMap,
    thumbnails: img.ImageMap,
    alloc: std.mem.Allocator,
    gfx: *graphics.GraphicsState,

    fn load_image(self: *ImagesState, decoded: DecodedImage) !img.ImageId {
        const image_id = decoded.id orelse img.id.hash(decoded.image.?.data);
        if (decoded.do_add) {
            try self.image_paths.add(image_id, decoded.path);
        }
        if (decoded.destroy_path) {
            self.alloc.destroy(decoded.path.ptr);
        }
        if (decoded.thumbnail) |thumbnail| {
            const thumbnail_handle = img.load_image(self.gfx.gctx, &thumbnail);
            try self.thumbnails.add(image_id, thumbnail_handle);
        } else {
            const handle = img.load_image(self.gfx.gctx, &decoded.image.?);
            try self.images.add(image_id, handle);
        }
        return image_id;
    }

    inline fn get_path(self: *const ImagesState, id: img.ImageId) ?[:0]const u8 {
        return self.image_paths.map.get(id);
    }

    inline fn get_image(self: *ImagesState, id: img.ImageId) ?img.ImageHandle {
        return self.images.get(id);
    }

    inline fn get_thumbnail(self: *ImagesState, id: img.ImageId) ?img.ImageHandle {
        return self.thumbnails.get(id);
    }

    fn deinit(self: *ImagesState) void {
        self.image_paths.deinit();
        self.images.deinit();
        self.thumbnails.deinit();
        // gfx is deinit in main.zig so it's fine
    }
};

fn impl_select_image(
    buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *const fs.FsState,
) !void {
    const file_path = try nfd.openFileDialog(null, null);
    if (file_path) |path| {
        defer nfd.freePath(path);
        // this will be put in Images and will be destroyed with it
        const image_path = try std.fmt.allocPrintZ(alloc, "{s}", .{path});
        decode_image(buffer, alloc, fs_state, image_path, true, true, false);
    }
}

fn impl_select_folder(
    buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *const fs.FsState,
) !void {
    const maybe_dir_path = try nfd.openFolderDialog(null);
    if (maybe_dir_path) |dir_path| {
        defer nfd.freePath(dir_path);
        var dir = try std.fs.openIterableDirAbsoluteZ(dir_path, .{});
        var walker = try dir.walk(alloc);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind == .File) {
                // this will be put in Images and will be destroyed with it
                const file_path = try std.fmt.allocPrintZ(
                    alloc,
                    "{s}/{s}",
                    .{ dir_path, entry.path },
                );
                decode_image(buffer, alloc, fs_state, file_path, true, true, false);
            }
        }
    }
}

fn impl_load_thumbnails(
    buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *const fs.FsState,
    ids_to_load: []const img.ImageId,
) !void {
    defer alloc.free(ids_to_load);
    for (ids_to_load) |id| {
        decode_thumbnail(buffer, alloc, fs_state, id);
    }
}

fn decode_image(
    buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *const fs.FsState,
    file_path: [:0]const u8,
    do_add: bool,
    make_thumbnail: bool,
    destroy_path: bool,
) void {
    std.log.debug("started decoding image on path {s}", .{file_path});
    var image = fs.read_image(file_path) catch |err| {
        std.log.err("could not decode image: {}", .{err});
        if (!do_add and destroy_path) alloc.destroy(file_path.ptr);
        return;
    };
    var thumbnail = thumb: {
        if (make_thumbnail) {
            var temp = img.make_thumbnail(&image);
            fs_state.write_thumbnail(&image, &temp) catch |err| {
                std.log.err("could not write thumbnail: {}", .{err});
            };
            break :thumb temp;
        } else {
            break :thumb null;
        }
    };
    // trust that we will deinit the image later (hopefully!)
    buffer.produce(.{
        .destroy_path = destroy_path,
        .do_add = do_add,
        .thumbnail = thumbnail,
        .image = image,
        .path = file_path,
        .id = null,
    }) catch |err| {
        std.log.err("ring buffer err: {}", .{err});
        if (thumbnail) |*thumb| thumb.deinit();
        image.deinit();
        if (!do_add and destroy_path) alloc.destroy(file_path.ptr);
    };
}

fn decode_thumbnail(
    buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *const fs.FsState,
    id: img.ImageId,
) void {
    const file_path = std.fmt.allocPrintZ(
        alloc,
        "{s}/{d}.jpg",
        .{ fs_state.cache_dir, id },
    ) catch |err| {
        std.log.err("can't allocate: {}", .{err});
        return;
    };
    std.log.debug("started decoding image on path {s}", .{file_path});
    var thumbnail = fs.read_image(file_path) catch |err| {
        std.log.err("could not decode thumbnail image: {}", .{err});
        alloc.destroy(file_path.ptr);
        return;
    };
    // trust that we will deinit the image later (hopefully!)
    buffer.produce(.{
        .destroy_path = true,
        .do_add = false,
        .thumbnail = thumbnail,
        .image = null,
        .path = file_path,
        .id = id,
    }) catch |err| {
        std.log.err("ring buffer err: {}", .{err});
        thumbnail.deinit();
        alloc.destroy(file_path.ptr);
    };
}

pub const UiState = struct {
    images_state: ImagesState,
    // images we'll show
    image_states: ImageStates,
    image_buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *fs.FsState,
    gfx: *graphics.GraphicsState,
    quit: bool = false,

    fn select_image(self: *UiState) void {
        var thread = std.Thread.spawn(
            .{},
            impl_select_image,
            .{ self.image_buffer, self.alloc, self.fs_state },
        ) catch |err| {
            std.log.err("cannot spawn thread: {}", .{err});
            return;
        };
        thread.detach();
    }

    fn select_folder(self: *UiState) void {
        var thread = std.Thread.spawn(
            .{},
            impl_select_folder,
            .{ self.image_buffer, self.alloc, self.fs_state },
        ) catch |err| {
            std.log.err("cannot spawn thread: {}", .{err});
            return;
        };
        thread.detach();
    }

    fn add_image(self: *UiState, id: img.ImageId, both_size: u32) bool {
        var buf = img.id.new_str_buf();
        const id_str = img.id.to_str(id, &buf);

        const maybe_image = self.images_state.get_thumbnail(id);

        if (maybe_image) |image| {
            const tex_id = self.gfx.gctx.lookupResource(image.texture).?;
            const is_wide = image.width > image.height;
            const size = size: {
                if (is_wide) {
                    break :size image.fit_to_width_size(both_size);
                } else {
                    break :size image.fit_to_height_size(both_size);
                }
            };
            const padding = pad: {
                if (is_wide) {
                    break :pad [_]f32{
                        0.0,
                        (@intToFloat(f32, both_size) - size[1]) / 2.0,
                    };
                } else {
                    break :pad [_]f32{
                        (@intToFloat(f32, both_size) - size[0]) / 2.0,
                        0.0,
                    };
                }
            };

            uitils.pushStyleVar(.frame_padding, .{ padding[0], padding[1] });
            const clicked = zgui.imageButton(
                id_str,
                tex_id,
                .{ .w = size[0], .h = size[1] },
            );
            uitils.popStyleVars(1);
            return clicked;
        } else {
            const bs = @intToFloat(f32, both_size);
            _ = zgui.button(
                "###image_button_no_img",
                .{ .w = bs, .h = bs },
            );
            return false;
        }

        const hovered_flags = utils.merge_packed_structs(
            u32,
            zgui.HoveredFlags.root_and_child_windows,
            zgui.HoveredFlags.rect_only,
        );
        if (zgui.isItemHovered(hovered_flags)) {
            _ = zgui.beginTooltip();
            zgui.text("{s}", .{id_str});
            zgui.endTooltip();
        }
    }

    fn show_image_window(self: *UiState, id: img.ImageId, is_open: *bool) void {
        const maybe_image = self.images_state.get_image(id);

        if (maybe_image) |image| {
            // set initial window size
            const viewport_size = zgui.getMainViewport().getWorkSize();
            const initial_window_size = size: {
                const style = zgui.getStyle();
                if (image.width > image.height) {
                    if (image.width > @floatToInt(u32, viewport_size[0])) {
                        break :size image.fit_to_width_size(@floatToInt(
                            u32,
                            viewport_size[0] - style.window_padding[0] * 2,
                        ));
                    }
                } else {
                    if (image.height > @floatToInt(u32, viewport_size[1])) {
                        break :size image.fit_to_height_size(@floatToInt(
                            u32,
                            viewport_size[1] - style.window_padding[1] * 2,
                        ));
                    }
                }
                break :size [_]f32{ image.widthf(), image.heightf() };
            };
            zgui.setNextWindowSize(.{
                .w = initial_window_size[0],
                .h = initial_window_size[1],
                .cond = .once,
            });
        }

        // get image id
        var buf = img.id.new_str_buf();
        const id_str = img.id.to_str(id, &buf);
        // create window
        _ = zgui.begin(id_str, .{ .popen = is_open });
        defer zgui.end();

        if (maybe_image) |image| {
            // the image
            const size = image.fit_to_width_size(@floatToInt(u32, zgui.getWindowSize()[0]) - 120);
            const tex_id = self.gfx.gctx.lookupResource(image.texture).?;
            _ = zgui.beginChild("image", .{ .w = size[0], .h = size[1] });
            zgui.image(tex_id, .{ .w = size[0], .h = size[1] });
            zgui.endChild();
        } else {
            _ = zgui.beginChild("image", .{});
            zgui.text("loading...", .{});
            zgui.endChild();
        }

        // image and metadata or on the "same line"
        zgui.sameLine(.{});

        // the metadata
        _ = zgui.beginChild("image_metadata", .{});
        zgui.text("Metadata", .{});
        if (maybe_image) |image| {
            zgui.text("width: {d}", .{image.width});
            zgui.text("height: {d}", .{image.height});
        }
        zgui.text("path: {s}", .{self.images_state.get_path(id).?});
        zgui.text("hash: {s}", .{std.fmt.fmtSliceHexLower(&@bitCast([16]u8, id))});
        zgui.endChild();
    }

    fn consume_images(self: *UiState) !void {
        var image: ?DecodedImage = try self.image_buffer.consume();
        while (image != null) {
            var decoded = image.?;
            var image_id = try self.images_state.load_image(decoded);
            if (decoded.do_add) {
                try self.image_states.put(image_id, .{});
            }
            if (decoded.image) |*dimage| dimage.deinit();
            if (decoded.thumbnail) |*thumbnail| thumbnail.deinit();
            image = try self.image_buffer.consume();
        }
    }

    pub fn draw(self: *UiState) void {
        // before *everything*, load in images!
        self.consume_images() catch |err| {
            std.log.err("cannot load images: {}", .{err});
        };
        // set main window size and position to entire viewport
        const viewport = zgui.getMainViewport();
        const viewport_pos = viewport.getWorkPos();
        zgui.setNextWindowPos(.{ .x = viewport_pos[0], .y = viewport_pos[1] });
        const viewport_size = viewport.getWorkSize();
        zgui.setNextWindowSize(.{ .w = viewport_size[0], .h = viewport_size[1] });

        // remove window padding and border size so it looks like there is no window
        uitils.pushStyleVar(.window_rounding, 0.0);
        uitils.pushStyleVar(.window_padding, .{ 0.0, 0.0 });
        uitils.pushStyleVar(.window_border_size, 0.0);

        _ = zgui.begin("main", .{
            .flags = utils.merge_packed_structs(
                u32,
                // remove window decorations (also disables resizing)
                zgui.WindowFlags.no_decoration,
                // make sure this window always stays at the bottom
                zgui.WindowFlags{ .no_bring_to_front_on_focus = true },
            ),
        });
        uitils.popStyleVars(3);
        defer zgui.end();

        // content
        zgui.beginTable("areas", .{
            .column = 2,
            .flags = .{
                .borders = zgui.TableBorderFlags.inner,
                .resizable = true,
            },
        });
        zgui.tableSetupColumn("main buttons", .{
            .init_width_or_height = 150,
            .flags = .{
                .width_fixed = true,
                .no_reorder = true,
            },
        });

        _ = zgui.tableNextColumn();
        zgui.pushItemWidth(150.0);
        var search_buf = std.mem.zeroes([1024:0]u8);
        _ = zgui.inputTextWithHint("###search", .{ .hint = "enter tags to search", .buf = search_buf[0..] });
        zgui.popItemWidth();

        if (zgui.button("quit", .{})) {
            self.quit = true;
        }

        if (zgui.button("add image", .{})) {
            self.select_image();
        }

        if (zgui.button("add folder", .{})) {
            self.select_folder();
        }

        _ = zgui.tableNextColumn();
        // the images //
        const style = zgui.getStyle();
        const line_args = .{
            .offset_from_start_x = zgui.getItemRectMax()[0] - style.frame_padding[0],
            .spacing = 0.0,
        };
        const max_width = zgui.getWindowContentRegionMax()[0];
        const avail_width = max_width - line_args.offset_from_start_x;
        // TODO: this should come from some sort of settings
        const items_per_line: usize = 6;
        const width_per_item = avail_width / @intToFloat(f32, items_per_line);
        // TODO: probably replace this with a proper usage of some scroll area
        // but it's whatever for now lol
        zgui.beginTable("images", .{ .column = 1, .flags = .{ .scroll_y = true } });
        _ = zgui.tableNextColumn();
        // actually add the images
        zgui.sameLine(.{});
        for (self.image_states.keys()) |image_id| {
            const state = self.image_states.getPtr(image_id).?;
            if (self.add_image(image_id, @floatToInt(u32, width_per_item))) {
                state.is_open = true;
                if (!self.images_state.images.has(image_id)) {
                    const thread = thread: {
                        break :thread std.Thread.spawn(
                            .{},
                            decode_image,
                            .{
                                self.image_buffer,
                                self.alloc,
                                self.fs_state,
                                self.images_state.get_path(image_id).?,
                                false,
                                false,
                                false,
                            },
                        ) catch |err| {
                            std.log.err("cannot spawn thread: {}", .{err});
                            break :thread null;
                        };
                    };
                    if (thread) |handle| handle.detach();
                }
            }
            if (state.is_open) {
                self.show_image_window(image_id, &state.is_open);
            }
            if (zgui.getItemRectMax()[0] + width_per_item > max_width) {
                zgui.newLine();
            }
            zgui.sameLine(.{});
        }
        zgui.endTable();
        // the images //
        zgui.endTable();
    }

    pub fn deinit(self: *UiState) void {
        self.images_state.deinit();
        self.image_buffer.deinit();
        self.image_states.deinit();
        self.alloc.destroy(self.image_buffer);
        self.alloc.destroy(self);
        // gfx is deinitialized in main.zig
    }
};

pub fn create(
    allocator: std.mem.Allocator,
    graphics_state: *graphics.GraphicsState,
    fs_state: *fs.FsState,
) !*UiState {
    var image_buffer = try allocator.create(RingBuffer(DecodedImage));
    try image_buffer.init(1024, allocator);
    errdefer image_buffer.deinit();

    var image_paths: db.Images = images: {
        var maybe_db_file: ?std.fs.File = db: {
            break :db std.fs.openFileAbsoluteZ(fs_state.images_db_path, .{}) catch |err| {
                if (err == std.fs.File.OpenError.FileNotFound) {
                    std.log.warn("no db file found", .{});
                } else {
                    std.log.err("could not open db file: {}", .{err});
                }
                break :db null;
            };
        };
        if (maybe_db_file) |file| {
            defer file.close();
            std.log.info("reading db file from '{s}'", .{fs_state.images_db_path});
            const metadata = try file.metadata();
            const data = try file.readToEndAlloc(allocator, @intCast(usize, metadata.size()));
            defer allocator.destroy(data.ptr);
            break :images try db.Images.from_data(data, allocator);
        } else {
            std.log.info("creating a new db", .{});
            break :images db.Images.init(allocator);
        }
    };
    errdefer image_paths.deinit();

    // add image ids from image paths for display
    // later on we should only do this if all images are being displayed
    // ensuring the capacity here is a good idea regardless though
    var image_states = ImageStates.init(allocator);
    errdefer image_states.deinit();

    var i: usize = 0;
    var thumbnails_to_load = try allocator.alloc(img.ImageId, image_paths.map.count());
    try image_states.ensureUnusedCapacity(image_paths.map.count());
    var id_iter = image_paths.map.keyIterator();
    while (id_iter.next()) |id| {
        // cannot fail since we ensure capacity beforehand
        image_states.put(id.*, .{}) catch unreachable;
        thumbnails_to_load[i] = id.*;
        i += 1;
    }

    const thumbnail_thread = try std.Thread.spawn(
        .{},
        impl_load_thumbnails,
        .{ image_buffer, allocator, fs_state, thumbnails_to_load },
    );
    thumbnail_thread.detach();

    const state = try allocator.create(UiState);
    state.* = .{
        .images_state = .{
            .image_paths = image_paths,
            .images = img.create_image_map(allocator),
            .thumbnails = img.create_image_map(allocator),
            .alloc = allocator,
            .gfx = graphics_state,
        },
        .image_states = image_states,
        .image_buffer = image_buffer,
        .alloc = allocator,
        .gfx = graphics_state,
        .fs_state = fs_state,
    };
    return state;
}
