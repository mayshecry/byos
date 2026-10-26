# 04 · Desktop & windows — adding apps and games

Every GUI program in BYOS (including all the system windows) is a
*window type* with up to five callbacks. This guide adds a complete
new one, step by step. The examples compile against the real APIs in
`include/desktop.h` / `include/win98_theme.h`.

## How a window lives

```c
struct window {
    char title[32];               // WINDOW_TITLE_MAX
    window_type_t type;
    window_state_t state;         // NORMAL / MINIMIZED / MAXIMIZED / CLOSING
    window_rect_t rect;           // x,y,width,height + client_x/y/w/h …
    bool visible, has_focus, needs_redraw;
    …
    void (*draw_func)(window_t* w);
    void (*keyboard_func)(window_t* w, char c);
    void (*mouse_func)(window_t* w, int mx, int my, int buttons);
    void (*close_func)(void);     // optional cleanup on close
    void (*game_tick)(void);      // optional ~60 Hz tick while focused
    void* user_data;              // yours
};
```

* Max **16 windows** (`MAX_WINDOWS`), 24 desktop icons, 32 start-menu
  entries.
* Coordinates: draw inside `w->rect.client_x/y/w/h` — *not* the
  outer rect; the frame/titlebar are the WM's.
* You are called to draw **only when needed**. After changing state
  set `w->needs_redraw = true; desktop.dirty = true;`.
* `mx,my` in `mouse_func` are **absolute screen** coordinates;
  `buttons` bit0 = left, bit1 = right, bit2 = middle. Wheel events
  reach windows via the desktop's own routing (see how
  `start_menu_scroll` / settings handle it in `desktop.c`).
* Keys in `keyboard_func`: printable ASCII, `'\n'`, `'\b'`, `27`
  (ESC — convention: games exit on ESC via `window_close_by_ptr(w)`),
  arrows `0x10` up, `0x11` down, `0x12` left, `0x13` right.
* `game_tick` is a bare `void(void)` called roughly every 16 ms
  **while your window is focused**. Store per-app state in statics
  or `user_data`; end the tick with `desktop.dirty = true` (the main
  loop does it for the focused game tick already).

## Cookbook: a new window in 6 steps

We'll add **"Counter"**: shows a number, click or Space to increment,
R to reset, ESC to close.

### 1. Register the type — `include/desktop.h`

```c
typedef enum {
    WINDOW_TYPE_TERMINAL,
    …
    WINDOW_TYPE_DISKMGMT,
    WINDOW_TYPE_COUNTER,     /* <-- add before MAX */
    WINDOW_TYPE_MAX
} window_type_t;
```

Order doesn't matter except: keep it before `WINDOW_TYPE_MAX`
(title-icon caches are sized by it).

### 2. Declare the handlers — `include/desktop.h`

Near the other `app_window_*` declarations:

```c
void app_window_draw_counter(window_t* w);
void app_window_keyboard_counter(window_t* w, char c);
void app_window_mouse_counter(window_t* w, int mx, int my, int buttons);
```

### 3. Implement them — new file `src/desktop/counter.c`

New files under `src/<anything>/*.c` are compiled automatically.
(Or append to `appwindows.c` like the system windows — your call.)

```c
#include "kernel.h"
#include "desktop.h"
#include "win98_theme.h"

static int counter_value = 0;

void app_window_draw_counter(window_t* w) {
    int cx = w->rect.client_x, cy = w->rect.client_y;
    int cw = w->rect.client_w, ch = w->rect.client_h;

    w98_fill(cx, cy, cw, ch, W98_BTNFACE);

    w98_rect_t clip = { cx, cy, cw, ch };
    w98_text_bold("Counter", cx + 8, cy + 8, W98_BTNTEXT,
                  W98_BTNFACE, 1, &clip);
    w98_bevel(cx + 4, cy + 22, cw - 8, 2, W98_BEVEL_ETCHED);

    /* sunken readout */
    w98_surface(cx + 16, cy + 36, 120, 28, W98_BEVEL_SUNKEN, W98_WINDOW);
    char buf[16];
    int_to_string((uint32_t)counter_value, buf);
    w98_text(buf, cx + 24, cy + 44, W98_WINDOWTEXT, W98_WINDOW, 1, &clip);

    w98_button(cx + 16, cy + 76, 80, 24, "Add", false, true, false);
    w98_text("Space/click: +1   R: reset   ESC: close",
             cx + 16, cy + 112, W98_GRAYTEXT, W98_BTNFACE, 1, &clip);
}

static void counter_bump(window_t* w, int delta) {
    counter_value += delta;
    w->needs_redraw = true;
    desktop.dirty = true;
}

void app_window_keyboard_counter(window_t* w, char c) {
    if (c == 27) { window_close_by_ptr(w); return; }
    if (c == ' ') counter_bump(w, 1);
    else if (c == 'r' || c == 'R') { counter_value = 0; counter_bump(w, 0); }
}

void app_window_mouse_counter(window_t* w, int mx, int my, int buttons) {
    if (!(buttons & 1)) return;                       /* left button */
    int bx = w->rect.client_x + 16, by = w->rect.client_y + 76;
    if (mx >= bx && mx < bx + 80 && my >= by && my < by + 24)
        counter_bump(w, 1);
}
```

Notes that save debugging time:

* `int_to_string`, `hex_to_string`, `strcpy`, `strlen`, `memcpy`
  are the kernel's freestanding versions from `kernel.h`. There is
  **no printf** — build strings into stack buffers (keep them small;
  the kernel stack is 256 KiB shared by everything).
* Colours are `0xAARRGGBB`. Use the `W98_*` macros (they read the
  *current theme*) unless you specifically want fixed colours.
