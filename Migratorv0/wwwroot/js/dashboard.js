const connection = new signalR.HubConnectionBuilder()
    .withUrl("/migrationHub")
    .withAutomaticReconnect()
    .configureLogging(signalR.LogLevel.Information)
    .build();

let currentFilter = 'all';
let autoScroll = true;
let engineStatusCheckInterval = null;
/** Avoid repeating “no configuration” toast on every status poll */
let engineConfigAlertShown = false;
/** Hub özetinde status Running ise true; aksi halde checkpoint’teki Running “yarım” sayılır. */
let lastMigrationSummaryActive = false;
/** Engine’in çalışıp çalışmadığını izler — idle kartının içeriğini günceller. */
let lastEngineRunning = false;
/** Tamamlanma banner’ının bir kez gösterilmesi için önceki terminal durumu izlenir. */
let _prevWasDone = false;
/** Son partition yanıtı (ham); özet satırı güncellenince rozetler yeniden çizilir. */
let _lastConfiguredTables = [];
let _frozenElapsedText = null;
let _frozenElapsedRunId = null;
let lastPartitionListRaw = [];

function setEngineStatusDetail(text, warn = false) {
    const det = document.getElementById('engineStatusDetail');
    if (!det) return;
    det.textContent = text || '';
    det.title = text || '';
    det.classList.toggle('text-warning', !!warn && !!text);
    det.classList.toggle('text-muted', !warn || !text);
}
/** @type {Map<string, HTMLTableRowElement>} */
const partitionRowById = new Map();
/** @type {Map<string, HTMLTableRowElement>} */
const tableRowByName = new Map();

function pick(obj, camel, pascal, fallback = undefined) {
    if (obj == null) return fallback;
    const a = obj[camel];
    if (a !== undefined && a !== null) return a;
    const b = obj[pascal];
    if (b !== undefined && b !== null) return b;
    return fallback;
}

/** Hub / JSON bazen PascalCase döner; grid anahtarı için tek şekil. */
function normalizePartition(p) {
    if (!p || typeof p !== 'object') return null;
    const id = pick(p, 'id', 'Id');
    return {
        id,
        tableName: String(pick(p, 'tableName', 'TableName', '') ?? ''),
        partitionKey: String(pick(p, 'partitionKey', 'PartitionKey', '') ?? ''),
        status: String(pick(p, 'status', 'Status', '') ?? ''),
        rowsProcessed: Number(pick(p, 'rowsProcessed', 'RowsProcessed', 0)),
        totalRows: Number(pick(p, 'totalRows', 'TotalRows', 0)),
        startTime: pick(p, 'startTime', 'StartTime', null),
        endTime: pick(p, 'endTime', 'EndTime', null),
        errorMessage: pick(p, 'errorMessage', 'ErrorMessage', null),
    };
}

function normalizeSummary(s) {
    if (!s || typeof s !== 'object') return null;
    const n = (c, p, d) => pick(s, c, p, d);
    return {
        runId: n('runId', 'RunId', 0),
        totalTables: n('totalTables', 'TotalTables', 0),
        completedTables: n('completedTables', 'CompletedTables', 0),
        runningTables: n('runningTables', 'RunningTables', 0),
        pendingTables: n('pendingTables', 'PendingTables', 0),
        failedTables: n('failedTables', 'FailedTables', 0),
        overallPercentComplete: Number(n('overallPercentComplete', 'OverallPercentComplete', 0)),
        elapsedTime: n('elapsedTime', 'ElapsedTime', ''),
        configuredTables: (() => {
            const raw = pick(s, 'configuredTables', 'ConfiguredTables', null);
            return Array.isArray(raw) ? raw.map(String) : [];
        })(),
        endTime: n('endTime', 'EndTime', null),
        estimatedRemaining: n('estimatedRemaining', 'EstimatedRemaining', null),
        currentRowsPerSecond: Number(n('currentRowsPerSecond', 'CurrentRowsPerSecond', 0)),
        totalRowsProcessed: Number(n('totalRowsProcessed', 'TotalRowsProcessed', 0)),
        totalRowsExpected: Number(n('totalRowsExpected', 'TotalRowsExpected', 0)),
        startTime: n('startTime', 'StartTime', null),
        estimatedCompletionTime: n('estimatedCompletionTime', 'EstimatedCompletionTime', null),
        status: n('status', 'Status', ''),
        totalRowsSource: Number(n('totalRowsSource', 'TotalRowsSource', 0)),
        totalRowsLoaded: Number(n('totalRowsLoaded', 'TotalRowsLoaded', 0)),
    };
}

/** Sunucudan gelen enum/JSON değerini bozmadan yalnızca ekranda Türkçe gösterir. */
function formatMigrationStatusLabel(s) {
    const k = String(s ?? '').trim();
    const low = k.toLowerCase();
    const map = {
        running: 'Çalışıyor',
        pending: 'Beklemede',
        done: 'Tamamlandı',
        failed: 'Hata',
        skipped: 'Atlandı',
        paused: 'Duraklatıldı',
        completed: 'Tamamlandı',
        stopped: 'Durduruldu',
        interrupted: 'Yarım (kesinti)',
    };
    return map[low] || k;
}

/** Checkpoint Running iken run artık aktif değilse UI’da kesinti gösterilir. */
function effectivePartitionUiStatus(p) {
    const raw = String(p?.status ?? '').trim();
    const low = raw.toLowerCase();
    if (low === 'running' && !lastMigrationSummaryActive) return 'Interrupted';
    return raw || 'Pending';
}

function rowKeyForPartition(p) {
    if (p.id != null && p.id !== '') return String(p.id);
    return `${p.tableName}|${p.partitionKey}`;
}

function getPartitionPercent(p) {
    const st = String(p?.status || '').trim().toLowerCase();
    if (st === 'done' || st === 'completed') return 100;
    const total = Number(p?.totalRows || 0);
    const done = Number(p?.rowsProcessed || 0);
    return total > 0 ? Math.min(100, Math.round((done / total) * 100)) : 0;
}

function summarizeTableProgress(partitions) {
    const m = new Map();
    for (const p of (partitions || []).map(normalizePartition).filter(Boolean)) {
        const key = p.tableName || '(tablo adı yok)';
        let t = m.get(key);
        if (!t) {
            t = {
                tableName: key,
                rowsProcessed: 0,
                totalRows: 0,
                running: 0,
                staleRunning: 0,
                pending: 0,
                done: 0,
                failed: 0,
                skipped: 0,
                totalPartitions: 0
            };
            m.set(key, t);
        }
        const st = String(p.status || '').toLowerCase();
        t.rowsProcessed += Number(p.rowsProcessed || 0);
        t.totalRows += Number(p.totalRows || 0);
        t.totalPartitions += 1;
        if (st === 'running') {
            if (lastMigrationSummaryActive) t.running += 1;
            else t.staleRunning += 1;
        }
        else if (st === 'pending') t.pending += 1;
        else if (st === 'done') t.done += 1;
        else if (st === 'failed') t.failed += 1;
        else if (st === 'skipped') t.skipped += 1;
    }
    return [...m.values()].sort((a, b) => a.tableName.localeCompare(b.tableName));
}

function tableStatusFromSummary(t) {
    if (t.failed > 0) return 'Failed';
    if (t.running > 0) return 'Running';
    if ((t.staleRunning || 0) > 0) return 'Interrupted';
    if (t.totalPartitions > 0 && (t.done + t.skipped) === t.totalPartitions) return 'Done';
    return 'Pending';
}

