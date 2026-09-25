'use strict';

// Small inline SVG icons for HUD buttons (these render the same on every device, unlike emoji).
const Icons = {
  lock: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3" fill="none" stroke="currentColor" stroke-width="2.5"/></svg>',
  pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>',
  music(on) {
    const slash = on ? '' : '<path d="M3 3l18 18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>';
    return `<svg viewBox="0 0 24 24"><path d="M9 17V5l10-2v12" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><circle cx="6.5" cy="17.5" r="2.5" fill="currentColor"/><circle cx="16.5" cy="15.5" r="2.5" fill="currentColor"/>${slash}</svg>`;
  },
  sound(on) {
    const waves = on
      ? '<path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'
      : '<path d="M16 9l5 6M21 9l-5 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>';
    return `<svg viewBox="0 0 24 24"><path d="M3 9h4l5-4v14l-5-4H3z" fill="currentColor"/>${waves}</svg>`;
  },
};
