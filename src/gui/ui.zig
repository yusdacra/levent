const graphics = @import("./graphics.zig");
const img = @import("./image.zig");
const uitils = @import("./ui/utils.zig");
const utils = @import("../utils.zig");

const std = @import("std");
const zgui = @import("zgui");

pub const window_title = "levent";

pub const UiState = struct {
    images: img.ImageMap,
    quit: bool = false,

    pub fn draw(self: *UiState, graphics_state: *graphics.GraphicsState) void {
        {
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
            defer uitils.popStyleVars(3);

            _ = zgui.begin("main", .{
                .flags = utils.merge_packed_structs(
                    u32,
                    // remove window decorations (also disables resizing)
                    zgui.WindowFlags.no_decoration,
                    // make sure this window always stays at the bottom
                    zgui.WindowFlags{ .no_bring_to_front_on_focus = true },
                ),
            });
            defer zgui.end();

            // content
            zgui.beginTable("areas", .{ .column = 2, .flags = .{ .sizing = .fixed_fit } });
            _ = zgui.tableNextColumn();
            if (zgui.button("test", .{})) {
                std.debug.print("aaaaaaaaaaaaaaa", .{});
            }
            if (zgui.button("quit", .{})) {
                self.quit = true;
            }
            _ = zgui.tableNextColumn();
            zgui.text("test", .{});
            zgui.endTable();
        }
        {
            _ = zgui.begin("image", .{});
            defer zgui.end();

            const image = self.images.get("test_image").?;
            const tex_id = graphics_state.gctx.lookupResource(image.texture).?;
            const size = image.scaled_size(0.15);
            zgui.image(tex_id, .{ .w = size[0], .h = size[1] });
        }
    }
    pub fn deinit(self: *UiState, allocator: std.mem.Allocator) void {
        self.images.deinit();
        allocator.destroy(self);
    }
};

pub fn create(allocator: std.mem.Allocator, graphics_state: *graphics.GraphicsState) !*UiState {
    const state = try allocator.create(UiState);
    var image_map = img.create_image_map(allocator);
    try image_map.load(graphics_state.gctx, "test_image", "/home/patriot/proj/levent/test.png");
    state.* = .{
        .images = image_map,
    };
    return state;
}
