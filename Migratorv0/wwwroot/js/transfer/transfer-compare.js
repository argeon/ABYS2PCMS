const API = '/api/transfer-studio';

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
    const sel = document.getElementById('cmpRecipe');
    sel.innerHTML = '<option value="">— Recipe seç —</option>' +
        recipes.map(r => `<option value="${r.id}">${escapeHtml(r.name)}</option>`).join('');

    const params = new URLSearchParams(window.location.search);
    const pre = params.get('recipeId');
    if (pre) sel.value = pre;
}

function renderMetrics(metrics) {
    const tbody = document.getElementById('metricResultsBody');
    if (!metrics?.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-muted p-3">Sonuç yok</td></tr>';
        return;
    }
    tbody.innerHTML = metrics.map(g => `
        <tr>
            <td>${escapeHtml(g.gateType)}</td>
            <td>${escapeHtml(g.sourceValue)}</td>
            <td>${escapeHtml(g.targetValue)}</td>
            <td class="${g.passed ? 'gate-pass' : 'gate-fail'}">${g.passed ? 'OK' : 'FAIL'}</td>
        </tr>`).join('');
}

function renderMismatches(rows) {
    const tbody = document.getElementById('mismatchBody');
    if (!rows?.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-muted p-3">Mismatch yok</td></tr>';
        return;
    }
    tbody.innerHTML = rows.map(r => `
        <tr>
            <td><code>${escapeHtml(r.bridgeKey)}</code></td>
            <td>${escapeHtml(r.columnLabel)}</td>
            <td>${escapeHtml(r.sourceValue)}</td>
            <td>${escapeHtml(r.targetValue)}</td>
            <td>${escapeHtml(r.compareAs)}</td>
        </tr>`).join('');
}

document.getElementById('btnRunCompare')?.addEventListener('click', async () => {
    const recipeId = parseInt(document.getElementById('cmpRecipe').value, 10);
    if (!recipeId) {
        document.getElementById('cmpStatus').textContent = 'Recipe seçin.';
        return;
    }
    document.getElementById('cmpStatus').textContent = 'Çalışıyor…';
    const r = await fetchJson(`${API}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            recipeId,
            phase: document.getElementById('cmpPhase').value,
            includeContent: document.getElementById('cmpIncludeContent').checked
        })
    });
    if (r.error) {
        document.getElementById('cmpStatus').textContent = 'Hata: ' + r.error;
        return;
    }
    document.getElementById('cmpStatus').textContent = r.allPassed ? 'Tüm kontroller geçti.' : 'Bazı kontroller başarısız.';
    renderMetrics(r.metrics);
    renderMismatches(r.contentMismatches);
});

loadRecipeSelect();
