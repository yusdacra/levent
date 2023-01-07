const graphics = @import("./graphics.zig");
const img = @import("./image.zig");
const uitils = @import("./ui/utils.zig");
const utils = @import("../utils.zig");

const std = @import("std");
const zgui = @import("zgui");
const nfd = @import("nfd");

const print = std.debug.print;

pub const window_title = "levent";

const ImageState = struct {
    is_open: bool = false,
};
const ImageStates = std.AutoHashMap(img.ImageId, ImageState);

const ImagesState = struct {
    // loaded images
    images: img.ImageMap,
    // ui states
    image_states: ImageStates,
    // images we'll show
    // this is separated from image states so that we can sort these
    // at anytime without also accessing the states.
    image_ids: std.ArrayList(img.ImageId),
    lock: std.Thread.RwLock = std.Thread.RwLock{},
    gfx: *graphics.GraphicsState,

    fn load_image(self: *ImagesState, path: [:0]const u8) !void {
        var image = try img.decode_image(path);
        const handle = img.load_image(self.gfx.gctx, image);
        image.deinit();
        self.lock.lock();
        defer self.lock.unlock();
        try self.images.add(handle);
        try self.image_states.put(handle.id, .{});
        try self.image_ids.append(handle.id);
    }

    inline fn get_image(self: *ImagesState, id: img.ImageId) ?img.ImageHandle {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.images.get(id);
    }

    inline fn get_state(self: *ImagesState, id: img.ImageId) ?*ImageState {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.image_states.getPtr(id);
    }

    fn deinit(self: *ImagesState) void {
        self.images.deinit();
        self.image_ids.deinit();
        self.image_states.deinit();
    }
};

pub const UiState = struct {
    images_state: ImagesState,
    quit: bool = false,
    alloc: std.mem.Allocator,
    gfx: *graphics.GraphicsState,

    fn select_image(self: *UiState) !void {
        const file_path = try nfd.openFileDialog(null, null);
        if (file_path) |path| {
            defer nfd.freePath(path);
            try self.images_state.load_image(path);
        }
    }

    fn select_folder(self: *UiState) !void {
        const maybe_dir_path = try nfd.openFolderDialog(null);
        if (maybe_dir_path) |dir_path| {
            defer nfd.freePath(dir_path);
            var dir = try std.fs.openIterableDirAbsoluteZ(dir_path, .{});
            var walker = try dir.walk(self.alloc);
            defer walker.deinit();

            while (try walker.next()) |entry| {
                if (entry.kind == .File) {
                    const file_path = try std.fmt.allocPrintZ(
                        self.alloc,
                        "{s}/{s}",
                        .{ dir_path, entry.path },
                    );
                    defer self.alloc.destroy(file_path.ptr);
                    print("started loading image on path {s}\n", .{file_path});
                    self.images_state.load_image(file_path) catch |err| {
                        print("could not load image: {}\n", .{err});
                    };
                }
            }
        }
    }

    fn add_image(self: *UiState, id: img.ImageId, both_size: u32) bool {
        const image = self.images_state.get_image(id).?;
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
                break :pad [_]f32{ 0.0, (@intToFloat(f32, both_size) - size[1]) / 2.0 };
            } else {
                break :pad [_]f32{ (@intToFloat(f32, both_size) - size[0]) / 2.0, 0.0 };
            }
        };

        var buf = img.id.new_str_buf();
        const id_str = img.id.to_str(id, &buf);

        uitils.pushStyleVar(.frame_padding, .{ padding[0], padding[1] });
        const clicked = zgui.imageButton(id_str, tex_id, .{ .w = size[0], .h = size[1] });
        uitils.popStyleVars(1);
        return clicked;
    }

    fn show_image_window(self: *UiState, id: img.ImageId, is_open: *bool) void {
        const image = self.images_state.get_image(id).?;
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
            .cond = .first_use_ever,
        });

        // get image id
        var buf = img.id.new_str_buf();
        const id_str = img.id.to_str(id, &buf);
        // create window
        _ = zgui.begin(id_str, .{ .popen = is_open });
        defer zgui.end();

        // the image
        const size = image.fit_to_width_size(@floatToInt(u32, zgui.getWindowSize()[0]) - 120);
        const tex_id = self.gfx.gctx.lookupResource(image.texture).?;
        _ = zgui.beginChild("image", .{ .w = size[0], .h = size[1] });
        zgui.image(tex_id, .{ .w = size[0], .h = size[1] });
        zgui.endChild();
        // image and metadata or on the "same line"
        zgui.sameLine(.{});
        // the metadata
        _ = zgui.beginChild("image_metadata", .{});
        zgui.text("Metadata", .{});
        zgui.text("width: {d}", .{image.width});
        zgui.text("height: {d}", .{image.height});
        zgui.endChild();
    }

    pub fn draw(self: *UiState) void {
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
            self.select_image() catch |err| {
                print("could not add image: {}\n", .{err});
            };
        }

        if (zgui.button("add folder", .{})) {
            var thread = std.Thread.spawn(.{}, UiState.select_folder, .{self}) catch |err| {
                std.debug.panic("cannot spawn thread: {}", .{err});
            };
            thread.detach();
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
        var i: usize = 0;
        zgui.sameLine(.{});
        self.images_state.lock.lockShared();
        while (i < self.images_state.image_ids.items.len) : (i += 1) {
            const image_id = self.images_state.image_ids.items[i];
            const state = self.images_state.get_state(image_id).?;
            if (self.add_image(image_id, @floatToInt(u32, width_per_item))) {
                state.is_open = true;
            }
            if (state.is_open) {
                self.show_image_window(image_id, &state.is_open);
            }
            if (zgui.getItemRectMax()[0] + width_per_item > max_width) {
                zgui.newLine();
            }
            zgui.sameLine(.{});
        }
        self.images_state.lock.unlockShared();
        zgui.endTable();
        // the images //
        zgui.endTable();
    }

    pub fn deinit(self: *UiState, allocator: std.mem.Allocator) void {
        self.images_state.deinit();
        allocator.destroy(self);
        // gfx is deinitialized in main.zig
    }
};

pub fn create(allocator: std.mem.Allocator, graphics_state: *graphics.GraphicsState) !*UiState {
    const state = try allocator.create(UiState);
    state.* = .{
        .images_state = .{
            .images = img.create_image_map(allocator),
            .image_ids = std.ArrayList(img.ImageId).init(allocator),
            .image_states = ImageStates.init(allocator),
            .gfx = graphics_state,
        },
        .alloc = allocator,
        .gfx = graphics_state,
    };
    return state;
}
