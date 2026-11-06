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

// Localhost-only fixture for visual QA. FiveM's NUI origin never matches this
// branch, so live state still comes exclusively from the Lua bridge.
if ((location.hostname === '127.0.0.1' || location.hostname === 'localhost')
    && new URLSearchParams(location.search).get('preview') === '1') {
    window.postMessage({
        action: 'open',
        payload: {
            installed: true,
            enabled: true,
            profile: 'Balanced',
            persistent: true,
            plate: 'RS DRIFT',
            profiles: [
                { name: 'Balanced', label: 'Balanced Street', description: 'Progressive breakaway, stable transitions, easy recovery.', power: 10, torque: 1.07, image: 'assets/mode-balanced.jpg', accent: '#ff9a3d', tag: 'SMOOTH' },
                { name: 'Arcade', label: 'Arcade GTA Native', description: 'Native drift tires blended with Balanced, JDM, Muscle, and Takeover control.', power: 15, torque: 1.11, image: 'assets/mode-arcade.jpg', accent: '#ffd45e', tag: 'FUSION' },
                { name: 'JDM', label: 'JDM Technical', description: 'Sharper response and more angle without abrupt rear-grip loss.', power: 14, torque: 1.10, image: 'assets/mode-jdm.jpg', accent: '#55c7ff', tag: 'TECHNICAL' },
                { name: 'Muscle', label: 'Muscle Torque', description: 'Longer power-over slides with controlled torque.', power: 18, torque: 1.13, image: 'assets/mode-muscle.jpg', accent: '#c86bff', tag: 'TORQUE' },
                { name: 'Takeover', label: 'Takeover Angle', description: 'Easy initiation and big, recoverable angle.', power: 16, torque: 1.12, image: 'assets/mode-takeover.jpg', accent: '#ff49cf', tag: 'ANGLE' },
                { name: 'Pursuit', label: 'Pursuit Hybrid', description: 'Near-stock grip with extra rotation for city driving.', power: 12, torque: 1.08, image: 'assets/mode-pursuit.jpg', accent: '#ffc83d', tag: 'HYBRID' },
                { name: 'OEM', label: 'Rockstar Native', description: 'Rockstar native drift tires with mild steering and powertrain support.', power: 12, torque: 1.08, image: 'assets/mode-oem.jpg', accent: '#7ef0ff', tag: 'NATIVE' },
                { name: 'NativeX', label: 'Native X', description: 'GTA V native drift tires plus a unique low-speed angle-assist tune.', power: 16, torque: 1.12, image: 'assets/mode-nativex.jpg', accent: '#8bf160', tag: 'NATIVE+' },
            ],
        },
    }, '*');
}
