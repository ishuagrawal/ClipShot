(() => {
  const previousSelector = window.__clipshotDOMSelector;
  if (previousSelector) {
    if (typeof previousSelector.destroy === "function") {
      previousSelector.destroy();
    } else if (typeof previousSelector.stop === "function") {
      previousSelector.stop();
    }
  }
  document.getElementById("clipshot-dom-selector-host")?.remove();

  const BRIDGE_URL = "http://127.0.0.1:17272/clipboard";
  const MAX_CANDIDATES = 48;
  const MAX_PREVIEW_BOXES = 8;
  const MAX_SCAN_ELEMENTS = 1600;
  const MIN_BOX_WIDTH = 10;
  const MIN_BOX_HEIGHT = 10;
  const MIN_USEFUL_BOX_WIDTH = 24;
  const MIN_USEFUL_BOX_AREA = 360;

  const SKIPPED_TAGS = new Set([
    "AREA",
    "BASE",
    "BR",
    "HEAD",
    "HTML",
    "LINK",
    "META",
    "NOSCRIPT",
    "SCRIPT",
    "SOURCE",
    "STYLE",
    "TEMPLATE",
    "TITLE"
  ]);

  const SEMANTIC_TAGS = new Set([
    "A",
    "ARTICLE",
    "ASIDE",
    "BUTTON",
    "DETAILS",
    "DIALOG",
    "FIELDSET",
    "FIGURE",
    "FOOTER",
    "FORM",
    "HEADER",
    "IMG",
    "INPUT",
    "LI",
    "MAIN",
    "NAV",
    "SECTION",
    "SELECT",
    "SUMMARY",
    "TEXTAREA"
  ]);

  const SEMANTIC_ROLES = new Set([
    "article",
    "banner",
    "button",
    "cell",
    "checkbox",
    "dialog",
    "feed",
    "form",
    "grid",
    "gridcell",
    "group",
    "heading",
    "img",
    "link",
    "list",
    "listbox",
    "listitem",
    "main",
    "menu",
    "menuitem",
    "navigation",
    "option",
    "region",
    "row",
    "search",
    "switch",
    "tab",
    "table",
    "textbox"
  ]);

  const COMPONENT_NAME_PATTERN =
    /(article|body|card|caption|cell|comment|compose|content|container|description|dialog|entry|feed|figure|item|message|modal|panel|photo|post|product|renderer|result|section|story|table|thread|tile|timeline|tweet|video)/i;

  const CAPTURE_NAME_PATTERN =
    /(article|body|card|caption|chart|code|comment|content|description|dialog|figure|image|img|media|message|modal|panel|photo|post|pre|product|quote|section|snippet|table|thread|tile|tweet|video)/i;

  const UTILITY_NAME_PATTERN =
    /(action|avatar|badge|button|caret|chevron|control|dislike|dropdown|expand|handle|icon|like|menu|more|option|overflow|reaction|reply|share|subscribe|timestamp|toggle|tooltip)/i;

  const UTILITY_TEXT_PATTERN =
    /^(\d+\s+)?(more|show more|read more|less|show less|reply|replies|like|dislike|share|save|subscribe|menu|options|\.{3}|…|…more)$/i;

  const DIRECTION_GLYPHS = { up: "↑", down: "↓", left: "←", right: "→" };

  let active = false;
  let rootElement = null;
  let candidates = [];
  let selectedIndex = 0;
  let previewIndex = -1;
  let previewDirection = null;
  let lastPointer = null;
  let overlayHost = null;
  let shadowRoot = null;
  let boxesLayer = null;
  let chipsLayer = null;
  let ghostsLayer = null;
  let hintElement = null;
  const placedChipRects = [];

  const messageListener = (message, _sender, sendResponse) => {
    if (message?.type !== "CLIPSHOT_VISIBLE_TAB_CAPTURED") {
      return false;
    }

    void cropAndCopy(message.dataUrl, message.rect)
      .then(() => sendResponse({ ok: true }))
      .catch((error) => {
        showError(error.message);
        sendResponse({ ok: false, message: error.message });
      });

    return true;
  };

  const api = {
    version: "overlay-navigation-v2",
    start,
    stop,
    destroy,
    inspect
  };

  window.__clipshotDOMSelector = api;
  chrome.runtime.onMessage.addListener(messageListener);

  start();

  function start() {
    if (active) {
      return;
    }

    active = true;
    rootElement = null;
    candidates = [];
    selectedIndex = 0;
    previewIndex = -1;
    previewDirection = null;
    ensureOverlay();
    overlayHost.style.display = "block";
    showDefaultHint();

    window.addEventListener("mousemove", handleMouseMove, true);
    window.addEventListener("keydown", handleKeyDown, true);
    window.addEventListener("keyup", handleKeyUp, true);
    window.addEventListener("mousedown", swallowPointerEvent, true);
    window.addEventListener("mouseup", handleMouseUp, true);
    window.addEventListener("click", swallowPointerEvent, true);
    window.addEventListener("scroll", refreshFromLastPointer, true);
    window.addEventListener("resize", refreshFromLastPointer, true);

    const x = Math.min(Math.max(window.innerWidth / 2, 0), window.innerWidth - 1);
    const y = Math.min(Math.max(window.innerHeight / 2, 0), window.innerHeight - 1);
    updateSelectionAt(x, y, true);
  }

  function stop() {
    if (!active) {
      return;
    }

    active = false;
    rootElement = null;
    candidates = [];
    selectedIndex = 0;
    previewIndex = -1;
    previewDirection = null;
    lastPointer = null;
    render();

    window.removeEventListener("mousemove", handleMouseMove, true);
    window.removeEventListener("keydown", handleKeyDown, true);
    window.removeEventListener("keyup", handleKeyUp, true);
    window.removeEventListener("mousedown", swallowPointerEvent, true);
    window.removeEventListener("mouseup", handleMouseUp, true);
    window.removeEventListener("click", swallowPointerEvent, true);
    window.removeEventListener("scroll", refreshFromLastPointer, true);
    window.removeEventListener("resize", refreshFromLastPointer, true);

    if (overlayHost) {
      overlayHost.style.display = "none";
    }
  }

  function destroy() {
    stop();
    chrome.runtime.onMessage.removeListener(messageListener);
    overlayHost?.remove();
    overlayHost = null;
    shadowRoot = null;
    boxesLayer = null;
    ghostsLayer = null;
    chipsLayer = null;
    hintElement = null;

    if (window.__clipshotDOMSelector === api) {
      delete window.__clipshotDOMSelector;
    }
  }

  function ensureOverlay() {
    if (overlayHost?.isConnected) {
      return;
    }

    overlayHost = document.createElement("clipshot-dom-overlay");
    overlayHost.id = "clipshot-dom-selector-host";
    overlayHost.style.position = "fixed";
    overlayHost.style.inset = "0";
    overlayHost.style.zIndex = "2147483647";
    overlayHost.style.pointerEvents = "none";
    overlayHost.style.display = "none";

    shadowRoot = overlayHost.attachShadow({ mode: "open" });
    shadowRoot.innerHTML = `
      <style>
        :host {
          all: initial;
        }

        .shade {
          position: fixed;
          inset: 0;
          background: rgba(5, 10, 18, 0.14);
          z-index: 0;
        }

        .ghosts,
        .boxes,
        .chips {
          position: fixed;
          inset: 0;
        }

        .boxes {
          z-index: 2;
        }

        .ghosts {
          z-index: 3;
          pointer-events: none;
        }

        .chips {
          z-index: 5;
          pointer-events: none;
        }

        .ghost {
          position: fixed;
          top: 0;
          left: 0;
          box-sizing: border-box;
          border-radius: 7px;
          pointer-events: none;
          border-width: 2.5px;
          border-style: solid;
        }

        .ghost.up {
          color: rgb(232, 152, 128);
          border-color: currentColor;
          box-shadow: 0 0 0 1px rgba(232, 152, 128, 0.35), inset 0 0 0 1px rgba(0, 0, 0, 0.35);
        }

        .ghost.down {
          color: rgb(240, 178, 70);
          border-color: currentColor;
          box-shadow: 0 0 0 1px rgba(240, 178, 70, 0.35), inset 0 0 0 1px rgba(0, 0, 0, 0.35);
        }

        .ghost.left {
          color: rgb(195, 145, 220);
          border-color: currentColor;
          box-shadow: 0 0 0 1px rgba(195, 145, 220, 0.35), inset 0 0 0 1px rgba(0, 0, 0, 0.35);
        }

        .ghost.right {
          color: rgb(150, 195, 125);
          border-color: currentColor;
          box-shadow: 0 0 0 1px rgba(150, 195, 125, 0.35), inset 0 0 0 1px rgba(0, 0, 0, 0.35);
        }


        .box {
          position: fixed;
          top: 0;
          left: 0;
          box-sizing: border-box;
          border: 0;
          background: transparent;
          border-radius: 6px;
          opacity: 1;
          pointer-events: none;
        }

        .box.selected {
          z-index: 2;
          border: 3.5px solid #1297ff;
          outline: 3px solid rgba(255, 255, 255, 0.96);
          outline-offset: 1px;
          background: rgba(18, 151, 255, 0.16);
          box-shadow:
            0 0 0 8px rgba(18, 151, 255, 0.32),
            0 0 0 1px rgba(0, 32, 96, 0.55),
            inset 0 0 0 1.5px rgba(255, 255, 255, 0.7),
            0 14px 36px rgba(0, 74, 173, 0.4);
        }

        .box.selected::before {
          content: "";
          position: absolute;
          inset: -8px;
          border-radius: 9px;
          pointer-events: none;
          background:
            linear-gradient(#7cc7ff, #7cc7ff) top left / 18px 3px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) top left / 3px 18px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) top right / 18px 3px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) top right / 3px 18px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) bottom left / 18px 3px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) bottom left / 3px 18px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) bottom right / 18px 3px no-repeat,
            linear-gradient(#7cc7ff, #7cc7ff) bottom right / 3px 18px no-repeat;
        }

        .box.preview-selection {
          z-index: 4;
          --preview-color: rgba(255, 230, 128, 0.98);
          --preview-fill: rgba(255, 230, 128, 0.18);
          --preview-glow: rgba(255, 230, 128, 0.22);
          border: 3px solid var(--preview-color);
          outline: 3px solid rgba(16, 22, 32, 0.86);
          outline-offset: 2px;
          background: var(--preview-fill);
          box-shadow:
            0 0 0 8px var(--preview-glow),
            0 16px 38px rgba(0, 0, 0, 0.32),
            inset 0 0 0 1.5px rgba(255, 255, 255, 0.72);
        }

        .box.preview-selection.up {
          --preview-color: rgb(232, 152, 128);
          --preview-fill: rgba(232, 152, 128, 0.18);
          --preview-glow: rgba(232, 152, 128, 0.24);
        }

        .box.preview-selection.down {
          --preview-color: rgb(240, 178, 70);
          --preview-fill: rgba(240, 178, 70, 0.18);
          --preview-glow: rgba(240, 178, 70, 0.24);
        }

        .box.preview-selection.left {
          --preview-color: rgb(195, 145, 220);
          --preview-fill: rgba(195, 145, 220, 0.18);
          --preview-glow: rgba(195, 145, 220, 0.24);
        }

        .box.preview-selection.right {
          --preview-color: rgb(150, 195, 125);
          --preview-fill: rgba(150, 195, 125, 0.18);
          --preview-glow: rgba(150, 195, 125, 0.24);
        }

        .chip {
          position: fixed;
          top: 0;
          left: 0;
          width: 34px;
          height: 34px;
          box-sizing: border-box;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          border-radius: 8px;
          background: rgba(20, 26, 36, 0.42);
          -webkit-backdrop-filter: blur(22px) saturate(180%);
          backdrop-filter: blur(22px) saturate(180%);
          border: 1.5px solid rgba(255, 255, 255, 0.2);
          border-bottom-width: 2.5px;
          box-shadow:
            0 8px 22px rgba(0, 0, 0, 0.4),
            0 1px 3px rgba(0, 0, 0, 0.3),
            inset 0 1px 0 rgba(255, 255, 255, 0.1);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 17px;
          font-weight: 700;
          line-height: 1;
          color: white;
          text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
          pointer-events: auto;
          cursor: pointer;
          transition: filter 110ms ease, transform 110ms ease;
          z-index: 3;
        }

        .chip:hover {
          filter: brightness(1.22);
          transform: scale(1.08);
        }

        .chip.up {
          background: rgb(232, 152, 128);
          border-color: rgba(232, 152, 128, 0.9);
          border-bottom-color: rgba(120, 50, 30, 0.95);
          color: rgb(60, 22, 12);
          text-shadow: 0 1px 1px rgba(255, 255, 255, 0.25);
          -webkit-backdrop-filter: none;
          backdrop-filter: none;
        }

        .chip.down {
          background: rgb(240, 178, 70);
          border-color: rgba(240, 178, 70, 0.92);
          border-bottom-color: rgba(112, 62, 10, 0.95);
          color: rgb(58, 32, 6);
          text-shadow: 0 1px 1px rgba(255, 255, 255, 0.25);
          -webkit-backdrop-filter: none;
          backdrop-filter: none;
        }

        .chip.left {
          background: rgb(195, 145, 220);
          border-color: rgba(195, 145, 220, 0.9);
          border-bottom-color: rgba(80, 40, 110, 0.95);
          color: rgb(50, 22, 70);
          text-shadow: 0 1px 1px rgba(255, 255, 255, 0.25);
          -webkit-backdrop-filter: none;
          backdrop-filter: none;
        }

        .chip.right {
          background: rgb(150, 195, 125);
          border-color: rgba(150, 195, 125, 0.9);
          border-bottom-color: rgba(50, 90, 30, 0.95);
          color: rgb(24, 50, 12);
          text-shadow: 0 1px 1px rgba(255, 255, 255, 0.25);
          -webkit-backdrop-filter: none;
          backdrop-filter: none;
        }

        .hint {
          position: fixed;
          left: 50%;
          top: 18px;
          transform: translateX(-50%);
          max-width: min(520px, calc(100vw - 24px));
          box-sizing: border-box;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 12px;
          font-weight: 500;
          letter-spacing: 0.02em;
          line-height: 16px;
          color: rgba(226, 232, 240, 0.9);
          background: rgba(16, 22, 32, 0.85);
          -webkit-backdrop-filter: blur(14px) saturate(180%);
          backdrop-filter: blur(14px) saturate(180%);
          border: 1px solid rgba(255, 255, 255, 0.1);
          border-radius: 999px;
          box-shadow: 0 6px 18px rgba(0, 0, 0, 0.28);
          padding: 6px 14px;
          pointer-events: none;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

      </style>
      <div class="shade"></div>
      <div class="ghosts"></div>
      <div class="boxes"></div>
      <div class="chips"></div>
      <div class="hint" hidden></div>
    `;

    boxesLayer = shadowRoot.querySelector(".boxes");
    ghostsLayer = shadowRoot.querySelector(".ghosts");
    chipsLayer = shadowRoot.querySelector(".chips");
    hintElement = shadowRoot.querySelector(".hint");
    document.documentElement.appendChild(overlayHost);
  }

  function handleMouseMove(event) {
    if (!active) {
      return;
    }

    if (isOverlayEvent(event)) {
      return;
    }

    updateSelectionAt(event.clientX, event.clientY, false);
  }

  function handleKeyDown(event) {
    if (!active) {
      return;
    }

    if (event.key === "Escape") {
      swallowEvent(event);
      stop();
      return;
    }

    if (event.key === "Tab") {
      swallowEvent(event);
      const hadPreview = clearPreview(false);
      if (event.shiftKey) {
        cycleSelection(-1);
      } else if (!selectChildCandidate()) {
        cycleSelection(1);
      }
      if (hadPreview && candidates.length) {
        showDefaultHint();
      }
      return;
    }

    const arrowDirection = arrowDirectionForKey(event.key);
    if (arrowDirection) {
      swallowEvent(event);
      if (event.altKey) {
        previewDirectionalCandidate(arrowDirection);
      } else {
        const hadPreview = clearPreview(false);
        const moved = selectDirectionalCandidate(arrowDirection);
        if (!moved && hadPreview) {
          render();
        }
        if (hadPreview && candidates.length) {
          showDefaultHint();
        }
      }
      return;
    }

    if (event.key === "Enter") {
      swallowEvent(event);
      confirmSelection();
    }
  }

  function handleKeyUp(event) {
    if (!active || event.altKey) {
      return;
    }

    if (previewIndex !== -1) {
      swallowEvent(event);
      clearPreview();
      return;
    }

    if (event.key === "Alt" || event.key === "Option") {
      swallowEvent(event);
      if (candidates.length) {
        showDefaultHint();
      }
    }
  }

  function swallowPointerEvent(event) {
    if (active && !isOverlayEvent(event)) {
      swallowEvent(event);
    }
  }

  function handleMouseUp(event) {
    if (!active) {
      return;
    }

    if (isOverlayEvent(event)) {
      return;
    }

    swallowEvent(event);
    confirmSelection();
  }

  function swallowEvent(event) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }

  function refreshFromLastPointer() {
    if (!active || !lastPointer) {
      return;
    }

    updateSelectionAt(lastPointer.x, lastPointer.y, true);
  }

  function updateSelectionAt(x, y, force) {
    lastPointer = { x, y };
    previewIndex = -1;
    previewDirection = null;
    const nextRoot = findComponentRoot(x, y);

    if (!nextRoot) {
      rootElement = null;
      candidates = [];
      selectedIndex = 0;
      previewIndex = -1;
      previewDirection = null;
      render();
      showHint("Move over page content   esc cancel");
      return;
    }

    if (force || nextRoot !== rootElement) {
      rootElement = nextRoot;
      candidates = collectCandidates(rootElement);
      selectedIndex = 0;
      previewIndex = -1;
      previewDirection = null;
    }

    selectPreviewCandidateAtPoint(x, y);
    render();

    if (candidates.length) {
      showDefaultHint();
    } else {
      showHint("No component boxes here   esc cancel");
    }
  }

  function findComponentRoot(x, y) {
    const stack = document
      .elementsFromPoint(x, y)
      .filter((element) => element instanceof Element)
      .filter((element) => !isOverlayElement(element))
      .filter((element) => !SKIPPED_TAGS.has(element.tagName));

    const leaf = stack.find((element) => {
      const rect = getVisibleRect(element);
      return rect && pointInsideRect(x, y, rect);
    });
    if (!leaf) {
      return document.body;
    }

    let bestElement = null;
    let bestScore = Number.NEGATIVE_INFINITY;
    let element = leaf;
    let distanceFromLeaf = 0;

    while (element && element !== document.body && element !== document.documentElement) {
      const rect = getVisibleRect(element);
      if (rect && pointInsideRect(x, y, rect)) {
        const score = componentRootScore(element, rect, distanceFromLeaf);
        if (score > bestScore) {
          bestElement = element;
          bestScore = score;
        }
      }
      element = element.parentElement;
      distanceFromLeaf += 1;
    }

    return bestElement || leaf || document.body;
  }

  function componentRootScore(element, rect, distanceFromLeaf = 0) {
    const viewportArea = Math.max(1, window.innerWidth * window.innerHeight);
    const area = rect.width * rect.height;
    const areaRatio = area / viewportArea;
    const childCount = visibleChildCount(element);
    const role = roleOf(element);
    const tagName = element.tagName;
    const identity = identityText(element);

    let score = 0;
    score += Math.min(30, Math.log10(area + 1) * 7);
    score += Math.min(18, childCount * 3);
    score -= Math.min(16, distanceFromLeaf * 1.6);

    if (SEMANTIC_TAGS.has(tagName)) {
      score += 18;
    }

    if (SEMANTIC_ROLES.has(role)) {
      score += 18;
    }

    if (COMPONENT_NAME_PATTERN.test(identity)) {
      score += tagName.includes("-") ? 30 : 20;
    }

    if (isInteractive(element)) {
      score -= area < 10_000 ? 32 : 10;
    }

    if (isLowValueUtility(element, rect)) {
      score -= 55;
    }

    if (area < 2_000) {
      score -= 50;
    } else if (area < 6_000) {
      score -= 18;
    }

    if (areaRatio > 0.82) {
      score -= 120;
    } else if (areaRatio > 0.55) {
      score -= 58;
    } else if (areaRatio > 0.38) {
      score -= 24;
    }

    if (rect.width > window.innerWidth * 0.96) {
      score -= 20;
    }

    if (rect.height > window.innerHeight * 0.92) {
      score -= 20;
    }

    return score;
  }

  function collectCandidates(root) {
    const rootRect = getVisibleRect(root);
    if (!rootRect) {
      return [];
    }

    const elements = [root];
    const descendants = root.querySelectorAll("*");
    for (let index = 0; index < descendants.length && elements.length < MAX_SCAN_ELEMENTS; index += 1) {
      elements.push(descendants[index]);
    }

    const rawCandidates = [];

    elements.forEach((element, domIndex) => {
      const rect = getVisibleRect(element);
      if (!rect || !isMeaningfullyInside(rect, rootRect)) {
        return;
      }

      if (!shouldKeepCandidate(element, root, rect, rootRect)) {
        return;
      }

      const captureScore = candidateCaptureScore(element, root, rect, rootRect);

      addCandidatePreservingOuter(rawCandidates, {
        element,
        rect,
        domIndex,
        depth: depthFromRoot(root, element),
        area: rect.width * rect.height,
        captureScore,
        semanticScore: candidateSemanticScore(element),
        preview: false
      });
    });

    rawCandidates.sort((left, right) => {
      if (left.element === root) {
        return -1;
      }
      if (right.element === root) {
        return 1;
      }
      if (right.captureScore !== left.captureScore) {
        return right.captureScore - left.captureScore;
      }
      if (right.semanticScore !== left.semanticScore) {
        return right.semanticScore - left.semanticScore;
      }
      if (left.depth !== right.depth) {
        return left.depth - right.depth;
      }
      if (right.area !== left.area) {
        return right.area - left.area;
      }
      return left.domIndex - right.domIndex;
    });

    const rootCandidate = rawCandidates.find((candidate) => candidate.element === root);
    if (rootCandidate) {
      rootCandidate.preview = true;
    }

    const previewCandidates = rawCandidates
      .filter((candidate) => candidate.element !== root && shouldPreviewCandidate(candidate, rootRect))
      .sort((left, right) => {
        if (right.captureScore !== left.captureScore) {
          return right.captureScore - left.captureScore;
        }
        if (left.depth !== right.depth) {
          return left.depth - right.depth;
        }
        return right.area - left.area;
      })
      .slice(0, MAX_PREVIEW_BOXES);

    previewCandidates.forEach((candidate) => {
      candidate.preview = true;
    });

    const previewSet = new Set(previewCandidates.map((candidate) => candidate.element));
    const hiddenCandidates = rawCandidates
      .filter((candidate) => candidate.element !== root && !previewSet.has(candidate.element))
      .filter((candidate) => shouldKeepHiddenCandidate(candidate, rootRect))
      .sort((left, right) => {
        if (left.depth !== right.depth) {
          return left.depth - right.depth;
        }
        if (right.captureScore !== left.captureScore) {
          return right.captureScore - left.captureScore;
        }
        return left.domIndex - right.domIndex;
      });

    return [
      ...(rootCandidate ? [rootCandidate] : []),
      ...previewCandidates,
      ...hiddenCandidates
    ].slice(0, MAX_CANDIDATES);
  }

  function getVisibleRect(element) {
    if (!(element instanceof Element) || SKIPPED_TAGS.has(element.tagName)) {
      return null;
    }

    const style = window.getComputedStyle(element);
    if (
      style.display === "none" ||
      style.visibility === "hidden" ||
      Number(style.opacity) === 0
    ) {
      return null;
    }

    const rect = element.getBoundingClientRect();
    if (rect.width < MIN_BOX_WIDTH || rect.height < MIN_BOX_HEIGHT) {
      return null;
    }

    const clipped = {
      left: clamp(rect.left, 0, window.innerWidth),
      top: clamp(rect.top, 0, window.innerHeight),
      right: clamp(rect.right, 0, window.innerWidth),
      bottom: clamp(rect.bottom, 0, window.innerHeight)
    };
    clipped.width = clipped.right - clipped.left;
    clipped.height = clipped.bottom - clipped.top;

    if (clipped.width < MIN_BOX_WIDTH || clipped.height < MIN_BOX_HEIGHT) {
      return null;
    }

    if (isTooSmallSelectionRect(clipped)) {
      return null;
    }

    return clipped;
  }

  function isTooSmallSelectionRect(rect) {
    return rect.width < MIN_USEFUL_BOX_WIDTH || rect.width * rect.height < MIN_USEFUL_BOX_AREA;
  }

  function shouldKeepCandidate(element, root, rect, rootRect) {
    if (element === root) {
      return true;
    }

    const rootArea = Math.max(1, rootRect.width * rootRect.height);
    const area = rect.width * rect.height;
    const areaRatio = area / rootArea;
    const identity = identityText(element);

    if (areaRatio > 0.96 && !CAPTURE_NAME_PATTERN.test(identity)) {
      return false;
    }

    if (isInlineFragment(element, rect, rootRect) && !hasCaptureWorthyText(element)) {
      return false;
    }

    if (area < 220 && !isInteractive(element)) {
      return false;
    }

    return true;
  }

  function addCandidatePreservingOuter(candidatesList, candidate) {
    const duplicateIndex = candidatesList.findIndex((existing) => nearSameRect(existing.rect, candidate.rect));
    if (duplicateIndex === -1) {
      candidatesList.push(candidate);
      return;
    }

    const existing = candidatesList[duplicateIndex];
    if (candidateIsMoreOuter(candidate, existing)) {
      candidatesList[duplicateIndex] = candidate;
    }
  }

  function candidateIsMoreOuter(candidate, existing) {
    if (candidate.depth !== existing.depth) {
      return candidate.depth < existing.depth;
    }

    if (candidate.element.contains(existing.element) && candidate.element !== existing.element) {
      return true;
    }

    if (existing.element.contains(candidate.element) && candidate.element !== existing.element) {
      return false;
    }

    if (candidate.area !== existing.area) {
      return candidate.area > existing.area;
    }

    return candidate.domIndex < existing.domIndex;
  }

  function candidateCaptureScore(element, root, rect, rootRect) {
    if (element === root) {
      return 1_000;
    }

    const rootArea = Math.max(1, rootRect.width * rootRect.height);
    const area = rect.width * rect.height;
    const areaRatio = area / rootArea;
    const identity = identityText(element);
    const role = roleOf(element);
    const tagName = element.tagName;
    const text = accessibleName(element);

    let score = 0;

    if (areaRatio > 0.55) {
      score += 28;
    } else if (areaRatio > 0.24) {
      score += 22;
    } else if (areaRatio > 0.08) {
      score += 14;
    } else if (areaRatio > 0.025) {
      score += 8;
    }

    if (CAPTURE_NAME_PATTERN.test(identity)) {
      score += 32;
    } else if (COMPONENT_NAME_PATTERN.test(identity)) {
      score += 18;
    }

    if (SEMANTIC_TAGS.has(tagName)) {
      score += 14;
    }

    if (SEMANTIC_ROLES.has(role)) {
      score += 14;
    }

    if (["BLOCKQUOTE", "CANVAS", "CODE", "FIGURE", "IMG", "PRE", "TABLE", "VIDEO"].includes(tagName)) {
      score += 36;
    }

    if (hasCaptureWorthyText(element)) {
      score += 28;
    } else if (text.length >= 28 && !isInteractive(element)) {
      score += 10;
    }

    if (isInteractive(element)) {
      score -= 22;
    }

    if (isLowValueUtility(element, rect)) {
      score -= 58;
    }

    if (area < 1_000) {
      score -= 24;
    }

    if (areaRatio > 0.9 && !CAPTURE_NAME_PATTERN.test(identity)) {
      score -= 24;
    }

    return score;
  }

  function shouldPreviewCandidate(candidate, rootRect) {
    if (candidate.element === rootElement) {
      return true;
    }

    if (isLowValueUtility(candidate.element, candidate.rect)) {
      return false;
    }

    const rootArea = Math.max(1, rootRect.width * rootRect.height);
    const minPreviewArea = Math.max(1_700, Math.min(12_000, rootArea * 0.035));

    if (candidate.area < minPreviewArea && candidate.captureScore < 60) {
      return false;
    }

    return candidate.captureScore >= 30;
  }

  function shouldKeepHiddenCandidate(candidate, rootRect) {
    const rootArea = Math.max(1, rootRect.width * rootRect.height);
    const areaRatio = candidate.area / rootArea;

    if (candidate.captureScore >= 8 || areaRatio >= 0.04) {
      return true;
    }

    if (isLowValueUtility(candidate.element, candidate.rect)) {
      return candidate.area >= 420;
    }

    return false;
  }

  function selectPreviewCandidateAtPoint(x, y) {
    if (!candidates.length) {
      return false;
    }

    const pointedPreviewEntries = candidates
      .map((candidate, index) => ({ candidate, index }))
      .filter(({ candidate }) => candidate.preview && pointInsideRect(x, y, candidate.rect))
      .sort((left, right) => {
        if (right.candidate.depth !== left.candidate.depth) {
          return right.candidate.depth - left.candidate.depth;
        }

        if (left.candidate.area !== right.candidate.area) {
          return left.candidate.area - right.candidate.area;
        }

        return left.index - right.index;
      });

    const nextIndex = pointedPreviewEntries[0]?.index ?? 0;
    if (nextIndex === selectedIndex) {
      return false;
    }

    selectedIndex = nextIndex;
    return true;
  }

  function isMeaningfullyInside(rect, rootRect) {
    const intersectionLeft = Math.max(rect.left, rootRect.left);
    const intersectionTop = Math.max(rect.top, rootRect.top);
    const intersectionRight = Math.min(rect.right, rootRect.right);
    const intersectionBottom = Math.min(rect.bottom, rootRect.bottom);
    const width = Math.max(0, intersectionRight - intersectionLeft);
    const height = Math.max(0, intersectionBottom - intersectionTop);
    const intersectionArea = width * height;
    const rectArea = Math.max(1, rect.width * rect.height);
    return intersectionArea / rectArea >= 0.72;
  }

  function render() {
    if (!boxesLayer || !ghostsLayer || !chipsLayer) {
      return;
    }

    boxesLayer.textContent = "";
    ghostsLayer.textContent = "";
    chipsLayer.textContent = "";

    const selected = candidates[selectedIndex];
    if (!selected) {
      return;
    }

    const preview = candidates[previewIndex];
    const isPreviewing = Boolean(preview && previewIndex !== selectedIndex && previewDirection);
    const neighbors = isPreviewing ? null : getNeighbors(selectedIndex);
    const targets = isPreviewing ? [] : navigationTargets(neighbors, selectedIndex);

    if (!isPreviewing) {
      targets.forEach(({ direction, index }) => drawGhost(index, direction));
    }

    drawSelectionBox(selected, "box selected");

    if (isPreviewing) {
      drawSelectionBox(preview, `box preview-selection ${previewDirection}`);
    }

    placedChipRects.length = 0;
    if (!isPreviewing) {
      targets.forEach(({ direction, index }) => drawDirectionChip(direction, index, selected.rect));
    }
  }

  function navigationTargets(neighbors, selectedCandidateIndex) {
    const targets = [];
    const usedIndexes = new Set();
    const usedRects = [];

    const addTarget = (direction, index) => {
      if (index === -1 || usedIndexes.has(index)) {
        return;
      }
      const candidate = candidates[index];
      if (!candidate || usedRects.some((rect) => nearSameRect(rect, candidate.rect))) {
        return;
      }
      targets.push({ direction, index });
      usedIndexes.add(index);
      usedRects.push(candidate.rect);
    };

    addTarget("up", neighbors.parentIdx);
    addTarget("down", neighbors.firstChildIdx);

    if (
      neighbors.leftSiblingIdx !== -1 &&
      neighbors.leftSiblingIdx === neighbors.rightSiblingIdx
    ) {
      const position = neighbors.siblingEntries.findIndex(({ index }) => index === selectedCandidateIndex);
      addTarget(position === 0 ? "right" : "left", neighbors.leftSiblingIdx);
      return targets;
    }

    addTarget("left", neighbors.leftSiblingIdx);
    addTarget("right", neighbors.rightSiblingIdx);
    return targets;
  }

  function drawSelectionBox(candidate, className) {
    const box = document.createElement("div");
    box.className = className;
    box.style.transform = `translate(${candidate.rect.left}px, ${candidate.rect.top}px)`;
    box.style.width = `${candidate.rect.width}px`;
    box.style.height = `${candidate.rect.height}px`;
    boxesLayer.appendChild(box);
  }

  function drawGhost(candidateIndex, kind) {
    if (candidateIndex === -1) {
      return;
    }
    const candidate = candidates[candidateIndex];
    if (!candidate) {
      return;
    }
    const rect = candidate.rect;
    const el = document.createElement("div");
    el.className = `ghost ${kind}`;
    el.style.transform = `translate(${rect.left}px, ${rect.top}px)`;
    el.style.width = `${rect.width}px`;
    el.style.height = `${rect.height}px`;
    ghostsLayer.appendChild(el);
  }

  function drawDirectionChip(direction, candidateIndex, selRect) {
    if (candidateIndex === -1) {
      return;
    }
    const candidate = candidates[candidateIndex];
    if (!candidate) {
      return;
    }

    const chip = document.createElement("div");
    chip.className = `chip ${direction}`;
    chip.textContent = DIRECTION_GLYPHS[direction];

    chip.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      selectCandidate(candidateIndex);
    });

    chipsLayer.appendChild(chip);

    const ghostRect = candidate.rect;
    const chipRect = chip.getBoundingClientRect();
    const chipW = chipRect.width;
    const chipH = chipRect.height;
    const margin = 6;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    const positions = chipPreferredPositions(direction, ghostRect, selRect, chipW, chipH);

    let best = null;
    for (const pos of positions) {
      const left = clamp(pos.left, margin, vw - chipW - margin);
      const top = clamp(pos.top, margin, vh - chipH - margin);
      const rect = { left, top, width: chipW, height: chipH };
      if (!rectCollidesAny(rect, placedChipRects)) {
        best = rect;
        break;
      }
    }

    if (!best) {
      const initial = positions[0];
      best = {
        left: clamp(initial.left, margin, vw - chipW - margin),
        top: clamp(initial.top, margin, vh - chipH - margin),
        width: chipW,
        height: chipH
      };
    }

    chip.style.left = `${best.left}px`;
    chip.style.top = `${best.top}px`;
    placedChipRects.push(best);
  }

  function chipPreferredPositions(direction, ghostRect, selRect, chipW, chipH) {
    const inset = 6;
    const centerX = clampCenter(
      selRect.left + selRect.width / 2,
      ghostRect.left,
      ghostRect.right,
      chipW,
      inset
    );
    const centerY = clampCenter(
      selRect.top + selRect.height / 2,
      ghostRect.top,
      ghostRect.bottom,
      chipH,
      inset
    );
    const xOptions = edgeCenterOptions(ghostRect.left, ghostRect.right, chipW, centerX, inset);
    const yOptions = edgeCenterOptions(ghostRect.top, ghostRect.bottom, chipH, centerY, inset);

    if (direction === "up") {
      return xOptions.map((x) => ({ left: x - chipW / 2, top: ghostRect.top - chipH / 2 }));
    }

    if (direction === "down") {
      return xOptions.map((x) => ({ left: x - chipW / 2, top: ghostRect.top - chipH / 2 }));
    }

    if (direction === "left") {
      return yOptions.map((y) => ({ left: ghostRect.right - chipW / 2, top: y - chipH / 2 }));
    }

    return yOptions.map((y) => ({ left: ghostRect.left - chipW / 2, top: y - chipH / 2 }));
  }

  function edgeCenterOptions(start, end, size, preferred, inset) {
    const centers = [
      preferred,
      clampCenter(start + (end - start) * 0.33, start, end, size, inset),
      clampCenter(start + (end - start) * 0.67, start, end, size, inset),
      clampCenter(start + size / 2 + inset, start, end, size, inset),
      clampCenter(end - size / 2 - inset, start, end, size, inset)
    ];
    return dedupeNumbers(centers);
  }

  function clampCenter(value, start, end, size, inset) {
    const min = start + size / 2 + inset;
    const max = end - size / 2 - inset;
    if (min > max) {
      return start + (end - start) / 2;
    }
    return clamp(value, min, max);
  }

  function dedupeNumbers(values) {
    const result = [];
    values.forEach((value) => {
      if (!result.some((existing) => Math.abs(existing - value) < 1)) {
        result.push(value);
      }
    });
    return result;
  }

  function rectCollidesAny(rect, others) {
    for (const other of others) {
      if (
        rect.left < other.left + other.width &&
        other.left < rect.left + rect.width &&
        rect.top < other.top + other.height &&
        other.top < rect.top + rect.height
      ) {
        return true;
      }
    }
    return false;
  }

  function selectCandidate(index) {
    if (index < 0 || index >= candidates.length) {
      return;
    }
    const hadPreview = previewIndex !== -1;
    const shouldRender = index !== selectedIndex || hadPreview;
    selectedIndex = index;
    previewIndex = -1;
    previewDirection = null;
    if (shouldRender) {
      render();
    }
    if (hadPreview) {
      showDefaultHint();
    }
  }

  function arrowDirectionForKey(key) {
    if (key === "ArrowUp") return "up";
    if (key === "ArrowDown") return "down";
    if (key === "ArrowLeft") return "left";
    if (key === "ArrowRight") return "right";
    return null;
  }

  function selectDirectionalCandidate(direction) {
    if (direction === "up") {
      return selectParentCandidate();
    }
    if (direction === "down") {
      return selectChildCandidate();
    }
    if (direction === "left") {
      return selectSiblingCandidate(-1);
    }
    if (direction === "right") {
      return selectSiblingCandidate(1);
    }
    return false;
  }

  function previewDirectionalCandidate(direction) {
    const nextPreviewIndex = neighborIndexForDirection(direction);
    if (nextPreviewIndex === -1) {
      if (clearPreview(false)) {
        render();
      }
      showHint("No target in that direction");
      return false;
    }

    previewIndex = nextPreviewIndex;
    previewDirection = direction;
    render();
    showHint("⌥ preview   release Option to return");
    return true;
  }

  function neighborIndexForDirection(direction) {
    const neighbors = getNeighbors(selectedIndex);
    if (direction === "up") return neighbors.parentIdx;
    if (direction === "down") return neighbors.firstChildIdx;
    if (direction === "left") return neighbors.leftSiblingIdx;
    if (direction === "right") return neighbors.rightSiblingIdx;
    return -1;
  }

  function clearPreview(shouldRender = true) {
    if (previewIndex === -1) {
      return false;
    }

    previewIndex = -1;
    previewDirection = null;
    if (shouldRender) {
      render();
      if (candidates.length) {
        showDefaultHint();
      }
    }
    return true;
  }

  function getNeighbors(selectedIdx) {
    const selected = candidates[selectedIdx];
    if (!selected) {
      return {
        parentIdx: -1,
        leftSiblingIdx: -1,
        rightSiblingIdx: -1,
        firstChildIdx: -1,
        childEntries: [],
        siblingEntries: []
      };
    }

    const parentIdx = parentCandidateIndex(selected, selectedIdx);
    const childEntries = sortedHierarchyEntries(childEntriesForParent(selectedIdx));
    const firstChildIdx = childEntries.length ? childEntries[0].index : -1;

    let leftSiblingIdx = -1;
    let rightSiblingIdx = -1;
    let siblingEntries = [];

    if (parentIdx !== -1) {
      siblingEntries = sortedHierarchyEntries(childEntriesForParent(parentIdx));
      const position = siblingEntries.findIndex(({ index }) => index === selectedIdx);
      if (position > 0) {
        leftSiblingIdx = siblingEntries[position - 1].index;
      } else if (siblingEntries.length > 1) {
        leftSiblingIdx = siblingEntries[siblingEntries.length - 1].index;
      }
      if (position !== -1 && position < siblingEntries.length - 1) {
        rightSiblingIdx = siblingEntries[position + 1].index;
      } else if (siblingEntries.length > 1) {
        rightSiblingIdx = siblingEntries[0].index;
      }
    }

    return {
      parentIdx,
      leftSiblingIdx,
      rightSiblingIdx,
      firstChildIdx,
      childEntries,
      siblingEntries
    };
  }

  function isOverlayEvent(event) {
    if (!overlayHost) {
      return false;
    }
    const path = typeof event.composedPath === "function" ? event.composedPath() : [];
    return path.includes(overlayHost);
  }

  function isOverlayElement(element) {
    if (!overlayHost) {
      return false;
    }

    return (
      element === overlayHost ||
      overlayHost.contains(element) ||
      element.getRootNode() === shadowRoot
    );
  }

  function inspect() {
    const selected = candidates[selectedIndex];
    const preview = candidates[previewIndex];
    return {
      active,
      version: api.version,
      root: rootElement ? describeElement(rootElement) : null,
      candidateCount: candidates.length,
      selectedIndex,
      previewIndex,
      previewDirection,
      selected: selected
        ? {
            element: describeElement(selected.element),
            rect: selected.rect,
            preview: selected.preview
          }
        : null,
      preview: preview
        ? {
            element: describeElement(preview.element),
            rect: preview.rect,
            preview: preview.preview
          }
        : null,
      lastPointer
    };
  }

  function describeElement(element) {
    const role = roleOf(element);
    const id = element.id ? `#${element.id}` : "";
    const className =
      typeof element.className === "string"
        ? element.className
            .split(/\s+/)
            .filter(Boolean)
            .slice(0, 3)
            .map((name) => `.${name}`)
            .join("")
        : "";

    return `${element.tagName.toLowerCase()}${id}${className}${role ? `[role=${role}]` : ""}`;
  }

  function cycleSelection(delta) {
    if (!candidates.length) {
      return;
    }

    selectedIndex = (selectedIndex + delta + candidates.length) % candidates.length;
    render();
  }

  function selectParentCandidate() {
    const selected = candidates[selectedIndex];
    if (!selected) {
      return false;
    }

    const parentIndex = parentCandidateIndex(selected, selectedIndex);
    if (parentIndex === -1) {
      return false;
    }

    selectedIndex = parentIndex;
    render();
    return true;
  }

  function selectChildCandidate() {
    const selected = candidates[selectedIndex];
    if (!selected) {
      return false;
    }

    const childEntries = sortedHierarchyEntries(
      childEntriesForParent(selectedIndex)
    );

    if (!childEntries.length) {
      return false;
    }

    selectedIndex = childEntries[0].index;
    render();
    return true;
  }

  function selectSiblingCandidate(delta) {
    const selected = candidates[selectedIndex];
    if (!selected) {
      return false;
    }

    const parentIndex = parentCandidateIndex(selected, selectedIndex);
    if (parentIndex === -1) {
      return false;
    }

    const siblingEntries = sortedHierarchyEntries(
      childEntriesForParent(parentIndex)
    );

    const currentSiblingPosition = siblingEntries.findIndex(({ index }) => index === selectedIndex);
    if (currentSiblingPosition === -1 || siblingEntries.length < 2) {
      return false;
    }

    const nextPosition = (currentSiblingPosition + delta + siblingEntries.length) % siblingEntries.length;
    selectedIndex = siblingEntries[nextPosition].index;
    render();
    return true;
  }

  function parentCandidateIndex(selected, selectedCandidateIndex) {
    let parentIndex = -1;
    let parentDepth = Number.NEGATIVE_INFINITY;

    candidates.forEach((candidate, index) => {
      if (index === selectedCandidateIndex || candidate.depth >= selected.depth) {
        return;
      }

      if (candidate.element.contains(selected.element) && candidate.depth > parentDepth) {
        parentIndex = index;
        parentDepth = candidate.depth;
      }
    });

    return parentIndex;
  }

  function childEntriesForParent(parentIndex) {
    return candidates
      .map((candidate, index) => ({ candidate, index }))
      .filter(({ index }) => {
        return index !== parentIndex && parentCandidateIndex(candidates[index], index) === parentIndex;
      });
  }

  function sortedHierarchyEntries(entries) {
    return entries.slice().sort((left, right) => compareCandidateVisualOrder(left.candidate, right.candidate));
  }

  function compareCandidateVisualOrder(left, right) {
    const rowTolerance = Math.max(10, Math.min(left.rect.height, right.rect.height) * 0.35);
    const topDelta = left.rect.top - right.rect.top;
    if (Math.abs(topDelta) > rowTolerance) {
      return topDelta;
    }

    const leftDelta = left.rect.left - right.rect.left;
    if (Math.abs(leftDelta) > 1) {
      return leftDelta;
    }

    return left.domIndex - right.domIndex;
  }

  function confirmSelection() {
    const selected = candidates[selectedIndex];
    if (!selected) {
      showError("No DOM component selected.");
      return;
    }

    overlayHost.style.display = "none";

    chrome.runtime.sendMessage(
      {
        type: "CLIPSHOT_DOM_CONFIRM",
        rect: selected.rect
      },
      (response) => {
        if (chrome.runtime.lastError) {
          showError(chrome.runtime.lastError.message);
          stop();
          return;
        }

        if (!response?.ok) {
          showError(response?.message || "Capture failed.");
          stop();
        }
      }
    );
  }

  async function cropAndCopy(dataUrl, rect) {
    const image = await loadImage(dataUrl);
    const scaleX = image.naturalWidth / Math.max(1, window.innerWidth);
    const scaleY = image.naturalHeight / Math.max(1, window.innerHeight);
    const sourceX = Math.max(0, Math.round(rect.left * scaleX));
    const sourceY = Math.max(0, Math.round(rect.top * scaleY));
    const sourceWidth = Math.min(
      image.naturalWidth - sourceX,
      Math.max(1, Math.round(rect.width * scaleX))
    );
    const sourceHeight = Math.min(
      image.naturalHeight - sourceY,
      Math.max(1, Math.round(rect.height * scaleY))
    );

    const canvas = document.createElement("canvas");
    canvas.width = sourceWidth;
    canvas.height = sourceHeight;

    const context = canvas.getContext("2d");
    if (!context) {
      throw new Error("Could not create crop canvas.");
    }

    context.drawImage(
      image,
      sourceX,
      sourceY,
      sourceWidth,
      sourceHeight,
      0,
      0,
      sourceWidth,
      sourceHeight
    );

    const pngBase64 = canvas.toDataURL("image/png").replace("data:image/png;base64,", "");
    const response = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ pngBase64 })
    });

    if (!response.ok) {
      throw new Error("ClipShot app is not accepting DOM captures.");
    }

    showCopiedToast();
    window.setTimeout(stop, 550);
  }

  function loadImage(dataUrl) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error("Could not load tab capture."));
      image.src = dataUrl;
    });
  }

  function showHint(text) {
    if (!hintElement) {
      return;
    }

    hintElement.hidden = false;
    hintElement.textContent = text;
  }

  function showDefaultHint() {
    showHint("⏎ capture   esc cancel");
  }

  function showCopiedToast() {
    ensureOverlay();
    overlayHost.style.display = "block";
    boxesLayer.textContent = "";
    if (ghostsLayer) ghostsLayer.textContent = "";
    if (chipsLayer) chipsLayer.textContent = "";
    showHint("Copied");
  }

  function showError(message) {
    ensureOverlay();
    overlayHost.style.display = "block";
    boxesLayer.textContent = "";
    if (ghostsLayer) ghostsLayer.textContent = "";
    if (chipsLayer) chipsLayer.textContent = "";
    showHint(message || "Capture failed");
    window.setTimeout(stop, 1600);
  }

  function visibleChildCount(element) {
    let count = 0;
    for (const child of element.children) {
      if (getVisibleRect(child)) {
        count += 1;
      }
      if (count >= 8) {
        break;
      }
    }
    return count;
  }

  function identityText(element) {
    return [
      element.tagName,
      element.id,
      element.className,
      roleOf(element),
      element.getAttribute("aria-label") || "",
      element.getAttribute("data-testid") || "",
      element.getAttribute("data-test-id") || ""
    ]
      .join(" ")
      .toLowerCase();
  }

  function isLowValueUtility(element, rect) {
    const identity = identityText(element);
    const text = accessibleName(element).toLowerCase();
    const area = rect.width * rect.height;

    if (UTILITY_TEXT_PATTERN.test(text)) {
      return true;
    }

    if (UTILITY_NAME_PATTERN.test(identity) && area < 22_000) {
      return true;
    }

    return isInteractive(element) && text.length <= 16 && area < 9_000;
  }

  function isInlineFragment(element, rect, rootRect) {
    if (isInteractive(element)) {
      return false;
    }

    const style = window.getComputedStyle(element);
    const rootArea = Math.max(1, rootRect.width * rootRect.height);
    const area = rect.width * rect.height;
    return style.display.startsWith("inline") && area / rootArea < 0.18;
  }

  function hasCaptureWorthyText(element) {
    if (isInteractive(element)) {
      return false;
    }

    const text = (element.innerText || element.textContent || "").replace(/\s+/g, " ").trim();
    if (text.length >= 80) {
      return true;
    }

    const tagName = element.tagName;
    const identity = identityText(element);
    if (["H1", "H2", "H3", "H4", "H5", "H6", "P", "SUMMARY"].includes(tagName) && text.length >= 18) {
      return true;
    }

    return CAPTURE_NAME_PATTERN.test(identity) && text.length >= 24;
  }

  function candidateSemanticScore(element) {
    let score = 0;
    const role = roleOf(element);
    if (SEMANTIC_TAGS.has(element.tagName)) {
      score += 3;
    }
    if (SEMANTIC_ROLES.has(role)) {
      score += 3;
    }
    if (isInteractive(element)) {
      score += 4;
    }
    if (COMPONENT_NAME_PATTERN.test(`${element.id} ${element.className}`)) {
      score += 2;
    }
    return score;
  }

  function accessibleName(element) {
    const explicitName =
      element.getAttribute("aria-label") ||
      element.getAttribute("title") ||
      element.getAttribute("alt") ||
      element.getAttribute("placeholder");

    const text = explicitName || element.innerText || element.textContent || "";
    return text.replace(/\s+/g, " ").trim().slice(0, 72);
  }

  function roleOf(element) {
    return (element.getAttribute("role") || "").trim().toLowerCase();
  }

  function isInteractive(element) {
    if (["A", "BUTTON", "INPUT", "SELECT", "SUMMARY", "TEXTAREA"].includes(element.tagName)) {
      return true;
    }

    const role = roleOf(element);
    return ["button", "checkbox", "link", "menuitem", "option", "switch", "tab", "textbox"].includes(role);
  }

  function depthFromRoot(root, element) {
    let depth = 0;
    let current = element;
    while (current && current !== root) {
      depth += 1;
      current = current.parentElement;
    }
    return depth;
  }

  function pointInsideRect(x, y, rect) {
    return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
  }

  function nearSameRect(left, right) {
    const tolerance = Math.max(
      3,
      Math.min(left.width, left.height, right.width, right.height) * 0.025
    );
    const edgeDelta =
      Math.abs(left.left - right.left) +
      Math.abs(left.top - right.top) +
      Math.abs(left.right - right.right) +
      Math.abs(left.bottom - right.bottom);

    if (edgeDelta <= tolerance * 4) {
      return true;
    }

    const leftArea = Math.max(1, left.width * left.height);
    const rightArea = Math.max(1, right.width * right.height);
    const areaRatio = Math.min(leftArea, rightArea) / Math.max(leftArea, rightArea);
    return areaRatio >= 0.96 && intersectionRatio(left, right) >= 0.94;
  }

  function intersectionRatio(left, right) {
    const intersectionLeft = Math.max(left.left, right.left);
    const intersectionTop = Math.max(left.top, right.top);
    const intersectionRight = Math.min(left.right, right.right);
    const intersectionBottom = Math.min(left.bottom, right.bottom);
    const width = Math.max(0, intersectionRight - intersectionLeft);
    const height = Math.max(0, intersectionBottom - intersectionTop);
    const intersectionArea = width * height;
    const smallerArea = Math.max(
      1,
      Math.min(left.width * left.height, right.width * right.height)
    );
    return intersectionArea / smallerArea;
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }
})();
