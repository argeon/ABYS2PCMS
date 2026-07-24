const API = '/api/transfer-studio';

let recipeId = null;
let document_ = emptyDocument();
let mssqlProfiles = [];

function emptyDocument() {
    return {
        migrationId: '',
        name: '',
        sortOrder: 0,
        endpoints: {
            sourceProfileId: null, sourceConnectionString: '', sourceDatabase: '', sourceSchema: 'dbo', sourceTable: '',
            targetProfileId: null, targetConnectionString: '', targetDatabase: '', targetSchema: 'dbo', targetTable: ''
        },
        bridge: { sourceKeyColumn: '', targetBridgeColumn: '', targetIdentityColumn: '', sourceFilter: '' },
        preDeploySteps: [],
        batch: { batchKeyColumn: '', batchSize: 2000, resume: true, maxErrors: 200, onBatchError: 'SingleRowRetry', allowHardReset: false },
        phases: [
            { name: 'INSERT', phaseType: 'InsertSelect', sourceJoins: [], lookups: [], columnMappings: [], fkResolves: [] },
            { name: 'UPDATE', phaseType: 'FkResolve', sourceJoins: [], lookups: [], columnMappings: [], fkResolves: [] }
        ],
        validation: {
            metrics: [
                { gateType: 'RowCount', enabled: true },
                { gateType: 'MissingByBridge', enabled: true },
                { gateType: 'BridgeNotNull', enabled: true }
            ],
            content: { enabled: true, strategy: 'SampleByKey', sampleSize: 100, fixedKeys: [], maxReportedMismatches: 50, rules: [] }
        },
        execution: { mode: 'Engine', defaultRunPhase: 'ALL', debug: false }
    };
}

async function fetchJson(url, options) {
    const res = await fetch(url, options);
    return res.json();
}

function getInsertPhase() {
    return document_.phases.find(p => p.name === 'INSERT') || document_.phases[0];
}

function getUpdatePhase() {
    return document_.phases.find(p => p.name === 'UPDATE') || document_.phases[1];
}

function bindFormToDocument() {
    document_.migrationId = document.getElementById('fldMigrationId').value.trim();
    document_.name = document.getElementById('fldName').value.trim();
    document_.sortOrder = parseInt(document.getElementById('fldSortOrder').value, 10) || 0;

    const ep = document_.endpoints;
    ep.sourceProfileId = parseInt(document.getElementById('fldSourceProfile').value, 10) || null;
    ep.sourceDatabase = document.getElementById('fldSourceDb').value.trim();
    ep.sourceSchema = document.getElementById('fldSourceSchema').value.trim() || 'dbo';
    ep.sourceTable = document.getElementById('fldSourceTable').value.trim();
    ep.targetProfileId = parseInt(document.getElementById('fldTargetProfile').value, 10) || null;
    ep.targetDatabase = document.getElementById('fldTargetDb').value.trim();
    ep.targetSchema = document.getElementById('fldTargetSchema').value.trim() || 'dbo';
    ep.targetTable = document.getElementById('fldTargetTable').value.trim();

    document_.bridge.sourceKeyColumn = document.getElementById('fldSourceKey').value.trim();
    document_.bridge.targetBridgeColumn = document.getElementById('fldTargetBridge').value.trim();
    document_.bridge.targetIdentityColumn = document.getElementById('fldTargetIdentity').value.trim();
    document_.bridge.sourceFilter = document.getElementById('fldSourceFilter').value.trim();

    document_.batch.batchKeyColumn = document.getElementById('fldBatchKey').value.trim();
    document_.batch.batchSize = parseInt(document.getElementById('fldBatchSize').value, 10) || 2000;
    document_.batch.maxErrors = parseInt(document.getElementById('fldMaxErrors').value, 10) || 200;
    document_.batch.resume = document.getElementById('fldResume').checked;

    const insert = getInsertPhase();
    insert.columnMappings = [];
    document.querySelectorAll('#mappingTableBody tr').forEach(row => {
        insert.columnMappings.push({
            targetColumn: row.querySelector('.map-target').value.trim(),
            sourceExpression: row.querySelector('.map-source').value.trim(),
            resolveInLaterPhase: row.querySelector('.map-phase2').checked,
            includeInContentValidation: row.querySelector('.map-val').checked
        });
    });

    const update = getUpdatePhase();
    update.fkResolves = [];
    document.querySelectorAll('#fkTableBody tr').forEach(row => {
        update.fkResolves.push({
            targetTable: row.querySelector('.fk-table').value.trim(),
            targetSchema: 'dbo',
            column: row.querySelector('.fk-col').value.trim(),
            lookupTable: row.querySelector('.fk-lookup').value.trim(),
            lookupSchema: 'dbo',
            lookupBridgeColumn: row.querySelector('.fk-bridge').value.trim(),
            lookupTargetColumn: row.querySelector('.fk-target-col').value.trim()
        });
    });

    document_.validation.metrics = [];
    document.querySelectorAll('.metric-gate').forEach(cb => {
        document_.validation.metrics.push({ gateType: cb.dataset.gate, enabled: cb.checked });
    });

    const content = document_.validation.content;
    content.enabled = document.getElementById('fldContentEnabled').checked;
    content.strategy = document.getElementById('fldContentStrategy').value;
    content.sampleSize = parseInt(document.getElementById('fldSampleSize').value, 10) || 100;
    const fixed = document.getElementById('fldFixedKeys').value.trim();
    content.fixedKeys = fixed ? fixed.split(',').map(x => parseInt(x.trim(), 10)).filter(n => !isNaN(n)) : [];
    content.rules = [];
    document.querySelectorAll('#contentRulesBody tr').forEach(row => {
        content.rules.push({
            label: row.querySelector('.cr-label').value.trim(),
            sourceExpression: row.querySelector('.cr-src').value.trim(),
            targetExpression: row.querySelector('.cr-tgt').value.trim(),
            compareAs: row.querySelector('.cr-cmp').value,
            validateAfterPhase: row.querySelector('.cr-phase').value.trim() || null
        });
    });

    document.getElementById('jsonPreview').value = JSON.stringify(document_, null, 2);
}

