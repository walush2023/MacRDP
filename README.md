# MacRDP

**An open-source alternative to Microsoft's Windows App for macOS, tuned for high frame-rate Remote Desktop.**

English | [繁體中文](README.zh-TW.md)

MacRDP looks and works like Windows App (saved PCs, groups, the same per-PC settings), but it exposes the performance options Windows App keeps hidden: **UDP transport**, **H.264 AVC444**, and **uncapped frame rate**. Together with a few Windows-side tweaks, a 1080p desktop that Windows caps at about 30 fps runs at **75+ fps** on a LAN.

## How it differs from Windows App

| | Windows App (Microsoft) | MacRDP |
|---|---|---|
| Transport | Chosen automatically | **UDP preferred or TCP only**, per PC |
| Graphics codec | Chosen automatically | **AVC444 / AVC420 / RemoteFX / Progressive / legacy**, per PC |
| Frame pacing | Waits for each frame to be acknowledged | **Optional uncapped frame rate** (`frame-ack:0`) |
| Windows-side tuning | Not documented | **One-click script** to lift the 30 fps cap and turn on H.264, UDP and GPU encoding |
| Clipboard | On or off | **Separate direction for text/images and for files** (both / to remote / to Mac / off) |
| Full screen | Native | Native: every session gets its own Space, so you can swipe between them |
| Extras | — | `.rdp` import/export, `--connect` command line (Shortcuts, Alfred, Raycast), custom FreeRDP arguments |
| Source | Closed | **Open source** (Apache-2.0), built on [FreeRDP 3](https://github.com/FreeRDP/FreeRDP) |
| Azure Virtual Desktop / Windows 365 | Yes | **Not supported**: MacRDP connects to PCs directly or through an RD Gateway |
| Camera redirection, swap mouse buttons | Yes | **Not supported** (FreeRDP has no macOS support for them) |
| UI language | Many | Traditional Chinese for now |

### Measured

1920×1080, a full-screen animation on Windows 11 (QEMU VM, no GPU), Mac mini on wired LAN:

| Setup | Average fps | Codec |
|---|---|---|
| Windows defaults | 32 | ClearCodec |
| Windows tweaks applied, TCP | 78 | AVC444 |
| Windows tweaks applied, UDP | 75 | AVC444 |
| Windows tweaks applied, UDP through MacRDP's local relay (default) | 72 | AVC444 |

On a sub-millisecond LAN, UDP and TCP perform about the same. UDP helps on links with latency or packet loss, such as Wi-Fi or connecting from outside your home.

## Features

- **Saved PCs**: grid or list view, groups, search, recently used, duplicate, delete
- **Per-PC settings**, following Windows App's "Add PC" dialog:

| Tab | Settings |
|---|---|
| General | Host / IP, port, friendly name, group, user name, domain, password (in Keychain), reconnect automatically, admin session |
| Display | Resolution (match display / match window / presets / custom), update resolution on resize, scale, full screen, use all monitors, fit session to window, color quality |
| Devices & Audio | Clipboard (text/images and files, each both / to remote / to Mac / off), printers, smart cards, microphone, where sound plays |
| Folders | Redirect any folder, share your home folder |
| Performance | UDP preferred or TCP only, codec, uncapped frame rate, network type, wallpaper / themes / ClearType / animations |
| Gateway | RD Gateway host, port, separate credentials, bypass for local addresses |
| Advanced | Certificate policy, security protocol (NLA / TLS / RDP), RemoteApp, alternate shell, load-balance info, keyboard layout, extra FreeRDP arguments |

- Passwords stay in the macOS Keychain and reach FreeRDP through stdin, never in a file or the process list
- Open `.rdp` files from Finder, or import and export them
- `MacRDP.app/Contents/MacOS/MacRDP --connect "<name or host>"` connects straight away

## Download

Get the notarized DMG from [Releases](https://github.com/walush2023/MacRDP/releases). It runs on Apple Silicon Macs with macOS 14 or later; Homebrew is not needed.

The first time you connect to a PC on your network, macOS asks whether MacRDP may access the local network. Click **Allow**. If you denied it, turn MacRDP on in System Settings → Privacy & Security → Local Network.

## Windows setup

MacRDP uses UDP, AVC444 and an uncapped frame rate by default, but **Windows caps Remote Desktop at about 30 fps and may not use H.264 unless you change it**.

### One click

Run [`tools/windows-setup.ps1`](tools/windows-setup.ps1) in PowerShell **as Administrator** on the Windows PC:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-setup.ps1          # apply
.\windows-setup.ps1 -Undo    # remove the performance tweaks
```

Then **sign out of Windows (or reboot)** so the next session picks the changes up.

### What the script changes

1. **Turns on Remote Desktop.** Needs Windows Pro, Enterprise or Education; Windows Home cannot host RDP.
2. **Firewall**: allows inbound **TCP 3389** and **UDP 3389**. If the PC sits behind a router, Docker or a VM, **forward UDP 3389 too**, or sessions fall back to TCP.
3. **UDP**: Group Policy `Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Session Host → Connections → Select RDP transport protocols` = **Use both UDP and TCP**
   (registry: `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\SelectTransport = 0`)
4. **Lifts the 30 fps cap**:
   `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\DWMFRAMEINTERVAL` (DWORD) = **15**
5. **Prefers H.264/AVC 4:4:4**: `… Remote Desktop Session Host → Remote Session Environment → Prioritize H.264/AVC 444 graphics mode for Remote Desktop Connections` = Enabled
   (registry: `…\Terminal Services\AVC444ModePreferred = 1`)
6. **GPU encoding** (with a dedicated GPU): `… Remote Session Environment → Configure H.264/AVC hardware encoding for Remote Desktop Connections` = Enabled, and `Use hardware graphics adapters for all Remote Desktop Services sessions` = Enabled
   (registry: `AVCHardwareEncodePreferred = 1`, `bEnumerateHWBeforeSW = 1`)

The account you sign in with needs a password. For a Microsoft account, use its email address and the Microsoft account password, not the PIN.

### Check that UDP is in use

Right-click a PC → Show Connection Log (`~/Library/Logs/MacRDP/<id>.log`). This line means the session runs over UDP:

```
UDP multitransport tunnel ready
```

To measure fps yourself, open [`tools/fps-test.html`](tools/fps-test.html) full screen in a browser on Windows.

## Build from source

Requirements: macOS 14+, Apple Silicon, Xcode Command Line Tools (`xcode-select --install`; full Xcode isn't needed), [Homebrew](https://brew.sh).

```bash
git clone https://github.com/walush2023/MacRDP.git
cd MacRDP
scripts/build-freerdp.sh   # FreeRDP with UDP and the macOS patches, 3–5 minutes
scripts/build-app.sh       # builds build/MacRDP.app with FreeRDP inside
open build/MacRDP.app
```

- `build-app.sh` runs `MacRDP --self-test` (argument and `.rdp` checks) and copies the Homebrew libraries FreeRDP needs (ffmpeg, SDL3, OpenSSL, about 46 files) into the app ([`scripts/bundle-dylibs.sh`](scripts/bundle-dylibs.sh)). Only building needs Homebrew.
- It signs with a Developer ID or Apple Development certificate from your keychain (choose one with `SIGN_IDENTITY=<identity>`). A stable signature lets the Keychain keep trusting MacRDP; with ad-hoc signing macOS asks for your Keychain password again after every rebuild.

**Why the local relay?** macOS grants Local Network access per executable, and a self-built `sdl-freerdp` is denied silently, without a prompt (`Couldn't get socket ip address`). So FreeRDP connects to `127.0.0.1` and MacRDP forwards TCP and UDP to the real host. You can turn this off in Settings; sessions through an RD Gateway don't use it.

### Release (sign, notarize, DMG)

```bash
scripts/release.sh
```

This builds `build/MacRDP-<version>.dmg`: signed with Developer ID and the hardened runtime, notarized by Apple, and stapled. It needs a "Developer ID Application" certificate and notarization credentials saved once (create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security):

```bash
xcrun notarytool store-credentials macrdp-notary --apple-id <Apple ID> --team-id <Team ID> --password <app-specific password>
```

`SKIP_NOTARIZE=1` signs without notarizing; `NOTARY_PROFILE=<name>` uses another saved profile. The version number lives in `VERSION`.

## Project layout

```
Sources/MacRDP/
  MacRDPApp.swift               app entry, menus, opening .rdp files
  Model/                        Connection (all settings), ConnectionStore (JSON), Keychain, RDPFile
  Session/FreeRDPCommand.swift  settings → FreeRDP arguments
  Session/SessionManager.swift  starts and tracks sdl-freerdp, reachability check, error messages
  Session/LocalRelay.swift      TCP + UDP relay on 127.0.0.1
  Views/                        main window, PC editor, password prompt
  SelfTest.swift                `--self-test` checks
Resources/                      app icon (AppIcon.icns, made by scripts/make-icon.swift from icon-source.png)
patches/                        FreeRDP patches (native full screen, flicker-free start)
scripts/                        build-freerdp.sh, build-app.sh, bundle-dylibs.sh, release.sh, make-icon.swift
tools/                          windows-setup.ps1, fps-test.html
```

Settings live in `~/Library/Application Support/MacRDP/connections.json`; passwords live in the Keychain under the service name `MacRDP`.

## License

Apache License 2.0, the same as FreeRDP. See [LICENSE](LICENSE).
