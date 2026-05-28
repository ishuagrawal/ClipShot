# ClipShot

Native macOS screenshot utility for clipping and editing precise web-page components.

ClipShot is a native macOS menu bar companion for the ClipShot browser
extension.

The current MVP is DOM-only:

1. Launch ClipShot.
2. Load `BrowserExtension/` as an unpacked Chrome/Arc extension.
3. In a web page, press the extension command `Control + Shift + 5` or click the
   extension action.
4. Hover a web component.
5. Select the DOM box you want to capture.
6. Click or press `Enter` to open that box in the desktop editor.

The extension captures the visible tab and posts the full viewport PNG plus the
selected DOM rectangle to the local ClipShot app at `127.0.0.1:17272/session`.
The macOS app displays the page image with the selected region overlaid, then
can crop/copy or export from that full screenshot.

No Accessibility or Screen Recording permissions are required for this flow.

## Local Development

Use `Scripts/build-install-run.sh` for local rebuilds. It builds the Xcode app,
re-signs the installed bundle with a stable local designated requirement, copies
it to `/Applications/ClipShot.app`, and reopens it.