function bindDocumentToForm() {
    document.getElementById('fldMigrationId').value = document_.migrationId || '';
    document.getElementById('fldName').value = document_.name || '';
    document.getElementById('fldSortOrder').value = document_.sortOrder || 0;

    const ep = document_.endpoints || {};
    document.getElementById('fldSourceProfile').value = ep.sourceProfileId || '';
    document.getElementById('fldSourceDb').value = ep.sourceDatabase || '';
    document.getElementById('fldSourceSchema').value = ep.sourceSchema || 'dbo';
    document.getElementById('fldSourceTable').value = ep.sourceTable || '';
    document.getElementById('fldTargetProfile').value = ep.targetProfileId || '';
    document.getElementById('fldTargetDb').value = ep.targetDatabase || '';
    document.getElementById('fldTargetSchema').value = ep.targetSchema || 'dbo';
    document.getElementById('fldTargetTable').value = ep.targetTable || '';

    const br = document_.bridge || {};
    document.getElementById('fldSourceKey').value = br.sourceKeyColumn || '';
    document.getElementById('fldTargetBridge').value = br.targetBridgeColumn || '';
    document.getElementById('fldTargetIdentity').value = br.targetIdentityColumn || '';
    document.getElementById('fldSourceFilter').value = br.sourceFilter || '';

    const batch = document_.batch || {};
    document.getElementById('fldBatchKey').value = batch.batchKeyColumn || '';
    document.getElementById('fldBatchSize').value = batch.batchSize || 2000;
    document.getElementById('fldMaxErrors').value = batch.maxErrors || 200;
    document.getElementById('fldResume').checked = batch.resume !== false;

    renderMappingTable(getInsertPhase().columnMappings || []);
    renderFkTable(getUpdatePhase().fkResolves || []);

    const metrics = document_.validation?.metrics || [];
    document.querySelectorAll('.metric-gate').forEach(cb => {
        const m = metrics.find(x => x.gateType === cb.dataset.gate);
        cb.checked = m ? m.enabled : false;
    });

    const content = document_.validation?.content || {};
    document.getElementById('fldContentEnabled').checked = content.enabled !== false;
    document.getElementById('fldContentStrategy').value = content.strategy || 'SampleByKey';
    document.getElementById('fldSampleSize').value = content.sampleSize || 100;
    document.getElementById('fldFixedKeys').value = (content.fixedKeys || []).join(',');

    renderContentRules(content.rules || []);
    document.getElementById('recipeTitle').textContent = document_.name || 'Yeni aktarım tanımı';
    document.getElementById('jsonPreview').value = JSON.stringify(document_, null, 2);
}

