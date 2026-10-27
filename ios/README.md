# 📱 CodePill iOS App (Swift & SwiftUI)

A **100% pure native, ultra-lightweight** iOS client designed specifically for vibe-coding on remote machines with Antigravity CLI and **Dynamic Island** support.

### ✨ Highlights
- **Zero Third-Party Dependencies**: No CocoaPods, No Carthage, No SPM bloat. Built strictly using Apple's official frameworks (`SwiftUI`, `ActivityKit`, `WidgetKit`, `URLSessionWebSocketTask`).
- **Dynamic Island & Live Activities**: Tracks agent status, active bash commands, and modified files in the physical Dynamic Island when minimized or locked.
- **Haptic Engine**: Tactile feedback on tool completions, turn completion, or errors.
- **Instant Launch**: Starts in < 0.1s and uses minimal RAM (< 20 MB).

---

## 🛠 How to Build & Install on iPhone

### Option A: Using Xcode (macOS)
1. Clone this repository on your Mac:
   ```bash
   git clone <repo-url>
   cd CodePill/ios
   ```
2. Generate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (or open `CodePill.xcodeproj`):
   ```bash
   # Install xcodegen if not already installed: brew install xcodegen
   xcodegen generate
   ```
3. Open `CodePill.xcodeproj` in Xcode.
4. Select your **Personal Team** under **Signing & Capabilities** for both `CodePill` and `CodePillWidget`.
5. Connect your iPhone via USB or Wi-Fi, select it as destination, and press **Run (Cmd + R)**.

---

### 🌐 Connecting to your Arch Linux Server
1. In the app, tap the **Settings** gear icon in the top right.
2. Enter your server's **Tailscale IP** (or local LAN IP) and port (`8080` by default).
3. Tap **Connect**.
4. You will see the green connection indicator: `Arch Linux (Connected)`.

---

## 📱 Dynamic Island Preview

| State | Dynamic Island Display |
|---|---|
| **Thinking** | Purple pill icon + spinner (`Thinking 🧠`) |
| **Running Tool** | Active command or file name (`Run: cargo test ⚡`) |
| **Editing File** | File badge (`Editing main.rs 📝`) |
| **Done** | Green badge (`Done ✅`) with tactile haptic notification |
