# Customizable Keyboard Shortcuts — Design

Date: 2026-06-23

## Goal

Add a dedicated Settings window with a **Keyboard Shortcuts** subtab where every
bindable action shows its current binding, can be rebound by recording a new
keypress, and can be reset to its default. Covers the global screenshot hotkey,
editor actions (home/copy/save/undo/redo/reset/preview), zoom, and tool switches.

Today the app has **no** in-app keyboard shortcuts wired (zero `.keyboardShortcut`
usages). The only existing shortcut is the global capture hotkey, hardcoded to
`⌃⇧5` in `NativeCaptureShortcut.swift`. This feature adds both the bindings and
the customization UI.

## Command set (16 bindable actions)

| Category | Command | Action site | Default |
|---|---|---|---|
| Capture | Capture screenshot (global) | `beginCapture` (AppDelegate) | ⌃⇧5 |
| Editor | Go Home | `onGoHome` (clears session) | ⌘H |
| Editor | Copy | export → clipboard | ⌘C |
| Editor | Save | export → save panel | ⌘S |
| Editor | Undo | `state.performUndo()` | ⌘Z |
| Editor | Redo | `state.performRedo()` | ⌘⇧Z |
| Editor | Reset all changes | `state.resetToOriginal()` | ⌘⇧R |
| Editor | Preview original | `state.togglePreviewOriginal()` | P |
| Zoom | Zoom in | `zoom.zoomIn()` | ⌘= |
| Zoom | Zoom out | `zoom.zoomOut()` | ⌘- |
| Zoom | Reset zoom | `zoom.resetToCenter()` | ⌘0 |
| Tools | Select | `state.selectCursorTool(.select)` | V |
| Tools | Arrow | `state.selectCursorTool(.arrow)` | A |
| Tools | Line | `state.selectCursorTool(.line)` | L |
| Tools | Rectangle | `state.selectCursorTool(.rectangle)` | R |
| Tools | Text | `state.selectCursorTool(.text)` | T |

Padding and Background tools are intentionally **not** bindable. The `blur` tool
is disabled and skipped.

## Decisions (from brainstorming)

- **Settings lives in a new window** (not inside Home, not a third editor state).
- **Bare single keys are allowed** (e.g. `V`, `A`, `P`), in addition to combos.
  Bare-key bindings are suppressed while a text editor / field is first responder.
- **Conflicts are blocked + warned**: a keypress already owned by another command
  is rejected during recording, with an inline message naming the current owner.

## Architecture

Four units, each independently understandable and (where logic-bearing) testable.

### 1. `KeyBinding` (value type)

```
struct KeyBinding: Codable, Equatable {
    var keyCode: UInt16              // virtual keycode (kVK_*)
    var modifiers: UInt              // NSEvent.ModifierFlags rawValue (device-independent subset)
}
```

Responsibilities:
- `displayString` → glyph form (`⌃⇧5`, `⌘Z`, `V`).
- `matches(_ event: NSEvent) -> Bool` — compares keycode + normalized modifier set.
- `carbonKeyCode` / `carbonModifiers` — translate to Carbon for the global hotkey
  (`controlKey`, `shiftKey`, `cmdKey`, `optionKey`).

Only the four standard modifiers (⌘⌥⌃⇧) are considered; other flags are masked out.

### 2. `ShortcutCommand` (enum)

`CaseIterable` enum of the 16 commands. Carries:
- `displayName: String`
- `category: ShortcutCategory` (`capture` / `editor` / `zoom` / `tools`)
- `defaultBinding: KeyBinding`
- `isGlobal: Bool` (only `.capture` is true)

### 3. `ShortcutStore` (`ObservableObject`, singleton)

Holds the live binding map and persists it.

```
@Published private(set) var bindings: [ShortcutCommand: KeyBinding]

func binding(for: ShortcutCommand) -> KeyBinding
func commandOwning(_ binding: KeyBinding, excluding: ShortcutCommand?) -> ShortcutCommand?
func setBinding(_ binding: KeyBinding, for command: ShortcutCommand) -> Bool   // false if conflict
func reset(_ command: ShortcutCommand)
func resetAll()
```

- Persisted to `UserDefaults` as JSON keyed by command rawValue. Missing keys fall
  back to `defaultBinding`, so new commands added later get sane defaults.
- `setBinding` runs the conflict check (`commandOwning`); returns `false` and makes
  no change on conflict (the recorder surfaces the owner).
- Publishing lets the global hotkey re-register and the UI refresh.

### 4. Dispatch — two mechanisms

