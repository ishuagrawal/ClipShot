# Line Annotation Tool — Design

## Goal

Add a new annotation tool, **Line**, supporting color, weight, and dash
style (solid / dashed / dotted). Primary use case: underlining text. A line is
an arrow without arrowheads, plus a dash pattern.

## Data Model

`ClipShot/Editor/Document/Annotation.swift`

Add a dash style enum and a new `Kind` case:

```swift
enum LineDash: Equatable { case solid, dashed, dotted }

case line(from: CGPoint, to: CGPoint, color: CGColor, weight: CGFloat, dash: LineDash)
```

Line geometry mirrors `arrow` (a single segment) with no arrowhead and an added
`dash` attribute.

## Tool Enum & Defaults

`ClipShot/Editor/EditorState.swift`

- Add `case line` to `EditorTool`.
- Add defaults to `ToolStyle`: `lineColor`, `lineWeight`, `lineDash`.

## Draw Behavior

`beginDraw` / `updateDraw` in `EditorState.swift`:

- `beginDraw`: construct `.line(from: point, to: point, color: toolStyle.lineColor,
  weight: toolStyle.lineWeight, dash: toolStyle.lineDash)`.
- `updateDraw`: **auto-snap** — if the segment angle is within ~7° of horizontal
  or vertical, lock the endpoint to that axis automatically (no Shift required).
  Holding Shift forces 45° snapping via the existing `snap45(from:to:)` helper
  (Shift takes precedence over auto-snap). Clamp endpoint to `documentBounds` as
  arrow does.
- `commitDraw`: degenerate (zero-length) lines are discarded, same as arrow.

## Geometry & Hit Testing

`ClipShot/Editor/Document/AnnotationGeometry.swift`

- Hit test: point-to-segment distance against `from`–`to`, padded by weight —
  identical to arrow's segment test (arrow = segment + head; line = segment only).
- Bounds: standardized bounding box of the `from`–`to` segment.

## Rendering

Preview — `ClipShot/Editor/Canvas/CanvasOverlayView.swift`
Export — `ClipShot/Editor/Export/DocumentRenderer.swift`

Stroke the `from`–`to` segment (CAShapeLayer for preview, CGContext path for
export). No arrowhead. Map dash → stroke pattern:

- `solid`: no dash pattern, butt cap.
- `dashed`: dash pattern `[weight*3, weight*2]`, butt cap.
- `dotted`: **round-cap dots** — dash pattern `[weight*0.01, weight*2]` with
  round line cap, producing circular dots spaced by `weight*2`.

Use the same color/weight conventions already used by the arrow renderer in each
file.

## UI

- New inspector `ClipShot/Editor/Tools/LineToolView.swift`: color well
  (`GlassColorWell`), weight slider (`1...18`), and a dash segmented control
  (solid / dashed / dotted). Follow `ArrowToolView` layout.
- Route it in `ClipShot/Editor/Tools/ToolSidebarView.swift` tool-defaults card.
- Add the tool to `ClipShot/Editor/Tools/ToolPaletteView.swift` tools list:
  shortcut **L**, SF Symbol `line.diagonal`.

## Tests

- `AnnotationGeometryTests`: line hit-test (on/off segment) and bounds.
- `AnnotationStateTests`: `beginDraw` with `.line` active produces a line kind;
  auto-snap locks near-horizontal/near-vertical endpoints; Shift forces 45°.
- `AnnotationCommandTests`: add/remove/move a line annotation round-trips.

## Out of Scope

- Line cap selection UI (cap is implied by dash style).
- Arrowhead options on lines.
- Migrating arrow into the line type.
