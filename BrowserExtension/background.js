const FORBIDDEN_URL_PREFIXES = [
  "chrome://",
  "chrome-extension://",
  "edge://",
  "arc://",
  "about:"
];

// High-resolution capture via the DevTools protocol. captureVisibleTab only renders
// at the display's devicePixelRatio, so a small component crops out of too few pixels
// and looks blurry when zoomed. Page.captureScreenshot lets us re-rasterize at a
// larger scale, so the selection carries real detail instead of an upscaled bitmap.
const DEBUGGER_PROTOCOL_VERSION = "1.3";
// Aim for the selected element's short side to reach roughly this many device pixels.
const TARGET_MIN_PX = 1200;
// Hard cap on the resolution multiplier so giant scales never get requested.
const MAX_SCALE = 6;
// Cap the captured image's long side to stay within GPU / CDP screenshot limits.
const MAX_OUTPUT_DIM = 8192;

chrome.action.onClicked.addListener((tab) => {
  void startDOMCapture(tab);
});

chrome.commands.onCommand.addListener((command) => {
  if (command !== "start-dom-capture") {
    return;
  }

  void getActiveTab().then((tab) => startDOMCapture(tab));
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "CLIPSHOT_DOM_CONFIRM") {
    return false;
  }

  void captureScreenshot(sender, message.rect, message.session)
    .then((dataUrl) => {
      if (!sender.tab?.id) {
        throw new Error("No active tab for DOM capture.");
      }

      return chrome.tabs.sendMessage(sender.tab.id, {
        type: "CLIPSHOT_VISIBLE_TAB_CAPTURED",
        dataUrl,
        rect: message.rect,
        session: message.session,
        tab: {
          title: sender.tab.title || "",
          url: sender.tab.url || ""
        }
      });
    })
    .then((response) => {
      sendResponse(response ?? { ok: true });
    })
    .catch((error) => {
      sendResponse({ ok: false, message: error.message });
    });

  return true;
});

async function getActiveTab() {
  const tabs = await chrome.tabs.query({
    active: true,
    currentWindow: true
  });
  return tabs[0];
}

async function startDOMCapture(tab) {
  if (!tab?.id || isForbiddenURL(tab.url)) {
    return;
  }

  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    files: ["content.js"]
  });
}

async function captureScreenshot(sender, rect, session) {
  const tab = sender.tab;
  if (!tab?.id || !tab?.windowId || !rect) {
    throw new Error("Missing tab capture context.");
  }

  try {
    return await captureHighRes(tab.id, rect, session?.viewport);
  } catch (error) {
    // Attaching the debugger can fail: another client (open DevTools) already owns
    // the tab, the page is restricted, or the user blocked it. Fall back to the
    // standard visible-tab capture so the flow still produces an image.
    console.warn("ClipShot high-res capture unavailable, using visible-tab fallback:", error?.message || error);
    return chrome.tabs.captureVisibleTab(tab.windowId, { format: "png" });
  }
}

async function captureHighRes(tabId, rect, viewport) {
  if (!viewport || !(viewport.width > 0) || !(viewport.height > 0)) {
    throw new Error("Missing viewport metrics for high-res capture.");
  }

  const scale = adaptiveScale(rect, viewport);
  const target = { tabId };
  await chrome.debugger.attach(target, DEBUGGER_PROTOCOL_VERSION);

  try {
    await chrome.debugger.sendCommand(target, "Page.enable");
    // captureBeyondViewport:false keeps the clip viewport-relative (origin at the
    // visible top-left), so fixed/sticky elements render in place and the selection
    // rect — reported in viewport CSS px — maps onto the image as rect * scale.
    const result = await chrome.debugger.sendCommand(target, "Page.captureScreenshot", {
      format: "png",
      captureBeyondViewport: false,
      clip: {
        x: 0,
        y: 0,
        width: viewport.width,
        height: viewport.height,
        scale
      }
    });

    if (!result?.data) {
      throw new Error("Empty screenshot from debugger.");
    }

    return `data:image/png;base64,${result.data}`;
  } finally {
    // Always tear down so the "ClipShot started debugging this browser" banner clears.
    try { await chrome.debugger.sendCommand(target, "Page.disable"); } catch (_) {}
    try { await chrome.debugger.detach(target); } catch (_) {}
  }
}

// Pick a scale so a small selection gains real pixels while large selections stay
// near native. Never below the display DPR (so it's never worse than captureVisibleTab),
// never above MAX_SCALE, and clamped so the output's long side stays within MAX_OUTPUT_DIM.
function adaptiveScale(rect, viewport) {
  const dpr = viewport.devicePixelRatio || 1;
  const baseline = Math.max(1, dpr);
  const shortSide = Math.max(1, Math.min(rect.width, rect.height));
  const desired = TARGET_MIN_PX / shortSide;

  let scale = Math.min(MAX_SCALE, Math.max(baseline, desired));

  const longSide = Math.max(1, viewport.width, viewport.height);
  const dimCap = MAX_OUTPUT_DIM / longSide;
  // Honor the dimension cap, but never drop below baseline (a normal capture is
  // already that size) even if baseline itself exceeds the cap.
  scale = Math.min(scale, Math.max(baseline, dimCap));

  return Math.max(1, scale);
}

function isForbiddenURL(url = "") {
  return FORBIDDEN_URL_PREFIXES.some((prefix) => url.startsWith(prefix));
}
