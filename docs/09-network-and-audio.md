# 09 · Network & audio APIs — using them from your code

Both stacks are polled from the main loop (every 10 ms), so these
APIs are **synchronous from your point of view**: call, wait (they
internally pump `net_poll`/yield as needed), get a result. Don't
call them from IRQ handlers. Guard network code with
`net_has_nic()` / `#if CONFIG_ENABLE_NETWORK` if your distro ships
with networking off.

## Networking (`include/net.h`)

### State you can read any time

```c
extern uint8_t net_mac[6];
extern int net_has_link;
extern char net_driver_name[32];      // "Intel e1000", "RTL8139", "none"…
extern uint8_t net_ip[4], net_mask[4], net_gw[4], net_dns[4];
extern int net_configured;            // DHCP done (or static set)
int  net_has_nic(void);
int  net_dhcp_state(void);            // and net_dhcp_status() string
uint32_t net_dhcp_lease_left(void);
void net_format_mac(char* out);       // "aa:bb:…"
```

The Network window (`app_window_draw_network`) is the reference
consumer. DHCP runs at boot via `net_stack_init()`; `net_dhcp_start()`
/ `net_dhcp()` re-run it.

### DNS + ping + address helpers

```c
int net_dns_lookup(const char* host, uint8_t ip_out[4]);      // 0 ok
int net_parse_ip4(const char* "10.0.2.2", uint8_t out[4]);
int net_ping(const char* ip_str, int count);                  // ICMP echo
int net_arp_resolve(const uint8_t* ip, uint8_t mac_out[6]);
```

### TCP (one connection at a time)

Two flavours. One-shot request/response:

```c
uint8_t ip[4];
if (net_dns_lookup("example.com", ip) == 0) {
    static uint8_t resp[8192];
    const char* req = "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n";
    int n = net_tcp_connect(ip, 80, (const uint8_t*)req, strlen(req),
                            resp, sizeof(resp));
    /* n = bytes received, resp[] = raw HTTP response */
}
```

Streaming socket style:

```c
if (net_tcp_open(ip, 443) >= 0) {
    net_tcp_send((const uint8_t*)req, len);
    int n;
    while ((n = net_tcp_recv(buf, sizeof buf, /*timeout_ms*/2000)) > 0) { … }
    bool closed = net_tcp_peer_closed();
    net_tcp_close();
}
```

Single-socket model: opening a second connection replaces the
first. Size your buffers statically or `kmalloc` once — do not
allocate per request in a loop (bump allocator, see
[03](03-architecture.md#memory-model)).

### HTTP(S) client

```c
int net_http_get(const char* url, uint8_t* out, uint32_t out_max);
/* after a call: */
extern int  net_http_last_status;              // 200, 301, …
extern char net_http_last_content_type[128];
extern char net_http_last_location[1024];      // redirect target
extern int  net_tls_last_error;                // 0 ok
extern char net_tls_peer_cn[64];
void net_http_close_idle(void);                // drop keep-alive
```

`https://` goes through the home-grown TLS 1.2/1.3 in `tls.c` +
`crypto.c` — good enough for APIs/plain pages, not a browser
replacement (the browser was removed in BYOS; this client remains
for *your* apps and the shell's `wget`). The first line of the
request carries `User-Agent: … <OS_NAME> x86_64) <OS_NAME>/<version>`
— from `config.mk`, automatically.

### Raw frames (bring-your-own protocol)

```c
void net_send_raw(const uint8_t* frame, uint32_t len);   // full Ethernet frame
typedef void (*net_rx_cb_t)(const uint8_t* frame, uint32_t len);
void net_set_rx_callback(net_rx_cb_t cb);                // tap every RX frame
```

Use the callback for sniffers/custom Ethertypes; remember the IP
stack still wants its frames too — observe, don't consume.

### Ready-made shell backends

`net_cmd_ifconfig/ping/wget/dns/netstat/dhcp` are the functions
behind the same-named shell commands — call them if "print the
standard report to the terminal" is literally what you want.

## Audio (`include/audio.h`)

Fixed pipeline: **48 kHz, s16, stereo**, 8 mixer channels, 10 ms
ticks. Backends (HDA → AC'97 → PC-speaker/null) are chosen in
`audio_init`; check `audio_available()` and
`audio_backend_name()` before assuming sound exists.

### Play something

```c
#include "audio.h"

/* raw PCM you already have */
int h = audio_play(pcm, pcm_bytes,
                   /*rate*/22050, /*channels*/1, /*bits*/16,
                   /*loop*/false, /*volume 0-255*/200);

/* s16 helper */
int h = audio_play_s16(samples, frame_count, 44100);

/* a whole .wav in memory (parsed for you) */
int h = audio_play_wav(wav_bytes, wav_len, 200, false);

/* a .wav stored as a file in the RAM filesystem (<=2 KiB! mostly a toy) */
int h = audio_play_wav_mem("startup.wav", 200);

/* control */
audio_set_volume(h, 128);  audio_is_playing(h);  audio_stop(h);
audio_set_master_volume(200);                     audio_stop_all();
```

Handles are small ints; ≤ 8 sounds at once. Resampling to 48 kHz is
linear and automatic (`audio_channel_t` keeps the fractional step).

### Generate tones / beeps

* `pcspkr_beep(freq_hz, ms)` — always available-ish pit/speaker
  beep (also the backend of last resort).
* Musical bleeps on real hardware: fill a small static s16 buffer
  with a sine/square at your sample rate and `audio_play_s16` it —
  the `audio` shell command (`cmd_audio` in `commands.c`) has
  worked examples incl. mixer tests and is your best reference.

### Embed a sound in your distro

Dump the file as a C array (same trick as icons,
[08](08-themes-icons-wallpapers.md#adding-an-icon)):

```bash
xxd -i chime.wav > src/desktop/chime_data.h   # or a tiny python dumper
```

…then `audio_play_wav(chime_wav, chime_wav_len, …)` from wherever
(a window's keyboard handler, a shell command). WAVs are big:
1 s of 22 kHz mono s16 ≈ 44 KiB linked into the kernel — keep
sounds short or loop a generated tone instead.

### Mixing yourself

`audio_mix_frames(int16_t* out, int frames)` renders the next N
frames of all channels without a backend — for visualisers or
writing audio to your own device. `g_audio` (`audio_state_t`)
exposes channels/master volume/stats if you need them; treat as
read-mostly.

## Timing both stacks

`net_poll()` and `audio_tick()` run every 10 ms in the desktop
loop and Lite loop. Consequences for your code:

* Network latency granularity ≈ 10 ms. Fine for HTTP/ping UIs.
* If you block the main loop (long compute without `yield()`),
  audio underruns (`g_audio.underruns` climbs) and TCP stalls.
  Chunk heavy work across `game_tick`s instead.
* Disabling a subsystem in `config.mk` (`ENABLE_AUDIO=0` etc.)
  skips its Init but **linking stays valid** — your calls become
  no-ops/failures; check return values.
