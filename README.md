# zig-hue-lightsync

Sync your screen colors to Philips Hue lights. Wayland-native, written in Zig.

## Quick Start

```bash
# Build
zig build

# Discover bridges
./zig-out/bin/zig-hue-lightsync discover

# Pair (press the link button on your bridge)
./zig-out/bin/zig-hue-lightsync pair <BRIDGE_IP>

# Start syncing
./zig-out/bin/zig-hue-lightsync start --area <AREA_ID>
```

## Requirements

- Zig 0.15+
- Philips Hue Bridge v2 with Entertainment Area configured
- Linux + Wayland (for screen capture)

## Linux Screen Capture

```bash
sudo apt install libdbus-1-dev libpipewire-0.3-dev
zig build -Denable-capture=true
```

## License

MIT
