let currentStep = 1;
const totalSteps = 4;

/** SweetAlert2 — koyu tema, layout’taki Swal ile uyumlu */
function swalBase() {
    return {
        background: '#212529',
        color: '#f8f9fa',
        confirmButtonColor: '#0d6efd',
        cancelButtonColor: '#6c757d',
        denyButtonColor: '#ffc107',
    };
}

let wizardData = {
    oracle: {
        tested: false,
        connectionString: ''
    },
    mssql: {
        tested: false,
        connectionString: ''
    },
    tables: [],
    config: {},
    tableRetryModes: {},   // { 'TABLE_NAME': 'Resume' | 'Truncate' | 'Recreate' }
    pendingTableNames: null  // profil yüklendiğinde step 3 checkbox'ları için
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
    updateUI();
    void loadConnectionProfiles();
    checkResumable();
});

function setupEventListeners() {
    // Navigation
    document.getElementById('nextBtn').addEventListener('click', () => void nextStep());
    document.getElementById('prevBtn').addEventListener('click', prevStep);
    document.getElementById('startBtn').addEventListener('click', startMigration);
    
    // Oracle connection
    document.getElementById('testOracleBtn').addEventListener('click', testOracleConnection);
    
    // MSSQL connection
    document.getElementById('testMssqlBtn').addEventListener('click', testMssqlConnection);
    document.getElementById('mssqlAuth').addEventListener('change', toggleMssqlCredentials);
    
    // Table selection
    document.getElementById('selectAllBtn')?.addEventListener('click', selectAllTables);
    document.getElementById('deselectAllBtn')?.addEventListener('click', deselectAllTables);
    document.getElementById('tableSearch')?.addEventListener('input', filterTables);
    document.getElementById('checkTableStatusBtn')?.addEventListener('click', () => void checkSelectedTableTransferStatus());

    // Paralel partition toggle → bilgi satırını göster/gizle
    document.getElementById('parallelPartitionLoad')?.addEventListener('change', function () {
        const group = document.getElementById('partitionParallelismGroup');
        if (group) group.style.display = this.checked ? '' : 'none';
    });

    const syncParallelHidden = () => {
        const ora = safePositiveInt(document.getElementById('oracleParallel')?.value, 56);
        const sql = safePositiveInt(document.getElementById('sqlMaxDop')?.value, 48);
        setInputValue('parallelism', ora);
        setInputValue('partitionDegreeOfParallelism', sql);
    };
    ['oracleParallel', 'sqlMaxDop', 'tableParallelism'].forEach((id) => {
        document.getElementById(id)?.addEventListener('change', syncParallelHidden);
        document.getElementById(id)?.addEventListener('input', syncParallelHidden);
    });
    syncParallelHidden();

    // Staging merge toggle → info kutusunu göster/gizle
    document.getElementById('useStagingMerge')?.addEventListener('change', function () {
        const info = document.getElementById('stagingMergeInfo');
        if (info) info.style.display = this.checked ? '' : 'none';
    });

    // Partition switch toggle → info + auto-enable staging merge
    document.getElementById('usePartitionSwitch')?.addEventListener('change', function () {
        const info = document.getElementById('partitionSwitchInfo');
        if (info) info.style.display = this.checked ? '' : 'none';
        if (this.checked) {
            const stagingChk = document.getElementById('useStagingMerge');
            if (stagingChk && !stagingChk.checked) {
                stagingChk.checked = true;
                stagingChk.dispatchEvent(new Event('change'));
            }
        }
    });
}

async function nextStep() {
    if (currentStep < totalSteps) {
        if (await validateStep(currentStep)) {
            // Step 3 → 4 geçişinde retry mod kontrolü
            if (currentStep === 3) {
                const handled = await checkAndShowRetryModal();
                if (handled) return; // Modal açıldı, kullanıcı karar verince devam edecek
            }

            currentStep++;

            if (currentStep === 3) {
                loadOracleTables();
            } else if (currentStep === 4) {
                updateSummary();
                const body = document.getElementById('tableTransferStatusBody');
                if (body) {
                    body.innerHTML = '<tr><td colspan="6" class="text-muted text-center py-3">Kontrol için "Kontrol et" butonunu kullanın.</td></tr>';
                }
            }

            updateUI();
        }
    }
}

/** Step 3 → 4 geçişinde retry gerektiren tablolar varsa modal açar.
 *  Açıldıysa true döner (çağıran nextStep'i durdurmalı). */
async function checkAndShowRetryModal() {
    if (!wizardData.mssql.connectionString || wizardData.tables.length === 0) return false;

    let retryTables = [];
    try {
        const res = await fetch('/api/wizard/check-retry-needed', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mssqlConnectionString: wizardData.mssql.connectionString,
                tables: wizardData.tables
            })
        });
        const data = await res.json();
        if (data.success && data.tables.length > 0) retryTables = data.tables;
    } catch { /* bağlantı hatası — devam et */ }

    if (retryTables.length === 0) return false;

    // Modal'ı doldur
    const tbody = document.getElementById('retryModeTableBody');
    tbody.innerHTML = '';
    for (const t of retryTables) {
        const statusBadges = [];
        if (t.hasTargetData) statusBadges.push('<span class="badge bg-warning text-dark">Hedefte veri var</span>');
        if (t.hasCheckpoint) statusBadges.push('<span class="badge bg-info text-dark">Checkpoint mevcut</span>');
        tbody.innerHTML += `
        <tr>
            <td class="align-middle fw-semibold">${t.tableName}</td>
            <td class="align-middle">${statusBadges.join(' ')}</td>
            <td>
                <div class="btn-group w-100" role="group">
                    <input type="radio" class="btn-check" name="retry_${t.tableName}" id="retry_resume_${t.tableName}" value="Resume" checked>
                    <label class="btn btn-outline-success btn-sm" for="retry_resume_${t.tableName}" title="Kaldığı yerden devam et">
                        &#8635; Devam
                    </label>
                    <input type="radio" class="btn-check" name="retry_${t.tableName}" id="retry_truncate_${t.tableName}" value="Truncate">
                    <label class="btn btn-outline-warning btn-sm" for="retry_truncate_${t.tableName}" title="Hedef tabloyu temizle, sıfırdan başla">
                        &#9003; Truncate
                    </label>
                    <input type="radio" class="btn-check" name="retry_${t.tableName}" id="retry_recreate_${t.tableName}" value="Recreate">
                    <label class="btn btn-outline-danger btn-sm" for="retry_recreate_${t.tableName}" title="Hedef tabloyu sil ve yeniden oluştur">
                        &#9746; Yeniden Oluştur
                    </label>
                </div>
            </td>
        </tr>`;
    }

    // "Tümüne uygula" satırı
    tbody.innerHTML += `
    <tr class="table-secondary">
        <td colspan="2" class="align-middle text-muted small">Tüm tablolara uygula:</td>
        <td>
            <div class="btn-group w-100" role="group">
                <button class="btn btn-outline-success btn-sm" onclick="setAllRetryMode('Resume')">&#8635; Hepsine Devam</button>
                <button class="btn btn-outline-warning btn-sm" onclick="setAllRetryMode('Truncate')">&#9003; Hepsine Truncate</button>
                <button class="btn btn-outline-danger btn-sm" onclick="setAllRetryMode('Recreate')">&#9746; Hepsini Yeniden Oluştur</button>
            </div>
        </td>
    </tr>`;

    // Buton event'leri
    const modal = new bootstrap.Modal(document.getElementById('retryModeModal'));
    document.getElementById('retryModalCancelBtn').onclick = () => modal.hide();
    document.getElementById('retryModalConfirmBtn').onclick = () => {
        // Seçimleri topla
        wizardData.tableRetryModes = {};
        for (const t of retryTables) {
            const selected = document.querySelector(`input[name="retry_${t.tableName}"]:checked`);
            if (selected) wizardData.tableRetryModes[t.tableName] = selected.value;
        }
        modal.hide();
        // Step 4'e geç
        currentStep++;
        updateSummary();
        const body = document.getElementById('tableTransferStatusBody');
        if (body) body.innerHTML = '<tr><td colspan="6" class="text-muted text-center py-3">Kontrol için "Kontrol et" butonunu kullanın.</td></tr>';
        updateUI();
    };

    modal.show();
    return true;
}

