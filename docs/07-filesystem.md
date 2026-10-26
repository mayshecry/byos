# 07 · Filesystem — shipping files in your distro

BYOS has a RAM-only filesystem (`src/fs/fs.c`, from SharkOS). The
tree you see at boot (`/User`, `/System`, …) is *created by code* in
`fs_initialize()` — so "shipping a file in your distro" means adding
a few lines there. This guide covers that, the hard limits, and the
runtime file API for your own code.

## The model

```c
#define MAX_NODES 128                 /* total files+dirs, ever */
#define MAX_CHILDREN 8                /* per directory! */
#define MAX_FILE_CONTENT_SIZE 2048    /* bytes per file */

struct fs_node {
    char name[32];
    node_type_t type;                 /* FS_DIRECTORY | FS_FILE */
    struct fs_node* parent;
    struct fs_node* children[8];
    int num_children;
    char content[2048];               /* inline content, no heap */
    int content_len;
};
extern struct fs_node* root;          /* "/" */
extern struct fs_node* current_dir;
```

Nodes come from a static pool (`node_pool[128]`, `pool_index`) —
there is no delete/alloc churn at the struct level; `rm` unlinks
from the parent. Content is inline, so a full filesystem costs
~270 KiB of BSS no matter what.

## Shipping default files (what distros actually do)

In `fs_initialize()`:

```c
struct fs_node* docs = create_node("Documents", FS_DIRECTORY, user);

struct fs_node* welcome = create_node("welcome.txt", FS_FILE, docs);
set_content(welcome,
    "Welcome to " OS_NAME " " OS_VERSION "!\n"
    "Kernel created by " KERNEL_AUTHOR ".\n"
    "Type 'help' in a terminal to get started.\n");
```

Rules learned the hard way:

* `set_content()` is a static helper in `fs.c` doing
  `strcpy + content_len = strlen`. Content > 2047 bytes **overflows
  the node** — there is no bounds check. Split long texts across
  files, or raise `MAX_FILE_CONTENT_SIZE` in `kernel.h` knowing
  every node grows (BSS cost × 128).
* Mind `MAX_CHILDREN = 8`. `/System` in the stock tree is already
  close; group new files in sub-directories (`create_node("Docs",
  FS_DIRECTORY, system)`) instead of piling into one dir.
  `create_node` returns `NULL` when the pool (128) is exhausted —
  check it if you add lots of files, or raise `MAX_NODES`
  (each +1 ≈ +2.2 KiB BSS).
* **Use the config macros in shipped text** (`OS_NAME`,
  `OS_HOSTNAME`, `KERNEL_AUTHOR`…) via C string concatenation, as
  the stock `os-release`/`readme.txt` do — never hard-code your
  distro name; keeps `make verify` and future renames working.
* Names: ≤ 31 chars, no `/`. Lookup is case-sensitive `strcmp`
  (`strcasecmp` exists if you need it).
* The home folder is created as `"User"` then renamed in `kmain` to
  `current_user` (`OS_DEFAULT_USER`). If you want a different
  layout, restructure `fs_initialize` but keep `root` and a
  `System/Bin` dir — the shell's ELF lookup depends on it (below).

Stock files worth editing for your distro: `readme.txt` (welcome),
`System/os-release`, `System/version`, `System/Kernel.sys`,
`System/hostname`, `System/sysconfig`, the joke logs (`boot.log`,
`syslog`, `dmesg`, `modules`). They're plain `set_content` strings.

## Runtime file API (for your windows/commands)

```c
struct fs_node* find_node(struct fs_node* parent, const char* name);
struct fs_node* search_path(const char* name);  /* cwd, then /System/Bin */
struct fs_node* create_node(const char* name, node_type_t type,
                            struct fs_node* parent);
/* editor glue (kernel.h): editor_target_file, editor_buffer[2048] */
```

Reading a file from a window/command:

```c
struct fs_node* f = find_node(current_dir, "notes.txt");
if (f && f->type == FS_FILE) {
    /* f->content[0 .. f->content_len), NUL-terminated by convention */
}
```

Writing (what Notepad/`edit` effectively do):

```c
struct fs_node* f = find_node(current_dir, "notes.txt");
if (!f) f = create_node("notes.txt", FS_FILE, current_dir);
if (f) {
    int n = 0;
    while (src[n] && n < MAX_FILE_CONTENT_SIZE - 1) { f->content[n] = src[n]; n++; }
    f->content[n] = 0;
    f->content_len = n;
}
```

Notepad (`app_window_draw_notepad` in `appwindows.c`) is the full
worked example of open/edit/save against this API, including its
own 4 KiB edit buffer — note it still must clamp to 2 KiB on save.

## `System/Bin` and runnable files

Any *file* found by `search_path()` (current dir first, then
`/System/Bin`) whose name is typed at the shell is handed to
`execute_elf(content, args)`. In practice files are 2 KiB max and
content is text until you load binaries some other way (there's no
disk/floppy import path by default — ATA is only used by Disk
Management), so treat this as a loader *mechanism* to build on.
Full contract: [10 · ELF programs](10-elf-programs.md).

## Making storage persistent (pointers, honestly)

Not built in. Your options, smallest first:

1. **Embed more content in the kernel**: raise limits, add
   `set_content` data. Fine for docs/configs.
2. **Save/load via ATA yourself**: `ata_read/write_sectors()` give
   raw LBA access ([06](06-drivers.md)). Disk Management already
   writes the kernel image to disk with an 8-byte magic header
   (`KRNLIMG1`) + length + checksum — copy that framing to persist
   a settings file or a serialised node pool at a fixed LBA.
3. **Write a real FS driver**: replace `fs.c`'s pool with an
   on-disk format behind the same `fs_node` API so the shell,
   Notepad and File Manager keep working. This is the "big distro
   feature" most BYOS forks will eventually want; the API surface
   to preserve is the four functions above + the node fields the
   shell walks (`children/num_children/parent`).

## Gotchas

* File Manager, `ls`, `tree`, `find` all walk `children[]` — if you
  mutate the tree while a window lists it, expect redraw weirdness;
  set `desktop.dirty` after changes.
* `cd` handles `..`/relative segments in the shell layer; the FS
  itself only knows single name components. Multi-segment paths in
  *your* code need manual walking with `find_node` per segment.
* Two files can share a name in different dirs; `find`/`grep`
  semantics are the shell's, not the FS's.
