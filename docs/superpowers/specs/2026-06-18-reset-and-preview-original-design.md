# Reset & Preview Original — Design

Date: 2026-06-18
Status: Approved (pending spec review)

## Goal

Add two dock controls to the ClipShot editor:

1. **Reset to original** — revert all edits back to the document's initial loaded state.
2. **Preview original** — toggle a non-destructive view of the original state without reverting.

## Definition of "original"

The **initial loaded state**: the `EditorDocument` as it first appeared when the
session opened, *including* the app's automatic processing (CV trim-to-content,
auto padding, dynamic/generative background). Reset undoes the user's manual
edits, not the automatic load-time setup.

## State changes — `EditorState`

- Add `let originalDocument: EditorDocument`, captured in `init` from the
  passed-in `document` (value-type struct copy, free).
- Add `@Published var previewingOriginal: Bool = false`.
- Add computed `var displayDocument: EditorDocument { previewingOriginal ? originalDocument : document }`.
- Add `var canReset: Bool { document != originalDocument }` (drives disabled
  state for both buttons — nothing to reset/preview when they're equal).

## Equality — `EditorDocument`

`EditorDocument` must support value comparison against `originalDocument` for the
`canReset` check. Make the struct `Equatable`. The `version: Int` field is an
identity/change token, not semantic content — exclude it from equality (custom
`==` comparing the edit fields, or move `version` out of synthesized equality).
The `screenshot: CGImage` reference is identical across original and edited
(never reassigned in normal editing), so reference/pointer comparison suffices.

## Reset — undoable command + confirm dialog

- New `ResetDocumentCommand: EditorCommand`:
  - `apply(to:)` — capture current document into the command (for revert), set
    document to the original snapshot.
  - `revert(to:)` — restore the captured edited document.
  - `coalesce(with:)` — return nil (never coalesce).
  - `displayName` — "Reset to Original".
- Triggered through a **macOS confirmation dialog** (SwiftUI `.confirmationDialog`):
  title "Discard all edits and reset to original?", a destructive "Reset" button
  and "Cancel". On confirm, push the command via `state.performCommand()` so it is
  also undoable (Cmd+Z restores edits). Dialog = intent guard; undo = safety net.
- The dialog presentation is owned by `DockView` via a local
  `@State var showResetConfirm: Bool`.

## Preview original — toggle

- The preview button flips `state.previewingOriginal`.
- `CanvasCoordinator.update(state:)` reads `state.displayDocument` instead of
  `state.document` for the rendered/displayed image (single substitution at the
  read site; downstream `apply`, overlay sizing, interaction bounds follow from
  that document).
- Canvas interaction (`interactionView.state`) stays bound to the real
  `document`. While `previewingOriginal` is true, gate draw/select input off so
  the user can't accidentally edit against the snapshot — the toggle is
  compare-only.
- Button shows an active/lit state while previewing (`isActive: previewingOriginal`).

## UI — `DockView` (bottom dock)

Extend the **history group** with a sub-section, mirroring the zoom group's
"reset view" pattern (`ZoomControlsView`): main controls, a thin sub-separator,
then the framing/meta action.

Layout left→right:

```
[undo][redo] ·sub-sep· [reset][preview]  ‖divider‖  [tools]  ‖divider‖  [zoom ·sub-sep· scope]
```

- sub-sep: `Rectangle().fill(Theme.hairline)`, width 1, height 14 (thin —
  matches `ZoomControlsView.separator`).
- group divider: existing `Theme.hairlineStrong`, height 18 (unchanged).
- **Reset button**: `IconButton(systemName: "arrow.counterclockwise")`,
  help/label "Reset to Original". Disabled + dimmed (opacity 0.35) when
  `!state.canReset`.
- **Preview button**: toggle styled like `ToolRailButton`
  (`systemName: "eye"`, `isActive: state.previewingOriginal`), help/label
  "Preview Original". Disabled when `!state.canReset` (nothing differs to show);
  if a preview is active and `canReset` flips false, force the toggle off.

## Files touched

| File | Change |
|------|--------|
| `Editor/EditorState.swift` | `originalDocument`, `previewingOriginal`, `displayDocument`, `canReset`; capture in init |
| `Editor/Document/EditorDocument.swift` | `Equatable` (version-excluded) |
| `Editor/Document/EditorCommand.swift` (or sibling) | `ResetDocumentCommand` |
| `Editor/Canvas/CanvasCoordinator.swift` | render `state.displayDocument` |
| `Editor/Tools/ToolPaletteView.swift` (`DockView`) | history sub-section: reset + preview buttons, sub-separator, confirm dialog state, input gating |

## Out of scope

- No separate per-edit reset (e.g. "reset padding only").
- No persisting original across app restart / file reload beyond the live session.
- No change to export pipeline (`DocumentRenderer`) — it already renders whatever
  document it's handed.