function setAllRetryMode(mode) {
    document.querySelectorAll(`#retryModeTableBody input[value="${mode}"]`).forEach(r => {
        r.checked = true;
    });
}

function prevStep() {
    if (currentStep > 1) {
        currentStep--;
        updateUI();
    }
}

function updateUI() {
    // Update steps
    document.querySelectorAll('.wizard-step').forEach((step, index) => {
        step.classList.toggle('active', index + 1 === currentStep);
    });
    
    document.querySelectorAll('.wizard-progress .step').forEach((step, index) => {
        step.classList.toggle('active', index + 1 === currentStep);
        step.classList.toggle('completed', index + 1 < currentStep);
    });
    
    // Update buttons
    document.getElementById('prevBtn').disabled = currentStep === 1;
    document.getElementById('nextBtn').style.display = currentStep < totalSteps ? 'inline-block' : 'none';
    document.getElementById('startBtn').classList.toggle('d-none', currentStep !== totalSteps);
}

async function validateStep(step) {
    switch (step) {
        case 1:
            if (!wizardData.oracle.tested) {
                await showAlert('warning', 'Önce Oracle bağlantısını test edin.');
                return false;
            }
            return true;
        case 2:
            if (!wizardData.mssql.tested) {
                await showAlert('warning', 'Önce MSSQL bağlantısını test edin.');
                return false;
            }
            return true;
        case 3:
            if (wizardData.tables.length === 0) {
                await showAlert('warning', 'En az bir tablo seçin.');
                return false;
            }
            return true;
        default:
            return true;
    }
}

async function testOracleConnection() {
    const btn = document.getElementById('testOracleBtn');
    const spinner = document.getElementById('oracleSpinner');
    const result = document.getElementById('oracleResult');
    
    btn.disabled = true;
    spinner.classList.remove('d-none');
    result.classList.add('d-none');
    
    const connection = {
        host: document.getElementById('oracleHost').value,
        port: document.getElementById('oraclePort').value,
        service: document.getElementById('oracleService').value,
        username: document.getElementById('oracleUser').value,
        password: document.getElementById('oraclePassword').value,
        schema: document.getElementById('oracleSchema').value
    };
    
    try {
        const response = await fetch('/api/wizard/test-oracle', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(connection)
        });
        
        const data = await response.json();
        
        if (data.success) {
            wizardData.oracle.tested = true;
            wizardData.oracle.connectionString = data.connectionString;
            wizardData.oracle.schema = connection.schema;
            showResult(result, 'success', `Connected successfully! Found ${data.tableCount} tables.`);
            
            const savePr = await Swal.fire({
                ...swalBase(),
                icon: 'question',
                title: 'Bağlantı başarılı',
                text: 'Bu Oracle bağlantısını profil olarak kaydetmek ister misiniz?',
                showCancelButton: true,
                confirmButtonText: 'Evet, kaydet',
                cancelButtonText: 'Hayır',
            });
            if (savePr.isConfirmed) {
                void promptSaveProfile('Oracle');
            }
        } else {
            wizardData.oracle.tested = false;
            showResult(result, 'error', `Connection failed: ${data.error}`);
        }
    } catch (error) {
        wizardData.oracle.tested = false;
        showResult(result, 'error', `Error: ${error.message}`);
    } finally {
        btn.disabled = false;
        spinner.classList.add('d-none');
    }
}

async function testMssqlConnection() {
    const btn = document.getElementById('testMssqlBtn');
    const spinner = document.getElementById('mssqlSpinner');
    const result = document.getElementById('mssqlResult');
    
    btn.disabled = true;
    spinner.classList.remove('d-none');
    result.classList.add('d-none');
    
    const connection = {
        server: document.getElementById('mssqlServer').value,
        authType: document.getElementById('mssqlAuth').value,
        username: document.getElementById('mssqlUser').value,
        password: document.getElementById('mssqlPassword').value,
        database: document.getElementById('mssqlDatabase').value,
        trustCert: document.getElementById('mssqlTrustCert').checked
    };
    
    try {
        const response = await fetch('/api/wizard/test-mssql', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(connection)
        });
        
        const data = await response.json();
        
        if (data.success) {
            wizardData.mssql.tested = true;
            wizardData.mssql.connectionString = data.connectionString;
            wizardData.mssql.database = connection.database;
            showResult(result, 'success', `Connected successfully! Database: ${data.databaseName}`);
            
            const savePr = await Swal.fire({
                ...swalBase(),
                icon: 'question',
                title: 'Bağlantı başarılı',
                text: 'Bu MSSQL bağlantısını profil olarak kaydetmek ister misiniz?',
                showCancelButton: true,
                confirmButtonText: 'Evet, kaydet',
                cancelButtonText: 'Hayır',
            });
            if (savePr.isConfirmed) {
                void promptSaveProfile('MSSQL');
            }
        } else {
            wizardData.mssql.tested = false;
            showResult(result, 'error', `Connection failed: ${data.error}`);
        }
    } catch (error) {
        wizardData.mssql.tested = false;
        showResult(result, 'error', `Error: ${error.message}`);
    } finally {
        btn.disabled = false;
        spinner.classList.add('d-none');
    }
}

async function loadOracleTables() {
    const loadingDiv = document.getElementById('loadingTables');
    const selectionDiv = document.getElementById('tableSelection');
    
    loadingDiv.classList.remove('d-none');
    selectionDiv.classList.add('d-none');
    
    try {
        const response = await fetch('/api/wizard/list-tables', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                connectionString: wizardData.oracle.connectionString,
                schema: wizardData.oracle.schema
            })
        });
        
        const data = await response.json();
        
        if (data.success) {
            displayTables(data.tables);
            loadingDiv.classList.add('d-none');
            selectionDiv.classList.remove('d-none');
        } else {
            void showAlert('error', `Tablolar yüklenemedi: ${data.error}`);
        }
    } catch (error) {
        void showAlert('error', `Tablo listesi hatası: ${error.message}`);
    }
}

