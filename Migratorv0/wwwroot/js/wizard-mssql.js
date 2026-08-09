let currentStep = 1;
const totalSteps = 4;

function swalBase() {
    return {
        background: '#212529',
        color: '#f8f9fa',
        confirmButtonColor: '#0d6efd',
        cancelButtonColor: '#6c757d',
        denyButtonColor: '#ffc107',
    };
}

async function showAlert(icon, title, text) {
    if (typeof Swal !== 'undefined') {
        await Swal.fire({ ...swalBase(), icon, title, text: text || '' });
    } else {
        window.alert(title + (text ? '\n' + text : ''));
    }
}

let wizardData = {
    source: { tested: false, connectionString: '', schema: 'dbo', database: '' },
    target: { tested: false, connectionString: '', database: '' },
    tables: [],
    tableRetryModes: {},
    pendingTableNames: null,
    /** Full catalog from API — not all rendered at once */
    catalog: [],
    selectedSet: new Set(),
    catalogRenderLimit: 200
};

document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
    updateUI();
    void loadConnectionProfiles();
    void checkResumable();
});

function setupEventListeners() {
    document.getElementById('nextBtn').addEventListener('click', () => void nextStep());
    document.getElementById('prevBtn').addEventListener('click', prevStep);
    document.getElementById('startBtn').addEventListener('click', () => void startMigration());
    document.getElementById('testSourceBtn').addEventListener('click', () => void testSide('source'));
    document.getElementById('testTargetBtn').addEventListener('click', () => void testSide('target'));
    document.getElementById('sourceAuth').addEventListener('change', () => toggleCreds('source'));
    document.getElementById('targetAuth').addEventListener('change', () => toggleCreds('target'));
    document.getElementById('selectAllBtn')?.addEventListener('click', selectAllTables);
    document.getElementById('deselectAllBtn')?.addEventListener('click', deselectAllTables);
    document.getElementById('tableSearch')?.addEventListener('input', filterTables);
    document.getElementById('includeViewsChk')?.addEventListener('change', () => {
        if (wizardData.source.tested) void loadSourceTables();
    });
    document.getElementById('checkTableStatusBtn')?.addEventListener('click', () => void checkSelectedTableTransferStatus());
    document.getElementById('wizardProfileLoadBtn')?.addEventListener('click', () => void loadSelectedProfile());
}

function toggleCreds(side) {
    const auth = document.getElementById(side + 'Auth').value;
    document.getElementById(side + 'Credentials').style.display = auth === 'sql' ? '' : 'none';
}

function readSideForm(side) {
    return {
        server: document.getElementById(side + 'Server').value,
        authType: document.getElementById(side + 'Auth').value,
        username: document.getElementById(side + 'User').value,
        password: document.getElementById(side + 'Password').value,
        database: document.getElementById(side + 'Database').value,
        trustCert: document.getElementById(side + 'TrustCert').checked
    };
}

async function nextStep() {
    if (currentStep >= totalSteps) return;
    if (!(await validateStep(currentStep))) return;

    if (currentStep === 3) {
        const handled = await checkAndShowRetryModal();
        if (handled) return;
    }

    currentStep++;
    if (currentStep === 3) loadSourceTables();
    if (currentStep === 4) updateSummary();
    updateUI();
}

function prevStep() {
    if (currentStep > 1) {
        currentStep--;
        updateUI();
    }
}

function updateUI() {
    document.querySelectorAll('.wizard-step').forEach((el, i) => {
        el.classList.toggle('active', i + 1 === currentStep);
    });
    document.querySelectorAll('.wizard-progress .step').forEach((el) => {
        const n = parseInt(el.dataset.step, 10);
        el.classList.toggle('active', n === currentStep);
        el.classList.toggle('completed', n < currentStep);
    });
    document.getElementById('prevBtn').disabled = currentStep === 1;
    document.getElementById('nextBtn').classList.toggle('d-none', currentStep === totalSteps);
    document.getElementById('startBtn').classList.toggle('d-none', currentStep !== totalSteps);
}