function renderTableProgress(partitions) {
    const tbody = document.getElementById('tableProgressGrid');
    const summaryEl = document.getElementById('tableProgressSummary');
    if (!tbody) return;
    let rows = summarizeTableProgress(partitions);

    // Config'teki tüm tabloları göster (henüz partition başlamamış olanlar dahil)
    if (_lastConfiguredTables.length) {
        const byName = new Map(rows.map((r) => [r.tableName.toUpperCase(), r]));
        for (const name of _lastConfiguredTables) {
            const key = String(name || '').toUpperCase();
            if (!key || byName.has(key)) continue;
            byName.set(key, {
                tableName: name,
                rowsProcessed: 0,
                totalRows: 0,
                running: 0,
                staleRunning: 0,
                pending: 1,
                done: 0,
                failed: 0,
                skipped: 0,
                totalPartitions: 0
            });
        }
        // Preserve config order, then any extras
        const ordered = [];
        const seen = new Set();
        for (const name of _lastConfiguredTables) {
            const key = String(name || '').toUpperCase();
            const row = byName.get(key);
            if (row && !seen.has(key)) {
                ordered.push(row);
                seen.add(key);
            }
        }
        for (const [key, row] of byName) {
            if (!seen.has(key)) ordered.push(row);
        }
        rows = ordered;
    }

    if (!rows.length) {
        tableRowByName.clear();
        tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted py-4">Tablo ilerleme verisi bekleniyor…</td></tr>';
        if (summaryEl) summaryEl.textContent = 'Henüz tablo başlamadı';
        return;
    }

    const totalTarget = rows.reduce((a, x) => a + x.totalRows, 0);
    const totalDone = rows.reduce((a, x) => a + x.rowsProcessed, 0);
    const totalRemaining = Math.max(0, totalTarget - totalDone);
    const completedTables = rows.filter((x) => tableStatusFromSummary(x) === 'Done').length;
    if (summaryEl) {
        summaryEl.textContent = `${formatNumber(completedTables)}/${formatNumber(rows.length)} tablo tamam · kalan ${formatNumber(totalRemaining)} satır`;
    }

    const keep = new Set(rows.map((x) => x.tableName));
    for (const k of [...tableRowByName.keys()]) {
        if (!keep.has(k)) tableRowByName.delete(k);
    }

    window._lastPendingTableNames = rows
        .filter((x) => {
            const st = tableStatusFromSummary(x);
            return st === 'Pending' || st === 'Interrupted';
        })
        .map((x) => x.tableName);

    const frag = document.createDocumentFragment();
    for (const t of rows) {
        let tr = tableRowByName.get(t.tableName);
        if (!tr) {
            tr = document.createElement('tr');
            for (let i = 0; i < 8; i++) tr.appendChild(document.createElement('td'));
            tableRowByName.set(t.tableName, tr);
        }
        const st = tableStatusFromSummary(t);
        const pct = t.totalRows > 0 ? Math.min(100, Math.round((t.rowsProcessed / t.totalRows) * 100)) : 0;
        const remaining = Math.max(0, t.totalRows - t.rowsProcessed);
        tr.cells[0].textContent = t.tableName;
        tr.cells[1].innerHTML = `<span class="badge bg-${getStatusColor(st)}">${formatMigrationStatusLabel(st)}</span>`;
        tr.cells[2].className = 'text-end';
        tr.cells[2].textContent = formatNumber(t.rowsProcessed);
        tr.cells[3].className = 'text-end';
        tr.cells[3].textContent = formatNumber(t.totalRows);
        tr.cells[4].className = 'text-end';
        tr.cells[4].textContent = formatNumber(remaining);
        tr.cells[5].innerHTML = `<div class="d-flex align-items-center gap-2"><div class="progress flex-grow-1 partition-progress"><div class="progress-bar ${pct >= 100 ? 'bg-success' : 'bg-primary'}" style="width:${pct}%"></div></div><small class="text-muted">${pct}%</small></div>`;
        tr.cells[6].className = 'text-end text-muted';
        const sr = t.staleRunning || 0;
        tr.cells[6].textContent = t.totalPartitions > 0
            ? (sr > 0 ? `${t.running}+${sr} yarım / ${t.totalPartitions}` : `${t.running}/${t.totalPartitions}`)
            : '—';
        if (sr > 0) tr.cells[6].title = `${sr} partition checkpoint’te Running; migration run şu an aktif değil.`;
        else tr.cells[6].title = '';
        tr.cells[7].className = 'text-end text-nowrap';
        if (!lastEngineRunning && (st === 'Failed' || st === 'Pending' || st === 'Interrupted')) {
            const safeName = String(t.tableName).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
            const label = st === 'Failed' ? 'Yeniden dene' : 'Devam';
            const icon = st === 'Failed' ? 'fa-redo' : 'fa-play';
            tr.cells[7].innerHTML =
                `<button type="button" class="btn btn-outline-${st === 'Failed' ? 'warning' : 'primary'} btn-sm py-0 px-1" ` +
                `title="${label}: sadece ${escapeHtml(String(t.tableName))}" ` +
                `onclick="continueTableEngine('${safeName}', '${st}')">` +
                `<i class="fas ${icon}"></i><span class="d-none d-lg-inline ms-1">${label}</span></button>`;
        } else {
            tr.cells[7].innerHTML = '';
        }
        frag.appendChild(tr);
    }
    tbody.replaceChildren(frag);
}

function updatePartitionParallelSummary(partitions) {
    const el = document.getElementById('partitionParallelSummary');
    if (!el) return;
    if (!partitions || partitions.length === 0) {
        el.innerHTML = '<span class="text-muted">Bu run için partition kaydı yok. Motor yeni başladıysa birkaç saniye bekleyin veya checkpoint veritabanı yolunu kontrol edin.</span>';
        return;
    }
    const list = partitions.map(normalizePartition).filter(Boolean);
    const st = (x) => String(x.status || '').trim().toLowerCase();
    const nRunDb = list.filter((p) => st(p) === 'running').length;
    const nRunActive = lastMigrationSummaryActive ? nRunDb : 0;
    const nStaleRun = lastMigrationSummaryActive ? 0 : nRunDb;
    const nPen = list.filter((p) => st(p) === 'pending').length;
    const nDone = list.filter((p) => st(p) === 'done').length;
    const nFail = list.filter((p) => st(p) === 'failed').length;
    const nSkip = list.filter((p) => st(p) === 'skipped').length;
    const stalePart =
        nStaleRun > 0
            ? `, <span class="text-warning">${nStaleRun} yarım</span> <span class="text-muted" style="font-size:.85em">(checkpoint Running; run aktif değil)</span>`
            : '';
    el.innerHTML =
        `<strong>${list.length}</strong> partition toplam — ` +
        `<span class="text-primary">${nRunActive} çalışıyor</span>` +
        stalePart +
        `, <span class="text-secondary">${nPen} bekliyor</span>, ` +
        `<span class="text-success">${nDone} tamam</span>, ` +
        `<span class="text-danger">${nFail} hata</span>` +
        (nSkip ? `, <span class="text-warning">${nSkip} atlandı</span>` : '');
}

/** Tablo adına göre sıralı gruplar (sortPartitions sırası korunur). */
function groupPartitionsByTable(sorted) {
    const groups = [];
    let lastKey = null;
    let current = null;
    for (const p of sorted) {
        const key = p.tableName || '(tablo adı yok)';
        if (key !== lastKey) {
            current = { tableName: key, partitions: [] };
            groups.push(current);
            lastKey = key;
        }
        current.partitions.push(p);
    }
    return groups;
}

function buildPartitionMiniCard(p) {
    const pct = getPartitionPercent(p);
    const card = document.createElement('div');
    card.className = 'border rounded-3 px-2 py-2 shadow-sm small partition-mini-card';
    const uiSt = effectivePartitionUiStatus(p);
    const color = getStatusColor(uiSt);
    const stClass = color === 'secondary' ? 'text-secondary' : `text-${color}`;
    const title = (p.errorMessage && String(p.errorMessage)) || `Partition ${p.partitionKey}`;
    card.title = title.length > 200 ? title.slice(0, 197) + '…' : title;
    card.innerHTML =
        `<div class="d-flex flex-wrap align-items-center gap-1">` +
        `<span class="badge rounded-pill border border-secondary bg-dark text-light">P${escapeHtml(String(p.partitionKey))}</span>` +
        `<span class="fw-medium ${stClass}">${escapeHtml(formatMigrationStatusLabel(uiSt))}</span>` +
        `<span class="text-muted">%${pct}</span>` +
        `</div>` +
        `<div class="text-muted mt-1" style="font-size:.72rem">${formatNumber(p.rowsProcessed)} / ${formatNumber(p.totalRows)} satır</div>`;
    return card;
}

/** Partition progress kartı içinde tablo bazında gruplanmış kutucuklar. */
function updatePartitionParallelList(partitions) {
    const el = document.getElementById('partitionParallelList');
    if (!el) return;
    const list = (partitions || []).map(normalizePartition).filter(Boolean);
    if (!list.length) {
        el.innerHTML = '<span class="text-muted fst-italic">Aşağıdaki tabloda satır görünür.</span>';
        return;
    }
    const sorted = sortPartitions(list);
    const groups = groupPartitionsByTable(sorted);
    el.replaceChildren();
    const root = document.createElement('div');
    root.className = 'partition-by-table';
    for (const g of groups) {
        const section = document.createElement('section');
        section.className = 'partition-table-group mb-3 pb-2 border-bottom border-light';
        const head = document.createElement('div');
        head.className = 'd-flex align-items-baseline flex-wrap gap-2 mb-2';
        const n = g.partitions.length;
        head.innerHTML =
            `<h6 class="mb-0 fw-semibold text-body partition-table-heading">` +
            `<i class="fas fa-table text-primary me-1"></i>${escapeHtml(g.tableName)}` +
            `</h6>` +
            `<span class="badge bg-secondary">${n} partition</span>`;
        section.appendChild(head);
        const row = document.createElement('div');
        row.className = 'd-flex flex-wrap align-items-stretch gap-2';
        for (const p of g.partitions) {
            row.appendChild(buildPartitionMiniCard(p));
        }
        section.appendChild(row);
        root.appendChild(section);
    }
    const last = root.querySelector('.partition-table-group:last-child');
    if (last) {
        last.classList.remove('mb-3', 'pb-2', 'border-bottom', 'border-secondary-subtle');
    }
    el.appendChild(root);
}

async function refreshDashboardFromHub() {
    try {
        const summary = await connection.invoke('GetCurrentSummary');
        updateOverallProgress(summary);
        const partitions = await connection.invoke('GetPartitionStatuses');
        const partList = Array.isArray(partitions) ? partitions : [];
        updatePartitionGrid(partList);
        const events = await connection.invoke('GetRecentEvents', 80);
        appendToLogStream(events);
    } catch (e) {
        console.warn('refreshDashboardFromHub', e);
    }
}

