# Tridactyl Keymaps

## Navigation

| Key | Action |
|-----|--------|
| `j` | Scroll down 10 lines |
| `k` | Scroll up 10 lines |
| `h` | Scroll left 50px |
| `l` | Scroll right 50px |
| `G` | Scroll to bottom |
| `gg` | Scroll to top |
| `^` | Scroll to left |
| `d` | Scroll down half page |
| `e` | Scroll up half page |
| `<C-u>` | Scroll up half page |
| `<C-b>` | Scroll up full page |
| `<C-y>` | Scroll up 10 lines |
| `H` | Go back |
| `L` | Go forward |
| `<C-o>` | Jump to previous position |
| `<C-i>` | Jump to next position |
| `[[` | Follow "previous" page link |
| `]]` | Follow "next" page link |
| `[c` | Decrement URL number |
| `]c` | Increment URL number |
| `<C-x>` | Decrement URL number |
| `<C-a>` | Increment URL number |
| `gu` | Go to parent URL |
| `gU` | Go to root URL |
| `gh` | Go home |
| `gH` | Go home (new tab) |

## Tabs

| Key | Action |
|-----|--------|
| `J` | Previous tab |
| `K` | Next tab |
| `gt` | Next tab (gt-style) |
| `gT` | Previous tab |
| `g^` / `g0` | First tab |
| `g$` | Last tab |
| `x` | Close tab |
| `D` | Close tab and switch to previous |
| `gx0` | Close all tabs to the left |
| `gx$` | Close all tabs to the right |
| `<<` | Move tab left |
| `>>` | Move tab right |
| `u` | Undo close tab |
| `U` | Undo close window |
| `r` | Reload |
| `R` | Hard reload |
| `gd` | Detach tab to new window |
| `gD` | Merge windows |
| `ga` | Go to audible tab |
| `<A-p>` | Pin tab |
| `<A-m>` | Toggle mute |

## Opening Pages

| Key | Action |
|-----|--------|
| `o` | Open URL |
| `O` | Open URL (prefill current) |
| `t` | Open in new tab |
| `T` | Open current URL in new tab |
| `w` | Open in new window |
| `W` | Open current URL in new window |
| `s` | Search |
| `S` | Search in new tab |
| `p` | Open clipboard URL |
| `P` | Open clipboard URL in new tab |
| `b` | Switch tab |
| `B` | Search all tabs |

## Quick Sites

| Key | Action |
|-----|--------|
| `gny` | New tab: YouTube |
| `goy` | Open: YouTube |
| `gwy` | New window: YouTube |
| `gpy` | Private window: YouTube |
| `gng` | New tab: GitHub |
| `gog` | Open: GitHub |
| `gwg` | New window: GitHub |
| `gpg` | Private window: GitHub |

## Hints

| Key | Action |
|-----|--------|
| `f` | Hint (follow link) |
| `F` | Hint (open in background tab) |
| `gF` | Hint (open in background, quick) |
| `;i` | Hint image |
| `;b` | Hint (background tab) |
| `;o` | Hint (open) |
| `;I` | Hint image (foreground) |
| `;k` | Hint (kill element) |
| `;K` | Hint (kill element sticky) |
| `;y` | Hint (yank URL) |
| `;Y` | Hint (yank image URL) |
| `;p` | Hint (open in private window) |
| `;P` | Hint (open in private window, clipboard) |
| `;h` | Hint (hover) |
| `v` | Hint (hover) |
| `;r` | Hint (read) |
| `;s` | Hint (save as) |
| `;S` | Hint (save as, silent) |
| `;a` | Hint (add bookmark) |
| `;A` | Hint (add bookmark, all) |
| `;;` | Hint (focus element) |
| `;#` | Hint (copy anchor) |
| `;v` | Hint (open in mpv) |
| `;V` | Hint (open in mpv, video) |
| `;w` | Hint (open in new window) |
| `;t` | Hint (open in new tab) |
| `;O` | Hint + fillcmdline open |
| `;W` | Hint + fillcmdline winopen |
| `;T` | Hint + fillcmdline tabopen |
| `;d` | Hint (open in discarded tab) |
| `;gd` | Hint (open in discarded tab, quick) |
| `;z` | Hint (zoom) |
| `;m` | Hint image (Google Lens) |
| `;M` | Hint image (Google Lens, new tab) |

### Hint Quick (`;g` prefix)

| Key | Action |
|-----|--------|
| `;gi` | Quick hint image |
| `;gI` | Quick hint image (foreground) |
| `;gk` | Quick hint kill |
| `;gy` | Quick hint yank |
| `;gp` | Quick hint private window |
| `;gP` | Quick hint private clipboard |
| `;gr` | Quick hint read |
| `;gs` | Quick hint save |
| `;gS` | Quick hint save silent |
| `;ga` | Quick hint bookmark |
| `;gA` | Quick hint bookmark all |
| `;g;` | Quick hint focus |
| `;g#` | Quick hint anchor |
| `;gv` | Quick hint mpv |
| `;gw` | Quick hint window |
| `;gb` / `;gF` | Quick hint background tab |
| `;gf` | Quick hint follow |

## Mouse Simulation (xdotool)

| Key | Action |
|-----|--------|
| `;x` | Hint + left click at element |
| `;c` | Hint + right click at element |
| `;:` | Hint + move mouse to element |
| `;X` | Hint + ctrl+shift+click at element |

## Yank / Clipboard

| Key | Action |
|-----|--------|
| `yy` | Yank URL |
| `ys` | Yank short URL |
| `yc` | Yank canonical URL |
| `ym` | Yank as markdown link |
| `yo` | Yank as org-mode link |
| `yt` | Yank page title |
| `yq` | URL to QR code (5s) |
| `yg` | Yank git clone command (SSH) |

## Bookmarks & Marks

| Key | Action |
|-----|--------|
| `a` | Bookmark current URL |
| `A` | Bookmark |
| `M` | Set quickmark |
| `m` | Set mark |
| `` ` `` | Go to mark |

## Zoom

| Key | Action |
|-----|--------|
| `zi` | Zoom in +0.1 |
| `zo` | Zoom out -0.1 |
| `zm` / `zM` | Zoom in +0.5 |
| `zr` / `zR` | Zoom out -0.5 |
| `zz` | Reset zoom (1x) |
| `zI` | Zoom to 3x |
| `zO` | Zoom to 0.3x |

## Modes & Misc

| Key | Action |
|-----|--------|
| `<Escape>` / `<C-[>` | Normal mode + hide cmdline |
| `<S-Insert>` / `<S-Escape>` | Ignore mode |
| `<AC-Escape>` / `<AC-`>` | Ignore mode |
| `<C-v>` | Ignore next key |
| `gi` | Focus last input |
| `:` | Open command line |
| `.` | Repeat last command |
| `gr` | Reader mode (old) |
| `gf` | View source |
| `g?` | ROT13 |
| `g!` | Jumble text |
| `g;` | Jump to last change |
| `EE` | Reload tridactyl config |
| `ZZ` | Quit all |
| `<F1>` | Help |

## Easter Egg

| Key | Action |
|-----|--------|
| `Up Up Down Down Left Right Left Right b a` | (with Alt+Shift held) Konami code — opens a YouTube video. **Note:** unusable in practice since `Alt+Shift+B` opens Firefox bookmarks menu. |