function renderMappingTable(mappings) {
    const tbody = document.getElementById('mappingTableBody');
    if (!mappings.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-muted p-2">Mapping satırı yok</td></tr>';
        return;
    }
    tbody.innerHTML = mappings.map((m, i) => mappingRowHtml(m, i)).join('');
    wireMappingRows();
}

function mappingRowHtml(m, i) {
    return `<tr data-idx="${i}">
        <td><input class="form-control map-target" value="${esc(m.targetColumn)}" /></td>
        <td><input class="form-control map-source" value="${esc(m.sourceExpression)}" /></td>
        <td class="text-center"><input type="checkbox" class="form-check-input map-phase2" ${m.resolveInLaterPhase ? 'checked' : ''} /></td>
        <td class="text-center"><input type="checkbox" class="form-check-input map-val" ${m.includeInContentValidation !== false ? 'checked' : ''} /></td>
        <td><button type="button" class="btn btn-sm btn-outline-danger btn-del-map">×</button></td>
    </tr>`;
}

function renderFkTable(fks) {
    const tbody = document.getElementById('fkTableBody');
    if (!fks.length) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-muted p-2">FK adımı yok</td></tr>';
        return;
    }
    tbody.innerHTML = fks.map((f, i) => fkRowHtml(f, i)).join('');
    wireFkRows();
}

function fkRowHtml(f) {
    return `<tr>
        <td><input class="form-control fk-table" value="${esc(f.targetTable)}" /></td>
        <td><input class="form-control fk-col" value="${esc(f.column)}" /></td>
        <td><input class="form-control fk-lookup" value="${esc(f.lookupTable)}" /></td>
        <td><input class="form-control fk-bridge" value="${esc(f.lookupBridgeColumn)}" /></td>
        <td><input class="form-control fk-target-col" value="${esc(f.lookupTargetColumn)}" /></td>
        <td><button type="button" class="btn btn-sm btn-outline-danger btn-del-fk">×</button></td>
    </tr>`;
}

function renderContentRules(rules) {
    const tbody = document.getElementById('contentRulesBody');
    if (!rules.length) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-muted p-2">İçerik kuralı yok</td></tr>';
        return;
    }
    tbody.innerHTML = rules.map(r => contentRuleRowHtml(r)).join('');
    wireContentRows();
}

function contentRuleRowHtml(r) {
    const opts = ['Exact', 'StringTrimIgnoreCase', 'Decimal', 'DateTime', 'DateOnly', 'NullEquivalent', 'Custom']
        .map(o => `<option value="${o}" ${r.compareAs === o ? 'selected' : ''}>${o}</option>`).join('');
    return `<tr>
        <td><input class="form-control cr-label" value="${esc(r.label)}" /></td>
        <td><input class="form-control cr-src" value="${esc(r.sourceExpression)}" /></td>
        <td><input class="form-control cr-tgt" value="${esc(r.targetExpression)}" /></td>
        <td><select class="form-select cr-cmp">${opts}</select></td>
        <td><input class="form-control cr-phase" value="${esc(r.validateAfterPhase || '')}" placeholder="INSERT" /></td>
        <td><button type="button" class="btn btn-sm btn-outline-danger btn-del-cr">×</button></td>
    </tr>`;
}