* Always clip: pass a `w98_rect_t` of your client area to text calls,
  and check `cw/ch` minimums before drawing fixed layouts — windows
  can be resized to `WINDOW_MIN_W/H` (160×80).

### 4. Wire it into the window factory — `src/desktop/windowmanager.c`

In `window_create()`'s `switch (type)`:

```c
        case WINDOW_TYPE_COUNTER:
            win->draw_func = app_window_draw_counter;
            win->keyboard_func = app_window_keyboard_counter;
            win->mouse_func = app_window_mouse_counter;
            break;
```

### 5. Give it a default size (optional) — `src/desktop/desktop.c`

In `desktop_icon_launch_offset()`:

```c
    } else if (type == WINDOW_TYPE_COUNTER) {
        win_w = 300; win_h = 200;
    }
```

Default is 400×300 if you skip this.

### 6. Make it launchable

Start menu — in `start_menu_open()` (`src/desktop/startmenu.c`),
add to the `names/types` list:

```c
    names[start_menu_count] = "Counter";
    types[start_menu_count] = WINDOW_TYPE_COUNTER;
    start_menu_count++;
```

Desktop icon — in `desktop_init()` (`src/desktop/desktop.c`):

```c
    desktop_icon_add("Counter", WINDOW_TYPE_COUNTER);
```

Its icon comes from `desktop_icon_pixels_for_type()` in
`src/desktop/icons.c`; unknown types fall back to the "info" icon.
To give it real art per theme, see
[08 · Themes, icons, wallpapers](08-themes-icons-wallpapers.md#adding-an-icon).

Rebuild with `make run` — done. Everything else (dragging,
min/max/close buttons, taskbar button, Alt-Tab, title icon,
animations) is inherited from the window manager.

## Making it a game (real-time tick)

Register the tick (and optional cleanup) in the same factory case
as your draw/input handlers, in `window_create()`:

```c
        case WINDOW_TYPE_COUNTER:
            …
            win->game_tick = counter_tick;   /* called ~every 16 ms while focused */
            win->close_func = counter_cleanup; /* free/reset on close */
            break;
```

`game_tick` and `close_func` take **no arguments** (historical API),
so keep module-level statics. Timing: compare `uptime_ticks`
(1 = 1 ms) against your own last-tick stamps for frame pacing; the
desktop also exposes `sys_frames_per_sec` if you want an FPS readout.

Drawing fast graphics: write pixels directly —

```c
uint32_t stride = (uint32_t)(screen_pitch / 4);
lfbptr[y * stride + x] = 0xFFRRGGBB;   /* back-buffer, absolute coords */
draw_rect(x, y, w, h, color);          /* or the helper from kernel.h */
draw_string_px(s, x, y, fg, bg);       /* 8x8 bitmap font, cheap */
```

—but clip to your client rect yourself. Upstream's games (deleted
here) all drew this way with a `set_window_rect` helper; you can
recreate that pattern from any system window that does custom
drawing (Task Manager's graphs are a good model).

## Widgets cheat-sheet (`win98_theme.h` / `win98_widgets.c`)

| Call | Does |
|---|---|
| `w98_fill(x,y,w,h,color)` | solid rect |
| `w98_bevel(x,y,w,h, W98_BEVEL_RAISED/_RAISED_PRESSED/_SUNKEN/_ETCHED)` | border only |
| `w98_surface(x,y,w,h,style,fill)` | bevel + fill (panels, readouts) |
| `w98_button(x,y,w,h,label,pressed,enabled,focused)` | full button face |
| `w98_hgradient/vgradient(x,y,w,h,c1,c2)` | gradients |
| `w98_text(s,x,y,fg,bg,scale,clip)` / `_bold` / `_outline` / `_alpha*` | UI text (TTF when theme allows, else bitmap) |
| `w98_text_width(s,scale)`, `w98_text_height(scale)` | measure before centring |
| `w98_text_fit(src,dst,len,maxw,scale)` | truncate with … to fit |
| `w98_icon_blit(src,32,dst,x,y,clip)` / `_small` | draw 32×32 icon pixels scaled |
| `w98_blit_rgb(src,sw,sh,x,y,clip)` | raw ARGB image blit (wallpaper thumbs use this) |
| `w98_glyph(kind,x,y,fg)` | min/max/restore/close glyphs |

`scale` is almost always `1` inside windows. Passing `NULL` clip is
allowed but then *you* own the bounds.

## Repaint rules (the #1 bug source)

1. One-off change → `w->needs_redraw = true; desktop.dirty = true;`
2. Your window moved under the cursor / menus → the desktop handles
   it via `desktop_invalidate_rect`.
3. Animation → set `desktop.dirty = true` every tick (the game-tick
   path does), Accept the cost: the compositor redraws the dirty
   region into the back-buffer and flushes rows to hardware.
4. **Never** draw outside a draw call — input handlers must only
   mutate state + mark dirty.
5. Hover effects: only Settings/FileManager/DiskMgmt get hover
   repaints in `main.c`'s pointer path (plus flat-bevel titlebars).
   If your window needs hover feedback, add its type to that list in
   `src/shell/main.c` or accept click-only feedback.

## Single-instance windows

Want "open or focus"? Copy `cmd_taskmanager`'s pattern: scan
`desktop.windows[]` for your type, `window_restore(i)` if minimized
else `window_focus(i)`, `desktop.dirty = true`, and skip creating.

## Removing a system window

The mirror image of the cookbook: delete the enum value, factory
case, draw functions, start-menu/icon entries, launch-size branch,
icon cases in all four theme switches in `icons.c`, and any
special-casing (`main.c` hover list, blink list, `desktop.c`
context menus). `make verify` + a compile will find the leftovers —
this is exactly how the games/browser were removed from SharkOS to
make BYOS.
