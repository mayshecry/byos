# =============================================================================
#  config.mk  --  OS identity & build configuration
# =============================================================================
#  This is the ONLY file you need to touch to rename / rebrand the OS.
#  Run `make` afterwards: the values below are baked into the kernel
#  (via a generated os_config.h), the bootloader menus (limine.conf /
#  grub.cfg), the kernel/ISO file names and the ISO volume label.
#
#  Every variable can also be overridden on the command line, e.g.:
#      make OS_NAME=ZynxOS OS_NAME_LOWER=zynxos
# =============================================================================

# --- OS identity --------------------------------------------------------------
OS_NAME        ?= MyOS                # Display name, shown everywhere in the UI
OS_NAME_LOWER  ?= myos                # File-system-safe name: kernel + ISO file
                                      #   names (lowercase, no spaces)
OS_VERSION     ?= 1.0                 # Version string
OS_CODENAME    ?= Base                # Release codename
OS_VENDOR      ?= YourName            # You / your project (shown in About)
OS_HOSTNAME    ?= myos-pc             # Default hostname
OS_DEFAULT_USER?= user                # Default user name (prompt, home dir)
OS_SHELL_NAME  ?= shell               # Name the shell calls itself

# Kernel authorship credit. This kernel was originally created by mayshecry.
# Please keep this credit intact -- it is printed in the About window,
# the system-info tool and System/os-release.
KERNEL_AUTHOR  ?= mayshecry

# --- Boot / display -----------------------------------------------------------
BOOT_TIMEOUT   ?= 5                   # Bootloader menu timeout (seconds)
BOOT_RESOLUTION?= 1024x768            # Bootloader menu resolution
                                      # (framebuffer mode requested in boot.s)

# --- Desktop defaults ---------------------------------------------------------
WALLPAPER_TOP    ?= 0xFF0B5FA5         # Default wallpaper gradient (ARGB)
WALLPAPER_BOTTOM ?= 0xFF083B66

# --- Optional subsystems (1 = initialise at boot, 0 = skip) -------------------
# The drivers are always compiled in; these only control boot-time init.
ENABLE_ATA     ?= 1                   # ATA disk driver
ENABLE_AUDIO   ?= 1                   # AC'97 / Intel HDA / PC-speaker audio
ENABLE_NETWORK ?= 1                   # NIC drivers + TCP/IP stack + DHCP

# --- Toolchain ----------------------------------------------------------------
# Leave PREFIX empty to use the host gcc (x86_64 Linux). For a bare-metal
# cross-compiler use e.g.  make PREFIX=x86_64-elf-
PREFIX         ?=
LIMINE_DIR     ?= limine

# --- QEMU (make run) ----------------------------------------------------------
QEMU           ?= qemu-system-x86_64
QEMU_MEMORY    ?= 512                 # MB of RAM
QEMU_CPUS      ?= 2
