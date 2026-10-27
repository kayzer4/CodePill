# 💊 CodePill

> **Remote Vibe-Coding iOS Client & Daemon for Antigravity CLI with Dynamic Island Integration.**

CodePill turns your iPhone into a native handheld cockpit for vibe-coding on your home Arch Linux server. Send prompts, review real-time diffs, and monitor ongoing agent tasks directly from the **Dynamic Island** even when the app is minimized.

---

## 🏗 Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Arch Linux Server                    │
│                                                        │
│   ┌──────────────────┐          ┌───────────────────┐  │
│   │  Antigravity CLI │ ◄──────► │  CodePill Daemon  │  │
│   │      (`agy`)     │  NDJSON  │   (Rust / Axum)   │  │
│   └──────────────────┘          └─────────┬─────────┘  │
└───────────────────────────────────────────┼────────────┘
                                            │ WebSocket / Tailscale
                                            ▼
┌────────────────────────────────────────────────────────┐
│                      Apple iPhone                      │
│                                                        │
│   ┌────────────────────────────────────────────────┐   │
│   │  iOS App (SwiftUI)                             │   │
│   │  - Streaming chat                              │   │
│   │  - Diff viewer & Approval controls             │   │
│   └───────────────────────┬────────────────────────┘   │
│                           │ ActivityKit                │
│                           ▼                            │
│   ┌────────────────────────────────────────────────┐   │
│   │  Dynamic Island & Live Activities              │   │
│   │  - Shows real-time progress in background      │   │
│   │  - "Thinking 🧠", "Editing file 📝", "Done ✅" │   │
│   └────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start (Server)

### 1. Requirements
- Arch Linux with `agy` (`antigravity-cli`) installed and configured
- Rust (Cargo 1.80+)
- Tailscale (recommended for zero-config encrypted remote access)

### 2. Build & Run the Rust Server
```bash
cd server
cargo build --release
./target/release/codepill-server --bind 0.0.0.0 --port 8080 --workspace ~/PetProjects
```

CLI Options:
- `-b, --bind <IP>`: Bind address (default: `0.0.0.0`)
- `-p, --port <PORT>`: Port to listen on (default: `8080`)
- `-w, --workspace <DIR>`: Default workspace root
- `--agy-bin <PATH>`: Path to `agy` binary (default: `agy` from PATH)

### 3. Run as a Systemd User Service (Optional)
Create `~/.config/systemd/user/codepill.service`:
```ini
[Unit]
Description=CodePill Daemon for Antigravity
After=network.target

[Service]
Type=simple
ExecStart=/home/kayzer/PetProjects/CodePill/server/target/release/codepill-server --workspace /home/kayzer/PetProjects
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

Enable and start:
```bash
systemctl --user daemon-reload
systemctl --user enable --now codepill.service
```

---

## 📱 iOS App Integration

The `ios/` folder contains the core Swift modules:
1. **`CodePillAttributes.swift`**: `ActivityAttributes` protocol defining the dynamic state structure.
2. **`CodePillWidgetLiveActivity.swift`**: Dynamic Island widget (Compact Leading, Trailing, Minimal, and Expanded views).
3. **`CodePillClient.swift`**: WebSocket manager with auto-reconnect, streaming chunk receiver, and LiveActivity controller.

### Dynamic Island States:
- **Compact Leading**: Purple pill icon with an active spinner while busy.
- **Compact Trailing**: Short status badge (`Thinking`, `Done`, `Tool`).
- **Expanded (Long Press)**: Shows current file being modified, detailed step summary, and interactive `Approve` / `Cancel` buttons.
- **Lock Screen / Banner**: Rich preview widget with progress status.

---

## 🔒 Networking: Tailscale Setup

1. Install Tailscale on Arch Linux:
   ```bash
   sudo pacman -S tailscale
   sudo systemctl enable --now tailscaled
   sudo tailscale up
   ```
2. Install Tailscale on your iPhone from the App Store and log in to the same tailnet.
3. In the iOS app, connect directly to `ws://<your-arch-tailscale-ip>:8080/ws`. No public ports or router port forwarding required!
