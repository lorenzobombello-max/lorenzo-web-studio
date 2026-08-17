(function () {
  "use strict";

  const flow = document.querySelector("[data-document-flow]");
  if (!flow) return;

  const status = flow.querySelector("[data-flow-status]");
  const description = flow.querySelector("[data-flow-description]");
  const toggle = flow.querySelector("[data-flow-toggle]");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const stages = [
    ["Ontvangen", "Een leeg document komt de flow binnen."],
    ["Aanvullen", "De eerste bruikbare gegevens verschijnen."],
    ["Verwerken", "Meer informatie krijgt een vaste structuur."],
    ["Controleren", "Velden worden gericht nagekeken."],
    ["Klaar", "Het complete document verlaat de flow."],
  ];
  let step = reducedMotion.matches ? stages.length - 1 : 0;
  let paused = reducedMotion.matches;
  let visible = false;
  let timer = 0;

  function render() {
    flow.dataset.step = String(step);
    flow.style.setProperty("--flow-step", String(step));
    status.textContent = stages[step][0];
    description.textContent = stages[step][1];
  }

  function stop() {
    window.clearInterval(timer);
    timer = 0;
  }

  function start() {
    stop();
    if (paused || !visible || reducedMotion.matches || document.hidden) return;
    timer = window.setInterval(() => {
      step = (step + 1) % stages.length;
      render();
    }, 2200);
  }

  toggle.addEventListener("click", () => {
    paused = !paused;
    toggle.textContent = paused ? "Hervat animatie" : "Pauzeer animatie";
    toggle.setAttribute("aria-pressed", String(paused));
    start();
  });

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver((entries) => {
      visible = entries.some((entry) => entry.isIntersecting);
      start();
    }, { threshold: 0.2 });
    observer.observe(flow);
  } else {
    visible = true;
    start();
  }

  document.addEventListener("visibilitychange", start);
  reducedMotion.addEventListener?.("change", () => {
    paused = reducedMotion.matches;
    step = reducedMotion.matches ? stages.length - 1 : 0;
    render();
    start();
  });
  render();
})();