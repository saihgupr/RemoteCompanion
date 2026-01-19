# RemoteCompanion Layout Plan

## Overview
Two-panel layout: **Triggers** (left) → **Actions** (right)

---

## Panel Structure

```
┌─────────────────────────────────────────────────────────────┐
│  [Master Toggle: ON/OFF]              RemoteCompanion       │
├─────────────────────────┬───────────────────────────────────┤
│                         │                                   │
│  TRIGGERS               │  ACTIONS (for selected trigger)   │
│  ─────────              │  ────────────────────────────     │
│  🔍 [Search...]         │                                   │
│                         │  ┌─────────────────────────────┐  │
│  📱 VOLUME BUTTONS      │  │ 1. haptic                   │  │
│  ─────────────────      │  │    ≡ (drag handle)          │  │
│  ▸ Volume Up Hold   (2) │  ├─────────────────────────────┤  │
│  ▸ Volume Down Hold (1) │  │ 2. media play-pause         │  │
│                         │  │    ≡                        │  │
│  ⏻ POWER BUTTON         │  └─────────────────────────────┘  │
│  ─────────────────      │                                   │
│  ▸ Double-Tap       (0) │           [ + Add Action ]        │
│  ▸ Long Press       (1) │                                   │
│                         │                                   │
│  🔇 MUTE SWITCH         │  ─────────────────────────────    │
│  ─────────────────      │  Actions run in sequence.         │
│  ▸ Mute Toggle      (0) │  Drag to reorder.                 │
│                         │                                   │
└─────────────────────────┴───────────────────────────────────┘
```

---

## Triggers Panel (Left)

### V1 Triggers
- **Volume Buttons**
  - Volume Up Hold
  - Volume Down Hold
- **Power Button**
  - Double-Tap
  - Long Press

### UI Elements
- **Badge count** (2) showing number of actions assigned
- **Chevron** (▸) indicates selectable row
- **Category headers** collapsible (optional)

---

## Actions Panel (Right)

### When Trigger Selected
Shows ordered list of actions to execute sequentially.

### Action Item UI
```
┌─────────────────────────────────────┐
│ ≡  haptic                       🗑️ │
│    "Trigger vibration feedback"     │
└─────────────────────────────────────┘
```
- **Drag handle** (≡) - reorder via drag
- **Action name** - primary label
- **Description** - subtitle (optional)
- **Delete button** (🗑️) - remove from sequence

### Add Action Flow
Tap **[ + Add Action ]** → Modal/Sheet appears:

```
┌─────────────────────────────────────┐
│         SELECT ACTION               │
├─────────────────────────────────────┤
│  📱 MEDIA                           │
│  ──────                             │
│  ○ Play/Pause                       │
│  ○ Next Track                       │
│  ○ Previous Track                   │
│  ○ Volume Up                        │
│  ○ Volume Down                      │
├─────────────────────────────────────┤
│  🔦 DEVICE CONTROLS                 │
│  ────────────────                   │
│  ○ Flash On                         │
│  ○ Flash Off                        │
│  ○ Rotate Lock                      │
│  ○ Rotate Unlock                    │
├─────────────────────────────────────┤
│  🔊 CONNECTIVITY                    │
│  ────────────                       │
│  ○ WiFi On                          │
│  ○ WiFi Off                         │
├─────────────────────────────────────┤
│  ⚡ SYSTEM                          │
│  ──────                             │
│  ○ Haptic                           │
│  ○ Screenshot                       │
│  ○ Lock                             │
│  ○ DND On                           │
│  ○ DND Off                          │
│  ○ LPM On                           │
│  ○ LPM Off                          │
├─────────────────────────────────────┤
│  🎧 AUDIO                           │
│  ─────                              │
│  ○ ANC On                           │
│  ○ ANC Off                          │
│  ○ ANC Transparency                 │
└─────────────────────────────────────┘
```

> **V2 Features** (not in V1):
> - Search bar in action picker
> - Actions with parameters (brightness level, unlock PIN, BT device name)
> - Additional triggers (mute switch, action button, custom gestures)

---

## Flow Example

**User wants Volume Down Hold → Play/Pause with haptic feedback:**

1. Tap "Volume Down Hold" in Triggers panel
2. Actions panel shows empty (or existing actions)
3. Tap **[ + Add Action ]**
4. Select "Haptic" from SYSTEM category
5. Tap **[ + Add Action ]** again
6. Select "Play/Pause" from MEDIA category
7. Result:
   ```
   Actions for: Volume Down Hold
   ─────────────────────────────
   1. ≡ haptic
   2. ≡ media play-pause
   ```

---

## Mobile Considerations (iPhone)

On smaller screens, use navigation-based flow instead of side-by-side:

```
┌─────────────────────┐     ┌─────────────────────┐
│  TRIGGERS           │ --> │  ACTIONS            │
│  ─────────          │     │  ────────           │
│  🔍 [Search]        │     │  ◀ Back  Vol Down   │
│                     │     │                     │
│  📱 VOLUME          │     │  1. haptic          │
│  ▸ Vol Up Hold  (2) │     │  2. play-pause      │
│  ▸ Vol Down    >(1) │     │                     │
│                     │     │  [ + Add Action ]   │
│  ⏻ POWER            │     │                     │
│  ▸ Double-Tap   (0) │     │                     │
└─────────────────────┘     └─────────────────────┘
     (Screen 1)                  (Screen 2)
```

---

## Data Model (Conceptual)

```
{
  "triggers": {
    "volume_down_hold": {
      "enabled": true,
      "actions": [
        { "command": "haptic" },
        { "command": "media", "args": ["play-pause"] }
      ]
    },
    "power_double_tap": {
      "enabled": true,
      "actions": [
        { "command": "haptic" },
        { "command": "url", "args": ["camera://"] }
      ]
    }
  },
  "masterEnabled": true
}
```

---

## V1 Scope Summary

- 4 triggers: Volume Up Hold, Volume Down Hold, Power Double-Tap, Power Long Press
- All existing `rc` commands as actions (no parameters)
- Navigation-based UI (iPhone)
- Drag-to-reorder actions
- Master toggle to enable/disable all triggers
