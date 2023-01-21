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
    id: ?img.ImageId,
    do_add: bool,
    image: ?Image,
    thumbnail: ?Image,
    path: [:0]const u8,
    destroy_path: bool,

    const Self = @This();

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        if (self.image) |*dimage| dimage.deinit();
        if (self.thumbnail) |*thumbnail| thumbnail.deinit();
        if (self.destroy_path) {
            alloc.destroy(self.path.ptr);
        }
    }
};

const ImagesState = struct {
    image_paths: db.Paths,
    image_tags: db.Tags,
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

    inline fn get_tags(self: *ImagesState, id: img.ImageId) ?[:0]const u8 {
        return self.image_tags.map.get(id);
    }

    inline fn get_image(self: *ImagesState, id: img.ImageId) ?img.ImageHandle {
        return self.images.get(id);
    }

    inline fn get_thumbnail(self: *ImagesState, id: img.ImageId) ?img.ImageHandle {
        return self.thumbnails.get(id);
    }

    fn deinit(self: *ImagesState) void {
        self.image_paths.deinit();
        self.image_tags.deinit();
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

// ids_to_load will be freed by this function.
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
        if (do_add) alloc.free(file_path);
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
    const decoded = .{
        .destroy_path = destroy_path,
        .do_add = do_add,
        .thumbnail = thumbnail,
        .image = image,
        .path = file_path,
        .id = null,
    };
    buffer.produce(decoded) catch |err| {
        std.log.err("ring buffer err: {}", .{err});
        if (thumbnail) |*thumb| thumb.deinit();
        image.deinit();
        if (do_add) alloc.free(file_path);
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
        alloc.free(file_path);
        return;
    };
    const decoded = .{
        .destroy_path = true,
        .do_add = false,
        .thumbnail = thumbnail,
        .image = null,
        .path = file_path,
        .id = id,
    };
    buffer.produce(decoded) catch |err| {
        std.log.err("ring buffer err: {}", .{err});
        thumbnail.deinit();
        alloc.free(file_path);
    };
}

const ShownImages = std.AutoArrayHashMap(img.ImageId, void);
const OpenImages = std.AutoArrayHashMap(img.ImageId, void);

pub const UiState = struct {
    images_state: ImagesState,
    images_to_show: ShownImages,
    open_images: OpenImages,
    image_buffer: *RingBuffer(DecodedImage),
    alloc: std.mem.Allocator,
    fs_state: *fs.FsState,
    gfx: *graphics.GraphicsState,
    quit: bool = false,
    editing_tags_for_image: ?img.ImageId = null,
    edit_tags_buf: [1024:0]u8 = std.mem.zeroes([1024:0]u8),
    current_tags: [1024:0]u8 = std.mem.zeroes([1024:0]u8),

    const Self = @This();

    fn select_image(self: *Self) void {
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

    fn select_folder(self: *Self) void {
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

    fn add_image(self: *Self, id: img.ImageId, both_size: u32) bool {
        var buf = img.id.new_str_buf();
        const id_str = img.id.to_str(id, &buf);

        const maybe_image = self.images_state.get_thumbnail(id);

        const clicked = click: {
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
                break :click clicked;
            } else {
                const bs = @intToFloat(f32, both_size);
                _ = zgui.button(
                    "###image_button_no_img",
                    .{ .w = bs, .h = bs },
                );
                break :click false;
            }
        };

        if (self.images_state.get_path(id)) |path| {
            if (zgui.isItemHovered(.{})) {
                _ = zgui.beginTooltip();
                zgui.textUnformatted(std.fs.path.basename(path));
                if (self.images_state.get_tags(id)) |tags| {
                    if (tags.len > 30) {
                        zgui.text("{s}...", .{tags[0..30]});
                    } else {
                        zgui.textUnformatted(tags);
                    }
                }
                zgui.endTooltip();
            }
        }

        return clicked;
    }

    fn show_image_window(self: *Self, id: img.ImageId, is_open: *bool) void {
        const maybe_image = self.images_state.get_image(id);
        const viewport_size = zgui.getMainViewport().getWorkSize();
        const metadata_size: f32 = viewport_size[0] * 0.2;

        if (maybe_image) |image| {
            // set initial window size
            const initial_window_size = size: {
                if (image.width > image.height) {
                    const viewport_x = viewport_size[0] * 0.7;
                    if (image.width > @floatToInt(u32, viewport_x)) {
                        break :size image.fit_to_width_size(@floatToInt(
                            u32,
                            viewport_x,
                        ));
                    }
                } else {
                    const viewport_y = viewport_size[1] * 0.7;
                    if (image.height > @floatToInt(u32, viewport_y)) {
                        break :size image.fit_to_height_size(@floatToInt(
                            u32,
                            viewport_y,
                        ));
                    }
                }
                break :size [_]f32{ image.widthf(), image.heightf() };
            };
            const style = zgui.getStyle();
            zgui.setNextWindowSize(.{
                .w = initial_window_size[0] + metadata_size,
                .h = initial_window_size[1] + style.window_padding[1] * 5,
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
            const size = image.fit_to_width_size(
                @floatToInt(u32, zgui.getWindowSize()[0] - metadata_size),
            );
            const tex_id = self.gfx.gctx.lookupResource(image.texture).?;
            _ = zgui.beginChild("image", .{ .w = size[0], .h = size[1] });
            zgui.image(tex_id, .{ .w = size[0], .h = size[1] });
            zgui.endChild();
            // image and metadata or on the "same line"
            zgui.sameLine(.{});
        } else {
            zgui.textUnformatted("loading...");
        }

        // the metadata
        _ = zgui.beginChild("image_metadata", .{});
        const path = self.images_state.get_path(id).?;
        const tags = self.images_state.get_tags(id);
        if (zgui.beginPopupContextWindow()) {
            if (zgui.menuItem("copy path", .{})) {
                zgui.setClipboardText(path);
            }
            if (tags) |tags_str| {
                if (zgui.menuItem("copy tags", .{})) {
                    zgui.setClipboardText(tags_str);
                }
            }
            zgui.endPopup();
        }
        zgui.text("Metadata", .{});
        if (maybe_image) |image| {
            zgui.text("width: {d}", .{image.width});
            zgui.text("height: {d}", .{image.height});
        } else {
            zgui.textUnformatted("width: loading");
            zgui.textUnformatted("height: loading");
        }
        zgui.textWrapped("path: {s}", .{path});
        zgui.textWrapped("hash: {s}", .{std.fmt.fmtSliceHexLower(&@bitCast([16]u8, id))});
        if (tags) |tags_str| {
            zgui.textWrapped("tags: {s}", .{tags_str});
        } else {
            zgui.textUnformatted("tags: <no tags>");
        }
        if (zgui.button("edit tags", .{})) {
            self.editing_tags_for_image = id;
        }
        zgui.endChild();
    }

    fn show_edit_tags_popup(self: *Self, id: img.ImageId) !void {
        const viewport_size = zgui.getMainViewport().getWorkSize();
        zgui.setNextWindowSize(.{
            .w = viewport_size[0] * 0.3,
            .h = viewport_size[1] * 0.01,
            .cond = .always,
        });
        _ = zgui.begin("edit tags", .{});
        defer zgui.end();

        const submit = zgui.inputText("new tags", .{
            .buf = self.edit_tags_buf[0..],
            .flags = .{ .enter_returns_true = true },
        });
        if (submit) {
            const new_tags = try self.alloc.dupeZ(u8, std.mem.sliceTo(&self.edit_tags_buf, 0));
            try self.images_state.image_tags.add(id, new_tags);
            self.editing_tags_for_image = null;
        }
    }

    fn consume_images(self: *Self) !void {
        var image: ?DecodedImage = try self.image_buffer.consume();
        while (image != null) {
            var decoded = image.?;
            defer decoded.deinit(self.alloc);
            var image_id = try self.images_state.load_image(decoded);
            if (decoded.do_add) {
                try self.images_to_show.put(image_id, {});
            }
            image = try self.image_buffer.consume();
        }
    }

    fn load_original_image(self: *const Self, image_id: img.ImageId) void {
        const handle = std.Thread.spawn(
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
            return;
        };
        handle.detach();
    }

    fn get_images_tags(self: *const Self) *const db.Tags {
        return &self.images_state.image_tags;
    }

    fn mark_image_as_shown(self: *Self, id: img.ImageId) void {
        self.images_to_show.put(id, {}) catch |err| {
            std.log.err("cannot allocate: {}", .{err});
        };
    }

    pub fn draw(self: *Self) void {
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
        const do_search = zgui.inputTextWithHint(
            "###search",
            .{
                .hint = "enter tags to search",
                .buf = search_buf[0..],
                .flags = .{ .enter_returns_true = true },
            },
        );
        zgui.popItemWidth();

        if (do_search) {
            self.images_to_show.clearRetainingCapacity();
            if (search_buf[0] != 0) {
                db.filter_tags(
                    Self,
                    Self.get_images_tags,
                    Self.mark_image_as_shown,
                    self,
                    std.mem.sliceTo(&search_buf, 0),
                );
            } else {
                var keys_iter = self.images_state.image_paths.map.keyIterator();
                while (keys_iter.next()) |id| {
                    self.images_to_show.put(id.*, {}) catch unreachable;
                }
            }
            std.mem.copy(u8, &self.current_tags, &search_buf);
        }

        if (self.current_tags[0] != 0) {
            zgui.textWrapped("{s}", .{self.current_tags[0.. :0]});
        }

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
        for (self.images_to_show.keys()) |image_id| {
            var is_open = self.open_images.contains(image_id);
            if (self.add_image(image_id, @floatToInt(u32, width_per_item))) {
                self.open_images.put(image_id, {}) catch |err| {
                    std.log.err("failed to allocate: {}", .{err});
                };
                if (!self.images_state.images.has(image_id)) {
                    self.load_original_image(image_id);
                }
            }
            if (is_open) {
                self.show_image_window(image_id, &is_open);
                if (!is_open) {
                    _ = self.open_images.swapRemove(image_id);
                }
            }
            if (zgui.getItemRectMax()[0] + width_per_item > max_width) {
                zgui.newLine();
            }
            zgui.sameLine(.{});
        }
        zgui.endTable();
        // the images //
        zgui.endTable();

        if (self.editing_tags_for_image) |edit_id| {
            if (self.images_state.get_tags(edit_id)) |current_tags| {
                std.mem.copy(u8, &self.edit_tags_buf, current_tags);
            }
            self.show_edit_tags_popup(edit_id) catch |err| {
                std.log.err("cannot show edit tags popup: {}", .{err});
                self.editing_tags_for_image = null;
            };
        }
    }

    pub fn deinit(self: *UiState) void {
        self.images_state.deinit();
        self.image_buffer.deinit();
        self.images_to_show.deinit();
        self.open_images.deinit();
        self.alloc.destroy(self.image_buffer);
        self.alloc.destroy(self);
        // gfx is deinitialized in main.zig
        // fs state is deinitalized in main.zig
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

    var image_paths = try fs_state.read_db_file(db.Paths);
    errdefer image_paths.deinit();

    var image_tags = try fs_state.read_db_file(db.Tags);
    errdefer image_tags.deinit();

    var shown_images = ShownImages.init(allocator);
    errdefer shown_images.deinit();

    // add image ids from image paths for display
    // later on we should only do this if all images are being displayed
    // ensuring the capacity here is a good idea regardless though
    var i: usize = 0;
    var thumbnails_to_load = try allocator.alloc(img.ImageId, image_paths.map.count());
    try shown_images.ensureUnusedCapacity(image_paths.map.count());
    var id_iter = image_paths.map.keyIterator();
    while (id_iter.next()) |id| {
        // cannot fail since we ensure capacity beforehand
        shown_images.put(id.*, {}) catch unreachable;
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
            .image_tags = image_tags,
            .images = img.create_image_map(allocator),
            .thumbnails = img.create_image_map(allocator),
            .alloc = allocator,
            .gfx = graphics_state,
        },
        .images_to_show = shown_images,
        .open_images = OpenImages.init(allocator),
        .image_buffer = image_buffer,
        .alloc = allocator,
        .gfx = graphics_state,
        .fs_state = fs_state,
    };
    return state;
}
