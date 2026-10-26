# Credits

**The kernel in this tree was originally created by mayshecry**
(SharkOS: <https://github.com/mayshecry/shark-os>).

This repository (BYOS — Build Your Own SharkOS) is a stripped-down base derived from SharkOS: the kernel,
all hardware drivers, and the desktop/window manager are kept, while the
bundled applications have been removed and all naming/branding has been
made configurable (see `config.mk` / `README.md`).

Please keep this credit intact. It is also shown inside the running system
— in the **About** window, **System Info**, the `fetch` / `sysinfo` shell
commands, and `System/os-release` in the boot filesystem
(`KERNEL_AUTHOR` in `config.mk` controls the string; don't remove it).

Other components:

* **Limine** bootloader binaries (`limine/`) — BSD-2-Clause, by the Limine
  project.
* Embedded font and icon pixel data — as provided in the upstream tree.
* Everything else: GPL-3.0, see `LICENSE` (unchanged from upstream).
