const std = @import("std");
const colortemp = @import("colortemp.zig");

const c = @cImport({
    @cInclude("xf86drm.h");
    @cInclude("xf86drmMode.h");
});

pub const DrmError = error{
    NoDeviceFound,
    OpenFailed,
    GetResourcesFailed,
    /// Acquiring DRM master failed — another process (compositor) already holds it.
    /// This tool must run before the display manager starts.
    MasterUnavailable,
    SetGammaFailed,
    OutOfMemory,
};

pub const GammaRgb = struct {
    r: f64,
    g: f64,
    b: f64,
    brightness: f64,
};

/// Scan cards 0..9, apply gamma to the first one that works.
/// card_override: if not null, only try that card index.
pub fn applyGammaAuto(allocator: std.mem.Allocator, card_override: ?u8, gamma: GammaRgb) DrmError!void {
    if (card_override) |idx| {
        return applyGamma(allocator, idx, gamma);
    }
    var i: u8 = 0;
    while (i < 10) : (i += 1) {
        applyGamma(allocator, i, gamma) catch |err| switch (err) {
            DrmError.OpenFailed, DrmError.GetResourcesFailed => continue,
            else => return err,
        };
        return;
    }
    return DrmError.NoDeviceFound;
}

fn applyGamma(allocator: std.mem.Allocator, card_index: u8, gamma: GammaRgb) DrmError!void {
    var path_buf: [32]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/dev/dri/card{d}", .{card_index}) catch return DrmError.OpenFailed;

    const fd_usize = std.posix.open(path, .{ .ACCMODE = .RDWR }, 0) catch return DrmError.OpenFailed;
    const fd: c_int = @intCast(fd_usize);
    defer std.posix.close(fd_usize);

    if (c.drmSetMaster(fd) != 0) return DrmError.MasterUnavailable;
    defer _ = c.drmDropMaster(fd);

    const res: *c.drmModeRes = @ptrCast(c.drmModeGetResources(fd) orelse return DrmError.GetResourcesFailed);
    defer c.drmModeFreeResources(res);

    const crtc_count: usize = @intCast(res.count_crtcs);
    for (0..crtc_count) |i| {
        const crtc_id = res.crtcs[i];
        const crtc: *c.drmModeCrtc = @ptrCast(c.drmModeGetCrtc(fd, crtc_id) orelse continue);
        defer c.drmModeFreeCrtc(crtc);

        // Skip CRTCs with no active display (mode_valid == 0 means unconnected)
        if (crtc.mode_valid == 0) continue;

        const gamma_size: usize = @intCast(crtc.gamma_size);
        if (gamma_size == 0) continue;

        const red = allocator.alloc(u16, gamma_size) catch return DrmError.OutOfMemory;
        defer allocator.free(red);
        const green = allocator.alloc(u16, gamma_size) catch return DrmError.OutOfMemory;
        defer allocator.free(green);
        const blue = allocator.alloc(u16, gamma_size) catch return DrmError.OutOfMemory;
        defer allocator.free(blue);

        colortemp.fillLut(red, gamma.r, gamma.brightness);
        colortemp.fillLut(green, gamma.g, gamma.brightness);
        colortemp.fillLut(blue, gamma.b, gamma.brightness);

        const ret = c.drmModeCrtcSetGamma(fd, crtc_id, @intCast(gamma_size), red.ptr, green.ptr, blue.ptr);
        if (ret != 0) {
            std.log.err("drmModeCrtcSetGamma failed for CRTC {d}: errno {d}", .{ crtc_id, -ret });
            return DrmError.SetGammaFailed;
        }
    }
}