**Global (`.capture`):** `NativeCaptureShortcut` becomes binding-driven. Instead of
the hardcoded `kVK_ANSI_5` + `controlKey|shiftKey`, it reads the `.capture` binding
from `ShortcutStore` and registers that. It exposes `reload()` to unregister +
re-register. `AppDelegate` subscribes to `ShortcutStore` changes (Combine sink on
`bindings`) and calls `reload()` when the capture binding changes.

**In-app (everything else):** a `ShortcutDispatcher` installs an
`NSEvent.addLocalMonitorForEvents(matching: .keyDown)` while the editor is active.
On each keyDown:
1. If first responder is an editable text view/field (Text-tool editor, title
   field, save-panel, etc.), pass the event through unhandled.
2. Otherwise find the command whose binding matches; if found, invoke its closure
   and swallow the event; else pass through.

The dispatcher is owned by `EditorShell`, which already holds `state` and
`zoomController` and receives `onGoHome`. Copy/Save are extracted from
`TopToolBarView`'s private `copyToClipboard()` / `save()` into a small shared
`ExportActions` (constructed from the document/state) so both the toolbar buttons
and the shortcut call identical code. The dispatcher maps each non-global command
to the corresponding closure on `state` / `zoomController` / `ExportActions` /
`onGoHome`.

Mechanism stays inactive on the Home page and in Settings (no editor `state`),
except global capture which is always live.

## Settings window

- `SettingsWindowController` mirrors `EditorWindowController`: a single reused
  window, `NSHostingController` root, dark appearance.
- `AppState` gains `onOpenSettings: (() -> Void)?`, set by `AppDelegate` to show
  the controller.
- Entry points: a **"Settings…"** item in the menu-bar menu (`MenuContentView`),
  and a gear button in the home/editor chrome.
- `SettingsView` is a tabbed container; **Keyboard Shortcuts** is the implemented
  subtab. The tab structure is left extensible for future tabs (e.g. General),
  satisfying the "as a subtab" requirement.

## Recorder UI

`KeyboardShortcutsView` lists commands grouped by category. Each row is a
`ShortcutRow`:

```
[ Command name ........... ]  [ binding chip ]  [ reset ↺ ]
```

- **Binding chip** shows `displayString`. Click → recording state ("Press keys…").
- In recording state a scoped local monitor captures the next keyDown, builds a
  `KeyBinding`, and calls `store.setBinding`. 
  - On success the chip updates.
  - On conflict (`setBinding` returns false / `commandOwning` non-nil) the row
    shows an inline warning: "Already used by <Owner>" and stays unrecorded.
  - **Esc** cancels recording; **⌫/Delete** is not used to clear (every command
    keeps a binding — there is no "unbound" state; use Reset to restore default).
- **Reset ↺** restores that command's `defaultBinding`.
- A **"Reset all"** button at the bottom calls `store.resetAll()`.

Only one row records at a time; entering recording on a second row cancels the first.

Styling matches the existing `Theme.swift` drafting-room dark system (panels,
accent, typography) — reuse existing glass/panel helpers where they fit.

## Edge cases

- **Modifier-only press** (e.g. just ⌘) during recording → ignored; wait for a
  non-modifier key.
- **Bare key while typing** in Text tool / title field → dispatcher passes through
  (first-responder check), so `T`, `V`, etc. type normally.
- **Global hotkey unavailable** (OS rejects re-register) → keep prior binding,
  surface status via existing `setCaptureStatus` path, and the recorder reports
  failure rather than silently dropping the old binding.
- **Capture binding with no key / only modifiers** → recorder requires a real key,
  same as in-app, so the global registration always has a keycode.

## Testing

Unit-testable (logic, no AppKit UI):
- `KeyBinding`: `displayString` for representative bindings; Carbon translation;
  `matches` against synthesized modifier sets; Codable round-trip.
- `ShortcutStore`: defaults on empty store; `setBinding` success vs conflict;
  `commandOwning` excludes self; `reset` / `resetAll`; UserDefaults persistence
  round-trip (inject a test `UserDefaults` suite).

Manual (GUI), via `Scripts/build-install-run.sh`:
- Open Settings → rebind a tool → verify the new key switches tools and the old
  one no longer does.
- Conflict path: assign an in-use key → warning shows owner, no change.
- Reset single + Reset all.
- Rebind capture hotkey → verify global trigger uses the new combo immediately.
- Confirm bare keys don't fire while typing in the Text tool.

## Out of scope

- Per-zoom-preset bindings (only Zoom In / Out / Reset).
- Binding the Padding / Background tools or the disabled Blur tool.
- Import/export of shortcut sets; multiple profiles; chord (multi-key) sequences.