async function validateStep(step) {
    if (step === 1 && !wizardData.source.tested) {
        await showAlert('warning', 'Önce kaynak MSSQL bağlantısını test edin.');
        return false;
    }
    if (step === 2 && !wizardData.target.tested) {
        await showAlert('warning', 'Önce hedef MSSQL bağlantısını test edin.');
        return false;
    }
    if (step === 3 && wizardData.tables.length === 0) {
        await showAlert('warning', 'En az bir tablo seçin.');
        return false;
    }
    return true;
}

async function testSide(side) {
    const btn = document.getElementById(side === 'source' ? 'testSourceBtn' : 'testTargetBtn');
    const spinner = document.getElementById(side + 'Spinner');
    const result = document.getElementById(side + 'Result');
    btn.disabled = true;
    spinner.classList.remove('d-none');
    result.classList.add('d-none');

    const body = readSideForm(side);
    const endpoint = side === 'source' ? '/api/wizard-mssql/test-source' : '/api/wizard-mssql/test-target';

    try {
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        const data = await response.json();
        result.classList.remove('d-none');
        if (data.success) {
            wizardData[side].tested = true;
            wizardData[side].connectionString = data.connectionString;
            wizardData[side].database = data.databaseName || body.database;
            if (side === 'source') {
                wizardData.source.schema = document.getElementById('sourceSchema').value || 'dbo';
            }
            result.innerHTML = `<span class="text-success">Connected: ${data.databaseName || body.database}</span>`;
        } else {
            wizardData[side].tested = false;
            result.innerHTML = `<span class="text-danger">${data.error || 'Failed'}</span>`;
        }
    } catch (ex) {
        wizardData[side].tested = false;
        result.classList.remove('d-none');
        result.innerHTML = `<span class="text-danger">${ex.message}</span>`;
    } finally {
        btn.disabled = false;
        spinner.classList.add('d-none');
    }
}

async function loadSourceTables() {
    const loading = document.getElementById('loadingTables');
    const selection = document.getElementById('tableSelection');
    loading.classList.remove('d-none');
    loading.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Katalog yükleniyor…';
    selection.classList.add('d-none');

    try {
        const response = await fetch('/api/wizard-mssql/list-tables', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                connectionString: wizardData.source.connectionString,
                schema: wizardData.source.schema || document.getElementById('sourceSchema').value || 'dbo',
                includeViews: document.getElementById('includeViewsChk')?.checked !== false,
                includeViewBases: false
            })
        });
        const data = await response.json();
        if (!data.success) throw new Error(data.error || 'Tablo listesi alınamadı');

        wizardData.catalog = data.tables || [];
        wizardData.selectedSet = new Set();
        if (wizardData.pendingTableNames?.length) {
            const pending = new Set(wizardData.pendingTableNames.map(n => n.toLowerCase()));
            for (const t of wizardData.catalog) {
                if (pending.has(t.name.toLowerCase()))
                    wizardData.selectedSet.add(t.name);
            }
        }
        wizardData.pendingTableNames = null;

        const list = document.getElementById('tableList');
        if (!list.dataset.delegated) {
            list.dataset.delegated = '1';
            list.addEventListener('change', (e) => {
                const cb = e.target.closest('.table-checkbox');
                if (!cb) return;
                if (cb.checked) wizardData.selectedSet.add(cb.value);
                else wizardData.selectedSet.delete(cb.value);
                syncSelectedTables();
            });
        }

        renderCatalog();
        loading.classList.add('d-none');
        selection.classList.remove('d-none');
        const meta = document.getElementById('catalogMeta');
        if (meta) {
            const views = wizardData.catalog.filter(t => (t.objectType || '').toUpperCase() === 'VIEW').length;
            meta.textContent = `${wizardData.catalog.length} nesne (${views} view). Arama ile daraltın — en fazla ${wizardData.catalogRenderLimit} satır çizilir.`;
        }
    } catch (ex) {
        loading.innerHTML = `<span class="text-danger">${ex.message}</span>`;
    }
}

function getFilteredCatalog() {
    const q = (document.getElementById('tableSearch')?.value || '').trim().toLowerCase();
    if (!q) return wizardData.catalog;
    return wizardData.catalog.filter(t =>
        t.name.toLowerCase().includes(q)
        || (t.objectType || '').toLowerCase().includes(q));
}

