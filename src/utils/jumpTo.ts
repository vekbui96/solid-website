// In-page jump for the nav and hero buttons. Fragment links don't cross the
// shadow boundary, so the site scrolls by hand; this also does the part an
// #anchor link gives for free: moving keyboard focus to the target, so the
// next Tab continues inside the section (and screen readers announce it).
export const jumpTo = (el?: HTMLElement | null) => {
    if (!el) return;
    const reduce = !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    el.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" });
    if (!el.hasAttribute("tabindex")) el.setAttribute("tabindex", "-1");
    // styled with outline: none; a section is never reached by Tab itself
    el.classList.add("hp-jump-target");
    el.focus({ preventScroll: true });
};
