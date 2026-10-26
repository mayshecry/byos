# 13 · API quick reference

One-page cheat sheet of the surface you'll actually call. All of
this is inherited from SharkOS (<https://github.com/mayshecry/shark-os>);
BYOS only renamed the branded bits. Config macros come from
`<os_config.h>` via `kernel.h`.

## Config macros (`config.mk` → `os_config.h`)

`OS_NAME OS_NAME_LOWER OS_VERSION OS_CODENAME OS_VENDOR OS_HOSTNAME
OS_DEFAULT_USER OS_SHELL_NAME KERNEL_AUTHOR KERNEL_CREDIT
OS_WALLPAPER_TOP OS_WALLPAPER_BOTTOM CONFIG_ENABLE_ATA
CONFIG_ENABLE_AUDIO CONFIG_ENABLE_NETWORK`

## Core kernel (`kernel.h`)

| Group | Key calls / globals |
|---|---|
| Ports | `inb/inw/inl outb/outw/outl` |
| Memory | `kmalloc kfree ksize pmm_init pmm_reserve virt_to_phys` · `total_system_memory` `free_memory_start/end` |
| Strings | `strcmp strcasecmp strcpy strchr strstr strlen fast_strlen memcpy memset int_to_string hex_to_string` (no printf!) |
| Serial | `serial_init serial_puts serial_puthex32 serial_putdec` |
| Time | `uptime_ticks` (1 ms/tick, `TICKS_PER_SEC` 1000) `delay_ms` `yield()` |
| Tasks (cosmetic) | `create_task(name)` (in `main.c`) · `task_list next_pid spin_lock/spin_unlock(&task_list_lock)` |
| CPU/power | `get_cpu_model(buf49)` `shutdown()` · reboot = `outb(0x64,0xFE)` |
| Screen | `lfbptr` (back-buffer) `hw_lfbptr` `screen_width/height/pitch` `flush_screen_to_hw` `flush_rows_to_hw(y0,y1)` `fill32` |
| Console draw | `draw_char draw_pixel draw_rect draw_string_px col_px row_px` |
| Terminal | `terminal_writestring terminal_putchar terminal_write_direct terminal_set_color terminal_clear terminal_* scrollback/capture` · `terminal_in_desktop_window` `desktop_terminal_cols` |
| Panes/UI (Lite) | `panes[] active_pane split_active_pane close_active_pane redraw_all_panes print_prompt faq_open/close settings_open apply_theme` |
| Input globals | `keyboard_getchar shift_pressed ctrl_pressed` · `mouse_state{x,y,buttons,dx,dy,wheel} mouse_cursor_x/y mouse_enabled` |
| Sysinfo stats | `sys_cpu_percent sys_cpu_history[] sys_frames_per_sec sys_frames_rendered` |
| ELF | `execute_elf(data, arg)` — see [10](10-elf-programs.md) (sharp edges) |
| Modes | `current_kernel_mode` (`KERNEL_MODE_CLI/EDITOR/FAQ/SETTINGS/DESKTOP`) · `lite_mode legacy_mode kawaii_mode tiling_enabled` |

## Filesystem (`kernel.h`, `src/fs/fs.c`)

`root current_dir node_pool[128] pool_index` ·
`create_node(name, FS_FILE|FS_DIRECTORY, parent) -> fs_node*|NULL`
`find_node(parent, name)` `search_path(name)` (cwd → `/System/Bin`)
`fs_initialize()` · limits: name ≤31, children ≤8/dir, content
≤`MAX_FILE_CONTENT_SIZE` (2048). Guide: [07](07-filesystem.md).

## Desktop (`desktop.h`)

| Area | Key calls |
|---|---|
| Lifecycle | `desktop_init desktop_render desktop_handle_mouse(mx,my,buttons,wheel) desktop_handle_keyboard(c) desktop_anim_tick` |
| Invalidate | `desktop_invalidate_rect(x0,y0,x1,y1)` · flags `desktop.dirty w->needs_redraw` |
| Windows | `window_create(type,title,x,y,w,h)->idx window_close/minimize/maximize/restore/focus window_close_by_ptr window_get_focused window_draw_all window_focus_top_visible` |
| Launch | `desktop_icon_launch_offset(type,title)` `desktop_icon_launch(idx)` |
| Icons | `desktop_icon_add(label,type) desktop_icon_remove desktop_layout_icons desktop_icons_load desktop_icon_pixels_for_type(type) desktop_icon_get_start/shutdown/folder/file` |
| Wallpaper | `desktop_set_wallpaper(id) desktop_set_wallpaper_color(top,bottom) desktop_set_wallpaper_mode(m) desktop_set_wallpaper_fit(f) desktop_wallpaper_count/name/thumb` · `WP_ID_CLASSIC/OCEAN/FOREST/SUNSET/GRAPHITE/PLUM` |
| Start menu | `start_menu_open/close/toggle/draw/handle_click/handle_hover/scroll/get_rect` |
| Boot screen | `boot_screen_show/update(msg,pct)/info(msg)/hide` · `draw_logo(cx,cy,size,color)` |
| Disk mgmt | `app_window_draw_diskmgmt app_window_mouse_diskmgmt diskmgmt_tick` |
| State | `desktop` (`desktop_state_t`: windows[16], icons[24], start_menu, wallpaper_id/mode/fit, ctx_menu…) · `desktop_mouse_x/y/down drag_window resize_window` |

Window callbacks: `draw_func(w)` `keyboard_func(w,c)`
`mouse_func(w,mx,my,buttons)` `close_func()` `game_tick()`
(~16 ms, focused only) `user_data`. Guide:
[04](04-desktop-and-windows.md).

## Widgets & themes (`win98_theme.h`, `theme.h`)

Colours: `W98_BTNFACE W98_BTNTEXT W98_GRAYTEXT W98_WINDOW
W98_WINDOWTEXT W98_HIGHLIGHT(TEXT) W98_ACTIVE_TITLE(2)
W98_INACTIVE_TITLE(2) W98_TITLETEXT(_INACT) W98_MENU_BG W98_LOGO …`
Draw: `w98_fill w98_fill_dither w98_bevel(w/ W98_BEVEL_*) w98_surface
w98_button w98_hgradient w98_vgradient w98_text{,_bold,_outline,
_alpha,_alpha_bold,_vertical} w98_text_width/height w98_text_fit
w98_glyph w98_icon_blit{,_small} w98_blit_rgb`
Themes: `THEME_ID_WIN98/MODERN/KAWAII/WINDOWMAKER (0-3)
THEME_COUNT theme_current theme_set theme_get_id theme_get_name`
Fonts: `br_font_init br_font_face br_font_draw{,_ex}
br_font_text_width …` (`font.h`). Guide:
[08](08-themes-icons-wallpapers.md).

## Drivers

| Header | Key calls |
|---|---|
| `ata.h` | `ata_init ata_drive_count ata_drive_get(idx)->{present,model,sectors…} ata_read_sectors ata_write_sectors` |
| `audio.h` | `audio_init/tick/shutdown/available/backend_name` · play: `audio_play audio_play_s16 audio_play_wav audio_play_wav_mem` · ctl: `audio_stop{,_all} audio_set_volume audio_set_master_volume audio_is_playing audio_mix_frames` · `wav_parse` · `pcspkr_beep` · backend struct + `ac97_* hda_* (probe/init/submit/tick)` · `pci_find_audio_device pci_read_bar pic_unmask_irq pic_mask_irq` |
| `net.h` | `net_init net_stack_init net_poll net_has_nic net_send_raw net_set_rx_callback` · `net_dhcp{,_start,_state,_status,_lease_left}` · `net_dns_lookup net_ping net_parse_ip4 net_arp_resolve` · TCP: `net_tcp_connect net_tcp_open/send/recv/peer_closed/close` · HTTP: `net_http_get + net_http_last_* net_tls_*` · `net_cmd_ifconfig/ping/wget/dns/netstat/dhcp` · globals `net_ip/mask/gw/dns/mac net_has_link net_configured net_driver_name` |
| `kernel.h` | `pci_config_read/write pci_list_devices` · `keyboard_handler/getchar` `mouse_init/handler` `rtc_init rtc_read_time rtc_seconds…rtc_year` |

Guides: [06](06-drivers.md) · [09](09-network-and-audio.md).

## Image decoders (no header — declare yourself)

```c
int png_decode_buf (data,len,&w,&h,pixels,max_pixels,scratch,scratch_len);
int jpeg_decode_buf(…);  int gif_decode_buf(…);  int webp_decode_buf(…);
uint32_t* decode_png(data,len,&w,&h);
long inflate_raw/zlib/gzip(in,in_len,out,out_len);   /* declared in kernel.h */
```

Pixels come out ARGB row-major. Details:
[08](08-themes-icons-wallpapers.md#using-a-real-image-instead).

## int 0x80 (for ELF programs)

`rax=1` print "Process exited." · `rax=3` read FS file
(`rbx`=name, `rcx`=buf → `rax`=len/-1) · `rax=4` write terminal
(`rcx`=buf, `rdx`=len) · `rax=24` yield. Full story:
[10](10-elf-programs.md).
