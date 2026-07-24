const API = '/api/transfer-studio/pipeline';

let projectId = null;
let document_ = emptyProject();
let recipes = [];
let oracleRuns = [];

function emptyProject() {
    return {
        name: '',
        description: '',
        oracleRunId: null,
        steps: [],
        e2eFixedKeys: [],
        failFast: true
    };
}

async function fetchJson(url, options) {
    const res = await fetch(url, options);
    return res.json();
}

function esc(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
}

const stageLabels = {
    1: 'Aşama 1 — Oracle → MSSQL-1',
    2: 'Aşama 2 — MSSQL-1 → MSSQL-2 (INSERT)',
    3: 'Aşama 3 — FK / UPDATE',
    4: 'E2E — Zincir key kontrolü',
    stage1_OracleToMssql1: 'Aşama 1 — Oracle → MSSQL-1',
    stage2_Mssql1ToMssql2_Insert: 'Aşama 2 — MSSQL-1 → MSSQL-2 (INSERT)',
    stage3_Mssql1ToMssql2_Update: 'Aşama 3 — FK / UPDATE',
    e2E_Chain: 'E2E — Zincir key kontrolü'
};

function stageTitle(stage) {
    return stageLabels[stage] || stageLabels[String(stage)] || `Aşama ${stage}`;
}

function bindFormToDocument() {
    document_.name = document.getElementById('fldProjectName').value.trim();
    document_.oracleRunId = parseInt(document.getElementById('fldOracleRun').value, 10) || null;
    document_.failFast = document.getElementById('fldFailFast').checked;
    const keys = document.getElementById('fldE2eKeys').value.trim();
    document_.e2eFixedKeys = keys
        ? keys.split(',').map(x => parseInt(x.trim(), 10)).filter(n => !isNaN(n))
        : [];

    document_.steps = [];
    document.querySelectorAll('#stepsEditor .step-row').forEach((row, i) => {
        document_.steps.push({
            recipeId: parseInt(row.querySelector('.step-recipe').value, 10) || 0,
            oracleTable: row.querySelector('.step-oracle').value.trim(),
            label: row.querySelector('.step-label').value.trim(),
            sortOrder: (i + 1) * 10
        });
    });
}

function bindDocumentToForm() {
    document.getElementById('fldProjectName').value = document_.name || '';
    document.getElementById('fldOracleRun').value = document_.oracleRunId || '';
    document.getElementById('fldE2eKeys').value = (document_.e2eFixedKeys || []).join(',');
    document.getElementById('fldFailFast').checked = document_.failFast !== false;
    renderSteps(document_.steps || []);
}

function recipeOptions(selectedId) {
    return '<option value="">— Recipe —</option>' +
        recipes.map(r =>
            `<option value="${r.id}" ${r.id === selectedId ? 'selected' : ''}>${esc(r.name)}</option>`
        ).join('');
}

function stepRowHtml(step) {
    return `<div class="step-row border rounded p-2 mb-2">
        <select class="form-select form-select-sm step-recipe mb-1">${recipeOptions(step.recipeId)}</select>
        <input class="form-control form-control-sm step-oracle mb-1" placeholder="Oracle tablo" value="${esc(step.oracleTable)}" />
        <input class="form-control form-control-sm step-label mb-1" placeholder="Etiket" value="${esc(step.label)}" />
        <button type="button" class="btn btn-sm btn-outline-danger btn-del-step">Kaldır</button>
    </div>`;
}

function renderSteps(steps) {
    const el = document.getElementById('stepsEditor');
    if (!steps.length) {
        el.innerHTML = '<p class="text-muted small mb-0">Adım yok</p>';
        return;
    }
    el.innerHTML = steps.map(stepRowHtml).join('');
    el.querySelectorAll('.btn-del-step').forEach(btn => {
        btn.onclick = () => { btn.closest('.step-row').remove(); bindFormToDocument(); };
    });
}

async function loadLookups() {
    [recipes, oracleRuns] = await Promise.all([
        fetchJson('/api/transfer-studio/recipes'),
        fetchJson(`${API}/oracle-runs`)
    ]);

    document.getElementById('fldOracleRun').innerHTML =
        '<option value="">— Oracle run seç —</option>' +
        oracleRuns.map(r =>
            `<option value="${r.runId}">#${r.runId} ${esc(r.status)} (${esc(r.oracleSchema)}, ${r.tableCount} tablo)</option>`
        ).join('');

    const projects = await fetchJson(`${API}/projects`);
    const list = document.getElementById('projectList');
    if (!projects.length) {
        list.innerHTML = '<li class="list-group-item bg-dark text-muted">Proje yok</li>';
        return;
    }
    list.innerHTML = projects.map(p => `
        <li class="list-group-item bg-dark list-group-item-action ${p.id === projectId ? 'active' : ''}"
            data-id="${p.id}" style="cursor:pointer">
            <strong>${esc(p.name)}</strong>
            <div class="small text-muted">Run #${p.oracleRunId ?? '—'} · ${p.stepCount} adım</div>
        </li>`).join('');

    list.querySelectorAll('[data-id]').forEach(li => {
        li.addEventListener('click', () => {
            window.location.href = `/transfer/pipeline?id=${li.dataset.id}`;
        });
    });
}