function displayTables(tables) {
    const tableList = document.getElementById('tableList');
    tableList.innerHTML = '';
    
    tables.forEach(table => {
        const div = document.createElement('div');
        div.className = 'table-item';
        div.innerHTML = `
            <div class="form-check">
                <input class="form-check-input table-checkbox" type="checkbox" value="${table.name}" id="table-${table.name}">
                <label class="form-check-label" for="table-${table.name}">
                    <strong>${table.name}</strong>
                    <span class="text-muted">(~${formatNumber(table.rowCount)} rows)</span>
                </label>
            </div>
        `;
        tableList.appendChild(div);
    });
    
    // Add change event to all checkboxes
    document.querySelectorAll('.table-checkbox').forEach(checkbox => {
        checkbox.addEventListener('change', updateSelectedCount);
    });

    applyPendingTableSelection();
}

function selectAllTables() {
    document.querySelectorAll('.table-checkbox').forEach(cb => cb.checked = true);
    updateSelectedCount();
}

function deselectAllTables() {
    document.querySelectorAll('.table-checkbox').forEach(cb => cb.checked = false);
    updateSelectedCount();
}

function filterTables() {
    const searchTerm = document.getElementById('tableSearch').value.toLowerCase();
    document.querySelectorAll('.table-item').forEach(item => {
        const text = item.textContent.toLowerCase();
        item.style.display = text.includes(searchTerm) ? 'block' : 'none';
    });
}

function updateSelectedCount() {
    const selected = document.querySelectorAll('.table-checkbox:checked');
    wizardData.tables = Array.from(selected).map(cb => cb.value);
    document.getElementById('selectedCount').textContent = selected.length;
}

function updateSummary() {
    const oracleHost = document.getElementById('oracleHost').value;
    const oracleSchema = document.getElementById('oracleSchema').value;
    document.getElementById('summaryOracle').textContent = `${oracleHost} / Schema: ${oracleSchema}`;
    
    const mssqlServer = document.getElementById('mssqlServer').value;
    const mssqlDb = document.getElementById('mssqlDatabase').value;
    document.getElementById('summaryMssql').textContent = `${mssqlServer} / Database: ${mssqlDb}`;

    const oracleParallel = safePositiveInt(document.getElementById('oracleParallel')?.value, 56);
    const sqlMaxDop = safePositiveInt(document.getElementById('sqlMaxDop')?.value, 48);
    const tableParallelism = safePositiveInt(document.getElementById('tableParallelism')?.value, 2);
    setInputValue('parallelism', oracleParallel);
    setInputValue('partitionDegreeOfParallelism', sqlMaxDop);

    const sumOra = document.getElementById('summaryOracleParallel');
    const sumSql = document.getElementById('summarySqlMaxDop');
    const sumPkg = document.getElementById('summaryTableParallelism');
    const sumCount = document.getElementById('summaryTableCount');
    if (sumOra) sumOra.textContent = String(oracleParallel);
    if (sumSql) sumSql.textContent = String(sqlMaxDop);
    if (sumPkg) sumPkg.textContent = String(tableParallelism);
    if (sumCount) sumCount.textContent = String(wizardData.tables.length);

    const tablesEl = document.getElementById('summaryTables');
    if (tablesEl) {
        if (!wizardData.tables.length) {
            tablesEl.textContent = 'Tablo seçilmedi';
        } else {
            const items = wizardData.tables.map(t => `<li><code>${escapeHtmlWizard(t)}</code></li>`).join('');
            tablesEl.innerHTML = `<ul>${items}</ul>`;
        }
    }
    
    wizardData.config = {
        degreeOfParallelism: oracleParallel,
        oracleParallel,
        partitionDegreeOfParallelism: sqlMaxDop,
        sqlMaxDop,
        tableParallelism,
        batchSize: parseInt(document.getElementById('batchSize').value),
        fetchSizeMB: parseInt(document.getElementById('fetchSize').value)
    };
}

function formatTransferStatusLabel(status) {
    const key = String(status || '').toLowerCase();
    const map = {
        running: 'Çalışıyor',
        completed: 'Tamamlandı',
        done: 'Tamamlandı',
        pending: 'Bekliyor',
        failed: 'Hata',
        unknown: 'Bilinmiyor',
        invalidname: 'Geçersiz'
    };
    return map[key] || String(status || 'Bilinmiyor');
}

function transferStatusBadgeClass(status) {
    const key = String(status || '').toLowerCase();
    if (key === 'completed' || key === 'done') return 'bg-success';
    if (key === 'running') return 'bg-primary';
    if (key === 'failed' || key === 'invalidname') return 'bg-danger';
    if (key === 'pending') return 'bg-warning text-dark';
    return 'bg-secondary';
}

async function checkSelectedTableTransferStatus() {
    if (!wizardData.tables.length) {
        await showAlert('warning', 'Önce en az bir tablo seçin.');
        return;
    }
    if (!wizardData.oracle.connectionString || !wizardData.mssql.connectionString) {
        await showAlert('warning', 'Önce Oracle ve MSSQL bağlantılarını test edin veya geçerli bir profil yükleyin.');
        return;
    }

    const btn = document.getElementById('checkTableStatusBtn');
    const body = document.getElementById('tableTransferStatusBody');
    if (!body) return;
    const original = btn?.innerHTML || 'Kontrol et';
    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Kontrol ediliyor…';
    }

    try {
        const response = await fetch('/api/wizard/table-transfer-status', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                oracleConnectionString: wizardData.oracle.connectionString,
                oracleSchema: wizardData.oracle.schema || document.getElementById('oracleSchema')?.value || '',
                mssqlConnectionString: wizardData.mssql.connectionString,
                tables: wizardData.tables
            })
        });
        const data = await response.json();
        if (!data.success) {
            body.innerHTML = `<tr><td colspan="6" class="text-danger text-center py-3">${escapeHtmlWizard(data.error || 'Kontrol başarısız')}</td></tr>`;
            return;
        }

        const rows = Array.isArray(data.tables) ? data.tables : [];
        if (!rows.length) {
            body.innerHTML = '<tr><td colspan="6" class="text-muted text-center py-3">Sonuç yok</td></tr>';
            return;
        }

        body.innerHTML = rows.map((r) => {
            const diff = Number(r.difference || 0);
            const matched = !!r.matched;
            const diffClass = matched ? 'text-success' : (diff > 0 ? 'text-warning' : 'text-danger');
            return `
                <tr>
                    <td><code>${escapeHtmlWizard(r.tableName)}</code></td>
                    <td><span class="badge ${transferStatusBadgeClass(r.transferStatus)}">${escapeHtmlWizard(formatTransferStatusLabel(r.transferStatus))}</span></td>
                    <td class="text-end">${formatNumber(r.sourceRows || 0)}</td>
                    <td class="text-end">${formatNumber(r.targetRows || 0)}</td>
                    <td class="text-end ${diffClass}">${formatNumber(Math.abs(diff))}</td>
                    <td>${matched ? '<span class="badge bg-success">Eşit</span>' : '<span class="badge bg-secondary">Fark var</span>'}</td>
                </tr>
            `;
        }).join('');
    } catch (error) {
        body.innerHTML = `<tr><td colspan="6" class="text-danger text-center py-3">Hata: ${escapeHtmlWizard(error.message)}</td></tr>`;
    } finally {
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = original;
        }
    }
}

function safePositiveInt(value, fallback) {
    const n = parseInt(String(value ?? ''), 10);
    return Number.isFinite(n) && n > 0 ? n : fallback;
}

function safeNonNegativeInt(value, fallback) {
    const n = parseInt(String(value ?? ''), 10);
    return Number.isFinite(n) && n >= 0 ? n : fallback;
}

