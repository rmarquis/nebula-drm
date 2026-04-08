const std = @import("std");

pub const SolarInput = struct {
    /// Decimal degrees, positive north
    latitude_deg: f64,
    /// Decimal degrees, positive east
    longitude_deg: f64,
    /// Unix timestamp (seconds since 1970-01-01 00:00:00 UTC)
    unix_timestamp: i64,
};

/// Returns solar elevation angle in degrees.
/// Positive = above horizon, negative = below horizon.
pub fn solarElevation(input: SolarInput) f64 {
    const ts: f64 = @floatFromInt(input.unix_timestamp);

    // Julian Day Number (Unix epoch = JD 2440587.5)
    const julian_day = ts / 86400.0 + 2440587.5;

    // Julian Century from J2000.0
    const jc = (julian_day - 2451545.0) / 36525.0;

    // Geometric mean longitude of the sun (degrees)
    const geom_mean_long = @mod(280.46646 + jc * (36000.76983 + jc * 0.0003032), 360.0);

    // Geometric mean anomaly of the sun (degrees)
    const geom_mean_anom = 357.52911 + jc * (35999.05029 - 0.0001537 * jc);
    const anom_rad = std.math.degreesToRadians(geom_mean_anom);

    // Eccentricity of Earth's orbit
    const eccentricity = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc);

    // Equation of center
    const eqn_of_center =
        @sin(anom_rad) * (1.914602 - jc * (0.004817 + 0.000014 * jc)) +
        @sin(2.0 * anom_rad) * (0.019993 - 0.000101 * jc) +
        @sin(3.0 * anom_rad) * 0.000289;

    // Sun's true longitude
    const sun_true_long = geom_mean_long + eqn_of_center;

    // Apparent longitude (corrected for aberration)
    const omega = 125.04 - 1934.136 * jc;
    const sun_apparent_long = sun_true_long - 0.00569 - 0.00478 * @sin(std.math.degreesToRadians(omega));

    // Mean obliquity of the ecliptic (degrees)
    const mean_obliquity = 23.0 + (26.0 + (21.448 - jc * (46.8150 + jc * (0.00059 - jc * 0.001813))) / 60.0) / 60.0;

    // Corrected obliquity
    const obliq_corr = mean_obliquity + 0.00256 * @cos(std.math.degreesToRadians(omega));

    // Solar declination (degrees)
    const sin_declin = @sin(std.math.degreesToRadians(obliq_corr)) * @sin(std.math.degreesToRadians(sun_apparent_long));
    const declination = std.math.radiansToDegrees(std.math.asin(sin_declin));

    // Equation of time (minutes)
    const obliq_half_rad = std.math.degreesToRadians(obliq_corr / 2.0);
    const var_y = @tan(obliq_half_rad) * @tan(obliq_half_rad);
    const geom_long_rad = std.math.degreesToRadians(geom_mean_long);
    const eqn_of_time = 4.0 * std.math.radiansToDegrees(
        var_y * @sin(2.0 * geom_long_rad) -
            2.0 * eccentricity * @sin(anom_rad) +
            4.0 * eccentricity * var_y * @sin(anom_rad) * @cos(2.0 * geom_long_rad) -
            0.5 * var_y * var_y * @sin(4.0 * geom_long_rad) -
            1.25 * eccentricity * eccentricity * @sin(2.0 * anom_rad),
    );

    // UTC minutes of day
    const utc_minutes = @mod(ts, 86400.0) / 60.0;

    // True solar time (minutes)
    const true_solar_time = @mod(utc_minutes + eqn_of_time + 4.0 * input.longitude_deg, 1440.0);

    // Hour angle (degrees)
    const hour_angle = if (true_solar_time / 4.0 < 0.0)
        true_solar_time / 4.0 + 180.0
    else
        true_solar_time / 4.0 - 180.0;

    // Solar zenith angle
    const lat_rad = std.math.degreesToRadians(input.latitude_deg);
    const decl_rad = std.math.degreesToRadians(declination);
    const ha_rad = std.math.degreesToRadians(hour_angle);
    const cos_zenith = @sin(lat_rad) * @sin(decl_rad) + @cos(lat_rad) * @cos(decl_rad) * @cos(ha_rad);
    const solar_zenith = std.math.radiansToDegrees(std.math.acos(std.math.clamp(cos_zenith, -1.0, 1.0)));

    return 90.0 - solar_zenith;
}

/// Returns the interpolation factor for color temperature blending.
/// 0.0 = full night, 1.0 = full day.
/// Transitions linearly across civil twilight: -6° to +6° elevation.
pub fn blendFactor(elevation_deg: f64) f64 {
    return std.math.clamp((elevation_deg + 6.0) / 12.0, 0.0, 1.0);
}

/// Interpolate between night and day temperatures using the blend factor.
pub fn interpolateTemp(day_k: u32, night_k: u32, factor: f64) u32 {
    const d: f64 = @floatFromInt(day_k);
    const n: f64 = @floatFromInt(night_k);
    return @intFromFloat(@round(n + factor * (d - n)));
}

test "solarElevation summer solstice noon" {
    // 2024-06-21 12:00:00 UTC, lat=47.0, lon=7.0 → elevation ≈ +63°
    const ts: i64 = 1718971200; // 2024-06-21 12:00:00 UTC
    const elevation = solarElevation(.{
        .latitude_deg = 47.0,
        .longitude_deg = 7.0,
        .unix_timestamp = ts,
    });
    try std.testing.expectApproxEqAbs(@as(f64, 63.0), elevation, 2.0);
}

test "blendFactor transitions" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), blendFactor(-10.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), blendFactor(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), blendFactor(10.0), 0.001);
}

test "interpolateTemp" {
    try std.testing.expectEqual(@as(u32, 6500), interpolateTemp(6500, 4000, 1.0));
    try std.testing.expectEqual(@as(u32, 4000), interpolateTemp(6500, 4000, 0.0));
    try std.testing.expectEqual(@as(u32, 5250), interpolateTemp(6500, 4000, 0.5));
}
