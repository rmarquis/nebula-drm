const std = @import("std");

pub const Rgb = struct { r: f64, g: f64, b: f64 };

/// Convert a color temperature in Kelvin to linear [0.0, 1.0] RGB multipliers
/// using the Tanner Helland approximation.
pub fn kelvinToRgb(kelvin: u32) Rgb {
    const t: f64 = @as(f64, @floatFromInt(kelvin)) / 100.0;

    const r = if (t <= 66.0)
        1.0
    else
        std.math.clamp(329.698727446 * std.math.pow(f64, t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);

    const g = if (t <= 66.0)
        std.math.clamp((99.4708025861 * std.math.log(f64, std.math.e, t) - 161.1195681661) / 255.0, 0.0, 1.0)
    else
        std.math.clamp(288.1221695283 * std.math.pow(f64, t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);

    const b = if (t >= 66.0)
        1.0
    else if (t <= 19.0)
        0.0
    else
        std.math.clamp((138.5177312231 * std.math.log(f64, std.math.e, t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0);

    return .{ .r = r, .g = g, .b = b };
}

/// Fill a 16-bit gamma LUT for one channel.
/// lut: caller-allocated slice of u16, len = gamma_size
/// channel_mult: RGB component from kelvinToRgb(), 0.0..1.0
/// brightness: overall brightness scalar, 0.0..1.0
pub fn fillLut(lut: []u16, channel_mult: f64, brightness: f64) void {
    const size = lut.len;
    for (lut, 0..) |*entry, i| {
        const normalized: f64 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(size - 1));
        const value = std.math.clamp(normalized * channel_mult * brightness * 65535.0, 0.0, 65535.0);
        entry.* = @intFromFloat(value);
    }
}

test "kelvinToRgb known values" {
    const eps = 0.01;

    // 6500K: near-white, slight warm bias
    const d = kelvinToRgb(6500);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), d.r, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 0.992), d.g, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), d.b, eps);

    // 4000K: warm orange
    const w = kelvinToRgb(4000);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), w.r, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 0.773), w.g, 0.02);
    try std.testing.expectApproxEqAbs(@as(f64, 0.573), w.b, 0.02);

    // 2700K: incandescent
    const i = kelvinToRgb(2700);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), i.r, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 0.573), i.g, 0.03);
    try std.testing.expectApproxEqAbs(@as(f64, 0.294), i.b, 0.03);
}

test "fillLut endpoints" {
    var lut = [_]u16{0} ** 256;
    fillLut(&lut, 1.0, 1.0);
    try std.testing.expectEqual(@as(u16, 0), lut[0]);
    try std.testing.expectEqual(@as(u16, 65535), lut[255]);
}