const startBtnDefaultHtml =
    '<svg width="16" height="16" fill="currentColor" class="bi bi-play-fill" viewBox="0 0 16 16"><path d="m11.596 8.697-6.363 3.692c-.54.313-1.233-.066-1.233-.697V4.308c0-.63.692-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393z"/></svg> Kaydet ve devam';

function resetStartButton(btn) {
    btn.disabled = false;
    btn.innerHTML = startBtnDefaultHtml;
}

function escapeHtmlWizard(text) {
    const div = document.createElement('div');
    div.textContent = text == null ? '' : String(text);
    return div.innerHTML;
}

/** Hedefte satır varsa SweetAlert ile sor; onaylanırsa TRUNCATE API çağrılır. */
async function confirmTargetDataHandling(migrationRequest) {
    let checkData;
    try {
        const checkRes = await fetch('/api/wizard/check-target-data', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                mssqlConnectionString: migrationRequest.mssqlConnectionString,
                tables: migrationRequest.tables,
            }),
        });
        checkData = await checkRes.json();
    } catch (e) {
        await showAlert('error', `Hedef kontrolü isteği başarısız: ${e.message}`);
        return false;
    }

    if (!checkData.success) {
        await showAlert('error', checkData.error || 'Hedef veritabanı kontrol edilemedi.');
        return false;
    }

    if (!checkData.hasAnyRows) {
        return true;
    }

    const rowsHtml = (checkData.details || [])
        .filter((d) => d.exists && d.rowCount > 0)
        .map(
            (d) =>
                `<tr><td><code>${escapeHtmlWizard(d.table)}</code></td><td class="text-end">${formatNumber(d.rowCount)}</td></tr>`
        )
        .join('');

    const r = await Swal.fire({
        ...swalBase(),
        icon: 'warning',
        title: 'Hedefte veri var',
        html:
            '<p class="text-start mb-2">Seçtiğiniz tablolardan bazılarında MSSQL (<code>dbo</code>) tarafında satır bulundu. Migration öncesi bu tablolarda <strong>TRUNCATE</strong> ile temizlemek ister misiniz?</p>' +
            `<p class="small text-secondary text-start mb-2">Yaklaşık toplam: <strong>${formatNumber(checkData.totalRows)}</strong> satır (sys.partitions; tahmini).</p>` +
            '<div class="table-responsive text-start rounded border border-secondary" style="max-height:240px;overflow:auto">' +
            '<table class="table table-sm table-dark mb-0"><thead><tr><th>Tablo</th><th class="text-end">Satır (yakl.)</th></tr></thead><tbody>' +
            rowsHtml +
            '</tbody></table></div>',
        showDenyButton: true,
        showCancelButton: true,
        confirmButtonText: 'Evet, TRUNCATE ile temizle',
        denyButtonText: 'Hayır, temizleme',
        cancelButtonText: 'İptal',
        width: '32rem',
        focusCancel: true,
    });

    if (r.dismiss === Swal.DismissReason.cancel || r.dismiss === Swal.DismissReason.esc || r.dismiss === Swal.DismissReason.backdrop) {
        return false;
    }

    if (r.isConfirmed) {
        let clearJson;
        try {
            const clearRes = await fetch('/api/wizard/clear-target-tables', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    mssqlConnectionString: migrationRequest.mssqlConnectionString,
                    tables: migrationRequest.tables,
                }),
            });
            clearJson = await clearRes.json();
        } catch (e) {
            await showAlert('error', `Temizleme isteği başarısız: ${e.message}`);
            return false;
        }

        if (!clearJson.success) {
            const lines = (clearJson.results || [])
                .filter((x) => x.ok === false)
                .map((x) => `${x.table}: ${x.error || 'hata'}`)
                .join('\n');
            await Swal.fire({
                ...swalBase(),
                icon: 'error',
                title: 'Temizleme tamamlanamadı',
                text: clearJson.error || lines || 'Bilinmeyen hata',
            });
            return false;
        }

        await Swal.fire({
            ...swalBase(),
            icon: 'success',
            title: 'Hedef tablolar temizlendi',
            text: 'TRUNCATE tamamlandı. Yapılandırma kaydedilecek.',
            timer: 2200,
            showConfirmButton: false,
        });
        return true;
    }

    if (r.isDenied) {
        const c2 = await Swal.fire({
            ...swalBase(),
            icon: 'question',
            title: 'Temizlemeden devam',
            text:
                'Mevcut satırlar yinelenen anahtar (PK/unique) veya bulk load hatalarına yol açabilir. Yine de yapılandırmayı kaydetmek istiyor musunuz?',
            showCancelButton: true,
            confirmButtonText: 'Evet, yine de kaydet',
            cancelButtonText: 'Vazgeç',
        });
        return !!c2.isConfirmed;
    }

    return false;
}

async function startMigration() {
    const btn = document.getElementById('startBtn');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Kaydediliyor…';

    updateSummary();

    const parallelism = safePositiveInt(document.getElementById('oracleParallel')?.value, 56);
    const sqlMaxDop = safePositiveInt(document.getElementById('sqlMaxDop')?.value, 48);
    const tableParallelism = safePositiveInt(document.getElementById('tableParallelism')?.value, 2);
    setInputValue('parallelism', parallelism);
    setInputValue('partitionDegreeOfParallelism', sqlMaxDop);
    const batchSize = safePositiveInt(document.getElementById('batchSize')?.value, 50000);
    const fetchSize = safePositiveInt(document.getElementById('fetchSize')?.value, 50);
    const validationMaxRows = safeNonNegativeInt(document.getElementById('validationMaxRows')?.value, 5000000);

    const migrationRequest = {
        oracleConnectionString: wizardData.oracle.connectionString,
        mssqlConnectionString: wizardData.mssql.connectionString,
        oracleSchema: wizardData.oracle.schema,
        tables: wizardData.tables,
        degreeOfParallelism: parallelism,
        oracleParallel: parallelism,
        tableParallelism,
        batchSize,
        fetchSizeMB: fetchSize,
        // Schema migration options
        migrateIndexes: document.getElementById('migrateIndexes')?.checked || false,
        migrateTriggers: document.getElementById('migrateTriggers')?.checked || false,
        migrateForeignKeys: document.getElementById('migrateForeignKeys')?.checked || false,
        migratePrimaryKeys: document.getElementById('migratePrimaryKeys')?.checked !== false, // default true
        migrateUniqueConstraints: document.getElementById('migrateUniqueConstraints')?.checked || false,
        migrateCheckConstraints: document.getElementById('migrateCheckConstraints')?.checked || false,
        validationMode: document.getElementById('validationMode')?.value || 'Balanced',
        validationMaxRowsForExtendedGates: validationMaxRows,
        validatePerTableAfterLoad: document.getElementById('validatePerTableAfterLoad')?.checked || false,
        validationFailFast: document.getElementById('validationFailFast')?.checked || false,
        enableCompositePkHash: document.getElementById('enableCompositePkHash')?.checked || false,
        autoStart: document.getElementById('autoStartDotnetRun')?.checked || false,
        parallelPartitionLoad: document.getElementById('parallelPartitionLoad')?.checked !== false,
        partitionDegreeOfParallelism: sqlMaxDop,
        sqlMaxDop,
        useStagingMerge: document.getElementById('useStagingMerge')?.checked || false,
        usePartitionSwitch: document.getElementById('usePartitionSwitch')?.checked || false,
        useBulkLoggedRecovery: document.getElementById('useBulkLoggedRecovery')?.checked !== false,
        tableRetryModes: wizardData.tableRetryModes
    };

    const okTarget = await confirmTargetDataHandling(migrationRequest);
    if (!okTarget) {
        resetStartButton(btn);
        return;
    }

    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Yapılandırma yazılıyor…';

    try {
        const response = await fetch('/api/wizard/start-migration', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(migrationRequest)
        });
        
        let data = {};
        try {
            data = await response.json();
        } catch {
            await showAlert('error', `Yapılandırma kaydedilemedi: HTTP ${response.status} (geçersiz JSON yanıtı)`);
            resetStartButton(btn);
            return;
        }

        if (response.ok && data.success) {
            await Swal.fire({
                ...swalBase(),
                icon: 'success',
                title: 'Yapılandırma kaydedildi',
                text: 'Başlat sayfasına yönlendiriliyorsunuz…',
                timer: 1600,
                showConfirmButton: false,
            });
            window.location.href = '/start';
        } else {
            const apiError = data.error || data.title || data.detail;
            const validationErrors = data.errors && typeof data.errors === 'object'
                ? Object.entries(data.errors).map(([k, v]) => {
                    if (Array.isArray(v)) return `${k}: ${v.join(', ')}`;
                    if (v && typeof v === 'object') return `${k}: ${JSON.stringify(v)}`;
                    return `${k}: ${v}`;
                }).join('; ')
                : '';
            const msg = apiError || validationErrors || `HTTP ${response.status} ${response.statusText}`;
            await showAlert('error', `Kayıt başarısız: ${msg}`);
            resetStartButton(btn);
        }
    } catch (error) {
        await showAlert('error', `Hata: ${error.message}`);
        resetStartButton(btn);
    }
}

