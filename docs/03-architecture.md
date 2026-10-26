# 03 · Architecture

How BYOS (the stripped SharkOS base — upstream:
<https://github.com/mayshecry/shark-os>) is put together. Read this
before restructuring anything; it explains the constraints every
other doc assumes.

## The one-sentence version

One freestanding 64-bit ELF image runs everything — kernel, drivers,
shell, desktop — in **Ring 0, one flat identity-mapped address
space**, composited into a RAM back-buffer that is flushed to the
bootloader-provided framebuffer. There is no userspace, no scheduler
in the preemptive sense, and no persistent storage by default. This
is inherited from SharkOS and is what makes the codebase small
enough to actually understand.

## Boot flow

```
BIOS/UEFI firmware
  └─ Limine (from the ISO; GRUB also works — multiboot1 protocol)
       └─ boot.s : _start (32-bit entry)
            • zeroes BSS, builds page tables: 128 × 1 GiB identity map
              (2 MiB pages, 128 GiB total), enables PAE + long mode
            • far-jumps to long_mode_entry, sets the 256 KiB kernel stack
            • calls kmain(magic, mb_info)
                 └─ src/shell/main.c : kmain()
                      1. serial_init (COM1 debug log from here on)
                      2. parse cmdline: "lite"/"legacy" -> console mode,
                         "kawaii" -> Kawaii theme at boot
                      3. framebuffer + memory size from Multiboot info
                         (memory map scan, capped at 128 GiB)
                      4. pmm_init (bump allocator), ui_init_metrics
                      5. lite? -> lite_kmain() (src/shell/lite.c) and never returns
                      6. boot screen on; GDT/IDT (init_descriptor_tables),
                         PIC remap IRQ0-15 -> INT 32-47, PIT @ 1000 Hz
                      7. fs_initialize, mouse_init, unmask keyboard/mouse IRQs
                      8. ata_init* / audio_init* / net_init+net_stack_init*
                         (* = skipped when ENABLE_* = 0 in config.mk)
                      9. rtc_init, desktop_init, boot screen off
                     10. shadow copy of the framebuffer becomes lfbptr
                         (all drawing goes here; flush_*_to_hw copies out)
                     11. THE MAIN LOOP (below)
```

Key globals you'll use everywhere: `lfbptr` (back-buffer),
`hw_lfbptr` (real framebuffer), `screen_width/height/pitch`,
`total_system_memory`, `uptime_ticks` (1 tick = 1 ms,
`TICKS_PER_SEC` 1000), `current_user`, `current_kernel_mode`.

## The main loop (desktop mode)

`kmain`'s tail is a cooperative loop. One iteration:

1. `yield()` (`sti; hlt`) — sleep until the next IRQ.
2. Poll the mouse (`mouse_cursor_x/y`, `mouse_state.buttons/wheel`
   maintained by the PS/2 IRQ handler); feed `desktop_handle_mouse`.
   Buttons bitmask: bit0 left, bit1 right, bit2 middle.
3. Drain up to 16 keys from `keyboard_getchar()` into
   `desktop_handle_keyboard`. Special codes: `0x10–0x13` = arrow
   up/down/left/right, `27` ESC, `'\n'`, `'\b'`; `shift_pressed` /
   `ctrl_pressed` flags are global.
4. `desktop_anim_tick()` (window open/close animations).
5. Every 10 ms: `audio_tick()` (mixer → backend DMA) and
   `net_poll()` (RX, DHCP, TCP timers). Network state changes dirty
   the Network window.
6. Every 1000 ms: RTC read, CPU% accounting, Task Manager refresh.
7. Focused window amenities: text-cursor blink (500 ms) for
   Terminal/Notepad; focused window's `game_tick` every 16 ms.
8. `diskmgmt_tick()` (background disk writes), then render **iff**
   `desktop.dirty`, else repaint only the cursor if it moved.

Lite mode's loop (`lite_kmain`) is the same idea shrunk: `net_poll`
every 10 ms + keyboard → `execute_command`.

**Consequence for your code:** anything you add is either *drawn*
(window draw functions), *event-fed* (keyboard/mouse funcs),
*ticked* (`game_tick`, or a new periodic call you add here), or
*interrupt-fed* (IRQ handlers in `src/arch/interrupts.c`). There are
no threads to spawn; `create_task()` only registers a task-list
entry (shown by `ps`/Task Manager) — it does not schedule anything.

## Memory model

* Identity map: virtual == physical for 0–128 GiB.
  `virt_to_phys(p)` is effectively a cast; MMIO (HDA BAR, APIC,
  framebuffer) is accessed by direct pointer. See
  [06 · Drivers](06-drivers.md#memory-rules-for-dma-and-mmio).
* `kmalloc` = 16-byte-aligned bump allocator over the RAM pool after
  the kernel image; `kfree` is essentially a no-op in effect for
  most uses — **allocate like it's forever**: allocate buffers once
  (`static`/lazy-Init), not per frame. `ksize` exists.
* The kernel image is linked at 1 MiB (`linker.ld`); `_kernel_start`
  / `_kernel_end` bracket it (Disk Management uses them to write the
  kernel to disk).

## Graphics model

* All drawing lands in `lfbptr` (RAM). `flush_screen_to_hw()` /
  `flush_rows_to_hw(y0,y1)` copy to hardware; the desktop tracks a
  dirty rect (`desktop_invalidate_rect`) and flushes partially.
* Two text stacks: the 8×8/8×16 bitmap console (`draw_char`,
  `terminal_*` in `src/ui/terminal.c`) used by Lite mode, the
  desktop Terminal window and panic screens; and the TrueType
  renderer (`src/desktop/font.c`, `br_font_*`) used by the W98
  widgets when the theme sets `nice_font`.
* Windows **do not self-refresh**. A draw function runs when its
  window has `needs_redraw` or the desktop is dirty. Set
  `w->needs_redraw = true; desktop.dirty = true;` after state
  changes, or your window will look frozen. Details in
  [04](04-desktop-and-windows.md).

## Filesystem model

RAM-only tree of `fs_node` (max 128 nodes, 8 children/dir, 2 KiB
file content). Built by `fs_initialize()`; nothing persists.
Shell lookup falls back to `/System/Bin` and will `execute_elf()` a
matching file. Details in [07](07-filesystem.md) and
[10](10-elf-programs.md).

## File map

| Area | Files | Owns |
|---|---|---|
| Boot | `boot.s`, `linker.ld` | Multiboot header, long-mode entry, GDT/ISR stubs, link layout |
| `src/arch` | `early.c io.c interrupts.c cpu.c mtrr.c` | descriptor tables, IRQ/ISR dispatch, serial, CPUID, framebuffer write-combining |
| `src/lib` | `lib.c globals.c pmm.c elf.c` | string/mem helpers, **all global state**, allocator, ELF loader |
| `src/drivers` | `keyboard mouse pci rtc ata` + `audio/{audio,mixer,ac97,hda,pcspkr,wav}` | hardware |
| `src/net` | `net.c crypto.c tls.c` (`nics.c` = unwired virtio WIP) | NIC drivers (in `net.c`), stack, TLS |
| `src/fs` | `fs.c` | node pool + default tree |
| `src/ui` | `terminal.c ui.c mouse.c fastfetch.c` | console terminal, panes, FAQ/settings overlays, console system-info |
| `src/shell` | `main.c lite.c commands.c` | `kmain`, Lite console, all shell commands |
| `src/desktop` | `desktop windowmanager appwindows startmenu icons theme win98_widgets bootscreen diskmgmt png gif jpeg webp font` | the whole GUI |
| `include` | `kernel.h desktop.h …` + `*_data.h` icon/font pixel tables | shared declarations & assets |

## Where new code goes (rule of thumb)

* Talks to hardware → `src/drivers/` (+ Init call in `kmain`).
* Draws in a window → `src/desktop/appwindows.c` or a new file in
  `src/desktop/` (auto-compiled; declare in `include/desktop.h`).
* Runs from `$` → `src/shell/commands.c`.
* Shared state → `src/lib/globals.c` + `extern` in `kernel.h`.
* New source *directories* need depth ≤ `src/<dir>/*.c` or
  `src/<dir>/<sub>/*.c` to be auto-discovered by the Makefile
  (see [11](11-building-and-releasing.md#how-sources-are-found)).
