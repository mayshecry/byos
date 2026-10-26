# 08 · Themes, icons, wallpapers, fonts

Making your distro *look* like yours. Three independent systems:
**desktop themes** (colours/flags), **icon packs** (per-theme pixel
art), **wallpaper presets** (generated gradients — plus how to do
real images). Fonts at the end.

## Adding a desktop theme

A theme is one `desktop_theme_t` in `src/desktop/theme.c`:

```c
typedef struct {                     /* include/theme.h */
    const char* name;                /* shown in Settings          */
    uint32_t desktop, desktop_dark;  /* background + dither pair   */
    uint32_t btnface, btnhilite, btnlight, btnshadow, btndkshadow,
             btntext, graytext;      /* the Win95 bevel palette    */
    uint32_t active_title, active_title2,
             inactive_title, inactive_title2,
             titletext, titletext_inact;
    uint32_t highlight, highlighttext;
    uint32_t window, windowtext;     /* client area defaults       */
    uint32_t caption_start, caption_end;
    uint32_t menu_bg, icon_label, logo;
    bool title_gradient;             /* blend title -> title2      */
    bool flat_bevels;                /* WM-style flat borders      */
    bool nice_font;                  /* TrueType UI text vs bitmap */
    bool animations;                 /* window open/close anim     */
    bool flat_taskbar;
    bool title_accent_line;
    bool modern_icons;
    int  ui_font_size;               /* TTF size for nice_font     */
} desktop_theme_t;
```

Steps:

1. Copy `theme_win98` in `theme.c`, rename, recolour
   (`theme_modern` is a good dark reference).
2. In `include/theme.h`: add `THEME_ID_MYTHEME 4`, bump
   `THEME_COUNT` to 5, `extern const desktop_theme_t theme_mytheme;`.
3. In `theme.c`: handle the ID in `theme_set()` (sets
   `theme_current`) and `theme_get_name()`.

That's all — **Settings lists themes by looping `0..THEME_COUNT`**
and calling `theme_get_name(i)`/`theme_set(i)`, so your theme
appears automatically. UI code reads colours through the `W98_*`
macros (`W98_BTNFACE` → `theme_current->btnface` etc. in
`win98_theme.h`), so nothing else changes. Watch for the one special
case: `theme_set` auto-selects the Plum wallpaper for the Kawaii
theme — copy/adjust that block if your theme wants its own preset.

Default theme at boot: Win98 (`theme_current` initialiser in
`theme.c`); Kawaii is selected if the boot cmdline contains
`kawaii` (see `kmain`). Note the *console* UI (Lite/panes) has a
separate, older theming triple (`THEME_DEFAULT`/`THEME_BLUE`/
`THEME_TEMPLEOS`, `apply_theme()` in `src/ui/ui.c`) — independent
from desktop themes.

## Adding an icon

Icons are **32×32 ARGB** (`uint32_t[1024]`, `0xAARRGGBB`, alpha
honoured by the blitter) stored as C arrays in per-theme headers:
`include/icon_data.h` (Win98), `modern_icon_data.h`,
`kawaii_icon_data.h`, `windowmaker_icon_data.h`.
`desktop_icon_pixels_for_type()` in `src/desktop/icons.c` switches
on theme × window type; the same art (via title-icon cache in
`windowmanager.c`) becomes 16×16 titlebar icons.

For a new window type add one case per theme (or point all four at
one array while prototyping):

```c
case WINDOW_TYPE_COUNTER: return (uint32_t*)icon_data_counter;
```

Convert a PNG to an array with Python (Pillow):

```python
# tools/png2icon.py  —  usage: python3 png2icon.py counter.png >> include/icon_data.h
import sys
from PIL import Image
name = sys.argv[2] if len(sys.argv) > 2 else "icon_data_counter"
im = Image.open(sys.argv[1]).convert("RGBA").resize((32, 32))
px = list(im.getdata())
print(f"static const uint32_t {name}[32 * 32] = {{")
for y in range(32):
    row = px[y*32:(y+1)*32]
    print("    " + ", ".join(f"0x{a:02x}{r:02x}{g:02x}{b:02x}" for r, g, b, a in row) + ",")
print("};")
```