connection.on("UpdateSummary", (summary) => {
    updateOverallProgress(summary);
});

connection.on("UpdatePartitions", (partitions) => {
    requestAnimationFrame(() => updatePartitionGrid(partitions));
});

connection.on("UpdateEvents", (events) => {
    appendToLogStream(events);
});

connection.onreconnecting(() => {
    document.getElementById('connectionStatus').classList.remove('d-none');
    document.getElementById('connectionStatus').classList.add('alert-warning');
    document.getElementById('connectionStatus').innerHTML = '<strong>Yeniden bağlanıyor…</strong> Bağlantı koptu, SignalR yeniden bağlanmayı deniyor…';
});

connection.onreconnected(async () => {
    document.getElementById('connectionStatus').classList.add('d-none');
    await refreshDashboardFromHub();
});

connection.onclose(() => {
    document.getElementById('connectionStatus').classList.remove('d-none');
    document.getElementById('connectionStatus').classList.remove('alert-info');
    document.getElementById('connectionStatus').classList.add('alert-danger');
    document.getElementById('connectionStatus').innerHTML = '<strong>Bağlantı kesildi</strong> — Migration motoru ile bağlantı yok.';
});

async function start() {
    try {
        await connection.start();
        console.log('[SignalR] Bağlantı başarılı! Polling interval: 2 saniye');
        console.log('[SignalR] Connection ID:', connection.connectionId);
        document.getElementById('connectionStatus').classList.add('d-none');
        await refreshDashboardFromHub();
    } catch (err) {
        console.error(err);
        setTimeout(start, 5000);
    }
}

// Initialize
start();

// Check engine status on page load and start monitoring
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
        checkEngineStatus();
        startEngineStatusMonitoring();
        loadRecentProfiles();
        setupPartitionCollapseToggle();
    });
} else {
    // DOM already loaded
    checkEngineStatus();
    startEngineStatusMonitoring();
    loadRecentProfiles();
    setupPartitionCollapseToggle();
}

function setupPartitionCollapseToggle() {
    const collapse = document.getElementById('partitionProgressCollapse');
    const icon = document.querySelector('.partition-collapse-icon');
    if (!collapse || !icon) return;
    collapse.addEventListener('show.bs.collapse', () => {
        icon.classList.remove('fa-chevron-right');
        icon.classList.add('fa-chevron-down');
    });
    collapse.addEventListener('hide.bs.collapse', () => {
        icon.classList.remove('fa-chevron-down');
        icon.classList.add('fa-chevron-right');
    });
}

// Load recent connection profiles
async function loadRecentProfiles() {
    try {
        const container = document.getElementById('profilesMenuContainer');
        if (!container) return;
        
        const response = await fetch('/api/history/profiles?limit=5');
        const profiles = await response.json();
        
        if (!profiles || profiles.length === 0) {
            container.innerHTML = '<div class="px-3 py-1 small text-muted"><i class="fas fa-inbox me-1"></i> Profil bulunamadı</div>';
            return;
        }
        
        container.innerHTML = profiles.map(profile => {
            const date = new Date(profile.lastUsedAt || profile.createdAt).toLocaleDateString('tr-TR');
            return `<div class="profile-menu-row d-flex align-items-center gap-2 px-3 py-1">
                <div class="min-w-0 flex-grow-1 overflow-hidden">
                    <div class="text-truncate small fw-medium">${escapeHtml(profile.name)}</div>
                    <div class="text-muted" style="font-size:.7rem">${date}</div>
                </div>
                <a href="/validation?profileId=${profile.id}" class="btn btn-xs btn-outline-info flex-shrink-0" title="Doğrulama">
                    <i class="fas fa-check-double"></i>
                </a>
                <a href="/wizard?profileId=${profile.id}" class="btn btn-xs btn-outline-primary flex-shrink-0" title="Wizard'da aç">
                    <i class="fas fa-magic"></i>
                </a>
            </div>`;
        }).join('');
    } catch (error) {
        console.error('Failed to load recent profiles:', error);
        const container = document.getElementById('profilesMenuContainer');
        if (container) {
            container.innerHTML = '<div class="px-3 py-1 small text-danger"><i class="fas fa-exclamation-circle me-1"></i> Yükleme hatası</div>';
        }
    }
}

// Load a specific profile
async function loadProfile(profileId, profileName) {
    if (!confirm(`"${profileName}" profilini yükleyip Wizard'a gitmek istiyor musunuz?`)) {
        return;
    }
    
    try {
        const response = await fetch(`/api/history/profiles/${profileId}`);
        const profile = await response.json();
        
        if (!profile) {
            alert('Profil yüklenemedi!');
            return;
        }
        
        // Store in sessionStorage for Wizard to pick up
        sessionStorage.setItem('loadedProfile', JSON.stringify(profile));
        
        // Redirect to wizard
        window.location.href = `/wizard?profileId=${profileId}`;
    } catch (error) {
        console.error('Failed to load profile:', error);
        alert('Profil yükleme hatası: ' + error.message);
    }
}

function updateIdleCard() {
    const card = document.querySelector('#noMigrationAlert .idle-state-card');
    if (!card) return;
    if (lastEngineRunning) {
        card.querySelector('h5').textContent = 'Migration bekleniyor';
        card.querySelector('p').textContent = 'Motor çalışıyor. Migration başladığında veriler burada görünecek.';
        const startBtn = card.querySelector('button');
        if (startBtn) startBtn.classList.add('d-none');
    } else {
        card.querySelector('h5').textContent = 'Migration motoru bekleniyor';
        card.querySelector('p').textContent = 'Henüz aktif bir migration yok. Başlamak için wizard\'ı kullanın veya motoru başlatın.';
        const startBtn = card.querySelector('button');
        if (startBtn) startBtn.classList.remove('d-none');
    }
}

