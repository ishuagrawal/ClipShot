# Resizable Annotations — Design

**Date:** 2026-06-19
**Goal:** Every annotation (arrow, line, rect, blur, text) can be resized after creation by dragging handles on the selected annotation.

## Background

Annotations are immutable `struct Annotation { id; kind }` where `kind` is the
`Annotation.Kind` enum (`arrow`, `line`, `rect`, `text`, `blur`). All geometry
is in selection-relative pixel coordinates (top-left origin, y-down), anchored
at `EditorDocument.baseSelection`. Zoom is applied via CALayer transforms, not
coordinate conversion.

Existing post-creation editing already works:

- **Select** — `EditorState.selectedAnnotationID`, hit-test via
  `AnnotationGeometry.hitTest`.
- **Move** — `beginMoveSelected` → `moveSelected(by:)` → `commitMoveSelected()`,
  driven from `CanvasInteractionView` mouse events, committed as
  `MoveAnnotationCommand(id, from, to)` (undoable, swaps `kind`).
- **Delete / keyboard nudge / style edit** — present.

**Missing:** resize. No handles, no edge/endpoint dragging.

## Decisions

- **Text resize** = scale `fontSize` (corner drag), not reflow.
- **Rect/blur** = 8 handles (4 corners + 4 edge mids); **Shift locks aspect**.
- **Arrow/line** = 2 endpoint handles.
- **Min size** = clamp at ~6px; never flip through.
- **Cursors** = custom diagonal NWSE/NESW NSCursor images for corners.

## Architecture

Resize is a new gesture flow that **mirrors the existing move flow**. It reuses
`MoveAnnotationCommand` for undo (the command already just swaps `kind`
from→to). No new command type.

Three layers change:

1. `AnnotationGeometry` — pure handle geometry (positions + resized kind).
2. `EditorState` — resize gesture lifecycle (begin/update/commit).
3. `CanvasInteractionView` + `CanvasOverlayView` — hit-testing, rendering,
   cursors.

### 1. AnnotationGeometry (pure geometry, no UI)

New handle identity:

```swift
enum ResizeHandle {
    case start, end                                              // arrow / line
    case topLeft, top, topRight, right,
         bottomRight, bottom, bottomLeft, left                   // rect / blur
    case scaleTopLeft, scaleTopRight, scaleBottomLeft, scaleBottomRight // text
}
```

New functions:

- `resizeHandles(_ kind: Annotation.Kind) -> [(handle: ResizeHandle, point: CGPoint)]`
  Returns handle anchor points in annotation coordinates.
  - arrow / line → `[(.start, from), (.end, to)]`
  - rect / blur → 8 points on the standardized frame
  - text → 4 corners of `textFrame(...)`
  - blur uses the same 8-handle scheme as rect.

- `resized(_ kind:, handle:, to point:, shiftLock: Bool, bounds: CGRect) -> Annotation.Kind`
  Pure: produces the new kind for a handle dragged to `point`.

**Rect / blur rules**

- Corner handle: that corner follows `point`; the opposite corner is the fixed
  anchor. Edge handle: only that edge's coordinate moves; the opposite edge is
  fixed.
- Min size: clamp width/height to ≥ 6px measured from the anchor — the dragged
  edge cannot cross the anchor (no flip).
- `shiftLock` (corners only): scale uniformly from the opposite corner so aspect
  ratio is preserved. Edge handles ignore `shiftLock`.
- Result frame clamped inside `bounds` (corner/edge that would leave the canvas
  is pinned to the border).

**Arrow / line rules**

- `.start` sets `from = point`; `.end` sets `to = point`. Other endpoint fixed.
- `shiftLock` applies the existing `snap45` (private → promote/duplicate into the
  geometry helper). Without shift, apply `snapNearAxis` so a near-axis segment
  straightens, matching creation behavior. (These two snap helpers currently live
  in `EditorState`; move the snap math the resize path needs into
  `AnnotationGeometry` so both creation and resize share one implementation.)
- The moved endpoint is clamped to `bounds`.

**Text rules**

- Anchor = the corner opposite the dragged corner.
- New `fontSize = oldFontSize * (newDistanceToAnchor / oldDistanceToAnchor)`,
  where distance is measured corner-to-anchor along the box diagonal.
- Recompute `origin` so the anchor corner stays fixed after the font size change
  (re-measure `textFrame` at the new size).
- Clamp `fontSize` to `[8, 400]`. Origin clamped so the box stays in `bounds`.

### 2. EditorState (gesture lifecycle, mirrors move)

New state:

```swift
private var resizeStartKind: Annotation.Kind?
private(set) var activeResizeHandle: ResizeHandle?
```

