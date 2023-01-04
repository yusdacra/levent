const graphics = @import("./graphics.zig");
const img = @import("./image.zig");
const uitils = @import("./ui/utils.zig");
const utils = @import("../utils.zig");

const std = @import("std");
const zgui = @import("zgui");

const print = std.debug.print;

pub const window_title = "levent";

pub const UiState = struct {
    images: img.ImageMap,
    image_ids: std.ArrayList(img.ImageId),
    gfx: *graphics.GraphicsState,
    quit: bool = false,

    fn add_image(self: *const UiState, id: img.ImageId, width: u32) void {
        const image = self.images.get(id).?;
        const tex_id = self.gfx.gctx.lookupResource(image.texture).?;
        const size = image.fit_to_width_size(width);
        const id_str = img.image_id_to_str(id);
        if (zgui.imageButton(id_str, tex_id, .{ .w = size[0], .h = size[1] })) {
            std.debug.print("clicked image {s}\n", .{std.fmt.fmtSliceHexLower(id_str)});
        }
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
        zgui.beginTable("areas", .{ .column = 2 });
        zgui.tableSetupColumn("main buttons", .{
            .init_width_or_height = 100,
            .flags = .{
                .width_fixed = true,
                .no_resize = true,
                .no_reorder = true,
            },
        });
        _ = zgui.tableNextColumn();
        if (zgui.button("test", .{})) {
            std.debug.print("aaaaaaaaaaaaaaa", .{});
        }
        if (zgui.button("quit", .{})) {
            self.quit = true;
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
        const items_per_line: usize = 5;
        const width_per_item = avail_width / @intToFloat(f32, items_per_line);
        // TODO: probably replace this with a proper usage of some scroll area
        // but it's whatever for now lol
        zgui.beginTable("images", .{ .column = 1, .flags = .{ .scroll_y = true } });
        _ = zgui.tableNextColumn();
        // actually add the images
        var i: usize = 0;
        zgui.sameLine(line_args);
        while (i < self.image_ids.items.len) : (i += 1) {
            self.add_image(self.image_ids.items[i], @floatToInt(u32, width_per_item));
            if (zgui.getItemRectMax()[0] + width_per_item > max_width) {
                zgui.newLine();
                zgui.sameLine(line_args);
            } else {
                zgui.sameLine(.{});
            }
        }
        zgui.endTable();
        // the images //
        zgui.endTable();
    }
    pub fn deinit(self: *UiState, allocator: std.mem.Allocator) void {
        self.images.deinit();
        self.image_ids.deinit();
        allocator.destroy(self);
        // gfx is deinitialized in main.zig
    }
};

pub fn create(allocator: std.mem.Allocator, graphics_state: *graphics.GraphicsState) !*UiState {
    const state = try allocator.create(UiState);
    var image_map = img.create_image_map(allocator);
    const id1 = try image_map.load(graphics_state.gctx, "/home/patriot/proj/levent/test.png");
    const id2 = try image_map.load(graphics_state.gctx, "/home/patriot/.config/wallpaper");
    var image_ids = std.ArrayList(img.ImageId).init(allocator);
    try image_ids.append(id2);
    try image_ids.append(id1);
    try image_ids.append(id2);
    try image_ids.append(id2);
    try image_ids.append(id2);
    try image_ids.append(id2);
    try image_ids.append(id1);
    try image_ids.append(id2);
    try image_ids.append(id1);
    try image_ids.append(id1);
    try image_ids.append(id1);
    state.* = .{
        .images = image_map,
        .image_ids = image_ids,
        .gfx = graphics_state,
    };
    return state;
}