function toggleMssqlCredentials() {
    const authType = document.getElementById('mssqlAuth').value;
    const credentials = document.getElementById('mssqlCredentials');
    credentials.style.display = authType === 'sql' ? 'block' : 'none';
}

function showResult(element, type, message) {
    element.className = `alert alert-${type === 'success' ? 'success' : 'danger'} d-inline-block`;
    element.textContent = message;
    element.classList.remove('d-none');
}

async function showAlert(type, message) {
    if (typeof Swal === 'undefined') {
        window.alert(message);
        return;
    }
    const icon =
        type === 'error' ? 'error' : type === 'success' ? 'success' : type === 'warning' ? 'warning' : 'info';
    const title =
        type === 'error' ? 'Hata' : type === 'success' ? 'Tamam' : type === 'warning' ? 'Uyarı' : 'Bilgi';
    await Swal.fire({
        ...swalBase(),
        icon,
        title,
        text: message,
        confirmButtonText: 'Tamam',
    });
}

function formatNumber(num) {
    return new Intl.NumberFormat().format(num);
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = String(text ?? '');
    return div.innerHTML;
}

// Connection Profiles
async function loadConnectionProfiles() {
    try {
        const response = await fetch('/api/wizard/connection-profiles');
        const data = await response.json();
        
        if (data.success) {
            populateProfileDropdowns(data.profiles);
        }
        await initWizardProfileFromUrl();
    } catch (error) {
        console.error('Failed to load connection profiles:', error);
    }
}

// ── Resume ──────────────────────────────────────────────────────────────────

async function checkResumable() {
    try {
        const res = await fetch('/api/wizard/resume-info');
        if (!res.ok) return;
        const data = await res.json();
        if (!data.hasResumable) return;

        const banner = document.getElementById('resumeBanner');
        const summaryText = document.getElementById('resumeSummaryText');
        const tableList = document.getElementById('resumeTableList');
        if (!banner) return;

        const started = new Date(data.startedAt).toLocaleString('tr-TR');
        const schema = data.oracleSchema ? ` (${data.oracleSchema})` : '';
        summaryText.textContent =
            `${started} tarihinde başlayan migration${schema} tamamlanamadı. ` +
            `${data.doneCount} tablo tamamlandı, ${data.pendingCount} tablo bekliyor.`;

        if (data.tables && data.tables.length > 0) {
            const pending = data.tables.filter(t => !t.isComplete);
            const done    = data.tables.filter(t =>  t.isComplete);
            let html = '';
            if (done.length)
                html += `<span class="text-success me-3"><i class="fas fa-check-circle me-1"></i>${done.length} tamamlandı</span>`;
            if (pending.length) {
                html += `<span class="text-warning"><i class="fas fa-clock me-1"></i>${pending.length} bekliyor: `;
                html += pending.slice(0, 5).map(t => `<strong>${escapeHtml(t.tableName)}</strong>`).join(', ');
                if (pending.length > 5) html += ` +${pending.length - 5} daha`;
                html += '</span>';
            }
            tableList.innerHTML = html;
        }

        banner.classList.remove('d-none');
    } catch (e) {
        console.warn('checkResumable:', e);
    }
}

async function startResume() {
    const btn = document.querySelector('#resumeBanner .btn-warning');
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Derleniyor…'; }
    try {
        const buildRes = await fetch('/api/engine/build', { method: 'POST' });
        const buildData = await buildRes.json();
        if (!buildData.success) {
            throw new Error(buildData.error || 'Build başarısız');
        }

        if (btn) btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Başlatılıyor…';
        const res = await fetch('/api/engine/resume', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            await showAlert('success', 'Migration kaldığı yerden devam ediyor. Dashboard\'a yönlendiriliyorsunuz…');
            window.location.href = '/';
        } else {
            await showAlert('error', 'Devam ettirilemedi: ' + (data.error || data.message));
            if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-play me-1"></i> Kaldığı Yerden Devam Et'; }
        }
    } catch (e) {
        await showAlert('error', 'Hata: ' + e.message);
        if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-play me-1"></i> Kaldığı Yerden Devam Et'; }
    }
}

function dismissResumeBanner() {
    const banner = document.getElementById('resumeBanner');
    if (banner) banner.classList.add('d-none');
}

// ── Connection Profiles ──────────────────────────────────────────────────────

function parseConnectionStringValue(connectionString, keys) {
    if (!connectionString) return '';
    for (const key of keys) {
        const re = new RegExp(`(?:^|;)\\s*${key}\\s*=\\s*([^;]*)`, 'i');
        const m = connectionString.match(re);
        if (m) return m[1].trim();
    }
    return '';
}

function parseOracleDataSource(connectionString) {
    const ds = parseConnectionStringValue(connectionString, ['Data Source']);
    if (!ds) return { host: '', port: '1521', service: '' };
    const slash = ds.indexOf('/');
    const colon = ds.indexOf(':');
    if (colon >= 0 && slash > colon) {
        return {
            host: ds.substring(0, colon),
            port: ds.substring(colon + 1, slash) || '1521',
            service: ds.substring(slash + 1)
        };
    }
    return { host: ds, port: '1521', service: '' };
}

function parseMssqlServer(connectionString) {
    return parseConnectionStringValue(connectionString, ['Data Source', 'Server']);
}

function parseMssqlDatabase(connectionString) {
    return parseConnectionStringValue(connectionString, ['Initial Catalog', 'Database']);
}