New methods:

- `beginResize(handle: ResizeHandle)` — store `resizeStartKind = selectedAnnotation.kind`,
  `activeResizeHandle = handle`.
- `resizeSelected(to point: CGPoint, shiftLock: Bool)` — live update:
  `document.annotations[i].kind = AnnotationGeometry.resized(resizeStartKind, handle:, to: point, shiftLock:, bounds: documentBounds)`.
- `commitResizeSelected()` — if changed, restore start then
  `performCommand(MoveAnnotationCommand(id, from: start, to: end, coalescingKey: .resize))`;
  clear `resizeStartKind` / `activeResizeHandle`.

Add `.resize` to `AnnotationEditCoalescingKey`.

### 3. CanvasInteractionView (input)

New fields: `activeResizeHandle: ResizeHandle?`, `resizeStartPoint: CGPoint?`.

`mouseDown` (select/padding/background tools), priority order:

1. **Handle hit** — if an annotation is selected, test the click against its
   handle anchors in **screen space** with a fixed ~10px target (zoom-
   independent). Hit → `state.beginResize(handle:)`, set local resize fields,
   return.
2. **Body move** — existing `annotationInteractionTarget` → `beginMove`.
3. **Select other** — handled inside `selectableAnnotation`.
4. **Deselect** — `state.deselect()`.

`mouseDragged` — if `activeResizeHandle != nil`, call
`state.resizeSelected(to: point, shiftLock: shift)`. (Move and draw branches
unchanged.)

`mouseUp` — if resizing, `state.commitResizeSelected()`; clear resize fields.

Cursor rects: add per-handle rects for the selected annotation mapping each
handle to its resize cursor (see below).

### 4. CanvasOverlayView (rendering)

In `configure(...)`, the `selected` branch keeps the dashed halo and **adds a
small filled square (~8px on screen) at each handle position** from
`resizeHandles`. Handles use the accent color with a white inner fill for
contrast.

**Zoom constraint:** handles must stay a constant screen size regardless of
zoom. The content layer is scaled by the zoom transform, so handle squares
drawn in annotation coordinates would scale with it. Counter-scale handle size
by the current zoom factor (divide handle px size by scale), or place handles in
a sibling layer that does not inherit the zoom transform. Implementation picks
whichever is cleaner given how the overlay reads the current scale.

### 5. Cursors

Custom `NSCursor` images for the two diagonal directions (NWSE for
TL/BR corners, NESW for TR/BL corners). Edge handles use built-in
`.resizeUpDown` (top/bottom) and `.resizeLeftRight` (left/right). Arrow/line
endpoints and text corners use the diagonal cursors.

## Data Flow (resize gesture)

```
mouseDown on handle
  → CanvasInteractionView.beginResize → EditorState.beginResize(handle)
       (stores resizeStartKind, activeResizeHandle)
mouseDragged
  → EditorState.resizeSelected(to:, shiftLock:)
       → AnnotationGeometry.resized(...) → live kind, clamped to documentBounds
mouseUp
  → EditorState.commitResizeSelected()
       → MoveAnnotationCommand(from: start, to: end)  [undoable]
```

## Error / Edge Handling

- **Degenerate resize:** min-size clamp in `resized()` prevents zero/negative
  size and flipping.
- **Out of bounds:** result clamped to `documentBounds`, same policy as move.
- **No-op resize:** `commitResizeSelected` skips the command if `end == start`.
- **Selection invalidated mid-gesture:** guarded by index/id lookups, same as
  move.
- **Undo:** one `MoveAnnotationCommand` per resize gesture; `.resize` coalescing
  key keeps a single drag from fragmenting.

## Testing

Unit (pure, no UI) on `AnnotationGeometry.resized`:

- Rect corner drag resizes correct corner, opposite fixed.
- Rect edge drag moves one axis only.
- Shift on rect corner preserves aspect ratio.
- Min-size clamp: dragging past the anchor stops at 6px, no flip.
- Bounds clamp: handle dragged outside canvas is pinned.
- Arrow/line endpoint moves the right end; shift snaps to 45°; near-axis snaps.
- Text corner scales fontSize by distance ratio; opposite corner stays fixed;
  fontSize clamped to [8, 400].
- `resizeHandles` returns the expected count per kind (2 / 8 / 8 / 4).

Manual: select each annotation type, drag every handle, confirm live preview,
commit, undo restores the pre-resize kind, redo reapplies. Confirm handle hit
target and rendering are zoom-independent.

## Out of Scope

- Multi-select resize.
- Rotation handles.
- Text reflow / wrapping width (text resize is font scaling only).
- Flip-through-resize.
