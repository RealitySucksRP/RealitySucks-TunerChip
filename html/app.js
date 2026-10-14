const app = document.getElementById('app');
const grid = document.getElementById('profile-grid');
const closeButton = document.getElementById('close-button');
const toggleButton = document.getElementById('toggle-button');
const plateElement = document.getElementById('vehicle-plate');
const persistenceBadge = document.getElementById('persistence-badge');
const activeProfile = document.getElementById('active-profile');
const activeState = document.getElementById('active-state');

const resourceName = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'rs-tunerchip';

let viewState = {
    installed: false,
    enabled: false,
    profile: 'Balanced',
    persistent: false,
    plate: '',
    profiles: [],
};
let busyUntil = 0;

const post = async (endpoint, payload = {}) => {
    try {
        const response = await fetch('https://' + resourceName + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload),
        });
        return await response.json();
    } catch (_) {
        return { ok: false };
    }
};

const escapeHtml = (value) => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

const profileByName = (name) => viewState.profiles.find((profile) => profile.name === name);

const profileCard = (profile) => {
    const isSelected = profile.name === viewState.profile;
    const selectedClass = isSelected ? ' selected' : '';
    const accent = escapeHtml(profile.accent || '#26d9ff');

    return '<button class="profile-card' + selectedClass + '" type="button"'
        + ' data-profile="' + escapeHtml(profile.name) + '"'
        + ' style="--accent:' + accent + '"'
        + ' aria-pressed="' + String(isSelected) + '">'
        + '<img class="card-image" src="' + escapeHtml(profile.image) + '" alt="">'
        + '<span class="card-shade"></span>'
        + '<span class="card-content">'
        + '<span class="card-top">'
        + '<span class="card-tag">' + escapeHtml(profile.tag || 'TUNE') + '</span>'
        + '<span class="selected-chip">SAVED</span>'
        + '</span>'
        + '<h3>' + escapeHtml(profile.label || profile.name) + '</h3>'
        + '<p>' + escapeHtml(profile.description || '') + '</p>'
        + '<span class="metrics">'
        + '<span class="metric">PWR +' + Number(profile.power || 0).toFixed(0) + '%</span>'
        + '<span class="metric">TRQ ×' + Number(profile.torque || 1).toFixed(2) + '</span>'
        + '</span>'
        + '</span>'
        + '</button>';
};

const render = () => {
    const selected = profileByName(viewState.profile) || viewState.profiles[0];
    const enabled = viewState.enabled === true;

    plateElement.textContent = viewState.plate?.trim() || 'NO PLATE';
    persistenceBadge.textContent = viewState.persistent ? 'PERSISTENT' : 'SESSION';
    persistenceBadge.title = viewState.persistent
        ? 'Saved to this player-owned vehicle'
        : 'Saved until this network vehicle despawns';
    activeProfile.textContent = (selected?.label || viewState.profile || 'BALANCED').toUpperCase();
    activeState.textContent = enabled ? 'ACTIVE' : 'STANDBY';
    activeState.classList.toggle('on', enabled);
    toggleButton.classList.toggle('on', enabled);
    toggleButton.setAttribute('aria-pressed', String(enabled));

    grid.innerHTML = viewState.profiles.map(profileCard).join('');
};

const close = async () => {
    app.classList.remove('visible');
    app.setAttribute('aria-hidden', 'true');
    await post('close');
};

const guardedAction = async (callback) => {
    const now = Date.now();
    if (now < busyUntil) return;
    busyUntil = now + 450;
    await callback();
};

grid.addEventListener('click', (event) => {
    const card = event.target.closest('[data-profile]');
    if (!card) return;
    const profile = card.dataset.profile;
    if (!profile) return;
    guardedAction(() => post('setProfile', { profile }));
});

toggleButton.addEventListener('click', () => guardedAction(() => post('toggle')));
closeButton.addEventListener('click', close);

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close();
});

window.addEventListener('message', (event) => {
    const message = event.data || {};

    if (message.action === 'close') {
        app.classList.remove('visible');
        app.setAttribute('aria-hidden', 'true');
        return;
    }

    if (message.action !== 'open' && message.action !== 'update') return;
    viewState = { ...viewState, ...(message.payload || {}) };
    render();
    app.classList.add('visible');
    app.setAttribute('aria-hidden', 'false');
});