function updateOverallProgress(summary) {
    summary = normalizeSummary(summary);
    if (!summary) {
        lastMigrationSummaryActive = false;
        updateIdleCard();
        document.getElementById('noMigrationAlert').classList.remove('d-none');
        document.getElementById('dashboardContent').classList.add('d-none');
        return;
    }

    document.getElementById('noMigrationAlert').classList.add('d-none');
    document.getElementById('dashboardContent').classList.remove('d-none');

    if (Array.isArray(summary.configuredTables) && summary.configuredTables.length) {
        _lastConfiguredTables = summary.configuredTables;
    }

    // Tablo sayıları (sunucu: partition satırı değil, tablo bazında)
    const displayTotalTables = Math.max(
        Number(summary.totalTables || 0),
        _lastConfiguredTables.length || 0
    );
    document.getElementById('totalTables').textContent = formatNumber(displayTotalTables);
    document.getElementById('completedTables').textContent = formatNumber(summary.completedTables);
    document.getElementById('runningTables').textContent = formatNumber(summary.runningTables);
    const pendingEl = document.getElementById('pendingTables');
    if (pendingEl) pendingEl.textContent = formatNumber(summary.pendingTables);
    document.getElementById('failedTables').textContent = formatNumber(summary.failedTables);

    // Yeniden dene / devam: motor idle ve bekleyen veya hatalı tablo varken
    const retryBanner = document.getElementById('migrationRetryBanner');
    const retryDetail = document.getElementById('migrationRetryBannerDetail');
    const retryTitle = document.getElementById('migrationRetryBannerTitle');
    const failedN = Number(summary.failedTables || 0);
    const pendingN = Number(summary.pendingTables || 0);
    const stLower = String(summary.status || '').toLowerCase();
    const showRetry = !lastEngineRunning
        && (failedN > 0 || pendingN > 0)
        && stLower !== 'done'
        && stLower !== 'completed';
    window._lastFailedTableCount = failedN;
    window._lastPendingTableCount = pendingN;
    if (retryBanner) {
        retryBanner.classList.toggle('d-none', !showRetry);
        if (retryDetail && showRetry) {
            const parts = [];
            if (failedN > 0) parts.push(`${formatNumber(failedN)} hatalı`);
            if (pendingN > 0) parts.push(`${formatNumber(pendingN)} bekleyen`);
            retryDetail.textContent = parts.join(' · ') + ' — satırdaki Devam / Yeniden dene ile tek tablo da çalıştırılabilir.';
        }
        if (retryTitle && showRetry) {
            retryTitle.textContent = failedN > 0 && pendingN > 0
                ? 'Bekleyen / hatalı tablo var.'
                : failedN > 0 ? 'Hatalı tablo aktarımı var.' : 'Bekleyen tablo var.';
        }
        const resumePendingBtn = document.getElementById('resumePendingBtn');
        resumePendingBtn?.classList.toggle('d-none', !(pendingN > 0));
    }
    const retryBtn = document.getElementById('retryEngineBtn');
    const idleRetryBtn = document.getElementById('idleRetryEngineBtn');
    if (!lastEngineRunning) {
        retryBtn?.classList.toggle('d-none', failedN <= 0);
        idleRetryBtn?.classList.toggle('d-none', failedN <= 0);
    } else {
        retryBtn?.classList.add('d-none');
        idleRetryBtn?.classList.add('d-none');
    }

    const rowLine = document.getElementById('summaryTableRowLine');
    if (rowLine) {
        const tgt = Number(summary.totalRowsExpected ?? summary.totalRowsSource ?? 0);
        const done = Number(summary.totalRowsProcessed ?? summary.totalRowsLoaded ?? 0);
        const remaining = Math.max(0, tgt - done);
        rowLine.textContent =
            `${formatNumber(summary.totalTables)} tablo · ` +
            `hedef ${formatNumber(tgt)} satır · ` +
            `işlenen ${formatNumber(done)} satır · ` +
            `kalan ${formatNumber(remaining)} satır`;
    }
    
    // Time information
    const startTimeEl = document.getElementById('migrationStartTime');
    if (startTimeEl && summary.startTime) {
        const startDate = new Date(summary.startTime);
        startTimeEl.textContent = startDate.toLocaleString('tr-TR');
    }
    
    const endTimeEl = document.getElementById('migrationEndTime');
    if (endTimeEl) {
        if (summary.estimatedCompletionTime) {
            const endDate = new Date(summary.estimatedCompletionTime);
            endTimeEl.textContent = endDate.toLocaleString('tr-TR');
        } else {
            endTimeEl.textContent = 'Hesaplanıyor…';
        }
    }
    
    // Row count comparison
    const sourceCount = summary.totalRowsSource || 0;
    const destCount = summary.totalRowsLoaded || 0;
    const difference = sourceCount - destCount;
    const percentMatch = sourceCount > 0 ? ((destCount / sourceCount) * 100).toFixed(2) : 0;
    
    document.getElementById('sourceRowCount').textContent = formatNumber(sourceCount);
    document.getElementById('destinationRowCount').textContent = formatNumber(destCount);
    document.getElementById('differenceRowCount').textContent = formatNumber(Math.abs(difference));
    
    // Match status badge
    const matchStatusEl = document.getElementById('matchStatus');
    if (matchStatusEl) {
        if (difference === 0 && sourceCount > 0) {
            matchStatusEl.textContent = '✓ Tam eşleşme (100%)';
            matchStatusEl.className = 'badge bg-success match-success';
        } else if (percentMatch >= 99) {
            matchStatusEl.textContent = `%${percentMatch} eşleşme`;
            matchStatusEl.className = 'badge bg-warning match-warning';
        } else if (percentMatch >= 90) {
            matchStatusEl.textContent = `%${percentMatch} eşleşme`;
            matchStatusEl.className = 'badge bg-warning match-warning';
        } else {
            matchStatusEl.textContent = `%${percentMatch} eşleşme`;
            matchStatusEl.className = 'badge bg-danger match-danger';
        }
    }

    const targetRows = Number(summary.totalRowsExpected ?? summary.totalRowsSource ?? 0);
    const doneRows = Number(summary.totalRowsProcessed ?? summary.totalRowsLoaded ?? 0);
    const percent = targetRows > 0
        ? Math.min(100, Math.max(0, Math.round((doneRows / targetRows) * 100)))
        : Math.round(summary.overallPercentComplete);
    document.getElementById('overallPercent').textContent = percent + '%';
    document.getElementById('overallProgress').style.width = percent + '%';
    document.getElementById('overallProgress').setAttribute('aria-valuenow', String(percent));

    const elapsedRaw = summary.elapsedTime;
    const elapsed = typeof elapsedRaw === 'string'
        ? formatDuration(elapsedRaw)
        : formatDuration(String(elapsedRaw ?? ''));

    const currentStatusEarly = String(summary.status || '').trim().toLowerCase();
    const isTerminalEarly = currentStatusEarly === 'done' || currentStatusEarly === 'completed'
        || currentStatusEarly === 'failed' || currentStatusEarly === 'stopped';
    if (_frozenElapsedRunId !== summary.runId) {
        _frozenElapsedText = null;
        _frozenElapsedRunId = summary.runId;
    }
    if (isTerminalEarly) {
        if (!_frozenElapsedText) _frozenElapsedText = elapsed;
        document.getElementById('elapsedTime').textContent = _frozenElapsedText;
    } else {
        _frozenElapsedText = null;
        document.getElementById('elapsedTime').textContent = elapsed;
    }

    const throughput = isTerminalEarly
        ? '0'
        : formatNumber(Math.round(summary.currentRowsPerSecond));
    document.getElementById('throughput').textContent = throughput + ' satır/sn';

    document.getElementById('migrationStatus').textContent = formatMigrationStatusLabel(summary.status);

    const eqEl = document.getElementById('rowEqualityBadge');
    if (eqEl) {
        const diff = Math.abs(sourceCount - destCount);
        if (sourceCount > 0 && diff === 0) {
            eqEl.className = 'badge rounded-pill bg-success-subtle text-success-emphasis border';
            eqEl.textContent = 'Kaynak=Hedef';
        } else if (destCount > sourceCount) {
            eqEl.className = 'badge rounded-pill bg-warning-subtle text-warning-emphasis border';
            eqEl.textContent = 'Hedef > Kaynak';
        } else {
            eqEl.className = 'badge rounded-pill bg-secondary-subtle text-secondary-emphasis border';
            eqEl.textContent = `Fark ${formatNumber(diff)} satır`;
        }
    }

    const lifecycleEl = document.getElementById('migrationLifecycle');
    if (lifecycleEl) {
        const st = String(summary.status || '').toLowerCase();
        const remainingRows = Math.max(0, targetRows - doneRows);
        const hasRemaining = targetRows > 0 && remainingRows > 0;
        const hasShortfallVsSource = sourceCount > 0 && destCount < sourceCount;
        const isTerminalDone = st === 'done' || st === 'completed';

        // Terminal state must win over row-difference heuristics.
        if (st === 'failed') {
            lifecycleEl.className = 'badge rounded-pill bg-danger-subtle text-danger-emphasis border';
            lifecycleEl.textContent = 'Hata ile durdu';
        } else if (isTerminalDone) {
            lifecycleEl.className = 'badge rounded-pill bg-success-subtle text-success-emphasis border';
            lifecycleEl.textContent = hasShortfallVsSource ? 'Tamamlandı (satır farkı var)' : 'Tamamlandı';
        } else if (hasRemaining || hasShortfallVsSource || st === 'running') {
            lifecycleEl.className = 'badge rounded-pill bg-primary-subtle text-primary-emphasis border';
            lifecycleEl.textContent = 'Aktarım sürüyor';
        } else {
            lifecycleEl.className = 'badge rounded-pill bg-secondary-subtle text-secondary-emphasis border';
            lifecycleEl.textContent = 'Beklemede';
        }
    }

    const currentStatus = String(summary.status || '').trim().toLowerCase();
    // Motor fiilen çalışmıyorsa checkpoint RUNNING kalsa bile UI'yi "aktif" sanma (donmuş görünüm)
    lastMigrationSummaryActive = currentStatus === 'running' && lastEngineRunning;
    const isTerminalDoneNow = currentStatus === 'done' || currentStatus === 'completed';

    // Tamamlanma banner'ı — ilk kez done/completed geçişinde göster
    const completeBanner = document.getElementById('migrationCompleteBanner');
    if (completeBanner) {
        if (isTerminalDoneNow && !_prevWasDone) {
            completeBanner.classList.remove('d-none');
            requestAnimationFrame(() => completeBanner.classList.add('show'));
        }
    }
    _prevWasDone = isTerminalDoneNow;

    // İlerleme çubuğu: tamamlandıysa animasyonu kaldır, yeşil yap
    const progressBar = document.getElementById('overallProgress');
    if (progressBar) {
        if (isTerminalDoneNow) {
            progressBar.classList.remove('progress-bar-striped', 'progress-bar-animated', 'bg-primary');
            progressBar.classList.add('bg-success');
        } else if (currentStatus === 'failed') {
            progressBar.classList.remove('progress-bar-striped', 'progress-bar-animated', 'bg-primary');
            progressBar.classList.add('bg-danger');
        } else {
            progressBar.classList.remove('bg-success', 'bg-danger');
            progressBar.classList.add('progress-bar-striped', 'progress-bar-animated');
        }
    }

    // Özet kart: aktif migration sırasında parlayan kenarlık
    const summaryCard = document.querySelector('.summary-card');
    if (summaryCard) {
        summaryCard.classList.toggle('migration-active', lastMigrationSummaryActive);
        summaryCard.classList.toggle('migration-done', isTerminalDoneNow);
        summaryCard.classList.toggle('migration-failed', currentStatus === 'failed');
    }

    // Faz etiketi
    const phaseLabel = document.getElementById('currentPhaseLabel');
    if (phaseLabel) {
        if (isTerminalDoneNow) {
            phaseLabel.textContent = 'Tamamlandı';
            phaseLabel.className = 'badge bg-success-subtle text-success-emphasis border';
            phaseLabel.classList.remove('d-none');
        } else if (currentStatus === 'failed') {
            phaseLabel.textContent = 'Hata';
            phaseLabel.className = 'badge bg-danger-subtle text-danger-emphasis border';
            phaseLabel.classList.remove('d-none');
        } else if (lastMigrationSummaryActive) {
            phaseLabel.textContent = 'Veri aktarımı';
            phaseLabel.className = 'badge bg-primary-subtle text-primary-emphasis border';
            phaseLabel.classList.remove('d-none');
        } else {
            phaseLabel.classList.add('d-none');
        }
    }

    // Partition/table grid: summary tick'te sadece hücre güncelle; full rebuild UpdatePartitions'ta
    if (lastPartitionListRaw.length) {
        updatePartitionParallelSummary(lastPartitionListRaw);
        renderTableProgress(lastPartitionListRaw);
        const tbody = document.getElementById('partitionGrid');
        if (tbody) {
            const normalized = lastPartitionListRaw.map(normalizePartition).filter(Boolean);
            for (const p of sortPartitions(normalized)) {
                const tr = partitionRowById.get(rowKeyForPartition(p));
                if (tr) fillPartitionRow(tr, p);
            }
        }
    }
}

