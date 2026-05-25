(() => {
  if (window.__clipshotDOMSelector) {
    window.__clipshotDOMSelector.start();
    return;
  }

  const BRIDGE_URL = "http://127.0.0.1:17272/clipboard";
  const MAX_CANDIDATES = 48;
  const MAX_PREVIEW_BOXES = 8;
  const MAX_SCAN_ELEMENTS = 1600;
  const MIN_BOX_WIDTH = 10;
  const MIN_BOX_HEIGHT = 10;

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

  let active = false;
  let rootElement = null;
  let candidates = [];
  let selectedIndex = 0;
  let lastPointer = null;
  let overlayHost = null;
  let shadowRoot = null;
  let boxesLayer = null;
  let labelElement = null;
  let hintElement = null;

  const api = {
    start,
    stop
  };

  window.__clipshotDOMSelector = api;

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
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
  });

  start();

  function start() {
    if (active) {
      return;
    }

    active = true;
    rootElement = null;
    candidates = [];
    selectedIndex = 0;
    ensureOverlay();
    overlayHost.style.display = "block";
    showHint("Move over a component. Tab enters nested boxes. Click or Enter copies.");

    window.addEventListener("mousemove", handleMouseMove, true);
    window.addEventListener("keydown", handleKeyDown, true);
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
    lastPointer = null;
    render();

    window.removeEventListener("mousemove", handleMouseMove, true);
    window.removeEventListener("keydown", handleKeyDown, true);
    window.removeEventListener("mousedown", swallowPointerEvent, true);
    window.removeEventListener("mouseup", handleMouseUp, true);
    window.removeEventListener("click", swallowPointerEvent, true);
    window.removeEventListener("scroll", refreshFromLastPointer, true);
    window.removeEventListener("resize", refreshFromLastPointer, true);

    if (overlayHost) {
      overlayHost.style.display = "none";
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
        }

        .boxes {
          position: fixed;
          inset: 0;
        }

        .box {
          position: fixed;
          box-sizing: border-box;
          border: 0;
          background: transparent;
          border-radius: 6px;
          opacity: 1;
          pointer-events: none;
          transition: background-color 140ms ease;
        }

        .box.preview {
          background: rgba(255, 255, 255, 0.055);
          box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.07);
        }

        .box.root-preview {
          background: rgba(255, 255, 255, 0.022);
          box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.035);
        }

        .box.selected {
          z-index: 2;
          border: 2px solid #1297ff;
          outline: 2px solid rgba(255, 255, 255, 0.92);
          outline-offset: 1px;
          background: rgba(18, 151, 255, 0.13);
          opacity: 1;
          box-shadow:
            0 0 0 5px rgba(18, 151, 255, 0.22),
            0 0 0 1px rgba(0, 48, 120, 0.4),
            inset 0 0 0 1px rgba(255, 255, 255, 0.58),
            0 8px 22px rgba(0, 74, 173, 0.18);
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

        .label,
        .hint {
          position: fixed;
          max-width: min(520px, calc(100vw - 24px));
          box-sizing: border-box;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 12px;
          line-height: 16px;
          color: white;
          background: rgba(12, 20, 32, 0.88);
          border: 1px solid rgba(255, 255, 255, 0.16);
          border-radius: 7px;
          box-shadow: 0 10px 30px rgba(0, 0, 0, 0.22);
          padding: 6px 8px;
          pointer-events: none;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .hint {
          left: 12px;
          bottom: 12px;
        }

        .selected-label {
          background: rgba(5, 91, 168, 0.94);
          border-color: rgba(180, 224, 255, 0.5);
          box-shadow: 0 10px 30px rgba(0, 74, 173, 0.28);
        }
      </style>
      <div class="shade"></div>
      <div class="boxes"></div>
      <div class="label" hidden></div>
      <div class="hint" hidden></div>
    `;

    boxesLayer = shadowRoot.querySelector(".boxes");
    labelElement = shadowRoot.querySelector(".label");
    hintElement = shadowRoot.querySelector(".hint");
    document.documentElement.appendChild(overlayHost);
  }

  function handleMouseMove(event) {
    if (!active) {
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
      cycleSelection(event.shiftKey ? -1 : 1);
      return;
    }

    if (event.key === "Enter") {
      swallowEvent(event);
      confirmSelection();
    }
  }

  function swallowPointerEvent(event) {
    if (active) {
      swallowEvent(event);
    }
  }

  function handleMouseUp(event) {
    if (!active) {
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
    const nextRoot = findComponentRoot(x, y);

    if (!nextRoot) {
      rootElement = null;
      candidates = [];
      selectedIndex = 0;
      render();
      return;
    }

    if (force || nextRoot !== rootElement) {
      rootElement = nextRoot;
      candidates = collectCandidates(rootElement);
      selectedIndex = 0;
      render();
    }
  }

  function findComponentRoot(x, y) {
    const stack = document
      .elementsFromPoint(x, y)
      .filter((element) => element instanceof Element)
      .filter((element) => element !== overlayHost && !overlayHost?.contains(element))
      .filter((element) => !SKIPPED_TAGS.has(element.tagName));

    const leaf = stack[0];
    if (!leaf) {
      return null;
    }

    let bestElement = leaf;
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

    return bestElement;
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
        label: labelForElement(element),
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
      Number(style.opacity) === 0 ||
      style.pointerEvents === "none"
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

    return clipped;
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
    if (!boxesLayer || !labelElement) {
      return;
    }

    boxesLayer.textContent = "";

    const visibleBoxes = candidates
      .map((candidate, index) => ({ candidate, index }))
      .filter(({ candidate, index }) => index === selectedIndex || candidate.preview);
    const previewBoxes = visibleBoxes.filter(({ index }) => index !== selectedIndex);
    const selectedBox = visibleBoxes.find(({ index }) => index === selectedIndex);

    previewBoxes.forEach(drawBox);
    if (selectedBox) {
      drawBox(selectedBox);
    }

    function drawBox({ candidate, index }) {
      const box = document.createElement("div");
      const classNames = ["box"];
      if (index === selectedIndex) {
        classNames.push("selected");
      } else {
        classNames.push("preview");
        if (candidate.element === rootElement) {
          classNames.push("root-preview");
        }
      }
      box.className = classNames.join(" ");
      box.style.transform = `translate(${candidate.rect.left}px, ${candidate.rect.top}px)`;
      box.style.width = `${candidate.rect.width}px`;
      box.style.height = `${candidate.rect.height}px`;
      boxesLayer.appendChild(box);
    }

    const selected = candidates[selectedIndex];
    if (!selected) {
      labelElement.hidden = true;
      showHint("No DOM component here");
      return;
    }

    labelElement.hidden = false;
    labelElement.className = "label selected-label";
    labelElement.textContent = `Selected ${selectedIndex + 1}/${candidates.length} - ${selected.label}`;
    const labelLeft = clamp(selected.rect.left, 12, window.innerWidth - 240);
    const labelTop = selected.rect.top > 36 ? selected.rect.top - 32 : selected.rect.bottom + 8;
    labelElement.style.left = `${labelLeft}px`;
    labelElement.style.top = `${clamp(labelTop, 12, window.innerHeight - 42)}px`;
  }

  function cycleSelection(delta) {
    if (!candidates.length) {
      return;
    }

    selectedIndex = (selectedIndex + delta + candidates.length) % candidates.length;
    render();
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

  function showCopiedToast() {
    ensureOverlay();
    overlayHost.style.display = "block";
    boxesLayer.textContent = "";
    labelElement.hidden = true;
    showHint("Copied");
  }

  function showError(message) {
    ensureOverlay();
    overlayHost.style.display = "block";
    boxesLayer.textContent = "";
    labelElement.hidden = true;
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

  function labelForElement(element) {
    const role = roleOf(element);
    const tag = element.tagName.toLowerCase();
    const name = accessibleName(element);
    if (name) {
      return `${tag}${role ? `/${role}` : ""} - ${name}`;
    }
    if (role) {
      return `${tag}/${role}`;
    }
    return tag;
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
