const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

pub const GraphicsState = struct {
    gctx: *zgpu.GraphicsContext,

    pub fn new_frame(self: *GraphicsState) void {
        zgui.backend.newFrame(
            self.gctx.swapchain_descriptor.width,
            self.gctx.swapchain_descriptor.height,
        );
    }

    pub fn deinit(self: *GraphicsState, allocator: std.mem.Allocator) void {
        zgui.backend.deinit();
        zgui.deinit();
        self.gctx.destroy(allocator);
        allocator.destroy(self);
    }

    pub fn draw(self: *GraphicsState) void {
        const gctx = self.gctx;

        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            // Gui pass.
            {
                const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
                defer zgpu.endReleasePass(pass);
                zgui.backend.draw(pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
};

pub fn create(allocator: std.mem.Allocator, window: *zglfw.Window) !*GraphicsState {
    const gctx = try zgpu.GraphicsContext.create(
        allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    errdefer gctx.destroy(allocator);

    zgui.init(allocator);
    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor if (scale[0] > scale[1]) scale[0] else scale[1];
    };

    // This needs to be called *after* adding your custom fonts.
    zgui.backend.init(window, gctx.device, @intFromEnum(gctx.swapchain_descriptor.format), @intFromEnum(zgpu.wgpu.TextureFormat.undef));

    // You can directly manipulate zgui.Style *before* `newFrame()` call.
    // Once frame is started (after `newFrame()` call) you have to use
    // zgui.pushStyleColor*()/zgui.pushStyleVar*() functions.
    const style = zgui.getStyle();

    // TODO: set a better default style later here
    style.window_min_size = .{ 320.0, 240.0 };
    style.scrollbar_size = 6.0;
    style.window_border_size = 8.0;
    style.window_rounding = 8.0;
    style.window_padding = .{ 8.0, 8.0 };
    style.frame_rounding = 4.0;
    {
        var color = style.getColor(.scrollbar_grab);
        color[1] = 0.8;
        style.setColor(.scrollbar_grab, color);
    }
    style.scaleAllSizes(scale_factor);

    const state = try allocator.create(GraphicsState);
    state.* = .{
        .gctx = gctx,
    };

    return state;
}
