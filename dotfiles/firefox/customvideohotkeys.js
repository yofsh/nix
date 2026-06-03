// ==UserScript==
// @name         Custom HTML5 video hotkeys
// @version      0.3
// @match        *://*/*
// @exclude      http://srv:8123*
// @exclude      http://192.168.1.50:8123*
// @grant        none
// ==/UserScript==

(function () {
  const SPEEDS = [1, 1.25, 1.5, 1.75, 2, 2.5, 3];
  const EXCLUDED_SITES = ["web.telegram.org"];

  // --- Helpers ---

  function getFirstVideo() {
    return document.querySelector("video");
  }

  function fmtSpeed(s) {
    return s.toFixed(s % 1 ? 2 : 1) + "×";
  }

  function setAllVideosSpeed(speed) {
    document.querySelectorAll("video").forEach((v) => (v.playbackRate = speed));
    document.querySelectorAll("iframe").forEach((iframe) => {
      try {
        iframe.contentWindow.document
          .querySelectorAll("video")
          .forEach((v) => (v.playbackRate = speed));
      } catch (_) {}
    });
    showSpeedOverlay(speed);
  }

  function matchHotkey(hotkey, e) {
    const parts = hotkey.split("+");
    const key = parts.pop();
    const needCtrl = parts.includes("Ctrl");
    const needAlt = parts.includes("Alt");
    const needShift = parts.includes("Shift");

    if (e.metaKey) return false;
    if (!needCtrl && e.ctrlKey) return false;
    if (!needAlt && e.altKey) return false;
    if (!needShift && e.shiftKey) return false;

    const actual = key.startsWith("Digit") || key.startsWith("Key") ? e.code : e.key;
    return (
      actual === key &&
      e.ctrlKey === needCtrl &&
      e.altKey === needAlt &&
      e.shiftKey === needShift
    );
  }

  // --- Speed overlay (center-bottom toast) ---

  let _overlayEl = null;
  let _overlayTimeout;

  function showSpeedOverlay(speed) {
    if (!_overlayEl) {
      _overlayEl = document.createElement("div");
      Object.assign(_overlayEl.style, {
        position: "fixed",
        bottom: "60px",
        left: "50%",
        transform: "translateX(-50%)",
        zIndex: "2147483647",
        background: "rgba(220, 80, 255, 0.9)",
        color: "#fff",
        font: "bold 20px/1 monospace",
        padding: "10px 18px",
        borderRadius: "8px",
        pointerEvents: "none",
        opacity: "0",
        transition: "opacity 0.15s",
        textShadow: "0 1px 3px rgba(0,0,0,0.5)",
      });
      document.documentElement.appendChild(_overlayEl);
    }
    _overlayEl.textContent = fmtSpeed(speed);
    _overlayEl.style.opacity = "1";
    clearTimeout(_overlayTimeout);
    _overlayTimeout = setTimeout(() => (_overlayEl.style.opacity = "0"), 800);
    if (_bubbleEl) _bubbleEl.textContent = fmtSpeed(speed);
  }

  // --- Speed bubble (bottom-left, hover to pick speed) ---

  let _bubbleEl = null;
  let _menuEl = null;

  function createSpeedBubble() {
    if (_bubbleEl) return;

    _bubbleEl = document.createElement("div");
    Object.assign(_bubbleEl.style, {
      position: "fixed",
      bottom: "12px",
      left: "12px",
      zIndex: "2147483646",
      background: "rgba(40, 40, 50, 0.5)",
      color: "rgba(255, 255, 255, 0.5)",
      font: "bold 13px/1 monospace",
      padding: "5px 8px",
      borderRadius: "6px",
      cursor: "pointer",
      transition: "opacity 0.15s, background 0.15s, color 0.15s",
      userSelect: "none",
    });
    const video = getFirstVideo();
    _bubbleEl.textContent = fmtSpeed(video ? video.playbackRate : 1);

    _menuEl = document.createElement("div");
    Object.assign(_menuEl.style, {
      position: "fixed",
      bottom: "12px",
      left: "60px",
      zIndex: "2147483646",
      background: "rgba(30, 30, 40, 0.95)",
      borderRadius: "8px",
      padding: "4px",
      display: "none",
      flexDirection: "row",
      gap: "2px",
      backdropFilter: "blur(8px)",
      border: "1px solid rgba(255, 255, 255, 0.15)",
    });

    SPEEDS.forEach((s) => {
      const btn = document.createElement("div");
      Object.assign(btn.style, {
        color: "#fff",
        font: "bold 12px/1 monospace",
        padding: "5px 10px",
        borderRadius: "4px",
        cursor: "pointer",
        textAlign: "center",
        transition: "background 0.1s",
      });
      btn.textContent = fmtSpeed(s);
      btn.addEventListener("mouseenter", () => {
        btn.style.background = "rgba(255, 255, 255, 0.15)";
      });
      btn.addEventListener("mouseleave", () => {
        const v = getFirstVideo();
        btn.style.background =
          v && Math.abs(v.playbackRate - s) < 0.01
            ? "rgba(255, 255, 255, 0.1)"
            : "transparent";
      });
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        setAllVideosSpeed(s);
        highlightActiveSpeed();
      });
      _menuEl.appendChild(btn);
    });

    let hideTimeout;
    const showMenu = () => {
      clearTimeout(hideTimeout);
      highlightActiveSpeed();
      _menuEl.style.display = "flex";
      _bubbleEl.style.background = "rgba(60, 60, 70, 0.8)";
      _bubbleEl.style.color = "rgba(255, 255, 255, 0.9)";
    };
    const hideMenu = () => {
      hideTimeout = setTimeout(() => {
        _menuEl.style.display = "none";
        _bubbleEl.style.background = "rgba(40, 40, 50, 0.5)";
        _bubbleEl.style.color = "rgba(255, 255, 255, 0.5)";
      }, 200);
    };

    _bubbleEl.addEventListener("mouseenter", showMenu);
    _bubbleEl.addEventListener("mouseleave", hideMenu);
    _menuEl.addEventListener("mouseenter", showMenu);
    _menuEl.addEventListener("mouseleave", hideMenu);

    document.documentElement.appendChild(_bubbleEl);
    document.documentElement.appendChild(_menuEl);
  }

  function highlightActiveSpeed() {
    if (!_menuEl) return;
    const current = getFirstVideo()?.playbackRate ?? 1;
    Array.from(_menuEl.children).forEach((btn, i) => {
      btn.style.background =
        Math.abs(current - SPEEDS[i]) < 0.01
          ? "rgba(255, 255, 255, 0.1)"
          : "transparent";
    });
  }

  function removeSpeedBubble() {
    _bubbleEl?.remove();
    _bubbleEl = null;
    _menuEl?.remove();
    _menuEl = null;
  }

  function checkForVideos() {
    const video = getFirstVideo();
    if (video && !_bubbleEl) createSpeedBubble();
    else if (!video && _bubbleEl) removeSpeedBubble();
    else if (video && _bubbleEl) _bubbleEl.textContent = fmtSpeed(video.playbackRate);
  }

  // --- Scroll wheel: Shift+wheel = speed, Shift+Ctrl+wheel = seek ---

  let _seekAccum = 0;
  let _speedAccum = 0;

  function handleWheel(e) {
    if (!e.shiftKey) return;
    const video = getFirstVideo();
    if (!video) return;

    const delta = e.wheelDelta || -e.deltaY * 3;

    if (e.ctrlKey) {
      _seekAccum += delta;
      if (Math.abs(_seekAccum) < 120) {
        e.stopPropagation();
        return;
      }
      video.currentTime += _seekAccum > 0 ? 5 : -5;
      _seekAccum = 0;
      e.stopPropagation();
      return;
    }

    _speedAccum += delta;
    if (Math.abs(_speedAccum) < 120) return;
    const newSpeed = Math.max(0.1, video.playbackRate + (_speedAccum > 0 ? 0.1 : -0.1));
    _speedAccum = 0;
    setAllVideosSpeed(newSpeed);
  }

  // --- Keyboard hotkeys ---

  function handleKeyDown(e) {
    const video = getFirstVideo();

    const hotkeys = [
      ["Alt+Digit4", () => {
        const iframe = document.querySelector("iframe:not(#cmdline_iframe)");
        if (iframe?.src) window.open(iframe.src, "_blank");
      }],
      ["Alt+ ", () => video.requestFullscreen()],
      ["Alt+ArrowUp", () => setAllVideosSpeed(Math.round((video.playbackRate + 0.25) * 100) / 100)],
      ["Alt+ArrowDown", () => setAllVideosSpeed(Math.max(0.25, Math.round((video.playbackRate - 0.25) * 100) / 100))],
      ["Shift+ArrowLeft", () => { video.currentTime = Math.max(0, video.currentTime - 10 * video.playbackRate); }],
      ["Shift+ArrowRight", () => { video.currentTime = Math.min(video.duration, video.currentTime + 10 * video.playbackRate); }],
      ...["1","2","3","4","5","6","7","8","9"].map((k) => [
        k, () => { video.currentTime = video.duration * parseInt(k, 10) * 0.1; },
      ]),
    ];

    for (const [hotkey, handler] of hotkeys) {
      if (matchHotkey(hotkey, e)) {
        handler();
        e.preventDefault();
        return;
      }
    }
  }

  // --- Init ---

  function init() {
    const isExcluded = EXCLUDED_SITES.some((s) => location.hostname.includes(s));
    document.body.addEventListener("wheel", handleWheel);
    if (!isExcluded) document.body.addEventListener("keydown", handleKeyDown, false);
    checkForVideos();
    setInterval(checkForVideos, 2000);
  }

  init();
})();
