'use strict';

// Menu chrome: an icon set for the home screen, and a header (back arrow, title, coins)
// added to every sub-screen. Loaded before game.js so its buttons get the normal handlers.

const UI_ICONS = {
  shop: '<path d="M5 8h14l-1.2 11.2a2 2 0 0 1-2 1.8H8.2a2 2 0 0 1-2-1.8z" fill="currentColor"/><path d="M9 10V7a3 3 0 0 1 6 0v3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  missions: '<rect x="4" y="3" width="16" height="18" rx="3" fill="currentColor"/><path d="M8 9l1.5 1.5L12 8M8 15l1.5 1.5L12 14" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M14 9.5h3M14 15.5h3" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>',
  pass: '<path d="M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z" fill="currentColor"/><path d="M12 7.5l1.2 2.5 2.7.4-2 1.9.5 2.7-2.4-1.3-2.4 1.3.5-2.7-2-1.9 2.7-.4z" fill="#fff"/>',
  clan: '<path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5z" fill="currentColor"/><path d="M8 11l3 3 5-6" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  profile: '<circle cx="12" cy="8" r="4.2" fill="currentColor"/><path d="M4 21a8 8 0 0 1 16 0z" fill="currentColor"/>',
  gear: '<path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 2.5l1.6 2.3 2.7-.6.6 2.7 2.3 1.6-1.2 2.5 1.2 2.5-2.3 1.6-.6 2.7-2.7-.6L12 21.5l-1.6-2.3-2.7.6-.6-2.7-2.3-1.6L6 13 4.8 10.5l2.3-1.6.6-2.7 2.7.6z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  back: '<path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>',
  trophy: '<path d="M7 3h10v4a5 5 0 0 1-10 0z" fill="currentColor"/><path d="M5 4H2v2a4 4 0 0 0 4 4M19 4h3v2a4 4 0 0 1-4 4" fill="none" stroke="currentColor" stroke-width="1.8"/><rect x="10.5" y="11" width="3" height="5" fill="currentColor"/><rect x="7" y="17" width="10" height="3" rx="1" fill="currentColor"/>',
  stats: '<rect x="4" y="12" width="4" height="8" rx="1.5" fill="currentColor"/><rect x="10" y="7" width="4" height="13" rx="1.5" fill="currentColor"/><rect x="16" y="3" width="4" height="17" rx="1.5" fill="currentColor"/>',
  rank: '<path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5z" fill="currentColor"/><path d="M12 7l1.5 3.1 3.3.5-2.4 2.3.6 3.3-3-1.6-3 1.6.6-3.3-2.4-2.3 3.3-.5z" fill="#fff"/>',
  challenge: '<path d="M4 20l7-7M14 4l6 0 0 6-9 9-2-2-2 2-2-2 2-2-2-2z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/><path d="M20 20l-4-4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  editor: '<rect x="3" y="3" width="18" height="18" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3 9h18M9 3v18" stroke="currentColor" stroke-width="2"/><rect x="11" y="11" width="8" height="8" rx="1" fill="currentColor"/>',
  help: '<circle cx="12" cy="12" r="9.5" fill="currentColor"/><path d="M9.5 9.3a2.6 2.6 0 1 1 3.6 2.4c-.8.4-1.1.9-1.1 1.8" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="17" r="1.3" fill="#fff"/>',
  install: '<path d="M12 3v11M7 9l5 5 5-5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/>',
  upgrade: '<path d="M12 3l7 7h-4v8H9v-8H5z" fill="currentColor"/><rect x="7" y="19" width="10" height="2.5" rx="1" fill="currentColor"/>',
  // Game modes
  classic: '<rect x="4" y="4" width="16" height="16" rx="4" fill="currentColor"/><rect x="8" y="8" width="8" height="8" rx="2" fill="#fff" opacity="0.55"/>',
  timed: '<circle cx="12" cy="13" r="8" fill="currentColor"/><path d="M12 9v4l3 2" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/><rect x="9.5" y="2" width="5" height="2.5" rx="1" fill="currentColor"/>',
  daily: '<rect x="3" y="5" width="18" height="16" rx="3" fill="currentColor"/><path d="M3 10h18" stroke="#fff" stroke-width="1.8"/><path d="M8 3v4M16 3v4" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><rect x="7" y="13" width="4" height="4" rx="1" fill="#fff"/>',
  weekly: '<path d="M5 21V10a7 7 0 0 1 14 0v11l-2.4-1.8L14.3 21 12 19.2 9.7 21l-2.3-1.8z" fill="currentColor"/><circle cx="9.5" cy="10.5" r="1.6" fill="#fff"/><circle cx="14.5" cy="10.5" r="1.6" fill="#fff"/>',
  marathon: '<path d="M6 21V3" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/><path d="M7 4h11l-2.5 4L18 12H7z" fill="currentColor"/>',
  cup: '<path d="M6 3h12v5a6 6 0 0 1-12 0z" fill="currentColor"/><path d="M6 5H3v1.5A3.5 3.5 0 0 0 6.5 10M18 5h3v1.5A3.5 3.5 0 0 1 17.5 10" fill="none" stroke="currentColor" stroke-width="1.8"/><rect x="10.5" y="13" width="3" height="4" fill="currentColor"/><rect x="7" y="17.5" width="10" height="3.5" rx="1.2" fill="currentColor"/>',
  duo: '<circle cx="8" cy="8" r="3.3" fill="currentColor"/><circle cx="16.5" cy="8" r="3.3" fill="currentColor" opacity="0.65"/><path d="M1.5 20a6.5 6.5 0 0 1 13 0z" fill="currentColor"/><path d="M10 20a6.5 6.5 0 0 1 13 0z" fill="currentColor" opacity="0.65"/>',
  team: '<circle cx="12" cy="7" r="3.2" fill="currentColor"/><circle cx="5" cy="9" r="2.5" fill="currentColor" opacity="0.65"/><circle cx="19" cy="9" r="2.5" fill="currentColor" opacity="0.65"/><path d="M6 21a6 6 0 0 1 12 0z" fill="currentColor"/><path d="M0.5 20a4.5 4.5 0 0 1 7-3.7M23.5 20a4.5 4.5 0 0 0-7-3.7" fill="none" stroke="currentColor" stroke-width="1.8" opacity="0.65"/>',
  puzzle: '<path d="M4 8h4a2.2 2.2 0 1 1 4 0h4v4a2.2 2.2 0 1 1 0 4v4H4v-4a2.2 2.2 0 1 0 0-4z" fill="currentColor"/>',
  custom: '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/><circle cx="16" cy="6" r="2.6" fill="currentColor"/><circle cx="10" cy="12" r="2.6" fill="currentColor"/><circle cx="18" cy="18" r="2.6" fill="currentColor"/>',
  share: '<path d="M12 3v12M7 8l5-5 5 5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/>',
  boss: '<path d="M3 8l4.5 4L12 4l4.5 8L21 8l-2 12H5z" fill="currentColor"/><circle cx="12" cy="15" r="1.8" fill="#fff"/>',
};

const uiIcon = (name, cls = 'ui-icon') => (UI_ICONS[name] ? `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${UI_ICONS[name]}</svg>` : '');

// Screens that keep their own layout (no header bar)
const NO_HEADER = ['menu', 'over', 'paused', 'howto', 'cup'];

function buildScreenHeaders() {
  for (const screen of document.querySelectorAll('.screen')) {
    if (NO_HEADER.includes(screen.id) || screen.querySelector('.screen-head')) continue;
    const title = screen.querySelector('h2');
    const head = document.createElement('div');
    head.className = 'screen-head';
    head.innerHTML = `<button class="back-btn" data-back aria-label="Back">${uiIcon('back')}</button>`
      + `<h2>${title ? title.innerHTML : ''}</h2>`
      + '<span class="wallet mini"><span class="coin"></span> <span class="coin-count">0</span></span>';
    if (title) title.remove();
    screen.prepend(head);
  }
  // Icons on the dock, the tiles and other buttons that ask for one
  for (const el of document.querySelectorAll('[data-icon]')) el.insertAdjacentHTML('afterbegin', uiIcon(el.dataset.icon));
}
buildScreenHeaders();
