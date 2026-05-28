# ClipShot DOM Selector

This unpacked Chrome/Arc extension handles web-page component detection for
ClipShot.

## Load in Arc or Chrome

1. Open `chrome://extensions` or `arc://extensions`.
2. Enable Developer Mode.
3. Choose Load unpacked.
4. Select the `BrowserExtension` folder from your local ClipShot checkout.

## Use

1. Keep `/Applications/ClipShot.app` running.
2. Open a normal web page.
3. Press `Control + Shift + 5`, or click the ClipShot extension action.
4. Move across the page to change the selected component.
5. The selected area is highlighted in blue.
6. Colored arrow chips show available navigation: up for parent, down for first child, and left/right for siblings.
7. Matching colored outlines appear on those destination boxes so you can see where each arrow key will move before pressing it.
8. Click any chip to jump to that destination, or use the arrow keys.
9. Hold `Space` to isolate the selected area and temporarily hide neighboring boxes; release `Space` to return.
10. Hold `Option` while pressing an arrow key to preview only that destination in the matching direction color; release `Option` to return.
11. Click or press `Enter` to open the selected region in the ClipShot editor.
12. Press `Escape` to cancel.

The extension captures the current visible tab and sends the viewport image plus
the selected DOM bounds to the native ClipShot app on `127.0.0.1:17272/session`.