function renderCatalog() {
    const list = document.getElementById('tableList');
    if (!list) return;
    const filtered = getFilteredCatalog();
    const limit = wizardData.catalogRenderLimit || 200;
    const slice = filtered.slice(0, limit);
    const parts = new Array(slice.length);
    for (let i = 0; i < slice.length; i++) {
        const t = slice[i];
        const isView = (t.objectType || '').toUpperCase() === 'VIEW';
        const checked = wizardData.selectedSet.has(t.name) ? ' checked' : '';
        const badge = isView
            ? '<span class="badge bg-warning text-dark ms-1">V</span>'
            : '';
        const rows = t.rowCount ? ` <span class="text-muted small">~${Number(t.rowCount).toLocaleString()}</span>` : '';
        parts[i] =
            `<div class="table-item form-check py-1">` +
            `<input class="form-check-input table-checkbox" type="checkbox" id="tbl_${i}" value="${escapeAttr(t.name)}" data-object-type="${t.objectType || 'TABLE'}"${checked}>` +
            `<label class="form-check-label" for="tbl_${i}"><strong>${escapeHtml(t.name)}</strong>${badge}${rows}</label>` +
            `</div>`;
    }
    let footer = '';
    if (filtered.length > limit) {
        footer = `<div class="small text-warning mt-2">Gösterilen ${limit} / ${filtered.length}. Daha fazlası için aramayı daraltın veya “Daha fazla göster”.</div>` +
            `<button type="button" class="btn btn-sm btn-outline-secondary mt-1" id="showMoreCatalogBtn">+200 daha göster</button>`;
    } else {
        footer = `<div class="small text-muted mt-2">${filtered.length} / ${wizardData.catalog.length} nesne</div>`;
    }
    list.innerHTML = parts.join('') + footer;
    document.getElementById('showMoreCatalogBtn')?.addEventListener('click', () => {
        wizardData.catalogRenderLimit = (wizardData.catalogRenderLimit || 200) + 200;
        renderCatalog();
    });
    syncSelectedTables();
}

function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function escapeAttr(s) {
    return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

function syncSelectedTables() {
    wizardData.tables = Array.from(wizardData.selectedSet);
    const el = document.getElementById('selectedCount');
    if (el) el.textContent = wizardData.tables.length;
}

function selectAllTables() {
    // Select all currently filtered (not only visible page)
    for (const t of getFilteredCatalog())
        wizardData.selectedSet.add(t.name);
    renderCatalog();
}

function deselectAllTables() {
    const filtered = new Set(getFilteredCatalog().map(t => t.name));
    for (const name of [...wizardData.selectedSet]) {
        if (filtered.has(name)) wizardData.selectedSet.delete(name);
    }
    renderCatalog();
}

let _filterTimer = null;
function filterTables() {
    clearTimeout(_filterTimer);
    _filterTimer = setTimeout(() => {
        wizardData.catalogRenderLimit = 200;
        renderCatalog();
    }, 150);
}

async function checkAndShowRetryModal() {
    if (!wizardData.target.connectionString || wizardData.tables.length === 0) return false;
    let retryTables = [];
    try {
        const res = await fetch('/api/wizard-mssql/check-retry-needed', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mssqlConnectionString: wizardData.target.connectionString,
                schema: wizardData.source.schema || 'dbo',
                tables: wizardData.tables
            })
        });
        const data = await res.json();
        if (data.success && data.tables.length > 0) retryTables = data.tables;
    } catch { /* continue */ }

    if (retryTables.length === 0) return false;

    const tbody = document.getElementById('retryModeTableBody');
    tbody.innerHTML = '';
    for (const t of retryTables) {
        const badges = [];
        if (t.hasTargetData) badges.push('<span class="badge bg-warning text-dark">Hedefte veri</span>');
        if (t.hasCheckpoint) badges.push('<span class="badge bg-info text-dark">Checkpoint</span>');
        tbody.innerHTML += `
        <tr>
            <td class="align-middle fw-semibold">${t.tableName}</td>
            <td class="align-middle">${badges.join(' ')}</td>
            <td>
                <div class="btn-group w-100" role="group">
                    <input type="radio" class="btn-check" name="retry_${t.tableName}" id="retry_resume_${t.tableName}" value="Resume" checked>
                    <label class="btn btn-outline-success btn-sm" for="retry_resume_${t.tableName}">Devam</label>
                    <input type="radio" class="btn-check" name="retry_${t.tableName}" id="retry_truncate_${t.tableName}" value="Truncate">
                    <label class="btn btn-outline-warning btn-sm" for="retry_truncate_${t.tableName}">Truncate</label>
                    <input type="radio" class="btn-check" name="retry_${t.tableName}" id="retry_recreate_${t.tableName}" value="Recreate">
                    <label class="btn btn-outline-danger btn-sm" for="retry_recreate_${t.tableName}">Recreate</label>
                </div>
            </td>
        </tr>`;
    }

    const modal = new bootstrap.Modal(document.getElementById('retryModeModal'));
    modal.show();

    return await new Promise(resolve => {
        const confirmBtn = document.getElementById('retryModalConfirmBtn');
        const cancelBtn = document.getElementById('retryModalCancelBtn');
        const onConfirm = () => {
            wizardData.tableRetryModes = {};
            for (const t of retryTables) {
                const selected = document.querySelector(`input[name="retry_${t.tableName}"]:checked`);
                wizardData.tableRetryModes[t.tableName] = selected ? selected.value : 'Resume';
            }
            cleanup();
            modal.hide();
            currentStep = 4;
            updateSummary();
            updateUI();
            resolve(true);
        };
        const onCancel = () => { cleanup(); modal.hide(); resolve(true); };
        const cleanup = () => {
            confirmBtn.removeEventListener('click', onConfirm);
            cancelBtn.removeEventListener('click', onCancel);
        };
        confirmBtn.addEventListener('click', onConfirm);
        cancelBtn.addEventListener('click', onCancel);
    });
}

