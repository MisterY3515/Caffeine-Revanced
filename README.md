<img src="https://github.caffeine-app.net/assets/icon.png" alt="Icon" width="120"/>

# Caffeine Revanced

**Don't let your Mac fall asleep.**

Caffeine Revanced is a lightweight macOS menu bar app that prevents your Mac from automatically going to sleep, dimming the screen, or starting the screen saver. It's based on the original Caffeine with expanded features for power users.

Requires **macOS 13.5** or later.

---

### Usage

Click the coffee cup icon in the menu bar to toggle Caffeine on or off. A full cup means sleep prevention is active; an empty cup means your Mac sleeps normally.

Right-click (or ⌃-click) the icon to access the menu, where you can activate Caffeine for a specific duration or open Preferences.

---

### Features

**General**
- Configurable default activation duration (or indefinitely)
- Activate automatically at launch or at login
- Deactivate when the device is manually put to sleep
- Show countdown timer in the menu bar
- System notification when the activation period ends
- Simulate app activity to prevent apps from going idle

**Sleep**
- Prevent sleep when the lid is closed (requires one-time administrator authorization via `/etc/sudoers.d/caffeine-revanced`)
- Dim the screen to zero when the lid is closed, restoring brightness on lid open
- Dim the keyboard backlight to zero when the lid is closed, restoring it on lid open
- Deactivate automatically when battery drops below a configurable threshold

**Shortcut**
- Global keyboard shortcut **⌘⌥C** to toggle from anywhere (requires Accessibility permission)

**Auto-Activate**
- Activate when connected to AC power; deactivate when switching to battery
- Activate while the Claude Code CLI is running
- Activate when specific apps are in the foreground
- Activate when connected to specific Wi-Fi networks

---

### Building

Open `src/Caffeine.xcodeproj` in Xcode 16 or later and build the `Caffeine` scheme.

---

### Credits

© 2006 Tomas Franzén  
© 2018 Michael Jones (IntelliScape Computer Solutions)  
© 2022 Dominic Rodemer  

Source code: https://github.caffeine-app.net
