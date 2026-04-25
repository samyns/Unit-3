# my-dots

Hyprland + Quickshell + Waybar rice for Arch Linux, with a NieR:Automata aesthetic.

## Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<TOI>/my-dots/main/install.sh)
```

## What's included

- **Window manager**: Hyprland with custom keybinds (AZERTY layout)
- **Shell/widgets**: Quickshell with custom QML widgets (menu, lockscreen, wallpaper picker, notifications, player)
- **Bar**: Waybar
- **Terminal**: Kitty
- **Theme**: NieR-inspired with custom video transitions

## Customization

Personal overrides go in `~/.config/hypr/user.conf` — this file is **never** overwritten by updates.

Example:
monitor = DP-1, 2560x1440@144, 0x0, 1
input { kb_layout = us }
bind = SUPER, B, exec, firefox

## Keybinds

| Key | Action |
|-----|--------|
| `SUPER` (tap) | Open app menu |
| `SUPER + L` | Lockscreen |
| `SUPER + T` | Terminal (kitty) |
| `SUPER + Return` | Toggle Quickshell player |
| `SUPER + P` | Wallpaper picker |
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen |
| `ALT + Tab` | Cycle windows |
| `ALT + a/z/e/...` | Switch workspace (AZERTY) |
| `Print` | Screenshot |
| `ALT SHIFT + S` | Region screenshot |

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell).

## License

MIT
EOF
