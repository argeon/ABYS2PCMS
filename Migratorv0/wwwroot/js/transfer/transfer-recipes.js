const API = '/api/transfer-studio';

async function fetchJson(url, options) {
    const res = await fetch(url, options);
    return res.json();
}

function escapeHtml(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

async function loadRecipes() {
    const tbody = document.getElementById('recipeTableBody');
    const recipes = await fetchJson(`${API}/recipes`);
    if (!recipes.length) {
        tbody.innerHTML = '<tr><td colspan="8" class="text-muted p-3">Tanım bulunamadı.</td></tr>';
        return;
    }
    tbody.innerHTML = recipes.map(r => `
        <tr>
            <td><code>${escapeHtml(r.migrationId)}</code></td>
            <td>${escapeHtml(r.name)}</td>
            <td>${escapeHtml(r.sourceTable)}</td>
            <td>${escapeHtml(r.targetTable)}</td>
            <td>${r.sortOrder}</td>
            <td>${escapeHtml(r.status)}</td>
            <td>${new Date(r.updatedAt).toLocaleString('tr-TR')}</td>
            <td class="text-nowrap">
                <a href="/transfer/recipe-edit?id=${r.id}" class="btn btn-sm btn-outline-light">Düzenle</a>
                <button class="btn btn-sm btn-outline-danger" data-delete="${r.id}">Sil</button>
            </td>
        </tr>`).join('');

    tbody.querySelectorAll('[data-delete]').forEach(btn => {
        btn.addEventListener('click', async () => {
            if (!confirm('Bu tanım silinsin mi?')) return;
            await fetchJson(`${API}/recipes/${btn.dataset.delete}`, { method: 'DELETE' });
            loadRecipes();
        });
    });
}

document.getElementById('btnItUserSample')?.addEventListener('click', async () => {
    const r = await fetchJson(`${API}/recipes/sample-it-user`, { method: 'POST' });
    if (r.id) window.location.href = `/transfer/recipe-edit?id=${r.id}`;
});

loadRecipes();
