# Unit-3

Hyprland + Quickshell + Waybar rice for Arch Linux, with a NieR:Automata aesthetic.


## Support

[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white&labelColor=101418)](https://ko-fi.com/samyns)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black&labelColor=101418)](https://www.buymeacoffee.com/samyns)

A ⭐ on the repo or sharing your own rice in the issues makes me just as happy.


# SHOW OFF
https://github.com/user-attachments/assets/f3366b70-cfa0-46ef-b4f5-e461546364e2

## Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/samyns/Unit-3/main/install.sh)
```
or
```
curl -fsSL https://raw.githubusercontent.com/samyns/Unit-3/main/install.sh | bash
```

## What's included

- **Window manager**: Hyprland with custom keybinds (QWERTY layout)
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
| `ALT + 1/2/3/...` | Switch workspace (QWERTY) |
| `Print` | Screenshot |
| `ALT SHIFT + S` | Region screenshot |

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell).

Inspired by https://github.com/flickowoa/dotfiles.git 
## License

MIT
EOF

## Star History


<a href="https://www.star-history.com/?repos=samyns%2FUnit-3&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=samyns/Unit-3&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=samyns/Unit-3&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=samyns/Unit-3&type=date&legend=top-left" />
 </picture>
</a>