function setInputValue(id, value) {
    const el = document.getElementById(id);
    if (el && value != null && value !== '') el.value = value;
}

function setCheckboxValue(id, value) {
    const el = document.getElementById(id);
    if (el) el.checked = !!value;
}

function applyMigrationConfigOptions(cfg) {
    if (!cfg) return;
    const oracleParallel = cfg.oracleParallel || cfg.degreeOfParallelism || 56;
    const sqlMaxDop = cfg.sqlMaxDop || cfg.partitionDegreeOfParallelism || 48;
    const tableParallelism = cfg.tableParallelism || 2;
    setInputValue('oracleParallel', oracleParallel);
    setInputValue('sqlMaxDop', sqlMaxDop);
    setInputValue('tableParallelism', tableParallelism);
    setInputValue('parallelism', oracleParallel);
    setInputValue('partitionDegreeOfParallelism', sqlMaxDop);
    if (cfg.batchSize) setInputValue('batchSize', cfg.batchSize);
    if (cfg.fetchSizeMB) setInputValue('fetchSize', cfg.fetchSizeMB);
    if (cfg.validationMaxRowsForExtendedGates != null) {
        setInputValue('validationMaxRows', cfg.validationMaxRowsForExtendedGates);
    }
    setCheckboxValue('migrateIndexes', cfg.migrateIndexes);
    setCheckboxValue('migrateTriggers', cfg.migrateTriggers);
    setCheckboxValue('migrateForeignKeys', cfg.migrateForeignKeys);
    setCheckboxValue('migratePrimaryKeys', cfg.migratePrimaryKeys !== false);
    setCheckboxValue('migrateUniqueConstraints', cfg.migrateUniqueConstraints);
    setCheckboxValue('migrateCheckConstraints', cfg.migrateCheckConstraints);
    setCheckboxValue('validatePerTableAfterLoad', cfg.validatePerTableAfterLoad);
    setCheckboxValue('validationFailFast', cfg.validationFailFast);
    setCheckboxValue('enableCompositePkHash', cfg.enableCompositePkHash);
    setCheckboxValue('parallelPartitionLoad', cfg.parallelPartitionLoad !== false);
    setCheckboxValue('useStagingMerge', cfg.useStagingMerge);
    setCheckboxValue('usePartitionSwitch', cfg.usePartitionSwitch);
    setCheckboxValue('useBulkLoggedRecovery', cfg.useBulkLoggedRecovery !== false);
    if (cfg.validationMode) setInputValue('validationMode', cfg.validationMode);
    const group = document.getElementById('partitionParallelismGroup');
    if (group) group.style.display = (cfg.parallelPartitionLoad !== false) ? '' : 'none';
    const stagingInfo = document.getElementById('stagingMergeInfo');
    if (stagingInfo) stagingInfo.style.display = cfg.useStagingMerge ? '' : 'none';
    const switchInfo = document.getElementById('partitionSwitchInfo');
    if (switchInfo) switchInfo.style.display = cfg.usePartitionSwitch ? '' : 'none';
}

function applyOracleConnectionFromProfile(profile, cfg) {
    const oracleCs = cfg?.oracleConnectionString || profile.connectionString || '';
    const parsed = parseOracleDataSource(oracleCs);

    setInputValue('oracleHost', profile.host || cfg?.oracleHost || parsed.host);
    setInputValue('oraclePort', profile.port || cfg?.oraclePort || parsed.port || '1521');
    setInputValue('oracleService', profile.serviceName || cfg?.oracleService || parsed.service);
    setInputValue('oracleUser', profile.username || cfg?.oracleUsername || parseConnectionStringValue(oracleCs, ['User Id', 'User ID']));
    setInputValue('oracleSchema', profile.schemaName || cfg?.oracleSchema || '');
    setInputValue('oraclePassword',
        cfg?.oraclePassword || parseConnectionStringValue(oracleCs, ['Password', 'Pwd']));

    if (oracleCs) {
        wizardData.oracle.connectionString = oracleCs;
        wizardData.oracle.tested = true;
        wizardData.oracle.schema = profile.schemaName || cfg?.oracleSchema || document.getElementById('oracleSchema')?.value || '';
    }
}

function applyMssqlConnectionFromProfile(profile, cfg) {
    const mssqlCs = cfg?.mssqlConnectionString || '';
    const authType = cfg?.mssqlAuthType || profile.authType || 'sql';

    setInputValue('mssqlServer', cfg?.mssqlHost || parseMssqlServer(mssqlCs));
    setInputValue('mssqlAuth', authType);
    toggleMssqlCredentials();
    if (authType === 'sql') {
        setInputValue('mssqlUser', cfg?.mssqlUsername || profile.username || parseConnectionStringValue(mssqlCs, ['User ID', 'UID']));
        setInputValue('mssqlPassword', cfg?.mssqlPassword || parseConnectionStringValue(mssqlCs, ['Password', 'Pwd']));
    }
    setInputValue('mssqlDatabase', cfg?.mssqlDatabase || profile.databaseName || parseMssqlDatabase(mssqlCs));
    const trustEl = document.getElementById('mssqlTrustCert');
    if (trustEl) {
        trustEl.checked = cfg?.mssqlTrustCert != null ? !!cfg.mssqlTrustCert : (profile.trustCert ?? true);
    }

    if (mssqlCs) {
        wizardData.mssql.connectionString = mssqlCs;
        wizardData.mssql.tested = true;
        wizardData.mssql.database = document.getElementById('mssqlDatabase')?.value || '';
    }
}

function applyPendingTableSelection() {
    const pending = wizardData.pendingTableNames;
    if (!pending || !Array.isArray(pending) || pending.length === 0) return;

    const pendingSet = new Set(pending.map(t => String(t).toUpperCase()));
    let matched = 0;
    document.querySelectorAll('.table-checkbox').forEach(cb => {
        if (pendingSet.has(cb.value.toUpperCase())) {
            cb.checked = true;
            matched++;
        }
    });
    updateSelectedCount();

    if (matched < pending.length) {
        wizardData.tables = [...pending];
        document.getElementById('selectedCount').textContent = pending.length;
    }
}

function applyFullMigrationProfile(profile) {
    if (!profile) return false;

    let cfg = null;
    if (profile.configJson) {
        try { cfg = JSON.parse(profile.configJson); } catch { cfg = null; }
    }

    applyOracleConnectionFromProfile(profile, cfg);
    applyMssqlConnectionFromProfile(profile, cfg);
    applyMigrationConfigOptions(cfg);

    if (cfg && Array.isArray(cfg.tables) && cfg.tables.length > 0) {
        wizardData.tables = [...cfg.tables];
        wizardData.pendingTableNames = [...cfg.tables];
        applyPendingTableSelection();
    }

    const statusEl = document.getElementById('wizardProfileLoadStatus');
    const tableCount = cfg?.tables?.length ?? wizardData.tables.length;
    const name = profile.profileName || profile.name || 'Profil';
    if (statusEl) {
        statusEl.innerHTML = `<span class="text-success"><i class="fas fa-check-circle me-1"></i><strong>${escapeHtmlWizard(name)}</strong> yüklendi — ${tableCount} tablo, bağlantılar ve aktarım seçenekleri uygulandı.</span>`;
    }

    return true;
}

