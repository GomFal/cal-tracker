const revealTargets = document.querySelectorAll("[data-reveal]");

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    },
    { rootMargin: "0px 0px -12% 0px", threshold: 0.16 },
  );

  revealTargets.forEach((target) => observer.observe(target));
} else {
  revealTargets.forEach((target) => target.classList.add("is-visible"));
}

const flowComparisons = [...document.querySelectorAll("[data-flow-comparison]")];

if (flowComparisons.length > 0) {
  const flowCycleMs = 16000;
  const flowProfiles = {
    manual: {
      finishMs: 15040,
      clicks: [720, 2720, 3760, 4560, 5000, 7200, 8240, 9040, 9440, 11680, 14720],
    },
    better: {
      finishMs: 7680,
      clicks: [1280, 7360],
    },
  };
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const flowStates = new Map(
    flowComparisons.map((comparison) => [
      comparison,
      { visible: false, elapsed: 0, lastFrame: null, frame: null },
    ]),
  );

  const formatFlowTime = (milliseconds) => {
    const totalTenths = Math.floor(milliseconds / 100);
    const minutes = Math.floor(totalTenths / 600);
    const seconds = Math.floor(totalTenths / 10) % 60;
    const tenths = totalTenths % 10;
    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}.${tenths}`;
  };

  const renderFlowMetrics = (comparison, elapsed, showFinal = false) => {
    for (const [name, profile] of Object.entries(flowProfiles)) {
      const currentTime = showFinal
        ? profile.finishMs
        : Math.min(elapsed, profile.finishMs);
      const clickCount = showFinal
        ? profile.clicks.length
        : profile.clicks.filter((moment) => moment <= elapsed).length;
      const timer = comparison.querySelector(`[data-flow-timer="${name}"]`);
      const clicks = comparison.querySelector(`[data-flow-clicks="${name}"]`);
      const formattedTime = formatFlowTime(currentTime);
      const formattedClicks = String(clickCount);
      if (timer && timer.textContent !== formattedTime) {
        timer.textContent = formattedTime;
      }
      if (clicks && clicks.textContent !== formattedClicks) {
        clicks.textContent = formattedClicks;
      }
    }
  };

  const stopFlowMetrics = (state) => {
    if (state.frame !== null) cancelAnimationFrame(state.frame);
    state.frame = null;
    state.lastFrame = null;
  };

  const tickFlowMetrics = (comparison, timestamp) => {
    const state = flowStates.get(comparison);
    if (!state) return;
    if (state.lastFrame !== null) {
      state.elapsed = (state.elapsed + timestamp - state.lastFrame) % flowCycleMs;
    }
    state.lastFrame = timestamp;
    renderFlowMetrics(comparison, state.elapsed);
    state.frame = requestAnimationFrame((nextTimestamp) =>
      tickFlowMetrics(comparison, nextTimestamp),
    );
  };

  const startFlowMetrics = (comparison, state) => {
    if (state.frame !== null) return;
    state.frame = requestAnimationFrame((timestamp) =>
      tickFlowMetrics(comparison, timestamp),
    );
  };

  const syncFlowPlayback = () => {
    for (const comparison of flowComparisons) {
      const state = flowStates.get(comparison);
      if (!state) continue;
      const shouldPlay =
        state.visible && !document.hidden && !reducedMotion.matches;
      comparison.classList.toggle("is-playing", Boolean(shouldPlay));
      if (reducedMotion.matches) {
        stopFlowMetrics(state);
        renderFlowMetrics(comparison, state.elapsed, true);
      } else if (shouldPlay) {
        startFlowMetrics(comparison, state);
      } else {
        stopFlowMetrics(state);
        renderFlowMetrics(comparison, state.elapsed);
      }
    }
  };

  flowComparisons.forEach((comparison) =>
    renderFlowMetrics(comparison, 0, reducedMotion.matches),
  );

  if ("IntersectionObserver" in window) {
    const flowObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const state = flowStates.get(entry.target);
          if (state) state.visible = entry.isIntersecting;
        }
        syncFlowPlayback();
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.24 },
    );

    flowComparisons.forEach((comparison) => flowObserver.observe(comparison));
  } else {
    flowStates.forEach((state) => {
      state.visible = true;
    });
    syncFlowPlayback();
  }

  document.addEventListener("visibilitychange", syncFlowPlayback);
  reducedMotion.addEventListener?.("change", () => {
    if (!reducedMotion.matches) {
      flowStates.forEach((state) => {
        state.elapsed = 0;
      });
    }
    syncFlowPlayback();
  });
}

document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (event) => {
    const targetId = link.getAttribute("href");
    if (!targetId || targetId === "#") return;
    const target = document.querySelector(targetId);
    if (!target) return;
    event.preventDefault();
    target.scrollIntoView({ behavior: "smooth", block: "start" });
    history.pushState(null, "", targetId);
  });
});