function updateSummary() {
    const src = `${document.getElementById('sourceServer').value} / ${document.getElementById('sourceDatabase').value} / ${document.getElementById('sourceSchema').value || 'dbo'}`;
    const tgt = `${document.getElementById('targetServer').value} / ${document.getElementById('targetDatabase').value}`;
    document.getElementById('summarySource').textContent = src;
    document.getElementById('summaryTarget').textContent = tgt;
    document.getElementById('summaryTables').textContent =
        `${wizardData.tables.length} tables: ${wizardData.tables.slice(0, 20).join(', ')}${wizardData.tables.length > 20 ? '…' : ''}`;
}

function buildMigrationRequest() {
    return {
        sourceConnectionString: wizardData.source.connectionString,
        targetConnectionString: wizardData.target.connectionString,
        schema: wizardData.source.schema || document.getElementById('sourceSchema').value || 'dbo',
        tables: wizardData.tables,
        degreeOfParallelism: Math.min(64, Math.max(1, parseInt(document.getElementById('parallelism').value, 10) || 8)),
        batchSize: parseInt(document.getElementById('batchSize').value, 10) || 50000,
        migratePrimaryKeys: document.getElementById('migratePrimaryKeys').checked,
        migrateIndexes: document.getElementById('migrateIndexes').checked,
        migrateForeignKeys: document.getElementById('migrateForeignKeys').checked,
        migrateUniqueConstraints: document.getElementById('migrateUniqueConstraints').checked,
        migrateCheckConstraints: document.getElementById('migrateCheckConstraints').checked,
        migrateTriggers: false,
        validationMode: document.getElementById('validationMode').value,
        validatePerTableAfterLoad: document.getElementById('validatePerTableAfterLoad').checked,
        validationFailFast: document.getElementById('validationFailFast').checked,
        autoStart: document.getElementById('autoStartDotnetRun').checked,
        tableRetryModes: wizardData.tableRetryModes
    };
}

