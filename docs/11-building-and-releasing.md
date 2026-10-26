# 11 · Building & releasing

The BYOS Makefile replaces SharkOS's 300-line hand-written one.
This doc explains how it finds sources, generates files, and packs
the ISO — plus the release checklist for your distro.

## Targets

| Target | Output |
|---|---|
| `make` / `make ISO` | `build/<lower>.ISO` (default) |
| `make kernel` | `build/<lower>.bin` only — fastest full compile+link check |
| `make run` / `run-serial` / `run-uefi` | QEMU (BIOS GUI / headless serial / OVMF) |
| `make config` | print active identity + switches |
| `make verify` | fail if: old OS name appears in code/build files, kernel credit missing, or removed-app identifiers creep back |
| `make clean` | delete `build/` entirely |
| `make help` | reminder list |

Variables from `config.mk` can be overridden per-invocation:
`make OS_VERSION=1.1 ISO`. Command-line values win over `?=` in
`config.mk`; if you switch to `:=` there, they won't.

## How sources are found

```make
SRCS := $(sort $(wildcard src/*/*.c src/*/*/*.c))
SRCS := $(filter-out src/net/nics.c,$(SRCS))  # unfinished virtio-net, kept for reference
```

* Drop a `.c` file at `src/<dir>/x.c` or `src/<dir>/<sub>/x.c`
  and it builds. **Deeper nesting is not globbed** — flatten or
  extend the wildcard.
* Headers are tracked automatically via `-MMD -MP` dep files in
  `build/obj/**/*.d`; touch a header, dependents rebuild.
* `boot.s` is assembled by its own rule; `linker.ld` + all objects
  link with `-lgcc`, `-gc-sections`, `--strip-all`. Unreferenced
  `static` data (e.g. spare icon arrays) is dropped at link.
* New *assembly* files: there's no pattern rule for them — add one
  next to the `boot.o` rule if you need more than inline asm.

Flags are upstream's (`-m64 -ffreestanding -Os -mno-red-zone
-mgeneral-regs-only -mcmodel=kernel …`). Two consequences: no
SSE/FPU codegen (do fixed-point math like the rest of the tree),
and no stack protector — your buffer overflows are your own.

## Generated files (never hand-edit)

| File | From | How |
|---|---|---|
| `build/generated/os_config.h` | `config.mk` values | printf block; rewritten only if contents change (cmp trick + phony `__config` prereq), so idle rebuilds stay incremental |
| `build/limine.conf` | `limine.conf.in` | `sed` on `@OS_NAME@` etc. |
| `build/grub.cfg` | `grub.cfg.in` | same |

`kernel.h` includes **`<os_config.h>`** (angle brackets!) and
`-Ibuild/generated` precedes `-Iinclude`, so the generated header
beats the fallback defaults in `include/os_config.h`. If a rename
"doesn't take", see
[12](12-troubleshooting-faq.md#build-problems).

## ISO anatomy

```
isodir/
  boot/<lower>.bin                 kernel
  boot/limine/{limine.conf,limine.cfg,limine-bios.sys,
               limine-bios-cd.bin,limine-uefi-cd.bin}
  limine.conf  limine.cfg  boot/limine.cfg    (Limine search paths)
  boot/grub/grub.cfg               for GRUB users
  EFI/BOOT/BOOTX64.EFI BOOTIA32.EFI
```

`xorriso -as mkisofs` writes El Torito (BIOS) + EFI-boot-partition
(UEFI) images with volume label `<LOWER upper-cased>`, then
`limine/limine bios-install` embeds stage 2 into the ISO's GPT/
MBR gap so the same file `dd`s to a USB stick. The recipe
`chmod +x limine/limine`s first because fresh checkouts sometimes
lose the bit.

## Cross-compiling

On x86_64 Linux the host gcc is used. Elsewhere:

```bash
make PREFIX=x86_64-elf-          # CC/AS become x86_64-elf-gcc/as
make CC=/opt/llvm/bin/clang      # explicit tools also work
```

(`CC`/`AS` use the `$(origin …)` trick so make's builtin `cc`
default doesn't shadow `PREFIX`.)

## Release checklist

1. Bump `OS_VERSION` (+ `OS_CODENAME` if it's a feature release)
   in `config.mk`; update `CHANGELOG.md`.
2. `make clean && make` — zero errors. Skim warnings you added.
3. `make verify` — branding/credit gates pass.
4. Boot test **both** entries (`make run`, choose Lite too):
   desktop opens, Terminal `fetch` shows the right name/version,
   `cat /System/os-release` matches, network gets DHCP, Settings
   theme switch works, no red exception banner.
5. If you can: `make run-uefi` + one real-hardware boot from USB.
6. Artifacts: `build/<lower>.ISO` +
   `sha256sum build/<lower>.ISO > <lower>.ISO.sha256`.
7. Publish source alongside the ISO (GPL-3.0), keep `LICENSE` +
   `CREDITS.md` + the SharkOS attribution in README ("based on
   SharkOS — https://github.com/mayshecry/shark-os — kernel by
   mayshecry"). Tag `v<OS_VERSION>`.
8. Screenshots: QEMU monitor `screendump out.ppm` →
   convert to PNG (we used Pillow) — recipe in
   [12](12-troubleshooting-faq.md#debugging-toolkit).

## Reproducibility notes

Same tree + same compiler ⇒ byte-identical `<lower>.bin` (no
timestamps are embedded by the build; the ISO does get xorriso
timestamps from file mtimes). If you need bit-identical ISOs, set
`SOURCE_DATE_EPOCH` — xorriso honours it via
`--modification-date`; add it to the recipe in your fork.
