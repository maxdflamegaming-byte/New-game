'use strict';

// The leaderboard and clans. Both live on the server (server/server.js), so these screens
// connect first (waking the free server if it's asleep) and then ask it for lists.

const EMBLEMS = ['🦁', '🐺', '🦅', '🐉', '🦈', '🐻', '⚡', '🔥', '❄️', '🌟', '🚀', '🛡️', '⚔️', '👑', '🍀', '💎'];
const CLAN_COLORS = ['#3d9bff', '#ff5257', '#ffc21f', '#45d35a', '#a66bff', '#ff8a3d', '#2ec3e0', '#ff6fb5'];
const CLAN_SIZE = 25;

// Connect, showing progress in a screen's status line. Returns false (and says why) if it can't.
async function goOnline(statusId) {
  const status = $(statusId);
  ensureName();
  status.textContent = 'Connecting…';
  try {
    await Net.connect(text => { status.textContent = text; });
    status.textContent = '';
    return true;
  } catch (err) {
    status.textContent = err.message === 'old'
      ? 'This version of the game is too old for the server. Please update it.'
      : 'Can\'t reach the server right now. Try again in a little while.';
    return false;
  }
}
const medal = i => (i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `<span class="rank">${i + 1}</span>`);
const emblemHtml = c => `<div class="emblem" style="background:${c.color}">${c.emblem}</div>`;

// ---------- Leaderboard ----------
let boardTab = 'players', boardData = null;
async function openBoard(tab = boardTab) {
  boardTab = tab;
  showScreen('board');
  renderBoard();
  if (!await goOnline('board-status')) return;
  try {
    boardData = await Net.request({ t: 'top' }, ['top']);
    renderBoard();
  } catch {
    $('board-status').textContent = 'The server didn\'t answer. Try again.';
  }
}
function renderBoard() {
  for (const b of document.querySelectorAll('#board .tab')) b.classList.toggle('on', b.dataset.tab === boardTab);
  const list = $('board-list');
  if (!boardData) { list.innerHTML = ''; return; }
  if (boardTab === 'players') {
    const rows = boardData.players.map((p, i) => `<div class="lb-row${p.id === save.pid ? ' me' : ''}">
      ${medal(i)}${avatarHtml(p.name, p.id === save.pid ? PLAYER : 2)}
      <div class="lb-name">${p.tag ? `<em>[${escapeHtml(p.tag)}]</em> ` : ''}${escapeHtml(p.name)}</div>
      <div class="lb-score">🏆 ${p.trophies}</div></div>`);
    if (!boardData.players.some(p => p.id === save.pid)) {
      rows.push(`<div class="lb-row me">${boardData.rank ? `<span class="rank">${boardData.rank}</span>` : '<span class="rank">–</span>'}${avatarHtml(save.name, PLAYER)}
        <div class="lb-name">${save.clan ? `<em>[${escapeHtml(save.clan.tag)}]</em> ` : ''}${escapeHtml(save.name)}</div>
        <div class="lb-score">🏆 ${save.trophies}</div></div>`);
    }
    list.innerHTML = rows.join('') || '<p class="empty">No one has played online yet. Be the first!</p>';
  } else {
    list.innerHTML = boardData.clans.map((c, i) => `<div class="lb-row${save.clan?.id === c.id ? ' me' : ''}" data-clan="${c.id}">
      ${medal(i)}${emblemHtml(c)}
      <div class="lb-name">${escapeHtml(c.name)} <em>[${escapeHtml(c.tag)}]</em><small>${c.members}/${CLAN_SIZE} members</small></div>
      <div class="lb-score">🏆 ${c.trophies}</div></div>`).join('') || '<p class="empty">No clans yet. Start one!</p>';
  }
  $('board-me').innerHTML = `Your rank: <b>${boardData.rank || '–'}</b> · 🏆 ${save.trophies} · ${leagueOf(save.trophies).name}`;
}

// ---------- Clans ----------
let clanView = null;   // the clan being looked at (details from the server)
let newClan = { emblem: EMBLEMS[0], color: CLAN_COLORS[0] };

async function openClans() {
  showScreen('clans');
  $('clan-mine').classList.add('hidden');
  $('clan-browse').classList.add('hidden');
  if (!await goOnline('clans-status')) return;
  // Ask who we are first: a leader may have removed us since
  try { await Net.request({ t: 'whoami' }, ['me']); } catch { /* use what we have */ }
  if (save.clan) await showClan(save.clan.id);
  else await browseClans();
}

async function browseClans(q = '') {
  clanView = null;
  $('clan-mine').classList.add('hidden');
  $('clan-browse').classList.remove('hidden');
  renderPickers();
  try {
    const res = await Net.request({ t: 'clans', q }, ['clans']);
    $('clan-list').innerHTML = res.list.map(c => `<div class="lb-row" data-clan="${c.id}">
      ${emblemHtml(c)}
      <div class="lb-name">${escapeHtml(c.name)} <em>[${escapeHtml(c.tag)}]</em><small>${c.members}/${CLAN_SIZE} members</small></div>
      <div class="lb-score">🏆 ${c.trophies}</div></div>`).join('')
      || `<p class="empty">${q ? 'No clans match that.' : 'No clans yet. Start the first one!'}</p>`;
  } catch (err) {
    $('clans-status').textContent = err.message === 'timeout' ? 'The server didn\'t answer. Try again.' : err.message;
  }
}