async function startMigration() {
    if (!wizardData.source.tested || !wizardData.target.tested) {
        await showAlert('warning', 'Kaynak ve hedef bağlantıları test edilmeli.');
        return;
    }
    if (wizardData.tables.length === 0) {
        await showAlert('warning', 'En az bir tablo seçin.');
        return;
    }

    const req = buildMigrationRequest();

    try {
        const checkRes = await fetch('/api/wizard-mssql/check-target-data', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mssqlConnectionString: req.targetConnectionString,
                schema: req.schema,
                tables: req.tables
            })
        });
        const checkData = await checkRes.json();
        if (checkData.success && checkData.hasAnyRows) {
            let action = 'continue';
            if (typeof Swal !== 'undefined') {
                const result = await Swal.fire({
                    ...swalBase(),
                    icon: 'warning',
                    title: 'Hedefte veri var',
                    text: `Toplam ~${checkData.totalRows} satır. Truncate edilsin mi?`,
                    showDenyButton: true,
                    showCancelButton: true,
                    confirmButtonText: 'TRUNCATE + devam',
                    denyButtonText: 'Truncate etme, devam',
                    cancelButtonText: 'İptal'
                });
                if (result.isDismissed) return;
                if (result.isConfirmed) action = 'truncate';
            }
            if (action === 'truncate') {
                await fetch('/api/wizard-mssql/clear-target-tables', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        mssqlConnectionString: req.targetConnectionString,
                        schema: req.schema,
                        tables: req.tables
                    })
                });
            }
        }

        const response = await fetch('/api/wizard-mssql/start-migration', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(req)
        });
        const data = await response.json();
        if (!data.success) throw new Error(data.error || 'Config kaydedilemedi');
        window.location.href = '/mssql-copy/start';
    } catch (ex) {
        await showAlert('error', 'Hata', ex.message);
    }
}

async function checkSelectedTableTransferStatus() {
    const body = document.getElementById('tableTransferStatusBody');
    body.innerHTML = '<tr><td colspan="5" class="text-center">Kontrol ediliyor…</td></tr>';
    try {
        const res = await fetch('/api/wizard-mssql/table-transfer-status', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                sourceConnectionString: wizardData.source.connectionString,
                targetConnectionString: wizardData.target.connectionString,
                schema: wizardData.source.schema || 'dbo',
                tables: wizardData.tables
            })
        });
        const data = await res.json();
        if (!data.success) throw new Error(data.error || 'Kontrol başarısız');
        body.innerHTML = '';
        for (const t of data.tables) {
            body.innerHTML += `<tr>
                <td>${t.table}</td>
                <td>${t.checkpointStatus}</td>
                <td class="text-end">${Number(t.sourceCount).toLocaleString()}</td>
                <td class="text-end">${Number(t.targetCount).toLocaleString()}</td>
                <td>${t.match ? '<span class="text-success">OK</span>' : '<span class="text-warning">Fark</span>'}</td>
            </tr>`;
        }
    } catch (ex) {
        body.innerHTML = `<tr><td colspan="5" class="text-danger">${ex.message}</td></tr>`;
    }
}

async function saveMigrationProfile() {
    const name = document.getElementById('migrationProfileName').value.trim();
    const result = document.getElementById('saveProfileResult');
    if (!name) {
        result.innerHTML = '<span class="text-warning">Profil adı gerekli</span>';
        return;
    }
    const req = {
        profileName: name,
        ...buildMigrationRequest(),
        sourcePassword: document.getElementById('sourcePassword').value,
        targetPassword: document.getElementById('targetPassword').value,
        sourceHost: document.getElementById('sourceServer').value,
        sourceUsername: document.getElementById('sourceUser').value,
        sourceDatabase: document.getElementById('sourceDatabase').value,
        sourceAuthType: document.getElementById('sourceAuth').value,
        sourceTrustCert: document.getElementById('sourceTrustCert').checked,
        targetHost: document.getElementById('targetServer').value,
        targetUsername: document.getElementById('targetUser').value,
        targetDatabase: document.getElementById('targetDatabase').value,
        targetAuthType: document.getElementById('targetAuth').value,
        targetTrustCert: document.getElementById('targetTrustCert').checked
    };
    try {
        const res = await fetch('/api/wizard-mssql/save-profile', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(req)
        });
        const data = await res.json();
        result.innerHTML = data.success
            ? '<span class="text-success">Profil kaydedildi</span>'
            : `<span class="text-danger">${data.error}</span>`;
        if (data.success) void loadConnectionProfiles();
    } catch (ex) {
        result.innerHTML = `<span class="text-danger">${ex.message}</span>`;
    }
}

