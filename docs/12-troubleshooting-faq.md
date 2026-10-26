# 12 · Troubleshooting & FAQ

Everything here was hit at least once while creating BYOS from
SharkOS. Start with the symptom you have.

## Build problems

**`make verify` fails on the old-OS-name check immediately.**
The check greps for `sha[r]k` (bracket trick so the Makefile
doesn't match its own pattern). If it still fires, the printed
lines are real hits — you pasted a branded string into code.
Route it through `OS_NAME` etc. from `<os_config.h>`. Mentions in
`README.md`/`docs/`/`CREDITS.md` are *intended* (attribution) and
are not checked.

**My rename doesn't show up** (binary still says the old name).
Almost always the generated header is being shadowed: `kernel.h`
must use `#include <os_config.h>` — with quotes, the compiler
prefers `include/os_config.h` (same dir as `kernel.h`) over
`build/generated/os_config.h`. Confirm with
`make config`, then `strings build/<lower>.bin | grep <name>`.
Also delete stale `build/<oldname>.bin` files before accusing the
build — `make` doesn't clean renamed outputs.

**Weird make errors / targets named like `build/myos` without
`.ISO`.** A `config.mk` value contains a space where a file name
is built (classic: `OS_NAME_LOWER` with a space or unsanitised
trailing content). The Makefile strips values, but embedded spaces
in `OS_NAME_LOWER` remain illegal — see
[02 · naming rules](02-making-your-distro.md#naming-rules-that-actually-bite).
The same applies to a variable *name* with a space in
(`ISO volume:=`), which make rejects with "empty variable name".

**`implicit declaration of function …` treated as error.** Modern
GCC is strict in freestanding code. Declare every cross-file
function in a header (`kernel.h` / `desktop.h` / your own in
`include/`). This bit BYOS itself: `font.c`'s `br_streq` had been
silently provided by a removed header.

**Link error: undefined reference to my new function.**
Your `.c` is deeper than `src/<dir>/<sub>/*.c` (not globbed), or
named `.C`/`.cc`, or the function is `static` in another file.
Check `build/obj/` for its `.o`.

**Everything rebuilds every time.** You probably edited
`build/generated/os_config.h` (don't — edit `config.mk`), or a
build step touches a header. The config rule only replaces the
file when contents change; if values keep changing (e.g. a
timestamp snuck into `config.mk`), every object is stale by design.

**`limine: Permission denied` / xorriso missing.** The ISO recipe
chmods `limine/limine` itself; if it still fails, `chmod +x
limine/limine` manually. `make kernel` works without xorriso;
`make` (ISO) does not.

## Boot problems

**Black screen in QEMU, no boot menu.** Wrong boot order/device:
use `-cdrom … -boot order=d` exactly as in `make run`. On real
UEFI, disable Secure Boot (Limine's loader here is unsigned).

**Limine menu shows the wrong name / old entries.** You're booting
a stale ISO (see "rename doesn't show up"), or you edited
`build/limine.conf` instead of `limine.conf.in`. Regenerate:
`make clean && make`.

**Boot screen hangs / takes ~30 s under emulation.** By design it
waits for `uptime_ticks >= 4600` (4.6 s of guest time); under TCG
(no KVM) that's longer in wall-clock. Not a hang unless serial
(see below) stops mid-driver-Init.

**Red banner: "…CPU EXCEPTION, SYSTEM HALTED".** The `isr_handler`
painted vector/registers. Usual suspects: new driver touching a
bad BAR/MMIO address, NULL `kmalloc` result used without a check,
stack overflow from huge locals (256 KiB stack total — a
`char buf[65536]` in a draw function *will* find you), or FS
content overflow past 2048 bytes corrupting the next node.
Bisect by commenting your Init calls in `kmain`.

**Triple fault / QEMU resets instantly.** Before the exception
handler is alive it's usually stack/paging: don't touch `boot.s`
early code casually, and keep ISRs in `boot.s` – `struct registers`
layout in `kernel.h` in lock-step.

**No network.** QEMU: add `-netdev user,id=net0 -device
e1000,netdev=net0` (or rtl8139/pcnet). In-OS: Network window /
`ifconfig` — driver `none` means no supported NIC was found;
`net_driver_name` + serial log will say which probe failed.
`ENABLE_NETWORK=0` in `config.mk`? DHCP slow on some QEMU user-net
setups — watch the Lite console for `DHCP: bound …`.

**No sound.** `-audiodev` + an HDA/AC97 device must exist; serial
log prints `[audio] … backend=HDA/AC97` or the pcspkr fallback.
In QEMU GUI builds without an audio backend on the host, use
`-audiodev none,id=snd0` to boot silently instead of failing.

**Mouse doesn't move / keyboard dead in Lite.** PS/2 only. In QEMU
that's the default; on hardware, USB-only peripherals won't work
(yet — driver contributions welcome, [06](06-drivers.md)).

## Desktop problems

**My window never updates.** You changed state but didn't set
`w->needs_redraw = true; desktop.dirty = true;` — see
[repaint rules](04-desktop-and-windows.md#repaint-rules-the-1-bug-source).

**My window draws, then smears when dragged.** You're drawing in
absolute coordinates cached at open time. Always compute from
`w->rect.client_x/y` in the draw function.

**Icon is the generic "i".** No case for your type in
`desktop_icon_pixels_for_type()` for the active theme — see
[08](08-themes-icons-wallpapers.md#adding-an-icon).

**Start menu is missing my entry / menu looks truncated.** Menu is
capped (`STARTMENU_MAX` 32, ≤12 visible rows + scroll). Entries
are rebuilt every `start_menu_open()` — if yours is missing, the
append didn't run (check you edited `startmenu.c`'s list, not just
`desktop_init` icons).

**Fetch art looks sheared.** The console fetch renderer prints `.`
as 1 space and any letter as `##`; artwork must be a single
contiguous run per row (no interior dots). See the comment above
`fetch_art` and [05](05-shell-commands.md).

## Debugging toolkit

**Serial log (your best friend).** Kernel/drivers print via
`serial_puts()` to COM1 from very early boot:

```bash
make run-serial
# or capture: qemu … -serial file:serial.log -display none
```

Add your own `serial_puts("[mything] …\n")` liberally while
developing; remove or keep — upstream style keeps a few.

**Headless screenshot.** Boot with a monitor socket and screendump:

```bash
qemu-system-x86_64 … -display none \
  -monitor tcp:127.0.0.1:4444,server,nowait -serial file:serial.log
# then (python/netcat): send  screendump /tmp/shot.ppm
python3 -c "from PIL import Image; Image.open('/tmp/shot.ppm').save('/tmp/shot.png')"
```

`sendkey <key>` over the same monitor types into the guest — that's
how the screenshots in this repo (desktop + Lite `fetch`) were
produced, and it doubles as a poor-man's integration test. Note
the boot-menu Down/Enter timing under TCG is finicky; for scripted
Lite tests we temporarily set `default_entry: 2` in a *copy* of the
ISO tree rather than fighting key timing.

**In-system:** `dmesg`/`sysinfo` (fake-but-plausible stock text —
it reflects `config.mk`, not live probes), `ps`, Task Manager's
Performance tab (live CPU history/FPS), Network window, and the
red exception banner itself (vector + register dump).

## FAQ

**Is this legal / can I really ship this as my distro?**
Yes — SharkOS is GPL-3.0. Ship source + license + keep the
mayshecry kernel credit. Details in
[02](02-making-your-distro.md#license--credit-duties-the-boring-but-important-bit).

**Why is there no SharkOS name anywhere in the running OS, then?**
That was the BYOS requirement: a blank canvas. Attribution lives
in the credit line (author, not product name) and in repo docs —
this FAQ included. Upstream: <https://github.com/mayshecry/shark-os>.

**Can I get the games/browser back?** They're in upstream SharkOS.
Porting one back is a clean exercise in
[04](04-desktop-and-windows.md): add the type, wire Init/tick/draw,
menu + icon. Mind their own licenses/assets.

**64-bit? The old FAQ said 32-bit.** Upstream moved to long mode;
some upstream strings lied. BYOS corrected them (`x86_64`). The
Multiboot1 *entry* is 32-bit; everything after `long_mode_entry`
is 64-bit.

**Where do I add a startup program?** There's no init.d. In
`kmain` after `desktop_init()`, open your window with
`desktop_icon_launch_offset(TYPE, "Title")`; for Lite-only,
special-case before the prompt loop in `lite_kmain`.