async function loadWizardProfileById(profileId) {
    const res = await fetch(`/api/history/profiles/${profileId}`);
    if (!res.ok) throw new Error(`Profil bulunamadı (${res.status})`);
    const profile = await res.json();
    if (profile.connectionType !== 'Migration' && !profile.configJson) {
        if (profile.connectionType === 'Oracle') {
            loadOracleProfile(normalizeProfile(profile));
            return;
        }
        if (profile.connectionType === 'MSSQL') {
            loadMssqlProfile(normalizeProfile(profile));
            return;
        }
    }
    applyFullMigrationProfile(normalizeProfile(profile));
}

function normalizeProfile(p) {
    return {
        ...p,
        profileName: p.profileName || p.name,
        connectionString: p.connectionString,
        configJson: p.configJson
    };
}

async function initWizardProfileFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const profileId = params.get('profileId');
    if (!profileId) return;
    try {
        await loadWizardProfileById(profileId);
        const select = document.getElementById('wizardProfileSelect');
        if (select) select.value = profileId;
    } catch (e) {
        console.warn('profileId load failed:', e);
        await showAlert('warning', `Profil yüklenemedi: ${e.message}`);
    }
}

function populateProfileDropdowns(profiles) {
    const oracleProfiles = profiles.filter(p => p.connectionType === 'Oracle');
    const mssqlProfiles = profiles.filter(p => p.connectionType === 'MSSQL');
    const migrationProfiles = profiles.filter(p => p.connectionType === 'Migration' && p.configJson);

    if (oracleProfiles.length > 0) {
        addProfileDropdown('oracleForm', oracleProfiles, loadOracleProfile);
    }
    if (mssqlProfiles.length > 0) {
        addProfileDropdown('mssqlForm', mssqlProfiles, loadMssqlProfile);
    }
    if (migrationProfiles.length > 0) {
        populateWizardProfileBanner(migrationProfiles);
    }

    const loadBtn = document.getElementById('wizardProfileLoadBtn');
    if (loadBtn && !loadBtn.dataset.bound) {
        loadBtn.dataset.bound = '1';
        loadBtn.addEventListener('click', () => void loadSelectedWizardProfile());
    }
}

function populateWizardProfileBanner(profiles) {
    const banner = document.getElementById('wizardProfileBanner');
    const select = document.getElementById('wizardProfileSelect');
    if (!banner || !select) return;

    select.innerHTML = '<option value="">-- Profil seç --</option>' +
        profiles.map(p => {
            let tableCount = '?';
            try {
                if (p.configJson) tableCount = JSON.parse(p.configJson).tables?.length ?? '?';
            } catch { /* ignore */ }
            const label = escapeHtmlWizard(p.profileName || p.name);
            const data = JSON.stringify(p).replace(/'/g, '&#39;');
            return `<option value="${p.id}" data-profile='${data}'>${label} (${tableCount} tablo)</option>`;
        }).join('');

    banner.classList.remove('d-none');
}

async function loadSelectedWizardProfile() {
    const select = document.getElementById('wizardProfileSelect');
    if (!select || !select.value) {
        await showAlert('warning', 'Lütfen bir profil seçin.');
        return;
    }
    const option = select.options[select.selectedIndex];
    const profile = normalizeProfile(JSON.parse(option.getAttribute('data-profile')));
    if (applyFullMigrationProfile(profile)) {
        await showAlert('success',
            `Profil "${profile.profileName}" yüklendi. Bağlantılar, şifreler, tablolar ve aktarım seçenekleri uygulandı.`);
    }
}

function loadMigrationProfile() {
    loadSelectedWizardProfile();
}

function addProfileDropdown(formId, profiles, loadCallback) {
    const form = document.getElementById(formId);
    const firstElement = form.querySelector('.mb-3');
    
    const profileDiv = document.createElement('div');
    profileDiv.className = 'mb-3';
    profileDiv.innerHTML = `
        <label class="form-label">
            <svg width="16" height="16" fill="currentColor" class="bi bi-bookmark-star" viewBox="0 0 16 16">
                <path d="M7.84 4.1a.178.178 0 0 1 .32 0l.634 1.285a.178.178 0 0 0 .134.098l1.42.206c.145.021.204.2.098.303L9.42 6.993a.178.178 0 0 0-.051.158l.242 1.414a.178.178 0 0 1-.258.187l-1.27-.668a.178.178 0 0 0-.165 0l-1.27.668a.178.178 0 0 1-.257-.187l.242-1.414a.178.178 0 0 0-.05-.158l-1.03-1.001a.178.178 0 0 1 .098-.303l1.42-.206a.178.178 0 0 0 .134-.098L7.84 4.1z"/>
                <path d="M2 2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v13.5a.5.5 0 0 1-.777.416L8 13.101l-5.223 2.815A.5.5 0 0 1 2 15.5V2zm2-1a1 1 0 0 0-1 1v12.566l4.723-2.482a.5.5 0 0 1 .554 0L13 14.566V2a1 1 0 0 0-1-1H4z"/>
            </svg>
            Load Saved Profile
        </label>
        <div class="d-flex gap-2">
            <select class="form-select profile-select">
                <option value="">-- Select a profile --</option>
                ${profiles.map(p => `<option value="${p.id}" data-profile='${JSON.stringify(p)}'>${p.profileName} (used ${p.useCount} times)</option>`).join('')}
            </select>
            <button type="button" class="btn btn-outline-primary load-profile-btn">Load</button>
        </div>
    `;
    
    form.insertBefore(profileDiv, firstElement);
    
    profileDiv.querySelector('.load-profile-btn').addEventListener('click', () => {
        const select = profileDiv.querySelector('.profile-select');
        const option = select.options[select.selectedIndex];
        if (option.value) {
            const profile = JSON.parse(option.getAttribute('data-profile'));
            loadCallback(profile);
        }
    });
}

function loadOracleProfile(profile) {
    const p = normalizeProfile(profile);
    let cfg = null;
    if (p.configJson) {
        try { cfg = JSON.parse(p.configJson); } catch { /* ignore */ }
    }
    applyOracleConnectionFromProfile(p, cfg);
    void showAlert('success', `Profil yüklendi: ${p.profileName}`);
}

function loadMssqlProfile(profile) {
    const p = normalizeProfile(profile);
    let cfg = null;
    if (p.configJson) {
        try { cfg = JSON.parse(p.configJson); } catch { /* ignore */ }
    }
    applyMssqlConnectionFromProfile(p, cfg);
    if (!wizardData.mssql.connectionString && p.connectionString) {
        wizardData.mssql.connectionString = p.connectionString;
        wizardData.mssql.tested = true;
        setInputValue('mssqlPassword', parseConnectionStringValue(p.connectionString, ['Password', 'Pwd']));
    }
    void showAlert('success', `Profil yüklendi: ${p.profileName}`);
}

async function saveConnectionProfile(type, data, profileName) {
    try {
        const response = await fetch('/api/wizard/save-profile', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                profileName: profileName,
                connectionType: type,
                connectionString: type === 'Oracle'
                    ? (wizardData.oracle.connectionString || null)
                    : (wizardData.mssql.connectionString || null),
                oracleConnectionString: type === 'Oracle' ? wizardData.oracle.connectionString : null,
                mssqlConnectionString: type === 'MSSQL' ? wizardData.mssql.connectionString : null,
                oraclePassword: data.oraclePassword || null,
                mssqlPassword: data.mssqlPassword || null,
                mssqlHost: data.host || null,
                mssqlUsername: data.username || null,
                mssqlDatabase: data.databaseName || null,
                mssqlAuthType: data.authType || null,
                mssqlTrustCert: data.trustCert,
                ...data
            })
        });
        
        const result = await response.json();
        if (result.success) {
            void showAlert('success', `Profil "${profileName}" kaydedildi.`);
            loadConnectionProfiles(); // Reload profiles
        }
    } catch (error) {
        console.error('Failed to save profile:', error);
    }
}

