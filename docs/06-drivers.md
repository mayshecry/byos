# 06 · Drivers — adding hardware support

All drivers live in `src/drivers/` (audio backends in
`src/drivers/audio/`), run in Ring 0, and are initialised from
`kmain()` in `src/shell/main.c`. There is no driver registry or
module loader — a driver is just `*_init()` + (usually) a poll or
IRQ hook. This guide shows the three shapes every BYOS driver takes.

## The toolbox (`include/kernel.h`)

```c
inb/inw/inl(port)  outb/outw/outl(port, val)      /* port I/O, static inline */
uint32_t pci_config_read(bus, slot, func, offset);
void     pci_config_write(bus, slot, func, offset, value);
void     pci_list_devices(void);                   /* debug dump to terminal */
void*    kmalloc(size_t);                          /* 16-byte aligned bump alloc */
uintptr_t virt_to_phys(void*);                     /* identity map: a cast */
void delay_ms(uint32_t ms);
serial_puts / serial_puthex32 / serial_putdec      /* COM1 logging (do this!) */
```

Plus audio.h's helpers: `pci_find_audio_device()`, `pci_read_bar()`,
`pic_unmask_irq()/pic_mask_irq()` — usable from any PCI driver.

## Driver shape 1: polled port device (simplest)

Model: RTC (`src/drivers/rtc.c`). Init once, read registers on
demand.

```c
/* src/drivers/mysensor.c */
#include "kernel.h"

#define SENSOR_PORT 0x2F8            /* example */
static bool sensor_present = false;

void mysensor_init(void) {
    outb(SENSOR_PORT + 1, 0x00);     /* quiesce */
    sensor_present = (inb(SENSOR_PORT + 2) != 0xFF);
    if (sensor_present) serial_puts("[mysensor] ready\n");
}

int mysensor_read(void) {
    if (!sensor_present) return -1;
    return inb(SENSOR_PORT);
}
```

Declare both in `kernel.h` (or your own header in `include/`), then
call `mysensor_init();` in `kmain` near the other driver inits
(after `init_descriptor_tables()`/PIC setup, alongside
`ata_init`/`audio_init`). If it must be polled regularly, add a call
in the main loop's 10 ms block next to `audio_tick()/net_poll()`,
and in `lite_kmain`'s loop if Lite needs it too.

## Driver shape 2: IRQ device

Model: keyboard/mouse (`src/drivers/keyboard.c`, `mouse.c`).

Interrupt plumbing facts:

* PIC is remapped: IRQ *n* arrives as `int_no == 32 + n`
  (keyboard IRQ1 → 33, mouse IRQ12 → 44, timer IRQ0 → 32).
* Dispatch is a fixed if-chain in `irq_handler()` in
  `src/arch/interrupts.c`. IRQ5–15 already forward to
  `audio_irq_handler(irq)`; add your own branch there:

```c
    if (r->int_no == 32 + 5) {          /* IRQ5 */
        mysensor_irq();
    }
```

* Unmask your IRQ line at Init. `kmain` does this with raw mask
  writes (ports `0x21`=PIC1, `0xA1`=PIC2); prefer the helper from
  `audio.h`: `pic_unmask_irq(5);` (declared there, works generally).
* Handlers must be **short**: read/clear the device status, stuff
  bytes into a ring buffer, return. `keyboard_handler()` is the
  template — it only enqueues; `keyboard_getchar()` dequeues in
  task context. EOI is sent by `irq_handler` itself — don't send
  your own.
* ISR stubs for IRQs 0–15 already exist in `boot.s`; you never need
  new assembly unless adding a brand-new interrupt vector.

## Driver shape 3: PCI device (the common big one)

Model: `src/drivers/audio/ac97.c` + the NICs inside `src/net/net.c`.

```c
static bool mydev_probe(uint8_t bus, uint8_t slot, uint8_t func) {
    uint32_t id = pci_config_read(bus, slot, func, 0x00);
    uint16_t vendor = id & 0xFFFF, device = (id >> 16) & 0xFFFF;
    if (vendor != 0x1234 || device != 0x5678) return false;

    uint32_t bar0 = pci_read_bar(bus, slot, func, 0);
    bool is_io = bar0 & 1;
    uintptr_t base = is_io ? (bar0 & ~0x3u) : (bar0 & ~0xFu);

    /* enable bus mastering + MEM/IO space in the command register */
    uint32_t cmd = pci_config_read(bus, slot, func, 0x04);
    pci_config_write(bus, slot, func, 0x04, cmd | 0x7);

    uint32_t irqline = pci_config_read(bus, slot, func, 0x3C) & 0xFF;
    serial_puts("[mydev] base 0x"); serial_puthex32((uint32_t)base);
    serial_puts(" irq "); serial_putdec(irqline); serial_puts("\n");
    (void)irqline;
    return true;
}

void mydev_init(void) {
    for (int bus = 0; bus < 256; bus++)
        for (int slot = 0; slot < 32; slot++)
            if (mydev_probe(bus, slot, 0)) return;   /* first match wins */
}
```