function sortPartitions(list) {
    return [...list].sort((a, b) => {
        const t = (a.tableName || '').localeCompare(b.tableName || '');
        if (t !== 0) return t;
        const sa = String(a.partitionKey ?? '');
        const sb = String(b.partitionKey ?? '');
        const na = parseInt(sa, 10);
        const nb = parseInt(sb, 10);
        if (/^\d+$/.test(sa) && /^\d+$/.test(sb) && !isNaN(na) && !isNaN(nb)) return na - nb;
        return sa.localeCompare(sb);
    });
}

function formatDurationFromSeconds(totalSeconds) {
    const s = Math.floor(Math.max(0, totalSeconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
    return `${m}:${String(r).padStart(2, '0')}`;
}

function fillPartitionRow(tr, p) {
    const cells = tr.cells;
    cells[0].textContent = p.tableName || '';
    cells[1].textContent = String(p.partitionKey ?? '');
    const st = effectivePartitionUiStatus(p);
    cells[2].innerHTML = '';
    const badge = document.createElement('span');
    badge.className = `badge bg-${getStatusColor(st)}`;
    badge.textContent = formatMigrationStatusLabel(st);
    cells[2].appendChild(badge);

    cells[3].textContent = formatNumber(p.rowsProcessed || 0);
    cells[4].textContent = formatNumber(p.totalRows || 0);

    const pct = getPartitionPercent(p);
    cells[5].textContent = '';
    const wrap = document.createElement('div');
    wrap.className = 'd-flex align-items-center gap-2';
    const prog = document.createElement('div');
    prog.className = 'progress flex-grow-1 partition-progress';
    const bar = document.createElement('div');
    bar.className = 'progress-bar ' + (pct >= 100 ? 'bg-success' : 'bg-primary');
    bar.style.width = pct + '%';
    bar.setAttribute('aria-valuenow', String(pct));
    prog.appendChild(bar);
    wrap.appendChild(prog);
    const pctLab = document.createElement('small');
    pctLab.className = 'text-muted text-nowrap';
    pctLab.textContent = pct + '%';
    wrap.appendChild(pctLab);
    cells[5].appendChild(wrap);

    let dur = '–';
    if (p.startTime) {
        const start = new Date(p.startTime);
        const end = p.endTime ? new Date(p.endTime) : new Date();
        dur = formatDurationFromSeconds((end - start) / 1000);
    }
    cells[6].textContent = dur;

    const err = p.errorMessage || '';
    cells[7].textContent = err.length > 120 ? err.slice(0, 117) + '…' : err;
    cells[7].title = err;
}

function renderActiveThreads(runningPartitions) {
    const grid = document.getElementById('activeThreadsGrid');
    if (!grid) return;
    if (!runningPartitions || runningPartitions.length === 0) {
        grid.innerHTML = '';
        return;
    }
    const frag = document.createDocumentFragment();
    runningPartitions.forEach((p, idx) => {
        const pct = getPartitionPercent(p);
        const now = Date.now();
        let elapsedStr = '–';
        let rowsPerSec = 0;
        if (p.startTime) {
            const elapsedMs = now - new Date(p.startTime).getTime();
            elapsedStr = formatDurationFromSeconds(elapsedMs / 1000);
            const elapsedSec = elapsedMs / 1000;
            if (elapsedSec > 0) rowsPerSec = Math.round((p.rowsProcessed || 0) / elapsedSec);
        }
        const col = document.createElement('div');
        col.className = 'col-12 col-sm-6 col-xl-4';
        col.innerHTML =
            `<div class="active-thread-card card border-primary border-opacity-25">` +
            `<div class="card-body p-3">` +
            `<div class="d-flex align-items-center justify-content-between mb-2 gap-2">` +
            `<span class="badge bg-primary rounded-pill">T${idx + 1}</span>` +
            `<span class="fw-semibold text-truncate small flex-grow-1 ms-1" title="${escapeHtml(p.tableName)}">${escapeHtml(p.tableName)}</span>` +
            `<span class="badge bg-secondary rounded-pill text-nowrap">P${escapeHtml(String(p.partitionKey))}</span>` +
            `</div>` +
            `<div class="progress mb-2" style="height:6px">` +
            `<div class="progress-bar progress-bar-striped progress-bar-animated bg-primary" style="width:${pct}%"></div>` +
            `</div>` +
            `<div class="d-flex justify-content-between align-items-center small text-muted">` +
            `<span>${formatNumber(p.rowsProcessed)} / ${formatNumber(p.totalRows)} satır</span>` +
            `<span class="text-nowrap">${pct}%</span>` +
            `</div>` +
            `<div class="d-flex justify-content-between align-items-center small text-muted mt-1">` +
            `<span><i class="fas fa-tachometer-alt me-1"></i>${formatNumber(rowsPerSec)} s/sn</span>` +
            `<span><i class="fas fa-clock me-1"></i>${elapsedStr}</span>` +
            `</div>` +
            `</div></div>`;
        frag.appendChild(col);
    });
    grid.replaceChildren(frag);
}

function updatePartitionGrid(partitions) {
    const tbody = document.getElementById('partitionGrid');
    const countEl = document.getElementById('partitionCount');
    if (!tbody) return;

    const raw = Array.isArray(partitions) ? partitions : [];
    lastPartitionListRaw = raw;
    const normalized = raw.map(normalizePartition).filter(Boolean);

    if (normalized.length === 0) {
        lastPartitionListRaw = [];
        partitionRowById.clear();
        tableRowByName.clear();
        tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted py-3">Partition checkpoint yok</td></tr>';
        if (countEl) countEl.textContent = '0';
        updatePartitionParallelSummary([]);
        updatePartitionParallelList([]);
        renderTableProgress([]);
        const threadsPanel = document.getElementById('activeThreadsPanel');
        if (threadsPanel) threadsPanel.style.display = 'none';
        return;
    }

    // Aktif partition varsa thread panelini göster
    const running = normalized.filter(p => String(p.status || '').toLowerCase() === 'running');
    const activeCount = running.length;
    const threadsPanel = document.getElementById('activeThreadsPanel');
    const threadCountEl = document.getElementById('activeThreadCount');
    if (threadsPanel) threadsPanel.style.display = activeCount > 0 ? 'block' : 'none';
    if (threadCountEl) threadCountEl.textContent = String(activeCount);
    renderActiveThreads(running);

    if (countEl) countEl.textContent = String(normalized.length);
    updatePartitionParallelSummary(raw);
    updatePartitionParallelList(raw);
    renderTableProgress(raw);

    const sorted = sortPartitions(normalized);
    const keepKeys = new Set(sorted.map((p) => rowKeyForPartition(p)));

    for (const key of [...partitionRowById.keys()]) {
        if (!keepKeys.has(key)) partitionRowById.delete(key);
    }

    const frag = document.createDocumentFragment();
    for (const p of sorted) {
        const key = rowKeyForPartition(p);
        let tr = partitionRowById.get(key);
        if (!tr) {
            tr = document.createElement('tr');
            for (let i = 0; i < 8; i++) tr.appendChild(document.createElement('td'));
            partitionRowById.set(key, tr);
        }
        fillPartitionRow(tr, p);
        frag.appendChild(tr);
    }
    tbody.replaceChildren(frag);
}

/** Dedupe keys for log stream — hub polls re-send the same progress_events rows. */
const _seenLogEventKeys = new Set();

function progressEventKey(evt) {
    const ts = evt.timestamp ?? evt.Timestamp ?? '';
    const tableName = evt.tableName ?? evt.TableName ?? '';
    const phase = evt.phase ?? evt.Phase ?? '';
    const message = evt.message ?? evt.Message ?? '';
    const status = evt.status ?? evt.Status ?? '';
    const partitionKey = evt.partitionKey ?? evt.PartitionKey ?? '';
    const rows = evt.rowsProcessed ?? evt.RowsProcessed ?? '';
    return `${ts}|${tableName}|${partitionKey}|${phase}|${status}|${rows}|${message}`;
}

function appendToLogStream(events) {
    const logStream = document.getElementById('logStream');
    
    if (!events || events.length === 0) {
        return;
    }

    const firstLoad = logStream.children.length === 1 && logStream.children[0].classList.contains('text-muted');
    if (firstLoad) {
        logStream.innerHTML = '';
        _seenLogEventKeys.clear();
    }

    // API returns newest-first; keep that order when prepending
    const fresh = [];
    for (const evt of events) {
        const key = progressEventKey(evt);
        if (_seenLogEventKeys.has(key)) continue;
        _seenLogEventKeys.add(key);
        fresh.push(evt);
    }
    if (!fresh.length) return;

    // Newest first in stream: insert in reverse so first of `fresh` ends on top
    for (let i = fresh.length - 1; i >= 0; i--) {
        const evt = fresh[i];
        const logEntry = document.createElement('div');
        logEntry.className = 'log-entry';

        const warning = evt.warning ?? evt.Warning;
        const status = evt.status ?? evt.Status;
        const ts = evt.timestamp ?? evt.Timestamp;
        const tableName = evt.tableName ?? evt.TableName;
        const phase = evt.phase ?? evt.Phase;
        const message = evt.message ?? evt.Message ?? '';

        let levelClass = 'log-info';
        if (warning) levelClass = 'log-warning';
        if (status === 'Failed' || status === 'FAILED') levelClass = 'log-error';

        logEntry.classList.add(levelClass);
        logEntry.dataset.level = levelClass.replace('log-', '');
        logEntry.dataset.eventKey = progressEventKey(evt);

        const timestamp = ts ? new Date(ts).toLocaleTimeString() : '';
        const table = tableName ? `[${tableName}] ` : '';
        const phaseStr = phase ? `[${phase}] ` : '';
        
        logEntry.innerHTML = `
            <span class="log-time">${timestamp}</span>
            <span class="log-message">${phaseStr}${table}${escapeHtml(message)}</span>
            ${warning ? `<div class="log-warning-detail">${escapeHtml(warning)}</div>` : ''}
        `;
        
        if (shouldShowLog(logEntry.dataset.level)) {
            logEntry.style.display = 'block';
        } else {
            logEntry.style.display = 'none';
        }
        
        logStream.insertBefore(logEntry, logStream.firstChild);
    }

    while (logStream.children.length > 100) {
        const last = logStream.lastChild;
        if (last?.dataset?.eventKey) _seenLogEventKeys.delete(last.dataset.eventKey);
        logStream.removeChild(last);
    }
    while (_seenLogEventKeys.size > 200) {
        _seenLogEventKeys.delete(_seenLogEventKeys.values().next().value);
    }

    if (autoScroll) {
        logStream.scrollTop = 0;
    }
}

function shouldShowLog(level) {
    if (currentFilter === 'all') return true;
    return level === currentFilter;
}

function getStatusColor(status) {
    if (!status || typeof status !== 'string') {
        return 'secondary';
    }
    
    switch (status) {
        case 'Done': 
        case 'DONE': 
            return 'success';
        case 'Running': 
        case 'RUNNING': 
            return 'primary';
        case 'Failed': 
        case 'FAILED': 
            return 'danger';
        case 'Pending': 
        case 'PENDING': 
            return 'secondary';
        case 'Skipped':
        case 'SKIPPED':
            return 'warning';
        case 'Interrupted':
        case 'INTERRUPTED':
            return 'warning';
        default: 
            return 'secondary';
    }
}

function formatNumber(num) {
    return new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 0 }).format(Number(num) || 0);
}