async function loadProject() {
    const root = document.querySelector('.transfer-studio');
    const id = root?.dataset.projectId;
    if (!id) {
        bindDocumentToForm();
        return;
    }
    projectId = parseInt(id, 10);
    const data = await fetchJson(`${API}/projects/${projectId}`);
    document_ = data.document;
    bindDocumentToForm();
    await loadLatestResult();
}

function renderResult(result) {
    const container = document.getElementById('pipelineResults');
    const badge = document.getElementById('overallBadge');
    if (!result || result.error) {
        container.innerHTML = `<div class="text-danger">${esc(result?.error || 'Hata')}</div>`;
        badge.className = 'badge bg-danger';
        badge.textContent = 'HATA';
        return;
    }

    badge.className = result.allPassed ? 'badge bg-success' : 'badge bg-danger';
    badge.textContent = result.allPassed ? 'TAMAM' : 'BAŞARISIZ';

    if (!result.steps?.length) {
        container.innerHTML = '<p class="text-muted">Adım sonucu yok.</p>';
        return;
    }

    container.innerHTML = result.steps.map(step => {
        const stageTitleText = stageTitle(step.stage);
        const status = step.passed
            ? '<span class="gate-pass">OK</span>'
            : '<span class="gate-fail">FAIL</span>';

        let body = '';
        if (step.error) {
            body = `<p class="text-danger small">${esc(step.error)}</p>`;
        } else if (step.gates?.length) {
            body = `<table class="table table-sm table-dark mb-0">
                <thead><tr><th>Gate</th><th>Kaynak</th><th>Hedef</th><th></th></tr></thead>
                <tbody>${step.gates.map(g => `<tr>
                    <td>${esc(g.gateType)}</td>
                    <td>${esc(g.sourceValue)}</td>
                    <td>${esc(g.targetValue)}</td>
                    <td class="${g.passed ? 'gate-pass' : 'gate-fail'}">${g.passed ? 'OK' : 'FAIL'}</td>
                </tr>`).join('')}</tbody></table>`;
        }

        if (step.contentMismatches?.length) {
            body += `<p class="small text-warning mt-2">${step.contentMismatches.length} içerik farkı</p>`;
        }

        if (step.e2eChecks?.length) {
            body += `<table class="table table-sm table-dark mt-2">
                <thead><tr><th>Key</th><th>Oracle</th><th>MSSQL-1</th><th>MSSQL-2</th><th></th></tr></thead>
                <tbody>${step.e2eChecks.map(c => `<tr>
                    <td>${c.key}</td>
                    <td>${c.oraclePresent ? '✓' : '✗'}</td>
                    <td>${c.stage1Present ? '✓' : '✗'}</td>
                    <td>${c.stage2Present ? '✓' : '✗'}</td>
                    <td class="${c.passed ? 'gate-pass' : 'gate-fail'}">${c.passed ? 'OK' : 'FAIL'}</td>
                </tr>`).join('')}</tbody></table>`;
        }

        return `<div class="pipeline-step-result mb-3 pb-3 border-bottom border-secondary">
            <div class="d-flex justify-content-between mb-1">
                <strong>${esc(stageTitleText)}</strong> ${status}
            </div>
            <div class="small text-muted mb-2">${esc(step.label || step.oracleTable)} · Recipe #${step.recipeId}</div>
            ${body}
        </div>`;
    }).join('');
}

async function loadLatestResult() {
    if (!projectId) return;
    try {
        const result = await fetchJson(`${API}/projects/${projectId}/validation/latest`);
        renderResult(result);
    } catch {
        /* no prior run */
    }
}

document.getElementById('btnAddStep')?.addEventListener('click', () => {
    bindFormToDocument();
    document_.steps.push({ recipeId: recipes[0]?.id || 0, oracleTable: '', label: '', sortOrder: 10 });
    renderSteps(document_.steps);
});

document.getElementById('btnSaveProject')?.addEventListener('click', async () => {
    bindFormToDocument();
    const url = projectId ? `${API}/projects/${projectId}` : `${API}/projects`;
    const r = await fetchJson(url, {
        method: projectId ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ document: document_ })
    });
    if (r.id) {
        projectId = r.id;
        window.location.href = `/transfer/pipeline?id=${projectId}`;
    }
});

document.getElementById('btnRunPipeline')?.addEventListener('click', async () => {
    if (!projectId) {
        document.getElementById('runStatus').textContent = 'Önce projeyi kaydedin.';
        return;
    }
    bindFormToDocument();
    await fetchJson(`${API}/projects/${projectId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ document: document_ })
    });

    document.getElementById('runStatus').textContent = 'Çalışıyor…';
    const result = await fetchJson(`${API}/projects/${projectId}/validate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            includeContent: document.getElementById('chkContent').checked,
            includeE2e: document.getElementById('chkE2e').checked
        })
    });
    document.getElementById('runStatus').textContent = new Date().toLocaleTimeString('tr-TR');
    renderResult(result);
});

document.getElementById('btnSamplePipeline')?.addEventListener('click', async () => {
    const r = await fetchJson(`${API}/projects/sample-it-user`, { method: 'POST' });
    if (r.id) window.location.href = `/transfer/pipeline?id=${r.id}`;
});

(async function init() {
    await loadLookups();
    await loadProject();
})();
