# 01 · Getting started

BYOS (Build Your Own SharkOS) is a stripped, rebrandable base derived
from [SharkOS](https://github.com/mayshecry/shark-os) by mayshecry.
This guide gets you from a fresh checkout to a running system, in QEMU
and on real hardware.

## Prerequisites

| Tool | Why | Install (Debian/Ubuntu) |
|---|---|---|
| `gcc` (x86_64 host) | compiles the kernel (`-m64 -ffreestanding`) | `sudo apt install build-essential` |
| `as`, `ld` | assembler/linker (binutils, comes with build-essential) | — |
| `xorriso` | builds the bootable ISO | `sudo apt install xorriso` |
| `qemu-system-x86_64` | testing without hardware (optional) | `sudo apt install qemu-system-x86` |
| OVMF | UEFI testing only (optional) | `sudo apt install ovmf` |

No cross-compiler is required on an x86_64 Linux host — the build uses
the host `gcc` in freestanding mode, exactly like upstream SharkOS.
If you *have* an `x86_64-elf-` toolchain, use it with
`make PREFIX=x86_64-elf-` (see [11 · Building & releasing](11-building-and-releasing.md)).

The Limine bootloader binaries are vendored in `limine/` — nothing is
downloaded at build time.

## First build

```bash
make            # full build -> build/myos.ISO   (name from config.mk)
make kernel     # kernel only -> build/myos.bin (fast syntax/link check)
make config     # show what name/version/switches are active
make verify     # branding + credit sanity checks
```

A clean build compiles ~65 C files. You will see a handful of
pre-existing `-Wunused-*` warnings inherited from upstream — those are
normal. Errors are not.

Build output layout:

```
build/
  generated/os_config.h   # C macros generated from config.mk
  obj/…                   # .o + .d files, mirroring src/
  limine.conf, grub.cfg   # boot menus generated from the *.in templates
  myos.bin                # the kernel image (ELF, Multiboot1)
  myos.ISO                # hybrid BIOS+UEFI bootable ISO
  isodir/                 # ISO staging tree (safe to ignore/delete)
```

## Running in QEMU

```bash
make run          # window, Intel HDA audio, e1000 network, KVM
make run-uefi     # same, but UEFI via OVMF (OVMF=/path/to/OVMF_CODE.fd)
make run-serial   # no window; kernel serial log in your terminal
```

The QEMU machine is defined at the bottom of the `Makefile`
(`QEMU_FLAGS`); RAM/CPU count come from `config.mk`
(`QEMU_MEMORY`, `QEMU_CPUS`). Equivalent manual command:

```bash
qemu-system-x86_64 -m 512 -smp 2 -enable-kvm -cpu host \
  -cdrom build/myos.ISO -boot order=d \
  -vga std -display gtk,zoom-to-fit=on \
  -audiodev pa,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0 \
  -netdev user,id=net0 -device e1000,netdev=net0
```

Notes:

* No KVM (CI, containers, non-Linux host)? Drop `-enable-kvm -cpu host`;
  TCG emulation works fine, just slower — the boot screen takes a few
  extra seconds because it intentionally lingers (~4.6 s of ticks).
* `-netdev user` gives the guest 10.0.2.15 via built-in DHCP, gateway
  10.0.2.2, DNS 10.0.2.3. `ping 10.0.2.2`, `dns example.com` and
  `wget http://…` work out of the box. Other NIC models work too:
  `-device rtl8139`, `-device pcnet`, `-device e1000`.
* For AC'97 instead of HDA: `-device AC97,audiodev=snd0`.
* For an ATA disk (Disk Management window, "Install…"):
  add `-drive file=disk.img,format=raw,if=ide` after
  `qemu-img create -f raw disk.img 64M`.

## The two boot entries

Limine shows (names follow `config.mk`):

1. **MyOS** — full desktop.
2. **MyOS Lite** — text console only (`lite` on the kernel command
   line → `lite_kmain()` in `src/shell/lite.c`): same shell and
   filesystem, no window manager. Great for debugging shell commands
   and drivers, and it is what the second README screenshot shows.

Both boot from the *same* `myos.bin`.

## First-boot tour (5 minutes)

At the desktop:

* Double-click icons; right-click the desktop for a context menu
  (show/hide icons, refresh, settings…).
* **Start menu** lists every system window. Try **System Info** and
  **About** — they show your `config.mk` name/version and the kernel
  credit line.
* **Settings** switches the four themes (Windows 98, Modern, Kawaii,
  WindowMaker), wallpaper presets and solid colours — live.
* Open **Terminal** and try: `fetch`, `help`, `ls /`, `cd /System`,
  `cat os-release`, `ps`, `ifconfig`, `ping 10.0.2.2`,
  `audio` (mixer test tones), `fetch`, `uname -a`.
* **Network** window shows link/DHCP state; **Task Manager** shows
  the (cooperative) task list, CPU graph and open windows;
  **Disk Management** lists ATA drives.

In Lite mode all shell commands work the same; GUI-only ones
(`taskmanager`) fall back to text output. Keys: `?` opens the console
FAQ, `+`/`-` split/close terminal panes, Tab switches panes, `s` in
the console UI opens settings (theme/mouse toggles).

## Real hardware / USB stick

The ISO is a hybrid image with Limine installed for both BIOS
(`limine bios-install` runs during `make`) and UEFI
(`EFI/BOOT/BOOTX64.EFI`):

```bash
sudo dd if=build/myos.ISO of=/dev/sdX bs=4M status=progress oflag=sync
```

(DD-mode in Rufus on Windows works too.) Hardware expectations,
inherited from SharkOS: PS/2 keyboard + mouse (most laptops emulate
PS/2 for built-in devices; USB HID is *not* supported), a VESA/VBE
framebuffer from the bootloader, AC'97 or Intel HDA audio, an
RTL8139/PCnet/e1000-family NIC for networking. The framebuffer mode
requested from the bootloader is 1024×768×32 (see `boot.s`).

Boots to a black screen? See
[12 · Troubleshooting](12-troubleshooting-faq.md#boot-problems).

## Next steps

* Rename it properly → [02 · Making your distro](02-making-your-distro.md)
* Understand the code → [03 · Architecture](03-architecture.md)
* Add your first window → [04 · Desktop & windows](04-desktop-and-windows.md)