async function showClan(id) {
  try {
    const res = await Net.request({ t: 'clan', id }, ['clan']);
    clanView = res.clan;
    renderClan();
  } catch (err) {
    $('clans-status').textContent = err.message === 'timeout' ? 'The server didn\'t answer. Try again.' : err.message;
    if (save.clan?.id === id) { save.clan = null; writeSave(); }
    browseClans();
  }
}

function renderClan() {
  const c = clanView;
  const mine = save.clan?.id === c.id;
  const leader = c.leader === save.pid;
  $('clan-browse').classList.add('hidden');
  $('clan-mine').classList.remove('hidden');
  $('clan-head').innerHTML = `${emblemHtml(c)}<div><b>${escapeHtml(c.name)}</b> <em>[${escapeHtml(c.tag)}]</em>
    <span>🏆 ${c.trophies} · ${c.members}/${CLAN_SIZE} members</span></div>`;
  $('clan-members').innerHTML = c.list.map((m, i) => `<div class="lb-row${m.id === save.pid ? ' me' : ''}">
    ${medal(i)}${avatarHtml(m.name, m.id === save.pid ? PLAYER : 2)}
    <div class="lb-name">${escapeHtml(m.name)}${m.leader ? ' <span class="crown" title="Leader">👑</span>' : ''}</div>
    <div class="lb-score">🏆 ${m.trophies}</div>
    ${leader && !m.leader ? `<button class="kick" data-kick="${m.id}" title="Remove from the clan" aria-label="Remove ${escapeHtml(m.name)}">✖</button>` : ''}</div>`).join('');
  $('clan-join').classList.toggle('hidden', mine);
  $('clan-join').disabled = c.members >= CLAN_SIZE;
  $('clan-join').textContent = c.members >= CLAN_SIZE ? 'Clan is full' : save.clan ? 'Switch to this clan' : 'Join clan';
  $('clan-leave').classList.toggle('hidden', !mine);
  $('clan-back').classList.toggle('hidden', mine);
}

function renderPickers() {
  $('emblem-pick').innerHTML = EMBLEMS.map(e => `<button class="pick${e === newClan.emblem ? ' on' : ''}" data-emblem="${e}">${e}</button>`).join('');
  $('color-pick').innerHTML = CLAN_COLORS.map(c => `<button class="pick swatch${c === newClan.color ? ' on' : ''}" data-color="${c}" style="background:${c}" aria-label="Color ${c}"></button>`).join('');
  $('clan-preview').innerHTML = emblemHtml({ color: newClan.color, emblem: newClan.emblem });
}

async function clanAction(msg, types, done) {
  $('clans-status').textContent = '';
  try {
    const res = await Net.request(msg, types);
    done(res);
  } catch (err) {
    $('clans-status').textContent = err.message === 'timeout' ? 'The server didn\'t answer. Try again.' : err.message;
  }
}

// ---------- Buttons ----------
$('board-btn').addEventListener('click', () => { Sfx.unlock(); openBoard(); });
$('clans-btn').addEventListener('click', () => { Sfx.unlock(); openClans(); });
$('pvp-clan').addEventListener('click', () => openClans());
for (const b of document.querySelectorAll('#board .tab')) b.addEventListener('click', () => { boardTab = b.dataset.tab; renderBoard(); });
$('board-list').addEventListener('click', e => {
  const row = e.target.closest('[data-clan]');
  if (row) { openClans().then(() => showClan(row.dataset.clan)); }
});
$('clan-list').addEventListener('click', e => {
  const row = e.target.closest('[data-clan]');
  if (row) showClan(row.dataset.clan);
});
$('clan-search').addEventListener('input', () => {
  clearTimeout(clanSearchTimer);
  clanSearchTimer = setTimeout(() => browseClans($('clan-search').value.trim()), 300);
});
let clanSearchTimer = 0;
$('emblem-pick').addEventListener('click', e => {
  const b = e.target.closest('[data-emblem]');
  if (b) { newClan.emblem = b.dataset.emblem; renderPickers(); }
});
$('color-pick').addEventListener('click', e => {
  const b = e.target.closest('[data-color]');
  if (b) { newClan.color = b.dataset.color; renderPickers(); }
});
$('clan-create').addEventListener('click', () => {
  const name = $('clan-name').value.trim(), tag = $('clan-tag').value.trim().toUpperCase();
  clanAction({ t: 'mkclan', name, tag, emblem: newClan.emblem, color: newClan.color }, ['clan'], res => {
    clanView = res.clan;
    sfx('trophy');
    renderClan();
  });
});
$('clan-join').addEventListener('click', () => {
  clanAction({ t: 'joinclan', id: clanView.id }, ['clan'], res => {
    clanView = res.clan;
    sfx('capture');
    renderClan();
  });
});
$('clan-leave').addEventListener('click', () => {
  if (!confirm(`Leave ${clanView.name}?`)) return;
  clanAction({ t: 'leaveclan' }, ['me'], () => browseClans());
});
$('clan-back').addEventListener('click', () => browseClans($('clan-search').value.trim()));
$('clan-members').addEventListener('click', e => {
  const b = e.target.closest('[data-kick]');
  if (!b) return;
  const m = clanView.list.find(x => x.id === b.dataset.kick);
  if (!m || !confirm(`Remove ${m.name} from the clan?`)) return;
  clanAction({ t: 'kick', id: m.id }, ['clan'], res => { clanView = res.clan; renderClan(); });
});
