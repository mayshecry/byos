# 02 · Making your distro

BYOS exists so that "my own operating system, based on SharkOS
(<https://github.com/mayshecry/shark-os>)" is an afternoon's work, not
a month. This guide covers the full rebrand: names, boot menus,
versioning, forking, and your license duties.

## The one-file identity: `config.mk`

Everything identity-shaped flows from `config.mk` into
`build/generated/os_config.h` (C macros), the generated boot menus,
and the output file names. **Never edit the generated files** — make
will overwrite them; edit `config.mk` (or pass overrides:
`make OS_NAME=ZynxOS OS_NAME_LOWER=zynxos`).

### Every variable, explained

| Variable | Default | Shows up in |
|---|---|---|
| `OS_NAME` | `MyOS` | Boot menu, boot screen banner, About, System Info, start-menu sidebar, `uname`, panic banners, window titles. Wrap in nothing, spaces OK (`Zynx OS`). |
| `OS_NAME_LOWER` | `myos` | File names: `<lower>.bin`, `<lower>.ISO`, ISO volume label (upper-cased), `os-release ID=`, `TERM=` in `env`. Rules below. |
| `OS_VERSION` | `1.0` | Boot banner, About, `fetch`/`sysinfo`/`uname -a`, `System/version`, `os-release VERSION=`. Free-form text. |
| `OS_CODENAME` | `Base` | Shown as `MyOS 1.0 (Base)` in banners, `System/version`, `os-release PRETTY_NAME=`. |
| `OS_VENDOR` | `YourName` | About window: "`<OS>` by `<vendor>`". Put your handle/team here. |
| `OS_HOSTNAME` | `myos-pc` | Shell prompt (`user@myos-pc`), `hostname` command, `fetch` header, `System/hostname`, `env HOSTNAME=`. No spaces. |
| `OS_DEFAULT_USER` | `user` | `current_user` at boot: prompt, `whoami`, the home folder name (the `/User` node is renamed to this in `kmain`). No spaces, ≤ 31 chars. |
| `OS_SHELL_NAME` | `shell` | `fetch`/`System Info` "Shell:" line, `env SHELL=`, `System/version`. |
| `KERNEL_AUTHOR` | `mayshecry` | The kernel credit (see [duties](#license--credit-duties-the-boring-but-important-bit)). Feeds `KERNEL_CREDIT` = `Kernel created by mayshecry`. |
| `BOOT_TIMEOUT` | `5` | Seconds in `limine.conf`/`grub.cfg` before the default entry boots. |
| `BOOT_RESOLUTION` | `1024x768` | Limine menu resolution. Note: the *framebuffer* mode requested from the bootloader is hard-coded 1024×768×32 in `boot.s`; see [changing resolution](#changing-the-framebuffer-resolution). |
| `WALLPAPER_TOP` / `WALLPAPER_BOTTOM` | `0xFF0B5FA5` / `0xFF083B66` | ARGB colours of the "Classic" gradient wallpaper preset + desktop fallback colours (`DESKTOP_BG_TOP/BOT`). |
| `ENABLE_ATA` / `ENABLE_AUDIO` / `ENABLE_NETWORK` | `1` | Boot-time Init switches (`ata_init`, `audio_init`, `net_init`+`net_stack_init` in `kmain`, network also in Lite). Drivers still *link*; they just aren't initialised. Turning network off keeps the Network window functional (shows "no adapter" states). |
| `PREFIX` | *(empty)* | Toolchain prefix, e.g. `x86_64-elf-`. |
| `LIMINE_DIR` | `limine` | Where Limine binaries live if you move/replace them. |
| `QEMU`, `QEMU_MEMORY`, `QEMU_CPUS` | `qemu-system-x86_64`, `512`, `2` | `make run*` machine. |

The Makefile `$(strip)`s every value, so the aligned comments in
`config.mk` are safe to keep. Still: don't put `"` or `\` inside
values — they land inside C string literals.

### Naming rules that actually bite

* **`OS_NAME_LOWER`** becomes file names and an ISO volume label:
  lowercase letters/digits/`-` only, no spaces, keep it ≤ ~20 chars
  (volume labels get truncated at 32 after upper-casing).
* **`OS_NAME`** is drawn with centred text whose width is measured at
  runtime (`w98_text_width`), so long names are fine; the start-menu
  sidebar prints it vertically, so > ~16 chars may crop there.
* Window titles max out at `WINDOW_TITLE_MAX` (32) — a 30-char
  `OS_NAME` + " FAQ" can truncate. Keep the display name shortish.
* `OS_DEFAULT_USER` and fs node names max out at 31 chars.

### What regenerates, and when

`build/generated/os_config.h` is compared-and-replaced on **every**
`make` run: change `config.mk` (or pass a variable) and the header is
rewritten, which recompiles everything that includes `kernel.h`
(i.e. everything). Unchanged values don't touch the file, so normal
incremental builds stay fast. The fallback `include/os_config.h`
exists only so the tree compiles if the generated file is absent —
the generated one wins because `kernel.h` uses `<os_config.h>` and
`-Ibuild/generated` precedes `-Iinclude`. **Don't "fix" that to
quotes** or the fallback will silently shadow your config (see
[troubleshooting](12-troubleshooting-faq.md#build-problems)).

Verify a rename actually landed:

```bash
make config                       # what make thinks the values are
strings build/zynxos.bin | grep -c ZynxOS     # should be ~40
strings build/zynxos.bin | grep -i mayshecry  # credit still there
make verify                       # no old branding anywhere
```

## Boot menus are templates

`limine.conf.in` and `grub.cfg.in` use `@OS_NAME@`,
`@OS_NAME_LOWER@`, `@BOOT_TIMEOUT@`, `@BOOT_RESOLUTION@`
placeholders, substituted by `sed` in the Makefile. To add a boot
entry (say, a "safe" entry using the `lite` flag, or one passing
your own `cmdline:` token that you parse like `lite`/`kawaii` in
`kmain`), copy a block in *both* templates and rebuild. The kernel
command line is read from Multiboot info in `src/shell/main.c`;
 Lite is selected by the substring `lite`, the Kawaii theme by
`kawaii` — add your own flag the same way.

Limine notes: the ISO ships the generated config at several paths
(Limine searches `/boot/limine/limine.conf`, `/limine.conf`, …) —
the Makefile copies it to all of them; keep that if you restructure.

## Changing the framebuffer resolution

The Multiboot header in `boot.s` requests 1024×768×32. To change it,
edit the three `.long` graphics fields there (width, height, depth).
Everything else (`screen_width`/`screen_height`/`screen_pitch`) is
read from Multiboot info at runtime. `BOOT_RESOLUTION` only sizes
the Limine *menu*.

## Versioning your distro

Suggested, boring, works:

* `OS_VERSION` = `MAJOR.MINOR` (bump MINOR per release, MAJOR when
  you break something on purpose). It's a free string — `2026.1`
  works too.
* New `OS_CODENAME` per MAJOR (or per release, your call).
* Tag git commits `v<OS_VERSION>` and keep a `CHANGELOG.md`.
* Keep `KERNEL_AUTHOR` as-is in every release (below).

## Forking / publishing checklist

1. `git init` (or fork the SharkOS repo and replace the tree) —
   keep `LICENSE`, `CREDITS.md`, `limine/` intact.
2. Set your identity in `config.mk`; update this README's title and
   screenshots, but keep the "based on SharkOS, kernel by mayshecry"
   attribution (below).
3. `make clean && make && make verify`; boot **both** entries in
   QEMU (and on hardware if you can).
4. Publish: source repo + `<lower>.ISO` + a checksum
   (`sha256sum build/*.ISO`). Full checklist in
   [11 · Building & releasing](11-building-and-releasing.md#release-checklist).

## License & credit duties (the boring but important bit)

* SharkOS and therefore BYOS are **GPL-3.0**. In plain terms (this
  is a summary, not legal advice): if you distribute your ISO, you
  must also provide the corresponding source under GPL-3.0, keep the
  `LICENSE` file and copyright/credit notices, and license your
  modifications the same way. Private experiments don't trigger this.
* The in-system kernel credit — `KERNEL_AUTHOR` = **mayshecry**,
  shown in About / System Info / `fetch` / `System/os-release` — is
  the one piece of attribution BYOS asks you to keep. It costs one
  line of screen space and it's how the original author gets thanked.
  `make verify` fails if it disappears from the sources.
* Limine binaries in `limine/` are BSD-2-Clause; keep their license
  if you redistribute that folder.
* You're free to name your distro anything — just don't imply it's
  endorsed by the SharkOS author. "Based on SharkOS
  (github.com/mayshecry/shark-os), kernel by mayshecry" in your
  README/About is the right shape.

## What's still upstream-flavoured on purpose

The Win98/Modern/Kawaii/WindowMaker **theme names**, the window
titles ("Task Manager", "Disk Management"), and the file-tree jokes
in `/System` (`sysconfig`, fake `dmesg`) are content, not branding —
rename or rewrite them as you like:
[themes](08-themes-icons-wallpapers.md) ·
[filesystem](07-filesystem.md). If you grep your built binary for
the old OS name it must come back empty; if it doesn't, you found a
spot `configs` don't cover yet — please route it through a macro
from `os_config.h` instead of hard-coding your distro's name, so the
next person can rename as easily as you did.