async function loadConnectionProfiles() {
    try {
        const response = await fetch('/api/wizard-mssql/connection-profiles?type=MssqlCopy');
        const data = await response.json();
        const select = document.getElementById('wizardProfileSelect');
        const banner = document.getElementById('wizardProfileBanner');
        if (!data.success || !data.profiles?.length) return;
        banner.classList.remove('d-none');
        select.innerHTML = '<option value="">-- Profil seç --</option>';
        for (const p of data.profiles) {
            select.innerHTML += `<option value="${p.id}">${p.profileName}</option>`;
        }
    } catch { /* ignore */ }
}

async function loadSelectedProfile() {
    const id = document.getElementById('wizardProfileSelect').value;
    const status = document.getElementById('wizardProfileLoadStatus');
    if (!id) return;
    try {
        const res = await fetch(`/api/history/profiles/${id}`);
        const p = await res.json();
        const cfg = p.configJson ? JSON.parse(p.configJson) : {};
        if (cfg.sourceHost) document.getElementById('sourceServer').value = cfg.sourceHost;
        if (cfg.sourceUsername) document.getElementById('sourceUser').value = cfg.sourceUsername;
        if (cfg.sourcePassword) document.getElementById('sourcePassword').value = cfg.sourcePassword;
        if (cfg.sourceDatabase) document.getElementById('sourceDatabase').value = cfg.sourceDatabase;
        if (cfg.sourceAuthType) document.getElementById('sourceAuth').value = cfg.sourceAuthType;
        if (cfg.schema) document.getElementById('sourceSchema').value = cfg.schema;
        if (cfg.targetHost) document.getElementById('targetServer').value = cfg.targetHost;
        if (cfg.targetUsername) document.getElementById('targetUser').value = cfg.targetUsername;
        if (cfg.targetPassword) document.getElementById('targetPassword').value = cfg.targetPassword;
        if (cfg.targetDatabase) document.getElementById('targetDatabase').value = cfg.targetDatabase;
        if (cfg.targetAuthType) document.getElementById('targetAuth').value = cfg.targetAuthType;
        toggleCreds('source');
        toggleCreds('target');
        if (cfg.sourceConnectionString) {
            wizardData.source.tested = true;
            wizardData.source.connectionString = cfg.sourceConnectionString;
            wizardData.source.schema = cfg.schema || 'dbo';
        }
        if (cfg.targetConnectionString) {
            wizardData.target.tested = true;
            wizardData.target.connectionString = cfg.targetConnectionString;
        }
        if (Array.isArray(cfg.tables)) wizardData.pendingTableNames = cfg.tables;
        if (cfg.degreeOfParallelism) document.getElementById('parallelism').value = cfg.degreeOfParallelism;
        if (cfg.batchSize) document.getElementById('batchSize').value = cfg.batchSize;
        status.textContent = 'Profil yüklendi. Bağlantıları yeniden test etmeniz önerilir.';
    } catch (ex) {
        status.textContent = 'Yükleme hatası: ' + ex.message;
    }
}

async function checkResumable() {
    try {
        const res = await fetch('/api/wizard-mssql/resume-info');
        const data = await res.json();
        if (!data.hasResumable) return;
        document.getElementById('resumeBanner').classList.remove('d-none');
        document.getElementById('resumeSummaryText').textContent =
            `Run #${data.runId} — ${data.doneCount}/${data.tableCount} tablo tamam, ${data.pendingCount} bekliyor${data.oracleSchema ? ' (' + data.oracleSchema + ')' : ''}`;
        document.getElementById('resumeTableList').innerHTML = (data.tables || [])
            .map(t => `${t.tableName}: ${t.done}/${t.total}`)
            .join('<br>');
    } catch { /* ignore */ }
}

function dismissResumeBanner() {
    document.getElementById('resumeBanner').classList.add('d-none');
}

async function startResume() {
    try {
        await fetch('/api/mssql-copy-engine/build', { method: 'POST' });
        const res = await fetch('/api/mssql-copy-engine/resume', { method: 'POST' });
        const data = await res.json();
        if (!data.success) throw new Error(data.error || data.message || 'Resume başarısız');
        window.location.href = '/mssql-copy';
    } catch (ex) {
        await showAlert('error', 'Resume hatası', ex.message);
    }
}
