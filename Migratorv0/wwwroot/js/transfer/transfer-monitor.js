const API = '/api/transfer-studio';

let selectedRunId = null;

async function fetchJson(url, options) {
    const res = await fetch(url, options);
    return res.json();
}

function escapeHtml(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

async function loadRecipeSelect() {
    const recipes = await fetchJson(`${API}/recipes`);
    const sel = document.getElementById('monRecipe');
    sel.innerHTML = '<option value="">Tümü</option>' +
        recipes.map(r => `<option value="${r.id}">${escapeHtml(r.name)}</option>`).join('');
}

async function loadRuns() {
    const recipeId = parseInt(document.getElementById('monRecipe').value, 10) || null;
    const url = recipeId ? `${API}/runs?recipeId=${recipeId}` : `${API}/runs`;
    const runs = await fetchJson(url);
    const tbody = document.getElementById('runsTableBody');
    if (!runs.length) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-muted p-2">Run yok</td></tr>';
        return;
    }
    tbody.innerHTML = runs.map(r => `
        <tr data-run-id="${r.id}" style="cursor:pointer">
            <td>${r.id}</td>
            <td>${escapeHtml(r.recipeName)}</td>
            <td>${escapeHtml(r.phase)}</td>
            <td>${escapeHtml(r.status)}</td>
            <td>${r.totalOk}</td>
            <td>${r.totalError}</td>
        </tr>`).join('');

    tbody.querySelectorAll('tr[data-run-id]').forEach(row => {
        row.addEventListener('click', () => selectRun(parseInt(row.dataset.runId, 10)));
    });
}

async function selectRun(runId) {
    selectedRunId = runId;
    document.getElementById('selectedRunLabel').textContent = `#${runId}`;
    const events = await fetchJson(`${API}/runs/${runId}/events`);
    const list = document.getElementById('eventLogList');
    if (!events.length) {
        list.innerHTML = '<li class="list-group-item bg-dark text-muted">Log kaydı yok</li>';
        return;
    }
    list.innerHTML = events.map(e => `
        <li class="list-group-item bg-dark text-light">
            <span class="text-muted">${new Date(e.createdAt).toLocaleTimeString('tr-TR')}</span>
            [${escapeHtml(e.level)}] ${escapeHtml(e.phase || '')} ${escapeHtml(e.message)}
        </li>`).join('');
}

document.getElementById('btnRefreshRuns')?.addEventListener('click', loadRuns);
document.getElementById('monRecipe')?.addEventListener('change', loadRuns);

document.getElementById('btnStartRun')?.addEventListener('click', async () => {
    const recipeId = parseInt(document.getElementById('monRecipe').value, 10);
    if (!recipeId) { alert('Recipe seçin'); return; }
    const r = await fetchJson(`${API}/runs`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ recipeId, phase: document.getElementById('monPhase').value })
    });
    if (r.runId) {
        await loadRuns();
        selectRun(r.runId);
    }
});

(async function init() {
    await loadRecipeSelect();
    await loadRuns();
})();
