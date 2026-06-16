/**
 * Tello GLB viewer bridge — model-viewer + spinning prop nodes.
 * Prop parents: pervane.001_1 … pervane.004_7
 */
(function () {
  if (window.telloGlbEngineV3) return;
  window.telloGlbEngineV3 = true;

  const MV_ID = 'tello_glb_mv';
  const PROP_NAMES = [
    'pervane.001_1',
    'pervane.002_3',
    'pervane.003_5',
    'pervane.004_7',
  ];

  const pending = { orientation: '0deg 0deg 0deg', speeds: [0, 0, 0, 0] };
  let activeMv = null;
  let propNodes = [];
  let rafId = 0;
  let lastTs = 0;
  let lastBindNames = [];

  function findMv(root) {
    if (!root) return null;
    if (root.tagName === 'MODEL-VIEWER') return root;
    const inRoot = root.querySelector?.('model-viewer#' + MV_ID + ', model-viewer');
    if (inRoot) return inRoot;
    return null;
  }

  function scanShadows() {
    const hosts = document.querySelectorAll('flt-glass-pane, flt-platform-view, flt-scene-host');
    for (const h of hosts) {
      if (h.shadowRoot) {
        const mv = findMv(h.shadowRoot);
        if (mv) return mv;
      }
    }
    return findMv(document);
  }

  function getModelScene(mv) {
    const sceneSym = Object.getOwnPropertySymbols(mv).find(
      (s) => s.description === 'scene'
    );
    return sceneSym ? mv[sceneSym] : null;
  }

  /** All Three.js roots that may contain named glTF nodes. */
  function getThreeRoots(mv) {
    const scene = getModelScene(mv);
    if (!scene) return [];

    const roots = [];
    const seen = new Set();
    const add = (obj) => {
      if (!obj || typeof obj.traverse !== 'function') return;
      if (seen.has(obj)) return;
      seen.add(obj);
      roots.push(obj);
    };

    add(scene.threeGLTF?.scene);
    add(scene.model);
    if (scene.threeGLTF) add(scene.threeGLTF);

    for (const sym of Object.getOwnPropertySymbols(scene)) {
      try {
        const val = scene[sym];
        if (val?.scene?.traverse) add(val.scene);
        if (val?.scenes?.length) val.scenes.forEach((s) => add(s));
        if (val?.isObject3D) add(val);
      } catch (_) {
        /* ignore private getters */
      }
    }

    const direct = mv.model;
    if (direct && typeof direct.traverse === 'function') add(direct);

    return roots;
  }

  function bindProps(mv) {
    const roots = getThreeRoots(mv);
    if (!roots.length) return false;

    const map = {};
    const allNames = [];

    for (const root of roots) {
      root.traverse((obj) => {
        if (obj.name) allNames.push(obj.name);
        const idx = PROP_NAMES.indexOf(obj.name);
        if (idx >= 0) map[idx] = obj;
      });
    }

    lastBindNames = allNames;

    if (Object.keys(map).length < 4) {
      const pervane = [];
      for (const root of roots) {
        root.traverse((obj) => {
          if (obj.name && /pervane/i.test(obj.name)) pervane.push(obj);
        });
      }
      pervane.sort((a, b) => a.name.localeCompare(b.name));
      for (let i = 0; i < 4 && i < pervane.length; i++) {
        if (!map[i]) map[i] = pervane[i];
      }
    }

    if (Object.keys(map).length < 4) {
      let sceneRoot = null;
      for (const root of roots) {
        root.traverse((obj) => {
          if (obj.name === 'GLTF_SceneRootNode') sceneRoot = obj;
        });
      }
      if (sceneRoot && sceneRoot.children.length >= 4) {
        for (let i = 0; i < 4; i++) map[i] = sceneRoot.children[i];
      }
    }

    propNodes = PROP_NAMES.map((_, i) => map[i] || null);
    return propNodes.some(Boolean);
  }

  function applyOrientation(mv) {
    if (pending.orientation) mv.setAttribute('orientation', pending.orientation);
  }

  function tick(ts) {
    rafId = requestAnimationFrame(tick);
    if (!activeMv) return;
    const dt = lastTs ? Math.min((ts - lastTs) / 1000, 0.05) : 0;
    lastTs = ts;
    if (dt <= 0) return;

    let moved = false;
    for (let i = 0; i < propNodes.length; i++) {
      const node = propNodes[i];
      const speed = pending.speeds[i] || 0;
      if (!node || Math.abs(speed) < 0.01) continue;
      node.rotation.y += speed * dt;
      moved = true;
    }
    if (moved && activeMv.queueRender) activeMv.queueRender();
  }

  function startLoop() {
    if (rafId) return;
    lastTs = 0;
    rafId = requestAnimationFrame(tick);
  }

  function tryBind(mv, attempt) {
    applyOrientation(mv);
    if (bindProps(mv)) {
      startLoop();
      if (mv.queueRender) mv.queueRender();
      return;
    }
    if (attempt < 15) {
      setTimeout(() => tryBind(mv, attempt + 1), 150);
    }
  }

  function hookMv(mv) {
    if (!mv) return;
    const isNew = mv !== activeMv;
    if (isNew) {
      activeMv = mv;
      propNodes = [];
    }
    if (isNew || propNodes.filter(Boolean).length === 0) {
      if (mv.loaded) tryBind(mv, 0);
      else mv.addEventListener('load', () => tryBind(mv, 0), { once: true });
    }
  }

  window.telloGlbRegisterHost = function (host) {
    const mv = findMv(host);
    if (mv) hookMv(mv);
  };

  window.telloGlbSetOrientation = function (ori) {
    pending.orientation = ori;
    const mv = activeMv || scanShadows();
    if (mv) {
      applyOrientation(mv);
      if (mv.queueRender) mv.queueRender();
    }
  };

  window.telloGlbSetPropSpeeds = function (s0, s1, s2, s3) {
    pending.speeds = [s0, s1, s2, s3];
    const mv = activeMv || scanShadows();
    if (mv) hookMv(mv);
  };

  window.telloGlbDiag = function () {
    return {
      engine: 'v3',
      active: !!activeMv,
      propsBound: propNodes.filter(Boolean).length,
      propNames: propNodes.filter(Boolean).map((n) => n.name),
      sceneRoots: activeMv ? getThreeRoots(activeMv).length : 0,
      sampleNames: lastBindNames.filter((n) => /pervane|Object_/i.test(n)).slice(0, 12),
      speeds: pending.speeds,
      orientation: pending.orientation,
    };
  };

  function boot() {
    const mv = scanShadows();
    if (mv) hookMv(mv);
  }

  if (customElements.get('model-viewer')) boot();
  else customElements.whenDefined('model-viewer').then(boot);

  setInterval(boot, 1500);
})();
