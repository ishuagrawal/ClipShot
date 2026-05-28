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
6. Click or press `Enter` to crop that box and copy it as PNG.

The extension captures the visible tab, crops the selected DOM rectangle in the
page, and posts the PNG to the local ClipShot app at
`127.0.0.1:17272/clipboard`. The macOS app only writes that PNG to
`NSPasteboard`.

No Accessibility or Screen Recording permissions are required for this flow.

## Local Development

Use `Scripts/build-install-run.sh` for local rebuilds. It builds the Xcode app,
re-signs the installed bundle with a stable local designated requirement, copies
it to `/Applications/ClipShot.app`, and reopens it.
