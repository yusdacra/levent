const graphics = @import("./graphics.zig");
const uitils = @import("./ui/utils.zig");
const utils = @import("../utils.zig");

const std = @import("std");
const zgui = @import("zgui");

pub const window_title = "levent";

pub const UiState = struct {
    pub fn draw(self: *const UiState, graphics_state: *graphics.GraphicsState) void {
        _ = self;
        _ = graphics_state;

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
        zgui.beginTable("areas", .{ .columns = 2, .flags = .{ .sizing = .fixed_fit } });
        _ = zgui.tableNextColumn();
        if (zgui.button("test", .{})) {
            std.debug.print("aaaaaaaaaaaaaaa", .{});
        }
        _ = zgui.tableNextColumn();
        zgui.text("test", .{});
        zgui.endTable();
    }
    pub fn update(self: *UiState) void {
        _ = self;
    }
    pub fn deinit(self: *UiState, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub fn create(allocator: std.mem.Allocator) !*UiState {
    const state = try allocator.create(UiState);
    return state;
}
