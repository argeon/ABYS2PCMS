const API = '/api/transfer-studio';

async function fetchJson(url, options) {
    const res = await fetch(url, options);
    return res.json();
}

function escapeHtml(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

async function loadHomeRecipes() {
    const tbody = document.getElementById('homeRecipeTable');
    const recipes = await fetchJson(`${API}/recipes`);
    if (!recipes.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-muted p-3">Henüz tanım yok. IT_USER örneğini yükleyebilirsiniz.</td></tr>';
        return;
    }
    tbody.innerHTML = recipes.slice(0, 8).map(r => `
        <tr>
            <td>${escapeHtml(r.name)}</td>
            <td><code>${escapeHtml(r.sourceTable)}</code> → <code>${escapeHtml(r.targetTable)}</code></td>
            <td>${escapeHtml(r.status)}</td>
            <td><a href="/transfer/recipe-edit?id=${r.id}" class="btn btn-sm btn-outline-light">Düzenle</a></td>
        </tr>`).join('');
}

document.getElementById('btnLoadItUserSample')?.addEventListener('click', async () => {
    const r = await fetchJson(`${API}/recipes/sample-it-user`, { method: 'POST' });
    if (r.id) window.location.href = `/transfer/recipe-edit?id=${r.id}`;
});

loadHomeRecipes();
