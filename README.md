# nebula-drm

DRM-based color temperature tool with solar position calculation.

## Purpose

COSMIC DE does not implement the `wlr-gamma-control-unstable-v1` Wayland protocol, so tools like wlsunset and gammastep cannot control color temperature from within the session. Redshift is X11-only and does not work on Wayland at all. The workaround is to manipulate DRM gamma tables directly via libdrm, before the compositor acquires DRM master.

nebula-drm applies a color temperature to all active displays based on the current UTC time and your geographic position. It transitions smoothly between day and night temperatures across civil twilight (solar elevation −6° to +6°). It is designed to run once at boot, before the display manager starts, and the gamma setting persists for the duration of the session since COSMIC does not reset gamma tables it does not manage.

## Requirements

- [Zig](https://ziglang.org/) 0.15+ (build only)
- libdrm

## Build

```sh
zig build -Doptimize=ReleaseSafe
```

The binary is output to `zig-out/bin/nebula-drm`.

## Usage

```
nebula-drm -l LAT:LON -t DAY:NIGHT [-d CARD] [-b DAY:NIGHT] [-v]

  -l LAT:LON      Location in decimal degrees (e.g. 47.37:8.54)
  -t DAY:NIGHT    Color temperatures in Kelvin (e.g. 6500:4500)
  -d CARD         DRM card index (default: auto-detect)
  -b DAY:NIGHT    Brightness multipliers 0.0–1.0 (default: 1.0:0.8)
  -v              Verbose output
```

The tool must run before the display manager. Running it inside an active compositor session will fail because the compositor holds DRM master.

## Mid-session refresh

The gamma setting applied at boot reflects the solar position at that time. If the session runs across a day/night transition, the setting will be stale.

To refresh mid-session, switch to a text console (the compositor releases DRM master on VT switch), restart the service, then switch back:

1. `Ctrl+Alt+F3`
2. `sudo systemctl restart nebula-drm`
3. `Ctrl+Alt+F2`

The service re-reads `/etc/nebula-drm.conf` and recomputes the temperature from the current time. The updated gamma persists after switching back to the graphical session.

## Manual Installation

### Binary

```sh
install -Dm755 zig-out/bin/nebula-drm /usr/local/bin/nebula-drm
```

### Configuration

```sh
install -Dm644 nebula-drm.conf /etc/nebula-drm.conf
```

Edit `/etc/nebula-drm.conf` to set your location and temperatures:

```sh
# Geographic position in decimal degrees (latitude:longitude)
NEBULA_LOCATION=47.37:8.54

# Color temperatures in Kelvin (day:night)
NEBULA_TEMP=6500:4500

# Brightness multipliers (day:night), 0.0 to 1.0
NEBULA_BRIGHTNESS=1.0:0.8

# DRM card index to use (leave empty for auto-detect)
# NEBULA_CARD=-d 1
```

### systemd Service

```sh
install -Dm644 systemd/nebula-drm.service \
    /etc/systemd/system/nebula-drm.service
```

To ensure the service starts before greetd, add a drop-in:

```sh
install -Dm644 systemd/greetd.service.d/after-nebula-drm.conf \
    /etc/systemd/system/greetd.service.d/after-nebula-drm.conf
```

Enable and start:

```sh
systemctl enable --now nebula-drm
```

## How it works

1. Computes the current solar elevation angle from latitude, longitude, and UTC time using the NOAA solar position algorithm.
2. Derives a blend factor from the elevation: 0.0 (night) at −6° and below, 1.0 (day) at +6° and above, linear in between.
3. Interpolates between the night and day Kelvin values and converts the result to RGB gamma multipliers using the Tanner Helland approximation.
4. Applies a 16-bit gamma LUT to all active CRTCs on the selected DRM card via `drmModeCrtcSetGamma`.

## License

MIT