async function saveMigrationProfile() {
    const nameEl = document.getElementById('migrationProfileName');
    const resultEl = document.getElementById('saveProfileResult');
    const btn = document.getElementById('saveMigrationProfileBtn');
    const profileName = nameEl?.value?.trim();

    if (!profileName) {
        if (resultEl) resultEl.innerHTML = '<span class="text-warning small"><i class="fas fa-exclamation-triangle me-1"></i>Profil adı girin.</span>';
        return;
    }
    if (!wizardData.tables || wizardData.tables.length === 0) {
        if (resultEl) resultEl.innerHTML = '<span class="text-warning small"><i class="fas fa-exclamation-triangle me-1"></i>Tablo seçimi yapılmamış.</span>';
        return;
    }

    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Kaydediliyor…'; }

    const parallelism = safePositiveInt(document.getElementById('oracleParallel')?.value, 56);
    const sqlMaxDop = safePositiveInt(document.getElementById('sqlMaxDop')?.value, 48);
    const tableParallelism = safePositiveInt(document.getElementById('tableParallelism')?.value, 2);
    const batchSize = safePositiveInt(document.getElementById('batchSize')?.value, 50000);
    const fetchSize = safePositiveInt(document.getElementById('fetchSize')?.value, 50);
    const validationMaxRows = safeNonNegativeInt(document.getElementById('validationMaxRows')?.value, 5000000);

    const payload = {
        profileName,
        connectionType: 'Migration',
        host: document.getElementById('oracleHost')?.value || '',
        port: document.getElementById('oraclePort')?.value || '1521',
        serviceName: document.getElementById('oracleService')?.value || '',
        username: document.getElementById('oracleUser')?.value || '',
        schemaName: document.getElementById('oracleSchema')?.value || '',
        databaseName: document.getElementById('mssqlDatabase')?.value || '',
        connectionString: wizardData.oracle.connectionString || null,
        oracleConnectionString: wizardData.oracle.connectionString,
        mssqlConnectionString: wizardData.mssql.connectionString,
        oracleSchema: wizardData.oracle.schema || document.getElementById('oracleSchema')?.value || '',
        oraclePassword: document.getElementById('oraclePassword')?.value || null,
        mssqlPassword: document.getElementById('mssqlPassword')?.value || null,
        mssqlHost: document.getElementById('mssqlServer')?.value || '',
        mssqlUsername: document.getElementById('mssqlUser')?.value || '',
        mssqlDatabase: document.getElementById('mssqlDatabase')?.value || '',
        mssqlAuthType: document.getElementById('mssqlAuth')?.value || 'sql',
        mssqlTrustCert: document.getElementById('mssqlTrustCert')?.checked ?? true,
        tables: wizardData.tables,
        degreeOfParallelism: parallelism,
        oracleParallel: parallelism,
        tableParallelism,
        batchSize,
        fetchSizeMB: fetchSize,
        migrateIndexes: document.getElementById('migrateIndexes')?.checked || false,
        migrateTriggers: document.getElementById('migrateTriggers')?.checked || false,
        migrateForeignKeys: document.getElementById('migrateForeignKeys')?.checked || false,
        migratePrimaryKeys: document.getElementById('migratePrimaryKeys')?.checked !== false,
        migrateUniqueConstraints: document.getElementById('migrateUniqueConstraints')?.checked || false,
        migrateCheckConstraints: document.getElementById('migrateCheckConstraints')?.checked || false,
        validationMode: document.getElementById('validationMode')?.value || 'Balanced',
        validationMaxRowsForExtendedGates: validationMaxRows,
        validatePerTableAfterLoad: document.getElementById('validatePerTableAfterLoad')?.checked || false,
        validationFailFast: document.getElementById('validationFailFast')?.checked || false,
        enableCompositePkHash: document.getElementById('enableCompositePkHash')?.checked || false,
        parallelPartitionLoad: document.getElementById('parallelPartitionLoad')?.checked !== false,
        partitionDegreeOfParallelism: sqlMaxDop,
        sqlMaxDop,
        useStagingMerge: document.getElementById('useStagingMerge')?.checked || false,
        usePartitionSwitch: document.getElementById('usePartitionSwitch')?.checked || false,
        useBulkLoggedRecovery: document.getElementById('useBulkLoggedRecovery')?.checked !== false
    };

    try {
        const res = await fetch('/api/wizard/save-profile', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (data.success) {
            if (resultEl) resultEl.innerHTML = `<span class="text-success small"><i class="fas fa-check-circle me-1"></i>Profil "<strong>${escapeHtml(profileName)}</strong>" kaydedildi (${wizardData.tables.length} tablo).</span>`;
            loadConnectionProfiles();
        } else {
            if (resultEl) resultEl.innerHTML = `<span class="text-danger small"><i class="fas fa-times-circle me-1"></i>${escapeHtml(data.error || 'Kayıt başarısız')}</span>`;
        }
    } catch (e) {
        if (resultEl) resultEl.innerHTML = `<span class="text-danger small"><i class="fas fa-times-circle me-1"></i>Hata: ${escapeHtml(e.message)}</span>`;
    } finally {
        if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-save me-1"></i> Profili Kaydet'; }
    }
}

async function promptSaveProfile(type) {
    const r = await Swal.fire({
        ...swalBase(),
        title: `${type} profil adı`,
        input: 'text',
        inputLabel: 'Profil adı',
        inputPlaceholder: 'ör. Prod Oracle',
        showCancelButton: true,
        confirmButtonText: 'Kaydet',
        cancelButtonText: 'İptal',
        inputValidator: (value) => {
            if (!value || !String(value).trim()) {
                return 'Bir ad girin';
            }
            return undefined;
        },
    });
    if (!r.isConfirmed || !r.value) {
        return;
    }
    const profileName = String(r.value).trim();
    if (type === 'Oracle') {
        await saveConnectionProfile('Oracle', {
            host: document.getElementById('oracleHost').value,
            port: document.getElementById('oraclePort').value,
            serviceName: document.getElementById('oracleService').value,
            username: document.getElementById('oracleUser').value,
            schemaName: document.getElementById('oracleSchema').value,
            oraclePassword: document.getElementById('oraclePassword').value
        }, profileName);
    } else if (type === 'MSSQL') {
        await saveConnectionProfile('MSSQL', {
            host: document.getElementById('mssqlServer').value,
            authType: document.getElementById('mssqlAuth').value,
            username: document.getElementById('mssqlUser').value,
            databaseName: document.getElementById('mssqlDatabase').value,
            trustCert: document.getElementById('mssqlTrustCert').checked,
            mssqlPassword: document.getElementById('mssqlPassword').value
        }, profileName);
    }
}
