// ==UserScript==
// @name         Custom HTML5 video hotkeys
// @version      0.2
// @match        *://*/*
// @exclude      http://srv:8123*
// @exclude      http://192.168.1.50:8123*
// @grant        none
// ==/UserScript==

(function () {
  let originalTitle = document.title;
  let titleTimeout;


  function showSpeedInTitle(speed) {
    if (!document.title.startsWith("[ ") && !document.title.endsWith(" ]")) {
      originalTitle = document.title;
    }
    document.title = `[ ${speed.toFixed(1)} ]`;
    clearTimeout(titleTimeout);
    titleTimeout = setTimeout(() => {
      document.title = originalTitle;
    }, 200);
  }

  function setAllVideosSpeed(speed) {
    document.querySelectorAll("video").forEach((video) => {
      video.playbackRate = speed;
    });
    document.querySelectorAll("iframe").forEach((iframe) => {
      try {
        iframe.contentWindow.document.querySelectorAll("video").forEach((video) => {
          video.playbackRate = speed;
        });
      } catch (e) {}
    });
    showSpeedInTitle(speed);
    console.log("Set video speed to", speed);
  }

  function getFirstVideo() {
    return document.querySelector("video");
  }

  function togglePiP() {
    // PiP API isn't available in extension content script context (X-ray wrappers),
    // so inject into page context via a script element
    const s = document.createElement("script");
    s.textContent = `(function() {
      var v = document.querySelector("video");
      if (!v) { console.error("[PiP] no video found"); return; }
      if (document.pictureInPictureElement) {
        document.exitPictureInPicture().catch(function(e) { console.error("[PiP] exit error:", e); });
      } else {
        v.requestPictureInPicture().catch(function(e) { console.error("[PiP] enter error:", e); });
      }
    })()`;
    document.documentElement.appendChild(s);
    s.remove();
  }

  let _seekAccum = 0;
  let _speedAccum = 0;

  function handleWheel(e) {
    if (!e.shiftKey) return;
    const video = getFirstVideo();
    if (!video) return;
    const delta = e.wheelDelta || -e.deltaY * 3;
    if (e.ctrlKey) {
      _seekAccum += delta;
      if (Math.abs(_seekAccum) < 120) { e.stopPropagation(); return; }
      const seekDelta = _seekAccum > 0 ? 5 : -5;
      _seekAccum = 0;
      video.currentTime += seekDelta;
      e.stopPropagation();
      return;
    }
    _speedAccum += delta;
    if (Math.abs(_speedAccum) < 120) return;
    const speedDelta = _speedAccum > 0 ? 0.1 : -0.1;
    _speedAccum = 0;
    const newSpeed = Math.max(0.1, video.playbackRate + speedDelta);
    setAllVideosSpeed(newSpeed);
  }

  function handleKeyDown(e) {
    const video = getFirstVideo();
    // if (!video) return;

    function matchHotkey(hotkey, e) {
      const parts = hotkey.split("+");
      const key = parts.pop();
      const needCtrl = parts.includes("Ctrl");
      const needAlt = parts.includes("Alt");
      const needShift = parts.includes("Shift");
      
      // Check if any other modifier keys are pressed
      if (e.metaKey || (!needCtrl && e.ctrlKey) || (!needAlt && e.altKey) || (!needShift && e.shiftKey)) {
        return false;
      }

      if (key.startsWith("Digit") || key.startsWith("Key")) {
        return (
          e.code === key &&
          e.ctrlKey === needCtrl &&
          e.altKey === needAlt &&
          e.shiftKey === needShift
        );
      }
      return (
        e.key === key &&
        e.ctrlKey === needCtrl &&
        e.altKey === needAlt &&
        e.shiftKey === needShift
      );
    }


    if (e.altKey) console.log("[hotkeys] keydown:", { key: e.key, code: e.code, alt: e.altKey, ctrl: e.ctrlKey, shift: e.shiftKey });

    const numKeys = ["1","2","3","4","5","6","7","8","9"];
    // const digitCodes = ["Digit1","Digit2","Digit3","Digit4","Digit5","Digit6","Digit7","Digit8","Digit9"];
    const hotkeys = [
      ["Alt+Digit1", () => {
        const iframe = document.querySelector("iframe:not(#cmdline_iframe)");
        if (iframe?.src) window.open(iframe.src, "_blank");
      }],
      ["Alt+ ", () => video.requestFullscreen()],
      // ["Alt+KeyI", () => togglePiP()],
      ["Alt+ArrowUp", () => setAllVideosSpeed(Math.round((video.playbackRate + 0.25) * 100) / 100)],
      ["Alt+ArrowDown", () => setAllVideosSpeed(Math.max(0.25, Math.round((video.playbackRate - 0.25) * 100) / 100))],
      // ...digitCodes.slice(0,7).map((code, i) => ["Shift+"+code, () => setAllVideosSpeed(Math.max(1, (i+1)/2))]),
      ["Shift+ArrowLeft", () => { video.currentTime = Math.max(0, video.currentTime - 10 * video.playbackRate); }],
      ["Shift+ArrowRight", () => { video.currentTime = Math.min(video.duration, video.currentTime + 10 * video.playbackRate); }],
      ...numKeys.map(k => [k, () => { video.currentTime = video.duration * (parseInt(k,10)*0.1); }]),
    ];

    for (const [hotkey, handler] of hotkeys) {
      if (matchHotkey(hotkey, e)) {
        handler(e.key);
        e.preventDefault();
        return;
      }
    }
  }

  const excludedSites = [
    "web.telegram.org",
  ];

  function init() {
    const isExcluded = excludedSites.some(site => location.hostname.includes(site));
    console.log("Initializing custom video hotkeys");
    document.body.addEventListener("wheel", handleWheel);

    if (!isExcluded) document.body.addEventListener("keydown", handleKeyDown, false);
  }

  init();
})();
