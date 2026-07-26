(() => {
  const header = document.querySelector("[data-header]");
  const nav = document.querySelector("[data-nav]");
  const toggle = document.querySelector("[data-nav-toggle]");

  const setScrolled = () => {
    if (!header) return;
    header.classList.toggle("is-scrolled", window.scrollY > 8);
  };

  const closeNav = () => {
    if (!nav || !toggle) return;
    nav.classList.remove("is-open");
    toggle.setAttribute("aria-expanded", "false");
  };

  const openNav = () => {
    if (!nav || !toggle) return;
    nav.classList.add("is-open");
    toggle.setAttribute("aria-expanded", "true");
  };

  setScrolled();
  window.addEventListener("scroll", setScrolled, { passive: true });

  if (toggle && nav) {
    toggle.addEventListener("click", () => {
      const expanded = toggle.getAttribute("aria-expanded") === "true";
      if (expanded) {
        closeNav();
      } else {
        openNav();
      }
    });

    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", closeNav);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeNav();
    });

    document.addEventListener("click", (event) => {
      if (!nav.classList.contains("is-open")) return;
      if (nav.contains(event.target) || toggle.contains(event.target)) return;
      closeNav();
    });
  }

  const downloadMenu = document.querySelector("[data-download-menu]");
  const downloadToggle = document.querySelector("[data-download-toggle]");
  const downloadPanel = document.querySelector("[data-download-panel]");

  if (downloadMenu && downloadToggle && downloadPanel) {
    const closeDownloadMenu = () => {
      downloadMenu.classList.remove("is-open");
      downloadToggle.setAttribute("aria-expanded", "false");
    };

    downloadToggle.addEventListener("click", () => {
      const isOpen = downloadMenu.classList.toggle("is-open");
      downloadToggle.setAttribute("aria-expanded", isOpen ? "true" : "false");
    });

    downloadPanel.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", closeDownloadMenu);
    });

    document.addEventListener("click", (event) => {
      if (!downloadMenu.classList.contains("is-open")) return;
      if (downloadMenu.contains(event.target)) return;
      closeDownloadMenu();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      if (!downloadMenu.classList.contains("is-open")) return;
      closeDownloadMenu();
      downloadToggle.focus();
    });
  }

  const carousel = document.querySelector("[data-carousel]");
  if (!carousel) return;

  const slides = Array.from(carousel.querySelectorAll("[data-slide]"));
  const prevBtn = carousel.querySelector("[data-carousel-prev]");
  const nextBtn = carousel.querySelector("[data-carousel-next]");
  const dotsRoot = carousel.querySelector("[data-carousel-dots]");
  const labelEl = carousel.querySelector("[data-carousel-label]");
  const captionEl = carousel.querySelector("[data-carousel-caption]");
  const stage = carousel.querySelector("[data-carousel-stage]");
  const reduceMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  let index = 0;
  let autoplayId = null;
  let isPaused = false;
  let touchStartX = 0;
  let touchDeltaX = 0;

  const wrap = (value) => {
    const total = slides.length;
    return ((value % total) + total) % total;
  };

  const updateMeta = () => {
    const active = slides[index];
    if (!active) return;

    const label = active.dataset.label || "";
    const caption = active.dataset.caption || "";

    if (!labelEl || !captionEl) return;

    if (reduceMotion) {
      labelEl.textContent = label;
      captionEl.textContent = caption;
      return;
    }

    captionEl.classList.add("is-fading");
    window.setTimeout(() => {
      labelEl.textContent = label;
      captionEl.textContent = caption;
      captionEl.classList.remove("is-fading");
    }, 160);
  };

  const render = () => {
    slides.forEach((slide, i) => {
      slide.classList.remove(
        "is-active",
        "is-prev",
        "is-next",
        "is-far-prev",
        "is-far-next",
        "is-hidden",
        "is-prev-dir",
        "is-next-dir",
      );

      const offset = wrap(i - index);
      const mirrored = offset > slides.length / 2 ? offset - slides.length : offset;

      if (mirrored === 0) {
        slide.classList.add("is-active");
        slide.setAttribute("aria-hidden", "false");
        slide.tabIndex = 0;
      } else if (mirrored === -1) {
        slide.classList.add("is-prev");
        slide.setAttribute("aria-hidden", "true");
        slide.tabIndex = -1;
      } else if (mirrored === 1) {
        slide.classList.add("is-next");
        slide.setAttribute("aria-hidden", "true");
        slide.tabIndex = -1;
      } else if (mirrored === -2) {
        slide.classList.add("is-far-prev");
        slide.setAttribute("aria-hidden", "true");
        slide.tabIndex = -1;
      } else if (mirrored === 2) {
        slide.classList.add("is-far-next");
        slide.setAttribute("aria-hidden", "true");
        slide.tabIndex = -1;
      } else {
        slide.classList.add("is-hidden");
        slide.classList.add(mirrored < 0 ? "is-prev-dir" : "is-next-dir");
        slide.setAttribute("aria-hidden", "true");
        slide.tabIndex = -1;
      }
    });

    if (dotsRoot) {
      dotsRoot.querySelectorAll(".shot-dot").forEach((dot, i) => {
        const active = i === index;
        dot.classList.toggle("is-active", active);
        dot.setAttribute("aria-selected", active ? "true" : "false");
        dot.tabIndex = active ? 0 : -1;
      });
    }

    updateMeta();
  };

  const goTo = (nextIndex) => {
    index = wrap(nextIndex);
    render();
  };

  const next = () => goTo(index + 1);
  const prev = () => goTo(index - 1);

  const stopAutoplay = () => {
    if (autoplayId != null) {
      window.clearInterval(autoplayId);
      autoplayId = null;
    }
  };

  const startAutoplay = () => {
    if (reduceMotion || isPaused) return;
    stopAutoplay();
    autoplayId = window.setInterval(next, 4200);
  };

  if (dotsRoot) {
    slides.forEach((slide, i) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "shot-dot";
      button.setAttribute("role", "tab");
      button.setAttribute("aria-label", slide.dataset.label || `Screenshot ${i + 1}`);
      button.textContent = slide.dataset.label || String(i + 1);
      button.addEventListener("click", () => {
        goTo(i);
        startAutoplay();
      });
      dotsRoot.appendChild(button);
    });
  }

  prevBtn?.addEventListener("click", () => {
    prev();
    startAutoplay();
  });

  nextBtn?.addEventListener("click", () => {
    next();
    startAutoplay();
  });

  slides.forEach((slide, i) => {
    slide.addEventListener("click", () => {
      if (i === index) return;
      goTo(i);
      startAutoplay();
    });
  });

  carousel.addEventListener("keydown", (event) => {
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      prev();
      startAutoplay();
    } else if (event.key === "ArrowRight") {
      event.preventDefault();
      next();
      startAutoplay();
    }
  });

  const pause = () => {
    isPaused = true;
    stopAutoplay();
  };

  const resume = () => {
    isPaused = false;
    startAutoplay();
  };

  carousel.addEventListener("mouseenter", pause);
  carousel.addEventListener("mouseleave", resume);
  carousel.addEventListener("focusin", pause);
  carousel.addEventListener("focusout", (event) => {
    if (!carousel.contains(event.relatedTarget)) resume();
  });

  if (stage) {
    stage.addEventListener(
      "touchstart",
      (event) => {
        touchStartX = event.changedTouches[0]?.clientX ?? 0;
        touchDeltaX = 0;
        pause();
      },
      { passive: true },
    );

    stage.addEventListener(
      "touchmove",
      (event) => {
        const x = event.changedTouches[0]?.clientX ?? touchStartX;
        touchDeltaX = x - touchStartX;
      },
      { passive: true },
    );

    stage.addEventListener(
      "touchend",
      () => {
        if (Math.abs(touchDeltaX) > 48) {
          if (touchDeltaX < 0) next();
          else prev();
        }
        resume();
      },
      { passive: true },
    );
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopAutoplay();
    else startAutoplay();
  });

  render();
  startAutoplay();
})();
