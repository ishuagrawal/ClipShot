const FORBIDDEN_URL_PREFIXES = [
  "chrome://",
  "chrome-extension://",
  "edge://",
  "arc://",
  "about:"
];

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

  void captureVisibleTab(sender, message.rect)
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

async function captureVisibleTab(sender, rect) {
  if (!sender.tab?.windowId || !rect) {
    throw new Error("Missing tab capture context.");
  }

  return chrome.tabs.captureVisibleTab(sender.tab.windowId, {
    format: "png"
  });
}

function isForbiddenURL(url = "") {
  return FORBIDDEN_URL_PREFIXES.some((prefix) => url.startsWith(prefix));
}
