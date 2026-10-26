# 05 · Shell commands — adding your own

The shell lives in `src/shell/commands.c` (~2,000 lines, inherited
from SharkOS). The same `execute_command()` backs three front-ends:
the Lite text console, the full-screen console panes, and the
desktop Terminal window — add a command once, it works in all three
(with one caveat below).

## How dispatch works

```
execute_command(cmd)
  ├─ split: first word -> cmd_name[32], rest -> args (leading spaces trimmed)
  ├─ cmd_table[] lookup  (find_command)      <- PREFERRED for new commands
  ├─ long else-if chain (tree, grep, touch, env, inb, …)  <- legacy, still used
  └─ else: search_path(cmd_name) -> file? execute_elf(...) : "Unknown command"
```

`search_path()` checks the current directory then `/System/Bin`, so
**any file there becomes a runnable command name** (see
[10 · ELF programs](10-elf-programs.md)).

## Cookbook: table-driven command (recommended)

Add a handler + one table row. Example: `roll` — prints a pseudo-random
number up to N.

```c
static void cmd_roll(const char* args) {
    int sides = 6;
    if (args && *args) {
        sides = simple_atoi(args);          /* helper at top of commands.c */
        if (sides < 2) sides = 6;
    }
    uint32_t v = (uptime_ticks * 1103515245u + 12345u) >> 16;
    char buf[16];
    int_to_string((v % (uint32_t)sides) + 1, buf);
    terminal_writestring(buf);
    terminal_writestring("\n");
}
```

Register it (and an alias, why not) in `cmd_table[]`:

```c
    {"roll", cmd_roll},
    {"dice", cmd_roll},
```

Update `cmd_help()`'s category lines so `help` mentions it. Done —
`roll`, `roll 20`, `dice 100` now work everywhere.

## Output rules

* Use `terminal_writestring(const char*)` and `terminal_putchar(c)`.
  `\n` inside strings is how you end lines (note `execute_command`
  prints one leading newline before dispatch; most commands don't
  print a trailing blank line).
* Numbers: `int_to_string(uint32_t, buf)`, `hex_to_string(...)`.
  There is no printf; `net.c` has a private `net_snprintf` if you
  want a model for your own formatter.
* Colour: `terminal_set_color(vga_entry_color(FG, BG))` with the
  `VGA_COLOR_*` enum, **or** ANSI escapes in strings — the terminal
  understands `\x1b[<n>m` / `\033[0;36m`-style sequences (see
  `cmd_fetch`/`cmd_neofetch` for the supported flavour: SGR colour
  codes). `execute_command` restores the previous colour after
  table commands; in the else-if chain you're expected to restore
  it yourself (look at how `cmd_fetch` ends).
* Args are **one mutable string** (`char* args` in the chain,
  `const char*` in table handlers). Parse by scanning: patterns to
  copy are in `cmd_cat` (filename), the `grep` branch (two words),
  and `seq` (up to three ints). `simple_atoi()` (static, top of
  file) stops at the first non-digit.
* Filesystem access: `find_node(current_dir, name)`,
  `search_path(name)`, `create_node(name, FS_FILE|FS_DIRECTORY,
  parent)`, node fields `content`/`content_len` — full tour in
  [07](07-filesystem.md#runtime-file-api-for-your-windowscommands).
* Long loops **must** `yield()` periodically (`sti; hlt`) or you'll
  starve the timer-driven UI/network — copy the `if (k % 3 == 0)
  yield();` pattern from `print_tree`.

## The desktop Terminal caveat (capture + blocklist)

The desktop Terminal window (`app_window_draw_terminal` in
`appwindows.c`) runs commands under `terminal_capture_begin/end`,
which diverts `terminal_writestring` output into a buffer the window
then renders. Two consequences:

1. Anything that draws pixels directly, reads keys interactively,
   or flips console modes (full-screen editor, `htop`) can't work
   there. Such commands are listed in `terminal_cmd_blocked()` in
   `src/desktop/appwindows.c` (`edit`, `htop`) with a helpful
   redirect message. **If your command is interactive/full-screen,
   add it there.**
2. Output that relies on cursor positioning (pane tabs, `draw_rect`
   on the framebuffer) won't be captured — stick to
   `terminal_writestring` and you're portable across all three
   front-ends.

`terminal_in_desktop_window` / `desktop_terminal_cols` let a command
adapt width (see `cmd_fetch`'s ≥96-column side-by-side check).

## The else-if chain (legacy commands)

Most Unix-y utilities (`grep`, `stat`, `env`, `head`, `inb`…)
live in one giant `else if (strcmp(cmd_name, …))` chain inside
`execute_command()`. It works fine; add there only if you need the
mutable `args`/shared locals (`i`, buffers at function scope).
Watch out: a name present in **both** places always runs the table
version (the chain copy is dead — BYOS deleted one such duplicate
`neofetch`; don't create more).

## Commands that open windows

From a command you can launch desktop windows — guard on the mode:

```c
if (current_kernel_mode != KERNEL_MODE_DESKTOP) {
    terminal_writestring("Needs the desktop.\n");
    return;
}
desktop_icon_launch_offset(WINDOW_TYPE_COUNTER, "Counter");
```

`cmd_taskmanager` is the reference (focus-or-open + text fallback
in Lite).

## Ring-0 commands already there (handle with care)

`ring0`, `priv`, `inb`, `outb` poke hardware directly, and anything
in this kernel can crash it — that's the BYOS/SharkOS deal (see
[03](03-architecture.md)). If you ship a distro for others, consider
compiling these out — they're four `else if` branches to delete.

## Quick test loop

```bash
make kernel && make run-serial   # watch it boot; or…
make run                          # …boot Lite from the menu, type away
```

Lite is the fastest shell testbed: pick entry 2, your command is
immediately at the prompt.