function formatDuration(durationString) {
    const match = durationString.match(/(\d+):(\d+):(\d+)/);
    if (match) {
        const [, hours, minutes, seconds] = match;
        return `${hours.padStart(2, '0')}:${minutes.padStart(2, '0')}:${seconds.padStart(2, '0')}`;
    }
    return durationString;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

document.querySelectorAll('[data-filter]').forEach(btn => {
    btn.addEventListener('click', (e) => {
        currentFilter = e.target.dataset.filter;
        
        document.querySelectorAll('[data-filter]').forEach(b => b.classList.remove('active'));
        e.target.classList.add('active');
        
        document.querySelectorAll('.log-entry').forEach(entry => {
            if (shouldShowLog(entry.dataset.level)) {
                entry.style.display = 'block';
            } else {
                entry.style.display = 'none';
            }
        });
    });
});

document.getElementById('autoScroll').addEventListener('change', (e) => {
    autoScroll = e.target.checked;
});

document.getElementById('exportReport').addEventListener('click', async () => {
    const summary = await connection.invoke('GetCurrentSummary');
    const tables = await connection.invoke('GetTableStatuses');
    const partitions = await connection.invoke('GetPartitionStatuses');

    const report = {
        exportTime: new Date().toISOString(),
        summary: summary,
        tables: tables,
        partitions: partitions
    };
    
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `migration-report-${new Date().toISOString().split('T')[0]}.json`;
    a.click();
    URL.revokeObjectURL(url);
});

// Engine Control Functions
function engineStartButtonHtml() {
    return '<i class="fas fa-play"></i><span class="d-none d-md-inline ms-1">Başlat</span>';
}

function engineStopButtonHtml() {
    return '<i class="fas fa-stop"></i><span class="d-none d-md-inline ms-1">Durdur</span>';
}

function engineRetryButtonHtml() {
    return '<i class="fas fa-redo"></i><span class="d-none d-md-inline ms-1">Yeniden dene</span>';
}

/** Per-table continue: Pending/Interrupted → continue-tables; Failed → retry-failed */
async function continueTableEngine(tableName, statusHint) {
    const name = String(tableName || '').trim();
    if (!name) return;
    const failed = String(statusHint || '').toLowerCase() === 'failed';
    if (failed) {
        await retryMigrationEngine([name]);
        return;
    }
    await launchScopedEngine({
        endpoint: '/api/engine/continue-tables',
        tables: [name],
        confirmTitle: `${name} devam etsin mi?`,
        confirmHtml: `Yalnızca <code>${escapeHtml(name)}</code> aktarılacak (Pending/Interrupted partition’lar).`,
        actionLabel: 'Devam'
    });
}

/** Continue all currently Pending tables from the table grid */
async function continuePendingTables() {
    const names = window._lastPendingTableNames || [];
    if (!names.length) {
        showEngineAlert('warning', 'Bekleyen tablo bulunamadı', { group: 'engine-retry', autoHideMs: 8000 });
        return;
    }
    await launchScopedEngine({
        endpoint: '/api/engine/continue-tables',
        tables: names,
        confirmTitle: 'Bekleyen tablolara devam?',
        confirmHtml: `${names.length} tablo: <code>${names.map(escapeHtml).join(', ')}</code>`,
        actionLabel: 'Devam'
    });
}

async function launchScopedEngine({ endpoint, tables, confirmTitle, confirmHtml, actionLabel }) {
    const btn = document.getElementById('retryEngineBtn');
    const statusBadge = document.getElementById('engineStatus');

    if (typeof Swal !== 'undefined') {
        const r = await Swal.fire({
            icon: 'question',
            title: confirmTitle,
            html: `${confirmHtml}<br><small class="text-muted">Motor <code>${escapeHtml(endpoint.replace('/api/engine/', '--'))}</code> ile başlar.</small>`,
            showCancelButton: true,
            confirmButtonText: actionLabel || 'Başlat',
            cancelButtonText: 'İptal',
            background: '#212529',
            color: '#f8f9fa',
            confirmButtonColor: '#0d6efd',
            cancelButtonColor: '#6c757d',
        });
        if (!r.isConfirmed) return;
    }

    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span><span class="d-none d-md-inline ms-1">Hazırlanıyor…</span>';
    }
    if (statusBadge) {
        statusBadge.className = 'badge rounded-pill bg-warning text-dark';
        statusBadge.textContent = 'Continue…';
    }
    setEngineStatusDetail(`${tables.length} tablo…`, false);

    try {
        const st = await fetch('/api/engine/status').then((x) => x.json());
        if (st.status === 'running') {
            showEngineAlert('info', 'Çalışan motor durduruluyor…', { group: 'engine-retry' });
            await fetch('/api/engine/stop', { method: 'POST' });
            await new Promise((resolve) => setTimeout(resolve, 800));
        }

        // Prefer existing exe; build only if needed (avoids UI hang)
        showEngineAlert('info', 'Migration Engine hazırlanıyor…', { group: 'engine-retry' });
        const buildResponse = await fetch('/api/engine/build', { method: 'POST' });
        const buildResult = await buildResponse.json();
        if (!buildResult.success) {
            throw new Error('Build başarısız: ' + (buildResult.error || ''));
        }

        const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ tables })
        });
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || data.message || 'Başlatma başarısız');
        }

        if (statusBadge) {
            statusBadge.className = 'badge rounded-pill bg-success';
            statusBadge.textContent = 'Çalışıyor';
        }
        setEngineStatusDetail(data.pid != null ? `PID ${data.pid}` : 'running', false);
        document.getElementById('startEngineBtn')?.classList.add('d-none');
        document.getElementById('stopEngineBtn')?.classList.remove('d-none');
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = engineRetryButtonHtml();
            btn.classList.add('d-none');
        }
        document.getElementById('idleRetryEngineBtn')?.classList.add('d-none');
        document.getElementById('migrationRetryBanner')?.classList.add('d-none');
        document.getElementById('migrationFatalBanner')?.classList.add('d-none');

        showEngineAlert('success', `✅ Devam başladı (${tables.join(', ')}) PID: ${data.pid}`, {
            group: 'engine-retry',
            autoHideMs: 120_000
        });
        lastEngineRunning = true;
        updateIdleCard();
        _frozenElapsedText = null;
        _prevWasDone = false;
    } catch (error) {
        console.error('Continue failed:', error);
        showEngineAlert('danger', `❌ Devam başarısız: ${error.message}`, { group: 'engine-retry' });
        if (statusBadge) {
            statusBadge.className = 'badge rounded-pill bg-danger';
            statusBadge.textContent = 'Hata';
        }
        setEngineStatusDetail(error.message || '', true);
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = engineRetryButtonHtml();
        }
    }
}

