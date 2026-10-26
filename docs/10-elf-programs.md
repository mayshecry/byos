# 10 · ELF programs — running external binaries

BYOS inherits SharkOS's minimal ELF loader (`src/lib/elf.c`). It is
**not** a Unix process model: no process isolation, no dynamic
linking, no libc, and the "syscall" table has four entries. This
doc states the exact contract so you can decide if a given program
belongs here — or linked straight into the kernel like everything
else (usually the right answer; see
[04](04-desktop-and-windows.md) / [05](05-shell-commands.md)).

## How execution happens

```
shell: user types "myprog hello"
  └─ no builtin matched
       └─ search_path("myprog")        current dir, then /System/Bin
            └─ execute_elf(node->content, "hello")
                 1. check \x7fELF magic
                 2. for each PT_LOAD: memcpy file bytes -> p_vaddr,
                    zero p_memsz-p_filesz tail        (identity map!)
                 3. rsp := &stack_top, push arg pointer, call e_entry
```

Sharp edges, all load-bearing:

* The file content lives in an `fs_node`: **max 2048 bytes** unless
  you raise `MAX_FILE_CONTENT_SIZE`. There is no built-in path to
  load binaries from disk/network into the FS (you can add one:
  [07](07-filesystem.md)).
* **`rsi`-style arg passing it is not.** The entry is called after
  `push arg` on a fresh kernel stack — i.e. as if
  `void entry(const char* arg)` in the SysV sense *except* the arg
  arrives **on the stack**, not in `rdi`. Write your entry in asm
  or read the arg from the stack accordingly; simplest is to ignore
  the arg or fetch it with a tiny asm trampoline.
* Returning from the entry returns to… nothing sane
  (`rsp = &stack_top` destroyed the call frame chain; `execute_elf`
  itself is unreachable after the call). Treat the program as
  **terminal**: loop forever, or end via syscall 1 (prints
  "Process exited." and the machine still needs a reset — it does
  not return to the shell prompt). Plan test programs accordingly
  (you'll reboot a lot).
* e_type 2 (EXEC) loads at absolute `p_vaddr`; e_type 3 (DYn/PIE)
  loads at `data + p_vaddr` (i.e. relative to the file buffer in
  RAM — quirk!). Prefer static non-PIE EXEC linked at a free high
  address that doesn't collide with the kernel image
  (≥ 16 MiB is safely past it).
* ELF64 and ELF32 headers are both parsed, but code runs in 64-bit
  long mode either way — ship ELF64.

## int 0x80 interface (`syscall_handler`, interrupts.c)

| `rax` | Args | Effect |
|---|---|---|
| 1 | — | print "\nProcess exited.\n" (does not actually exit) |
| 3 | `rbx`=file name, `rcx`=buf | copy named FS file's content to `buf`; returns length in `rax`, or -1 |
| 4 | `rcx`=buf, `rdx`=len | write bytes to terminal |
| 24 | — | `yield()` (hlt until next IRQ) |

Every int 0x80 also bumps `syscall_count` on all tasks (Task
Manager eye candy). There is **no** read-keyboard, graphics, or
memory syscall — but you're in Ring 0: programs may call kernel
functions directly *if* linked against their addresses (fragile
across rebuilds — don't build a distro ABI on this without pinning
a symbol file; `System/System.map` in the stock FS is a nod to the
idea).

## Worked example (position-aware, ~60 bytes of code)

A "hello" that prints via syscall 4 and then idles:

```asm
; hello.s — as --64
.global _start
_start:
    lea msg(%rip), %rcx        /* buf  */
    mov $msg_len, %rdx         /* len  */
    mov $4, %rax               /* write */
    int $0x80
1:  mov $24, %rax              /* yield forever */
    int $0x80
    jmp 1b
msg: .ascii "hello from ELF\n"
.set msg_len, . - msg
```

```bash
as --64 hello.s -o hello.o
ld -Ttext=0x1000000 -o hello hello.o     # static EXEC at 16 MiB
```

It fits in 2 KiB easily. Getting it *in*: embed the bytes as a file
with `set_content` is awkward for binary (NULs + `strcpy`
semantics) — instead create the node in `fs_initialize()` and
`memcpy(node->content, blob, len); node->content_len = len;` with
the blob as a C array. Then typing its name runs it. For anything
bigger, first raise the FS limits ([07](07-filesystem.md)) or add a
disk loader.

## Honest recommendation

For distro features, **link code into the kernel** (windows +
commands + drivers). Use the ELF path for: tiny experiments,
demoware, testing the loader itself, or as the seed of your own
real loader (proper stack, `rdi` arg, return-to-shell, size
limits — all fixable in ~100 lines in `elf.c`; pull requests to
your own fork welcome).
