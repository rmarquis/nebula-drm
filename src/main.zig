const std = @import("std");
const solar = @import("solar.zig");
const colortemp = @import("colortemp.zig");
const drm = @import("drm.zig");

const usage =
    \\Usage: nebula-drm -l LAT:LON -t DAY:NIGHT [-d CARD] [-b BRIGHTNESS] [-v]
    \\
    \\  -l LAT:LON      Location in decimal degrees (e.g. 47.37:8.54)
    \\  -t DAY:NIGHT    Color temperatures in Kelvin (e.g. 6500:4500)
    \\  -d CARD         DRM card index to use (default: auto-detect 0-9)
    \\  -b BRIGHTNESS   Brightness multiplier 0.0-1.0 (default: 1.0)
    \\  -v              Verbose output
    \\
;

const Args = struct {
    lat: f64 = 0.0,
    lon: f64 = 0.0,
    day_k: u32 = 6500,
    night_k: u32 = 4500,
    card: ?u8 = null,
    brightness: f64 = 1.0,
    verbose: bool = false,
    lat_set: bool = false,
    temp_set: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args_iter = std.process.args();
    _ = args_iter.next(); // skip argv[0]

    var cfg = Args{};

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-l")) {
            const val = args_iter.next() orelse fatal("missing value for -l");
            cfg = parseLocation(cfg, val) catch fatal("invalid location format, expected LAT:LON");
        } else if (std.mem.eql(u8, arg, "-t")) {
            const val = args_iter.next() orelse fatal("missing value for -t");
            cfg = parseTemps(cfg, val) catch fatal("invalid temperature format, expected DAY:NIGHT");
        } else if (std.mem.eql(u8, arg, "-d")) {
            const val = args_iter.next() orelse fatal("missing value for -d");
            cfg.card = std.fmt.parseInt(u8, val, 10) catch fatal("invalid card index");
        } else if (std.mem.eql(u8, arg, "-b")) {
            const val = args_iter.next() orelse fatal("missing value for -b");
            cfg.brightness = std.fmt.parseFloat(f64, val) catch fatal("invalid brightness value");
        } else if (std.mem.eql(u8, arg, "-v")) {
            cfg.verbose = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            std.process.exit(0);
        } else {
            std.log.err("unknown argument: {s}", .{arg});
            std.debug.print("{s}", .{usage});
            std.process.exit(1);
        }
    }

    if (!cfg.lat_set or !cfg.temp_set) {
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }

    // Compute solar position from current UTC time and location
    const now = std.time.timestamp();
    const elevation = solar.solarElevation(.{
        .latitude_deg = cfg.lat,
        .longitude_deg = cfg.lon,
        .unix_timestamp = now,
    });
    const factor = solar.blendFactor(elevation);
    const kelvin = solar.interpolateTemp(cfg.day_k, cfg.night_k, factor);

    if (cfg.verbose) {
        std.log.info("solar elevation: {d:.2}°, blend: {d:.3}, temperature: {d}K", .{ elevation, factor, kelvin });
    }

    // Convert temperature to RGB gamma multipliers
    const rgb = colortemp.kelvinToRgb(kelvin);

    if (cfg.verbose) {
        std.log.info("gamma RGB: R={d:.4} G={d:.4} B={d:.4} brightness={d:.3}", .{ rgb.r, rgb.g, rgb.b, cfg.brightness });
    }

    // Apply gamma to DRM
    drm.applyGammaAuto(allocator, cfg.card, .{
        .r = rgb.r,
        .g = rgb.g,
        .b = rgb.b,
        .brightness = cfg.brightness,
    }) catch |err| {
        std.log.err("DRM error: {s}", .{@errorName(err)});
        if (err == drm.DrmError.MasterUnavailable) {
            std.log.err("hint: a compositor is holding DRM master — run this tool before the display manager starts", .{});
        }
        std.process.exit(1);
    };

    if (cfg.verbose) {
        std.log.info("gamma applied successfully", .{});
    }
}

fn fatal(msg: []const u8) noreturn {
    std.log.err("{s}", .{msg});
    std.process.exit(1);
}

fn parseLocation(cfg: Args, val: []const u8) !Args {
    const colon = std.mem.indexOfScalar(u8, val, ':') orelse return error.InvalidFormat;
    var result = cfg;
    result.lat = try std.fmt.parseFloat(f64, val[0..colon]);
    result.lon = try std.fmt.parseFloat(f64, val[colon + 1 ..]);
    result.lat_set = true;
    return result;
}

fn parseTemps(cfg: Args, val: []const u8) !Args {
    const colon = std.mem.indexOfScalar(u8, val, ':') orelse return error.InvalidFormat;
    var result = cfg;
    result.day_k = try std.fmt.parseInt(u32, val[0..colon], 10);
    result.night_k = try std.fmt.parseInt(u32, val[colon + 1 ..], 10);
    result.temp_set = true;
    return result;
}