function esc(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

function wireMappingRows() {
    document.querySelectorAll('.btn-del-map').forEach(btn => btn.onclick = () => { btn.closest('tr').remove(); bindFormToDocument(); });
}

function wireFkRows() {
    document.querySelectorAll('.btn-del-fk').forEach(btn => btn.onclick = () => { btn.closest('tr').remove(); bindFormToDocument(); });
}

function wireContentRows() {
    document.querySelectorAll('.btn-del-cr').forEach(btn => btn.onclick = () => { btn.closest('tr').remove(); bindFormToDocument(); });
}

async function loadProfiles() {
    mssqlProfiles = await fetchJson(`${API}/mssql-profiles`);
    const opt = '<option value="">— Profil seç —</option>' +
        mssqlProfiles.map(p => `<option value="${p.id}">${p.profileName} (${p.databaseName || p.host || ''})</option>`).join('');
    document.getElementById('fldSourceProfile').innerHTML = opt;
    document.getElementById('fldTargetProfile').innerHTML = opt;
}

async function testConnection(side) {
    const profileId = parseInt(document.getElementById(side === 'source' ? 'fldSourceProfile' : 'fldTargetProfile').value, 10);
    const db = document.getElementById(side === 'source' ? 'fldSourceDb' : 'fldTargetDb').value.trim();
    const r = await fetchJson(`${API}/test-connection`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ profileId: profileId || null, database: db, trustCert: true })
    });
    document.getElementById('generalStatus').textContent = r.success
        ? `${side} OK: ${r.database}`
        : `${side} HATA: ${r.error}`;
}

async function loadRecipe() {
    const root = document.querySelector('.transfer-studio');
    const id = root?.dataset.recipeId;
    if (!id) { bindDocumentToForm(); return; }
    recipeId = parseInt(id, 10);
    const data = await fetchJson(`${API}/recipes/${recipeId}`);
    document_ = data.document;
    if (!document_.phases?.length) document_.phases = emptyDocument().phases;
    bindDocumentToForm();
}

document.getElementById('btnBack')?.addEventListener('click', () => { window.location.href = '/transfer/recipes'; });

document.getElementById('btnSaveRecipe')?.addEventListener('click', async () => {
    bindFormToDocument();
    const status = document.getElementById('fldStatus').value;
    const payload = { document: document_, status };
    const url = recipeId ? `${API}/recipes/${recipeId}` : `${API}/recipes`;
    const r = await fetchJson(url, {
        method: recipeId ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });
    if (r.id) {
        recipeId = r.id;
        history.replaceState(null, '', `/transfer/recipe-edit?id=${recipeId}`);
        document.getElementById('generalStatus').textContent = 'Kaydedildi.';
    }
});

document.getElementById('btnAddMapping')?.addEventListener('click', () => {
    bindFormToDocument();
    getInsertPhase().columnMappings.push({ targetColumn: '', sourceExpression: '', resolveInLaterPhase: false, includeInContentValidation: true });
    renderMappingTable(getInsertPhase().columnMappings);
});

document.getElementById('btnAddFk')?.addEventListener('click', () => {
    bindFormToDocument();
    getUpdatePhase().fkResolves.push({ targetTable: '', column: '', lookupTable: 'LS_USER', lookupSchema: 'dbo', lookupBridgeColumn: 'ABYS_ID', lookupTargetColumn: 'USERID' });
    renderFkTable(getUpdatePhase().fkResolves);
});

document.getElementById('btnAddContentRule')?.addEventListener('click', () => {
    bindFormToDocument();
    document_.validation.content.rules.push({ label: '', sourceExpression: '', targetExpression: '', compareAs: 'Exact' });
    renderContentRules(document_.validation.content.rules);
});

document.getElementById('btnGenValidationFromMapping')?.addEventListener('click', () => {
    bindFormToDocument();
    const rules = getInsertPhase().columnMappings
        .filter(m => m.includeInContentValidation && m.targetColumn && m.sourceExpression)
        .map(m => ({
            label: m.targetColumn,
            sourceExpression: m.sourceExpression,
            targetExpression: `t.${m.targetColumn}`,
            compareAs: 'Exact',
            validateAfterPhase: m.resolveInLaterPhase ? 'UPDATE' : 'INSERT'
        }));
    document_.validation.content.rules = rules;
    renderContentRules(rules);
});

document.getElementById('btnTestSource')?.addEventListener('click', () => testConnection('source'));
document.getElementById('btnTestTarget')?.addEventListener('click', () => testConnection('target'));

document.querySelectorAll('#recipeTabs .nav-link').forEach(tab => {
    tab.addEventListener('shown.bs.tab', () => bindFormToDocument());
});

(async function init() {
    await loadProfiles();
    await loadRecipe();
})();
