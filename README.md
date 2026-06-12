# ClipShot

Native macOS screenshot utility for clipping and editing precise UI components.

ClipShot lives in the menu bar:

1. Launch ClipShot.
2. Press `Control + Shift + 5`.
3. Drag an exact region, or click to pick a window or component boundary.
4. The capture opens in the desktop editor, where you can pad, frame,
   annotate, and export it.

## Local Development

Use `Scripts/build-install-run.sh` for local rebuilds. It builds the Xcode app,
re-signs the installed bundle with a stable local designated requirement, copies
it to `/Applications/ClipShot.app`, and reopens it.
