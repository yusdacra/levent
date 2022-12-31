const graphics = @import("./graphics.zig");

const std = @import("std");

pub const window_title = "levent";

pub const UiState = struct {
    pub fn draw(self: *const UiState, graphics_state: *graphics.GraphicsState) void {
        _ = self;
        _ = graphics_state;
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
