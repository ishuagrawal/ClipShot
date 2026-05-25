# ClipShot

ClipShot is a native macOS screenshot utility prototype for capturing UI components.

The current web MVP uses a Chrome/Arc extension for DOM-based detection and the
macOS app as a local clipboard bridge. The older Accessibility-based flow remains
as a native fallback.

## Web DOM Loop

1. Launch ClipShot.
2. Load `BrowserExtension/` as an unpacked Chrome/Arc extension.
3. In a web page, press the extension command `Control + Shift + 5` or click the extension action.
4. Hover a web component.
5. ClipShot shows all DOM candidate boxes inside the component under the cursor.
6. Press `Tab` to cycle into nested candidates.
7. Click or press `Enter` to crop the selected DOM box and copy it as PNG.
8. Press `Escape` to cancel.

This path crops from `chrome.tabs.captureVisibleTab()` and posts the cropped PNG
to the native app at `127.0.0.1:17272`, so it does not need Accessibility
permission or browser-window coordinate conversion.

## Native Fallback Loop

1. Grant Screen Recording and Accessibility permissions from the menu bar popover.
2. Press `Control + Option + Command + 5`.
3. Hover a UI element.
4. Press `Tab` to cycle nested Accessibility candidates.
5. Click or press `Enter` to copy the selected crop to the clipboard.
6. Press `Escape` to cancel.

## Notes

- Web detection is DOM-first through the browser extension.
- Native fallback detection still uses Accessibility frames.
- Cropping writes PNG data to `NSPasteboard`.
- Manual drag crop, OCR, ML detection, screenshot editing, history, and distribution are intentionally deferred.

## Local Development

Use `Scripts/build-install-run.sh` for local rebuilds. It builds the Xcode app,
re-signs the installed bundle with a stable local designated requirement, copies
it to `/Applications/ClipShot.app`, and reopens it.

If macOS shows ClipShot as enabled in Privacy & Security but the app still sees
permissions as missing, run `Scripts/reset-permissions.sh`, reopen ClipShot, and
grant Accessibility and Screen Recording again.