Real drivers also probe function ≠ 0 for multifunction devices
(check header type bit 7 at offset 0x0E — `pci.c`/audio show how).

### Memory rules for DMA and MMIO

* Identity map ⇒ `virt_to_phys(ptr) == (uintptr_t)ptr`. Give the
  device the pointer value directly (that's what AC'97's BDL and
  e1000's descriptor rings do).
* `kmalloc` is 16-byte aligned; for stricter alignment (page,
  64 B descriptor rings) over-allocate and round up — copy the
  pattern in `src/net/nics.c` (`virtio_queue_alloc`) or `net.c`'s
  e1000 ring setup.
* Buffers are forever: allocate rings/BDLs once at Init. `kfree`
  won't make bump-allocator space reusable in any useful way.
* MMIO: cast BAR to `volatile uint32_t*` and read/write directly
  (HDA in `hda.c` is the reference). For the framebuffer only there
  is `framebuffer_enable_write_combining()` (MTRR) — don't call it
  for device MMIO.

## Adding an audio backend

`include/audio.h` defines the contract:

```c
typedef struct {
    const char* name;
    bool (*init)(void);
    void (*shutdown)(void);
    bool (*submit)(const int16_t* frames, size_t frame_count);
    void (*set_volume)(uint32_t vol);
    bool (*is_ready)(void);
    void (*tick)(void);
} audio_backend_t;
```

Implement the six functions and a `*_probe(bus,slot,func)` like
`ac97_probe/hda_probe`, then hook selection in
`src/drivers/audio/audio.c` (`audio_init` scans PCI via
`pci_find_audio_device`, tries backends in order, falls back to
PC-speaker). The mixer above you is fixed: 48 kHz s16 stereo,
`AUDIO_BUFFER_FRAMES` (480) per 10 ms tick — your `submit` just has
to push frames to DMA. User-facing API is in
[09 · Network & audio](09-network-and-audio.md#audio-includeaudioh).

## Adding a NIC

All three NICs (RTL8139, AMD PCnet, Intel e1000) live **inside**
`src/net/net.c` as probe/Init/tx/rx sections feeding two functions:
the stack calls your TX to put an Ethernet frame on the wire, and
your RX path hands frames up (`net_set_rx_callback` is the external
tap; internally follow how `e1000`'s poll loop delivers frames).
To add a NIC: add its PCI IDs to the scan in `net_init`, implement
`<nic>_init/<nic>_send/<nic>_poll`-style sections mirroring PCnet
(simplest of the three), set `net_mac`, `net_driver_name` and
`net_has_link`. `src/net/nics.c` is an unfinished virtio-net in
that style — finishing it is a great first driver project; it's
excluded from the build (see Makefile note) until wired this way.
Stack-facing API: [09](09-network-and-audio.md#networking-includeneth).

## ATA as a model storage driver

`include/ata.h` is the tidy end of the spectrum — copy its shape
for new block devices:

```c
void ata_init(void);
int  ata_drive_count(void);
const ata_drive_t* ata_drive_get(int idx);
bool ata_read_sectors (int drive, uint32_t lba, uint8_t count, uint8_t* dst);
bool ata_write_sectors(int drive, uint32_t lba, uint8_t count, const uint8_t* src);
```

Disk Management (`src/desktop/diskmgmt.c`) shows how a consumer
uses it, including chunked async writes via `diskmgmt_tick()` from
the main loop — copy that pattern instead of blocking the UI thread
on a slow device.

## Debugging drivers

* `serial_puts()` early and often; watch it with `make run-serial`
  (or `-serial file:log.txt`). Audio/Net drivers log `[audio] …`,
  `[hda] …` style — match it.
* `lspci`-style dumps: `pci_list_devices()` from a shell command or
  temporary boot code.
* Triple fault = your Init likely touched a bad BAR/pointer; the
  CPU exception screen prints vector + registers on the red banner
  (`isr_handler`). Bisect by commenting the Init call in `kmain`.
* QEMU device not appearing? You forgot the `-device` flag 90% of
  the time. The other 10%: you masked its IRQ.
