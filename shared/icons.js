'use strict';

// Small inline SVG icons for HUD buttons (these render the same on every device, unlike emoji).
const Icons = {
  pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>',
  sound(on) {
    const waves = on
      ? '<path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'
      : '<path d="M16 9l5 6M21 9l-5 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>';
    return `<svg viewBox="0 0 24 24"><path d="M3 9h4l5-4v14l-5-4H3z" fill="currentColor"/>${waves}</svg>`;
  },
};