async function retryMigrationEngine(tableNames) {
    const btn = document.getElementById('retryEngineBtn');
    const statusBadge = document.getElementById('engineStatus');
    const tables = Array.isArray(tableNames)
        ? tableNames.filter((t) => t && String(t).trim())
        : [];
    const scopeHtml = tables.length
        ? `Yalnızca <code>${tables.map((t) => escapeHtml(String(t))).join(', ')}</code> yeniden denenecek.`
        : 'Yalnızca <strong>hata alan tablolar</strong> yeniden denenecek; tamamlanan / hatasız bekleyen tablolara dokunulmaz.';

    if (typeof Swal !== 'undefined') {
        const r = await Swal.fire({
            icon: 'question',
            title: 'Hatalı tablolar yeniden denensin mi?',
            html: `${scopeHtml}<br><small class="text-muted">Motor <code>--retry-failed</code> ile başlar. Paralel ayarlar güncel appsettings’ten okunur.</small>`,
            showCancelButton: true,
            confirmButtonText: 'Yeniden dene',
            cancelButtonText: 'İptal',
            background: '#212529',
            color: '#f8f9fa',
            confirmButtonColor: '#ffc107',
            cancelButtonColor: '#6c757d',
        });
        if (!r.isConfirmed) return;
    }

    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span><span class="d-none d-md-inline ms-1">Hazırlanıyor…</span>';
    }
    if (statusBadge) {
        statusBadge.className = 'badge rounded-pill bg-warning text-dark';
        statusBadge.textContent = 'Retry…';
    }
    setEngineStatusDetail(tables.length ? `--retry-failed (${tables.length} tablo)` : '--retry-failed…', false);

    try {
        const st = await fetch('/api/engine/status').then((x) => x.json());
        if (st.status === 'running') {
            showEngineAlert('info', 'Çalışan motor durduruluyor…', { group: 'engine-retry' });
            await fetch('/api/engine/stop', { method: 'POST' });
            await new Promise((resolve) => setTimeout(resolve, 800));
        }

        showEngineAlert('info', 'Migration Engine hazırlanıyor…', { group: 'engine-retry' });
        const buildResponse = await fetch('/api/engine/build', { method: 'POST' });
        const buildResult = await buildResponse.json();
        if (!buildResult.success) {
            throw new Error('Build başarısız: ' + (buildResult.error || ''));
        }

        if (btn) btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span><span class="d-none d-md-inline ms-1">Başlatılıyor…</span>';
        const response = await fetch('/api/engine/retry-failed', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(tables.length ? { tables } : {})
        });
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || data.message || 'Retry-failed başarısız');
        }

        if (statusBadge) {
            statusBadge.className = 'badge rounded-pill bg-success';
            statusBadge.textContent = 'Çalışıyor';
        }
        setEngineStatusDetail(data.pid != null ? `PID ${data.pid} (retry-failed)` : 'retry-failed', false);

        document.getElementById('startEngineBtn')?.classList.add('d-none');
        document.getElementById('stopEngineBtn')?.classList.remove('d-none');
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = engineRetryButtonHtml();
            btn.classList.add('d-none');
        }
        document.getElementById('idleRetryEngineBtn')?.classList.add('d-none');
        document.getElementById('migrationRetryBanner')?.classList.add('d-none');

        const scopeMsg = tables.length ? ` (${tables.join(', ')})` : '';
        showEngineAlert('success', `✅ Hatalı tablo yeniden denemesi başladı${scopeMsg} (PID: ${data.pid})`, {
            group: 'engine-retry',
            autoHideMs: 120_000
        });
        lastEngineRunning = true;
        updateIdleCard();
        _frozenElapsedText = null;
        _prevWasDone = false;
    } catch (error) {
        console.error('Yeniden deneme başarısız:', error);
        showEngineAlert('danger', `❌ Yeniden deneme başarısız: ${error.message}`, { group: 'engine-retry' });
        if (statusBadge) {
            statusBadge.className = 'badge rounded-pill bg-danger';
            statusBadge.textContent = 'Hata';
        }
        setEngineStatusDetail('', false);
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = engineRetryButtonHtml();
        }
    }
}

async function startMigrationEngine() {
    const btn = document.getElementById('startEngineBtn');
    const statusBadge = document.getElementById('engineStatus');
    
    // Disable button
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span><span class="d-none d-md-inline ms-1">Başlatılıyor…</span>';
    statusBadge.className = 'badge rounded-pill bg-warning text-dark';
    statusBadge.textContent = 'Başlatılıyor';
    setEngineStatusDetail('Build ve başlatma…', false);
    
    try {
        // Ensure engine binary exists (build if source present; skip if published exe only)
        showEngineAlert('info', 'Migration Engine hazırlanıyor…', { group: 'engine-launch' });
        const buildResponse = await fetch('/api/engine/build', {
            method: 'POST'
        });
        const buildResult = await buildResponse.json();
        
        if (!buildResult.success) {
            throw new Error('Build başarısız: ' + buildResult.error);
        }
        
        const prepMsg = (buildResult.output || '').includes('Using existing executable')
            ? 'Hazır motor bulundu. Başlatılıyor…'
            : 'Build tamam. Motor başlatılıyor…';
        showEngineAlert('success', prepMsg, { group: 'engine-launch' });
        
        // Start engine
        const response = await fetch('/api/engine/start', {
            method: 'POST'
        });
        const data = await response.json();
        
        if (data.success) {
            statusBadge.className = 'badge rounded-pill bg-success';
            statusBadge.textContent = 'Çalışıyor';
            setEngineStatusDetail(data.pid != null ? `PID ${data.pid}` : '', false);
            
            btn.classList.add('d-none');
            document.getElementById('stopEngineBtn').classList.remove('d-none');
            
            showEngineAlert('success', `✅ Migration Engine çalışıyor (PID: ${data.pid})`, {
                group: 'engine-launch',
                autoHideMs: 120_000
            });

            lastEngineRunning = true;
            updateIdleCard();
        } else {
            throw new Error(data.error || 'Motor başlatılamadı');
        }
    } catch (error) {
        console.error('Motor başlatılamadı:', error);
        showEngineAlert('danger', `❌ Motor başlatılamadı: ${error.message}`, { group: 'engine-launch' });
        
        statusBadge.className = 'badge rounded-pill bg-danger';
        statusBadge.textContent = 'Hata';
        setEngineStatusDetail('', false);
        
        btn.disabled = false;
        btn.innerHTML = engineStartButtonHtml();
    }
}

async function stopMigrationEngine() {
    const btn = document.getElementById('stopEngineBtn');
    const statusBadge = document.getElementById('engineStatus');
    
    if (typeof Swal !== 'undefined') {
        const r = await Swal.fire({
            icon: 'warning',
            title: 'Migration Engine durdurulsun mu?',
            text: 'Aktif migration duraklar.',
            showCancelButton: true,
            confirmButtonText: 'Durdur',
            cancelButtonText: 'İptal',
            background: '#212529',
            color: '#f8f9fa',
            confirmButtonColor: '#dc3545',
            cancelButtonColor: '#6c757d',
        });
        if (!r.isConfirmed) {
            return;
        }
    } else if (!confirm('Migration Engine\'i durdurmak istediğinize emin misiniz? Aktif migration duraklar.')) {
        return;
    }
    
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span><span class="d-none d-md-inline ms-1">Durduruluyor…</span>';
    statusBadge.className = 'badge rounded-pill bg-warning text-dark';
    statusBadge.textContent = 'Durduruluyor';
    setEngineStatusDetail('', false);
    
    try {
        const response = await fetch('/api/engine/stop', {
            method: 'POST'
        });
        const data = await response.json();
        
        if (data.success) {
            statusBadge.className = 'badge rounded-pill bg-secondary';
            statusBadge.textContent = 'Durduruldu';
            setEngineStatusDetail('', false);
            
            btn.classList.add('d-none');
            document.getElementById('startEngineBtn').classList.remove('d-none');
            document.getElementById('startEngineBtn').disabled = false;
            document.getElementById('startEngineBtn').innerHTML = engineStartButtonHtml();
            
            showEngineAlert('warning', '⚠️ Migration Engine durduruldu', { group: 'engine-stop', autoHideMs: 90_000 });
        } else {
            throw new Error(data.error || 'Motor durdurulamadı');
        }
    } catch (error) {
        console.error('Motor durdurulamadı:', error);
        showEngineAlert('danger', `❌ Motor durdurulamadı: ${error.message}`, { group: 'engine-stop' });
        
        btn.disabled = false;
        btn.innerHTML = engineStopButtonHtml();
    }
}

