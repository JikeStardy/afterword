(function () {
  "use strict";

  var MOTION_TYPES = [
    { type: "idle", label: "Idle", description: "尾巴轻轻呼吸，适合品牌主形停留。" },
    { type: "collect", label: "Collect", description: "尾巴向内收拢，表达捕获、收藏、添加来源。" },
    { type: "analyze", label: "Analyze", description: "强调点轻微环绕，表达阅读分析和研究生成。" },
    { type: "saved", label: "Saved", description: "整体短促上扬，表达保存成功。" },
    { type: "empty", label: "Empty", description: "慢速入场后停住，适合空态。" },
    { type: "retry", label: "Retry", description: "路径回摆，表达重试和恢复。" },
    { type: "paused", label: "Paused", description: "动作收束到静止，表达暂停。" },
    { type: "complete", label: "Complete", description: "主体稳定，强调完成状态。" },
  ];

  var state = {
    query: "",
    category: "all",
    size: 24,
    color: "#476b4f",
    selected: false,
    speed: 1,
    reduceMotion: window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    motionType: "idle",
    sceneId: "",
  };

  var runningAnimations = [];
  var refs = {};
  var reduceMotionQuery = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : null;

  document.addEventListener("DOMContentLoaded", function () {
    refs = {
      brandFox: document.getElementById("brandFox"),
      searchInput: document.getElementById("searchInput"),
      categoryFilter: document.getElementById("categoryFilter"),
      colorInput: document.getElementById("colorInput"),
      selectedToggle: document.getElementById("selectedToggle"),
      iconGrid: document.getElementById("iconGrid"),
      sceneGrid: document.getElementById("sceneGrid"),
      iconCount: document.getElementById("iconCount"),
      sceneCount: document.getElementById("sceneCount"),
      motionStage: document.getElementById("motionStage"),
      motionType: document.getElementById("motionType"),
      sceneSelect: document.getElementById("sceneSelect"),
      playButton: document.getElementById("playButton"),
      pauseButton: document.getElementById("pauseButton"),
      replayButton: document.getElementById("replayButton"),
      reduceMotionToggle: document.getElementById("reduceMotionToggle"),
      motionDescription: document.getElementById("motionDescription"),
    };

    bindControls();
    renderAll();
  });

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      pauseMotion();
    }
  });

  function bindControls() {
    refs.searchInput.addEventListener("input", function (event) {
      state.query = event.target.value.trim().toLowerCase();
      renderIcons();
    });

    refs.categoryFilter.addEventListener("change", function (event) {
      state.category = event.target.value;
      renderIcons();
    });

    refs.colorInput.addEventListener("input", function (event) {
      state.color = event.target.value;
      renderIcons();
      renderScenes();
      renderBrand();
      renderStage(false);
    });

    refs.selectedToggle.addEventListener("change", function (event) {
      state.selected = event.target.checked;
      renderIcons();
    });

    Array.prototype.forEach.call(document.querySelectorAll("[data-size]"), function (button) {
      button.addEventListener("click", function () {
        state.size = Number(button.getAttribute("data-size"));
        setPressed("[data-size]", String(state.size));
        renderIcons();
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll("[data-speed]"), function (button) {
      button.addEventListener("click", function () {
        state.speed = Number(button.getAttribute("data-speed"));
        setPressed("[data-speed]", String(state.speed));
        replayMotion();
      });
    });

    refs.motionType.addEventListener("change", function (event) {
      state.motionType = event.target.value;
      pickSceneForMotion();
      renderMotionDescription();
      renderStage(true);
    });

    refs.sceneSelect.addEventListener("change", function (event) {
      state.sceneId = event.target.value;
      renderStage(true);
    });

    refs.reduceMotionToggle.checked = state.reduceMotion;
    refs.reduceMotionToggle.addEventListener("change", function (event) {
      state.reduceMotion = event.target.checked;
      if (state.reduceMotion) {
        cancelAnimations();
      }
      renderStage(false);
    });

    refs.playButton.addEventListener("click", playMotion);
    refs.pauseButton.addEventListener("click", pauseMotion);
    refs.replayButton.addEventListener("click", replayMotion);

    refs.motionStage.addEventListener("keydown", function (event) {
      if (event.key === " " || event.key === "Enter") {
        event.preventDefault();
        if (isMotionRunning()) {
          pauseMotion();
        } else {
          playMotion();
        }
      }
    });

    if (reduceMotionQuery && reduceMotionQuery.addEventListener) {
      reduceMotionQuery.addEventListener("change", function (event) {
        state.reduceMotion = event.matches;
        refs.reduceMotionToggle.checked = state.reduceMotion;
        if (state.reduceMotion) {
          cancelAnimations();
        }
        renderStage(false);
      });
    } else if (reduceMotionQuery && reduceMotionQuery.addListener) {
      reduceMotionQuery.addListener(function (event) {
        state.reduceMotion = event.matches;
        refs.reduceMotionToggle.checked = state.reduceMotion;
        if (state.reduceMotion) {
          cancelAnimations();
        }
        renderStage(false);
      });
    }
  }

  function renderAll() {
    renderBrand();
    renderCategoryOptions();
    renderMotionOptions();
    renderSceneOptions();
    renderIcons();
    renderScenes();
    pickSceneForMotion();
    renderMotionDescription();
    renderStage(false);
  }

  function iconApi() {
    return window.AfterwordIcons || { icons: [], svg: null };
  }

  function sceneApi() {
    return window.AfterwordScenes || { scenes: [], motions: [], svg: null, fox: null };
  }

  function renderBrand() {
    var api = sceneApi();
    clearNode(refs.brandFox);
    if (typeof api.fox === "function") {
      appendSvg(refs.brandFox, api.fox({ color: "#faf8f3", eyeColor: "#476b4f" }), "brand-fox-svg");
      return;
    }
    refs.brandFox.appendChild(emptyFragment("等待 fox() 主形数据"));
  }

  function renderCategoryOptions() {
    var current = refs.categoryFilter.value || "all";
    var categories = unique(iconApi().icons.map(function (icon) { return icon.category || "uncategorized"; })).sort();
    clearNode(refs.categoryFilter);
    refs.categoryFilter.appendChild(optionNode("all", "全部"));
    categories.forEach(function (category) {
      refs.categoryFilter.appendChild(optionNode(category, category));
    });
    refs.categoryFilter.value = categories.indexOf(current) >= 0 ? current : "all";
    state.category = refs.categoryFilter.value;
  }

  function renderMotionOptions() {
    var motions = sceneApi().motions || [];
    var availableTypes = unique(motions.map(function (motion) { return motion.type; }).filter(Boolean));
    var types = MOTION_TYPES.map(function (entry) {
      var enabled = !availableTypes.length || availableTypes.indexOf(entry.type) >= 0;
      return {
        type: entry.type,
        label: entry.label,
        description: entry.description,
        enabled: enabled,
      };
    });

    clearNode(refs.motionType);
    types.forEach(function (entry) {
      var motion = motions.filter(function (item) { return item.type === entry.type; })[0];
      var option = optionNode(entry.type, motion ? motion.label : entry.label);
      option.disabled = !entry.enabled;
      refs.motionType.appendChild(option);
    });

    if (!refs.motionType.querySelector("option[value='" + state.motionType + "']:not(:disabled)")) {
      var firstEnabled = types.filter(function (entry) { return entry.enabled; })[0] || types[0];
      state.motionType = firstEnabled.type;
    }
    refs.motionType.value = state.motionType;
  }

  function renderSceneOptions() {
    var scenes = sceneApi().scenes || [];
    clearNode(refs.sceneSelect);
    if (!scenes.length) {
      refs.sceneSelect.appendChild(optionNode("", "等待 scenes.js"));
      refs.sceneSelect.disabled = true;
      state.sceneId = "";
      return;
    }
    refs.sceneSelect.disabled = false;
    scenes.forEach(function (scene) {
      refs.sceneSelect.appendChild(optionNode(scene.id, scene.label || scene.id));
    });
    if (!state.sceneId || !scenes.some(function (scene) { return scene.id === state.sceneId; })) {
      state.sceneId = scenes[0].id;
    }
    refs.sceneSelect.value = state.sceneId;
  }

  function renderIcons() {
    var api = iconApi();
    var icons = (api.icons || []).filter(iconMatches);
    clearNode(refs.iconGrid);
    refs.iconCount.value = String(icons.length);

    if (!icons.length) {
      refs.iconGrid.appendChild(emptyNote(api.icons && api.icons.length ? "没有匹配的图标。" : "等待 icons.js。数据到位后会在这里显示完整功能图标库。"));
      return;
    }

    icons.forEach(function (icon) {
      var card = assetCard(icon.label || icon.id, icon.category || "icon");
      var art = card.querySelector(".asset-card__art");
      if (typeof api.svg === "function") {
        appendSvg(art, api.svg(icon.id, { size: state.size, color: state.color, selected: state.selected }), "icon-svg");
      }
      card.querySelector(".download-button").addEventListener("click", function () {
        if (typeof api.svg === "function") {
          var selectedSuffix = state.selected && icon.selectedBody ? "-selected" : "";
          downloadText(icon.id + selectedSuffix + ".svg", api.svg(icon.id, { size: state.size, color: state.color, selected: state.selected }));
        }
      });
      refs.iconGrid.appendChild(card);
    });
  }

  function renderScenes() {
    var api = sceneApi();
    var scenes = api.scenes || [];
    clearNode(refs.sceneGrid);
    refs.sceneCount.value = String(scenes.length);

    if (!scenes.length) {
      refs.sceneGrid.appendChild(emptyNote("等待 scenes.js。数据到位后会在这里显示空态、运行态和品牌场景。"));
      return;
    }

    scenes.forEach(function (scene) {
      var card = assetCard(scene.label || scene.id, scene.description || scene.id);
      var art = card.querySelector(".asset-card__art");
      if (typeof api.svg === "function") {
        appendSvg(art, api.svg(scene.id, { color: state.color, background: "#faf8f3", rounded: false }), "scene-svg");
      }
      card.querySelector(".download-button").addEventListener("click", function () {
        if (typeof api.svg === "function") {
          downloadText(scene.id + ".svg", api.svg(scene.id, { color: state.color, background: "#faf8f3", rounded: false }));
        }
      });
      refs.sceneGrid.appendChild(card);
    });
  }

  function renderMotionDescription() {
    var motion = currentMotion();
    var typeMeta = MOTION_TYPES.filter(function (entry) { return entry.type === state.motionType; })[0];
    refs.motionDescription.textContent = motion
      ? motion.description || typeMeta.description
      : (typeMeta ? typeMeta.description : "");
  }

  function renderStage(autoplay) {
    cancelAnimations();
    clearNode(refs.motionStage);

    var api = sceneApi();
    var svgText = "";
    if (state.sceneId && typeof api.svg === "function") {
      svgText = api.svg(state.sceneId, { color: state.color, background: "#faf8f3", rounded: false });
    } else if (typeof api.fox === "function") {
      svgText = api.fox({ color: state.color, background: "#faf8f3", rounded: false });
    }

    if (svgText) {
      appendSvg(refs.motionStage, svgText, "motion-svg");
    } else {
      refs.motionStage.appendChild(emptyFragment("等待可播放素材"));
    }

    if (autoplay && !state.reduceMotion && !document.hidden) {
      playMotion();
    }
  }

  function playMotion() {
    if (state.reduceMotion || document.hidden) {
      cancelAnimations();
      setPlaying(false);
      return;
    }
    if (!runningAnimations.length) {
      runningAnimations = createAnimations();
    } else {
      runningAnimations.forEach(function (animation) { animation.play(); });
    }
    setPlaying(true);
  }

  function pauseMotion() {
    runningAnimations.forEach(function (animation) { animation.pause(); });
    setPlaying(false);
  }

  function replayMotion() {
    renderStage(true);
  }

  function createAnimations() {
    var svg = refs.motionStage.querySelector("svg");
    if (!svg || !svg.animate) {
      return [];
    }

    var motion = currentMotion();
    var type = state.motionType;
    var duration = ((motion && motion.duration) || durationFor(type)) / state.speed;
    var loop = motion ? motion.loop !== false : type === "idle" || type === "analyze" || type === "retry";
    var options = {
      duration: duration,
      iterations: loop ? Infinity : 1,
      easing: "cubic-bezier(.3,.02,.2,1)",
      fill: "both",
    };

    var tail = svg.querySelector(".fox-tail") || svg;
    var body = svg.querySelector(".fox-body") || svg;
    var eye = svg.querySelector(".fox-eye");
    var accent = svg.querySelector(".scene-accent");
    var pathGroup = svg.querySelector(".motion-path");
    var path = svg.querySelector(".motion-path path") || pathGroup;
    var animations = [];

    if (type === "idle") {
      animations.push(tail.animate([{ transform: "rotate(0deg)" }, { transform: "rotate(3deg)" }, { transform: "rotate(0deg)" }], options));
      animations.push(body.animate([{ transform: "translateY(0)" }, { transform: "translateY(-2px)" }, { transform: "translateY(0)" }], options));
    } else if (type === "collect") {
      animations.push(tail.animate([{ transform: "rotate(-2deg)" }, { transform: "rotate(3deg)" }, { transform: "rotate(0deg)" }], options));
      animations.push((accent || body).animate([{ transform: "translateY(-8px)", opacity: 0.72 }, { transform: "translateY(0)", opacity: 1 }], options));
    } else if (type === "analyze") {
      if (path) {
        animations.push(path.animate([{ strokeDashoffset: "18" }, { strokeDashoffset: "0" }, { strokeDashoffset: "-18" }], options));
      }
      animations.push((accent || eye || body).animate([{ opacity: 0.54 }, { opacity: 1 }, { opacity: 0.54 }], options));
      animations.push(tail.animate([{ transform: "rotate(0deg)" }, { transform: "rotate(2deg)" }, { transform: "rotate(0deg)" }], options));
    } else if (type === "saved") {
      animations.push((accent || body).animate([{ transform: "scale(.92)", opacity: 0 }, { transform: "scale(1.05)", opacity: 1 }, { transform: "scale(1)", opacity: 1 }], options));
      animations.push(body.animate([{ transform: "translateY(2px)" }, { transform: "translateY(-3px)" }, { transform: "translateY(0)" }], options));
    } else if (type === "empty") {
      animations.push(svg.animate([{ transform: "translateY(10px)", opacity: 0 }, { transform: "translateY(0)", opacity: 1 }], options));
    } else if (type === "retry") {
      animations.push((accent || body).animate([{ transform: "rotate(-3deg)" }, { transform: "rotate(3deg)" }, { transform: "rotate(-1deg)" }, { transform: "rotate(0deg)" }], options));
    } else if (type === "paused") {
      animations.push(tail.animate([{ transform: "rotate(5deg)" }, { transform: "rotate(0deg)" }], Object.assign({}, options, { iterations: 1 })));
    } else if (type === "complete") {
      animations.push((accent || body).animate([{ transform: "scale(.94)", opacity: 0.56 }, { transform: "scale(1.08)", opacity: 1 }, { transform: "scale(1)", opacity: 1 }], Object.assign({}, options, { iterations: 1 })));
    }

    animations.forEach(function (animation) {
      animation.onfinish = function () {
        if (!runningAnimations.some(function (item) { return item.playState === "running"; })) {
          setPlaying(false);
        }
      };
    });
    return animations;
  }

  function currentMotion() {
    var motions = sceneApi().motions || [];
    return motions.filter(function (motion) {
      return motion.type === state.motionType && (!state.sceneId || motion.sceneId === state.sceneId);
    })[0] || motions.filter(function (motion) { return motion.type === state.motionType; })[0] || null;
  }

  function pickSceneForMotion() {
    var motions = sceneApi().motions || [];
    var scenes = sceneApi().scenes || [];
    var motion = motions.filter(function (entry) { return entry.type === state.motionType && entry.sceneId; })[0];
    if (motion && scenes.some(function (scene) { return scene.id === motion.sceneId; })) {
      state.sceneId = motion.sceneId;
      refs.sceneSelect.value = state.sceneId;
    } else if (!state.sceneId && scenes[0]) {
      state.sceneId = scenes[0].id;
      refs.sceneSelect.value = state.sceneId;
    }
  }

  function iconMatches(icon) {
    var matchesCategory = state.category === "all" || (icon.category || "uncategorized") === state.category;
    if (!matchesCategory) {
      return false;
    }
    if (!state.query) {
      return true;
    }
    var haystack = [
      icon.id,
      icon.label,
      icon.category,
      (icon.tags || []).join(" "),
      (icon.material || []).join(" "),
    ].join(" ").toLowerCase();
    return haystack.indexOf(state.query) >= 0;
  }

  function assetCard(title, meta) {
    var card = document.createElement("article");
    card.className = "asset-card";

    var art = document.createElement("div");
    art.className = "asset-card__art";
    card.appendChild(art);

    var titleNode = document.createElement("div");
    titleNode.className = "asset-card__title";
    titleNode.textContent = title;
    card.appendChild(titleNode);

    var metaNode = document.createElement("div");
    metaNode.className = "asset-card__meta";
    metaNode.textContent = meta;
    card.appendChild(metaNode);

    var actions = document.createElement("div");
    actions.className = "asset-card__actions";
    var download = document.createElement("button");
    download.type = "button";
    download.className = "download-button";
    download.textContent = "SVG";
    download.setAttribute("aria-label", "下载" + title + " SVG");
    actions.appendChild(download);
    card.appendChild(actions);
    return card;
  }

  function appendSvg(target, svgText, className) {
    var parser = new DOMParser();
    var doc = parser.parseFromString(svgText, "image/svg+xml");
    var svg = doc.documentElement;
    if (!svg || svg.nodeName.toLowerCase() !== "svg" || doc.querySelector("parsererror")) {
      target.appendChild(emptyFragment("SVG 解析失败"));
      return;
    }
    var imported = document.importNode(svg, true);
    imported.classList.add(className);
    imported.setAttribute("focusable", "false");
    target.appendChild(imported);
  }

  function emptyNote(text) {
    var note = document.createElement("div");
    note.className = "empty-note";
    note.textContent = text;
    return note;
  }

  function emptyFragment(text) {
    var note = document.createElement("div");
    note.className = "empty-note";
    note.textContent = text;
    return note;
  }

  function optionNode(value, label) {
    var option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    return option;
  }

  function clearNode(node) {
    while (node.firstChild) {
      node.removeChild(node.firstChild);
    }
  }

  function unique(values) {
    return values.filter(function (value, index, list) {
      return value && list.indexOf(value) === index;
    });
  }

  function setPressed(selector, value) {
    Array.prototype.forEach.call(document.querySelectorAll(selector), function (button) {
      button.setAttribute("aria-pressed", String(button.getAttribute(selector.slice(1, -1)) === value));
    });
  }

  function cancelAnimations() {
    runningAnimations.forEach(function (animation) { animation.cancel(); });
    runningAnimations = [];
    setPlaying(false);
  }

  function setPlaying(isPlaying) {
    refs.playButton.classList.toggle("is-active", isPlaying);
    refs.pauseButton.classList.toggle("is-active", !isPlaying && runningAnimations.some(function (animation) { return animation.playState === "paused"; }));
  }

  function isMotionRunning() {
    return runningAnimations.some(function (animation) { return animation.playState === "running"; });
  }

  function durationFor(type) {
    if (type === "saved" || type === "complete") {
      return 760;
    }
    if (type === "empty" || type === "paused") {
      return 900;
    }
    return 1400;
  }

  function downloadText(filename, text) {
    var blob = new Blob([text], { type: "image/svg+xml;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }
})();