Guidelines: design at 32×32 with chunky shapes (it will be shown at
32 and downscaled to 16 for titlebars/start menu via
`w98_icon_blit_small`). Keep one unnamed-style array per theme pack
naming convention (`icon_data_*`, `micon_*`, `kawaii_icon_data_*`,
`wm_icon_data_*`) so the switches stay greppable. Unused arrays in
headers cost compile time only — `static const` + `-gc-sections`
means unreferenced art is not linked.

The four shared glyphs (`desktop_icon_get_start/shutdown/folder/file`
in `icons.c`) follow the same pattern — replace their arrays to
rebrand the Start button.

## Wallpapers: presets, colours, real images

### The preset system

`wallpaper_catalog[WP_COUNT]` in `src/desktop/desktop.c` pairs a
name with a top/bottom ARGB; `desktop_set_wallpaper(id)` selects
one (mode `W98_WALL_IMAGE`), the renderer builds a full-screen
vertical gradient cache, and Settings shows auto-generated 72×45
thumbnails. Add a preset:

1. `include/desktop.h`: add `WP_ID_MYWP 6`, bump `WP_COUNT` to 7.
2. `desktop.c`: append `{ "My WP", 0xFF112233u, 0xFF445566u }`.

Settings enumerates via `desktop_wallpaper_count()/name()/thumb()`,
so it just appears. `WP_ID_CLASSIC` (index 0) uses
`WALLPAPER_TOP/BOTTOM` from `config.mk` — that's your distro's
default look; change it there, not in code.

Modes: `W98_WALL_DITHER` (theme two-colour dither — the default at
boot), `W98_WALL_SOLID` (`desktop_set_wallpaper_color()` + Settings
colour swatches), `W98_WALL_IMAGE` (preset/gradient cache). Fit
(`desktop_set_wallpaper_fit`) is accepted for API compatibility but
irrelevant to gradients.

### Using a real image instead

The decoders are still linked (`src/desktop/{png,jpeg,gif,webp}.c`)
— they just have **no header** (upstream declared them in the
removed browser header). Declare what you need:

```c
/* returns >=0 on success; pixels are ARGB, row-major, w*h */
int png_decode_buf (const uint8_t* data, size_t len, int* out_w, int* out_h,
                    uint32_t* pixels, size_t max_pixels,
                    uint8_t* scratch, size_t scratch_len);
int jpeg_decode_buf(...same shape...);
int gif_decode_buf (...same shape...);
int webp_decode_buf(...same shape...);
uint32_t* decode_png(const uint8_t* data, size_t len, int* w, int* h); /* allocs */
```

Then embed an image (xxd-style array, `kmalloc` a pixel buffer +
scratch sized like upstream did), decode once at boot into the
wallpaper cache path in `desktop_wallpaper_rebuild_cache()` — i.e.
replace the gradient fill with a nearest/bilinear scale of your
decoded image (the git history of upstream SharkOS has a scaler
you can adapt). Keep images small: a 1024×768 ARGB buffer is 3 MiB
of your bump-allocator pool.

## Fonts

Three layers, don't confuse them:

| Layer | Data | Used by |
|---|---|---|
| 8×8 bitmap `font8x8[96][8]` in `src/lib/globals.c` | hand table | `draw_char` (console/panic) |
| 8×16 terminal font `include/term_font16_data.h` | generated table | framebuffer terminal cells |
| TrueType `include/font_data.h` + renderer `src/desktop/font.c` (`br_font_*`, declared in `include/font.h`) | embedded TTF faces | W98 widgets when `theme->nice_font`; `br_font_init()` runs in `desktop_init` |

Swap the TTF by regenerating `font_data.h` from your font files in
the same array layout (inspect the header's face table first —
`font.c` parses real TTF tables `cmap/glyf/loca`, so a valid TTF
dump works; keep an eye on total size). `w98_classic_font_force`
forces bitmap text globally — handy A/B switch while theming.

## Boot screen & start-menu sidebar

* Boot banner: `OS_NAME " " OS_VERSION " (" OS_CODENAME ")"` in
  `boot_screen_show()` (`src/desktop/bootscreen.c`); `draw_logo()`
  there draws the generic ring emblem used on the About window —
  replace its rasteriser with your own mark (keep the signature).
* Start-menu sidebar text is `OS_NAME` drawn vertically in
  `start_menu_draw()`; long names crop — shorten or customise there.