async function checkEngineStatus() {
    try {
        const statusBadge = document.getElementById('engineStatus');
        const startBtn = document.getElementById('startEngineBtn');
        const stopBtn = document.getElementById('stopEngineBtn');
        
        // Check if elements exist
        if (!statusBadge || !startBtn || !stopBtn) {
            console.warn('Motor kontrol öğeleri sayfada yok');
            return;
        }
        
        const response = await fetch('/api/engine/status');
        const data = await response.json();
        
        const retryBtn = document.getElementById('retryEngineBtn');

        if (data.status === 'running') {
            statusBadge.className = 'badge rounded-pill bg-success';
            statusBadge.textContent = 'Çalışıyor';

            const parts = [];
            if (data.pid != null) parts.push(`PID ${data.pid}`);
            if (data.uptime !== null && data.uptime !== undefined) {
                const uptimeMin = Math.floor(data.uptime / 60);
                const uptimeSec = Math.floor(data.uptime % 60);
                parts.push(uptimeMin > 0 ? `${uptimeMin} dk ${uptimeSec} sn` : `${uptimeSec} sn`);
            }
            setEngineStatusDetail(parts.join(' · '), false);
            
            startBtn.classList.add('d-none');
            stopBtn.classList.remove('d-none');
            retryBtn?.classList.add('d-none');
            document.getElementById('idleRetryEngineBtn')?.classList.add('d-none');
            document.getElementById('migrationRetryBanner')?.classList.add('d-none');

            lastEngineRunning = true;
            updateIdleCard();
        } else if (data.status === 'stopped') {
            statusBadge.className = 'badge rounded-pill bg-secondary';
            statusBadge.textContent = 'Durduruldu';

            lastEngineRunning = false;
            updateIdleCard();
            startBtn.classList.remove('d-none');
            stopBtn.classList.add('d-none');
            const hasFailed = Number(window._lastFailedTableCount || 0) > 0;
            retryBtn?.classList.toggle('d-none', !hasFailed);
            document.getElementById('idleRetryEngineBtn')?.classList.toggle('d-none', !hasFailed);

            const fatalBanner = document.getElementById('migrationFatalBanner');
            const fatalDetail = document.getElementById('migrationFatalBannerDetail');
            const fatalText = data.lastFatalError || data.lastExitMessage || null;
            const showFatal = !!(data.lastFatalError || (data.lastExitCode != null && data.lastExitCode !== 0));
            if (fatalBanner) {
                fatalBanner.classList.toggle('d-none', !showFatal);
                if (fatalDetail && showFatal) {
                    fatalDetail.textContent = fatalText
                        || `Exit code: ${data.lastExitCode}`;
                }
            }
            if (showFatal) {
                setEngineStatusDetail(
                    data.lastExitCode != null
                        ? `exit ${data.lastExitCode}` + (data.lastFatalError ? ` · ${String(data.lastFatalError).slice(0, 80)}` : '')
                        : String(data.lastFatalError || '').slice(0, 100),
                    true
                );
            }
            
            if (!data.hasConfiguration) {
                setEngineStatusDetail('appsettings yok — Wizard’ı açın', true);
                if (!engineConfigAlertShown) {
                    engineConfigAlertShown = true;
                    showEngineAlert('warning', '⚠️ Yapılandırma bulunamadı. Önce wizard ile ayar oluşturun.', {
                        group: 'engine-config',
                        autoHideMs: 60_000
                    });
                }
            } else {
                setEngineStatusDetail('Başlatılmaya hazır', false);
            }
        } else {
            statusBadge.className = 'badge rounded-pill bg-danger';
            statusBadge.textContent = 'Hata';
            setEngineStatusDetail('', false);
        }
    } catch (error) {
        console.error('Motor durumu alınamadı:', error);
        
        // Update badge to show error
        const statusBadge = document.getElementById('engineStatus');
        if (statusBadge) {
            statusBadge.className = 'badge rounded-pill bg-danger';
            statusBadge.textContent = 'Hata';
            setEngineStatusDetail('Durum sorgusu başarısız', true);
        }
    }
}

function startEngineStatusMonitoring() {
    // Check engine status every 5 seconds
    engineStatusCheckInterval = setInterval(checkEngineStatus, 5000);
}

const __engineToastHideTimers = new Map();
const __engineToastMaxStack = 8;

function ensureEngineToastStack() {
    let stack = document.getElementById('engineToastStack');
    if (!stack) {
        stack = document.createElement('div');
        stack.id = 'engineToastStack';
        stack.className = 'engine-toast-stack';
        stack.setAttribute('aria-live', 'polite');
        document.body.appendChild(stack);
    }
    return stack;
}

function __clearToastTimer(el) {
    const t = __engineToastHideTimers.get(el);
    if (t) {
        clearTimeout(t);
        __engineToastHideTimers.delete(el);
    }
}

function __scheduleToastHide(el, ms) {
    __clearToastTimer(el);
    if (!ms || ms <= 0) return;
    const id = setTimeout(() => {
        __engineToastHideTimers.delete(el);
        if (el.isConnected) el.remove();
    }, ms);
    __engineToastHideTimers.set(el, id);
}

/**
 * @param {string} type Bootstrap alert: info | success | warning | danger
 * @param {string} message Düz metin
 * @param {{ group?: string, autoHideMs?: number | null, pinnable?: boolean }} [options]
 *        group: aynı gruptaki önceki bildirim kaldırılır (ör. engine-launch zinciri)
 *        autoHideMs: 0 veya null = yalnızca × veya sabitleme kuralı; >0 ms sonra kapanır. Sabitle (pin) otomatik kapanmayı iptal eder.
 */
function showEngineAlert(type, message, options = {}) {
    const group = options.group ?? null;
    const pinnable = options.pinnable !== false;
    /** Varsayılan: kendiliğinden kapanmasın; istersek çağrıda autoHideMs verilebilir */
    const rawHide = options.autoHideMs;
    const autoHideMs =
        rawHide === undefined ? 0 : rawHide === null ? 0 : Number(rawHide);

    const stack = ensureEngineToastStack();
    if (group) {
        stack.querySelectorAll(`[data-toast-group="${group}"]`).forEach((n) => {
            __clearToastTimer(n);
            n.remove();
        });
    }
    while (stack.childElementCount >= __engineToastMaxStack) {
        const first = stack.firstElementChild;
        if (first) {
            __clearToastTimer(first);
            first.remove();
        }
    }

    const el = document.createElement('div');
    el.className = `toast-engine alert alert-${type} shadow-sm mb-0`;
    el.setAttribute('role', 'alert');
    if (group) el.dataset.toastGroup = group;

    const row = document.createElement('div');
    row.className = 'd-flex align-items-start gap-2';

    const body = document.createElement('div');
    body.className = 'flex-grow-1 small';
    body.textContent = message;

    const actions = document.createElement('div');
    actions.className = 'd-flex align-items-center gap-1 flex-shrink-0';

    if (pinnable) {
        const pin = document.createElement('button');
        pin.type = 'button';
        pin.className = 'btn btn-link btn-sm p-1 engine-toast-pin text-secondary';
        pin.title =
            autoHideMs > 0
                ? 'Sabitle — otomatik kapanmayı durdurur'
                : 'Sabitle — bildirimi vurgula (otomatik kapanma yok)';
        pin.setAttribute('aria-pressed', 'false');
        pin.innerHTML = '<i class="fas fa-thumbtack" aria-hidden="true"></i>';
        pin.addEventListener('click', (ev) => {
            ev.preventDefault();
            const pinned = !el.classList.contains('engine-toast-pinned');
            if (pinned) {
                el.classList.add('engine-toast-pinned');
                pin.classList.add('active');
                pin.setAttribute('aria-pressed', 'true');
                pin.title = 'Sabitlemeyi kaldır — otomatik kapanma yeniden (varsa) uygulanır';
                __clearToastTimer(el);
            } else {
                el.classList.remove('engine-toast-pinned');
                pin.classList.remove('active');
                pin.setAttribute('aria-pressed', 'false');
                pin.title = 'Sabitle — otomatik kapanmayı durdurur (açıksa)';
                const ms = Number(el.dataset.autoHideMs) || 0;
                if (ms > 0) __scheduleToastHide(el, ms);
            }
        });
        actions.appendChild(pin);
    }

    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'btn-close';
    close.title = 'Kapat';
    close.addEventListener('click', () => {
        __clearToastTimer(el);
        el.remove();
    });

    actions.appendChild(close);
    row.appendChild(body);
    row.appendChild(actions);
    el.appendChild(row);
    el.dataset.autoHideMs = String(autoHideMs);
    stack.appendChild(el);

    if (autoHideMs > 0) __scheduleToastHide(el, autoHideMs);
}
