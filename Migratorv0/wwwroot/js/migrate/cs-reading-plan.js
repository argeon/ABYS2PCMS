(function () {
    const API = '/api/migrate/cs-reading-plan';

    function buildOracleConnectionString() {
        const host = document.getElementById('oracleHost').value.trim();
        const port = document.getElementById('oraclePort').value.trim() || '1521';
        const service = document.getElementById('oracleService').value.trim();
        const user = document.getElementById('oracleUser').value.trim();
        const password = document.getElementById('oraclePassword').value;
        return `User Id=${user};Password=${password};Data Source=${host}:${port}/${service};`;
    }

    function buildMssqlConnectionString() {
        const server = document.getElementById('mssqlServer').value.trim();
        const database = document.getElementById('mssqlDatabase').value.trim();
        const user = document.getElementById('mssqlUser').value.trim();
        const password = document.getElementById('mssqlPassword').value;
        return `Server=${server};Database=${database};User Id=${user};Password=${password};TrustServerCertificate=True;`;
    }

    function collectDefinition() {
        return {
            oracleConnectionString: buildOracleConnectionString(),
            oracleSchema: document.getElementById('oracleSchema').value.trim() || 'SMS',
            mssqlConnectionString: buildMssqlConnectionString(),
            targetTableName: 'CS_READING_PLAN',
            degreeOfParallelism: parseInt(document.getElementById('degreeOfParallelism').value, 10) || 4,
            batchSize: parseInt(document.getElementById('batchSize').value, 10) || 50000,
            fetchSizeMB: parseInt(document.getElementById('fetchSizeMB').value, 10) || 50,
            migratePrimaryKeys: document.getElementById('migratePrimaryKeys').checked,
            migrateForeignKeys: document.getElementById('migrateForeignKeys').checked,
            migrateIndexes: document.getElementById('migrateIndexes').checked,
            migrateUniqueConstraints: false,
            migrateCheckConstraints: false,
            hardReset: document.getElementById('hardReset').checked
        };
    }

    function setStatus(text, isError) {
        const el = document.getElementById('statusMessage');
        el.textContent = text;
        el.className = 'small ' + (isError ? 'text-danger' : 'text-success');
    }

    function parseConnectionString(conn, keys) {
        const result = {};
        if (!conn) return result;
        conn.split(';').forEach(part => {
            const idx = part.indexOf('=');
            if (idx <= 0) return;
            const key = part.substring(0, idx).trim();
            const val = part.substring(idx + 1).trim();
            if (keys.some(k => k.toLowerCase() === key.toLowerCase()))
                result[key] = val;
        });
        return result;
    }

    function applyDefinition(def) {
        if (!def) return;

        const ora = parseConnectionString(def.oracleConnectionString, ['Data Source', 'User Id', 'Password']);
        if (ora['Data Source']) {
            const ds = ora['Data Source'];
            const slash = ds.indexOf('/');
            const colon = ds.lastIndexOf(':', slash > 0 ? slash : ds.length);
            if (colon > 0) {
                document.getElementById('oracleHost').value = ds.substring(0, colon);
                document.getElementById('oraclePort').value = ds.substring(colon + 1, slash > 0 ? slash : ds.length);
            }
            if (slash > 0)
                document.getElementById('oracleService').value = ds.substring(slash + 1);
        }
        if (ora['User Id']) document.getElementById('oracleUser').value = ora['User Id'];
        if (ora.Password) document.getElementById('oraclePassword').value = ora.Password;
        if (def.oracleSchema) document.getElementById('oracleSchema').value = def.oracleSchema;

        const ms = parseConnectionString(def.mssqlConnectionString, ['Server', 'Database', 'User Id', 'Password']);
        if (ms.Server) document.getElementById('mssqlServer').value = ms.Server;
        if (ms.Database) document.getElementById('mssqlDatabase').value = ms.Database;
        if (ms['User Id']) document.getElementById('mssqlUser').value = ms['User Id'];
        if (ms.Password) document.getElementById('mssqlPassword').value = ms.Password;

        if (def.degreeOfParallelism) document.getElementById('degreeOfParallelism').value = def.degreeOfParallelism;
        if (def.batchSize) document.getElementById('batchSize').value = def.batchSize;
        if (def.fetchSizeMB) document.getElementById('fetchSizeMB').value = def.fetchSizeMB;
        document.getElementById('migratePrimaryKeys').checked = def.migratePrimaryKeys !== false;
        document.getElementById('migrateForeignKeys').checked = !!def.migrateForeignKeys;
        document.getElementById('migrateIndexes').checked = !!def.migrateIndexes;
        document.getElementById('hardReset').checked = def.hardReset !== false;
    }

    async function loadDefinition() {
        try {
            const res = await fetch(API + '/definition');
            const data = await res.json();
            if (data.success && data.definition)
                applyDefinition(data.definition);
        } catch (e) {
            console.warn('Definition load failed', e);
        }
    }

    function renderPreview(preview) {
        const summary = document.getElementById('previewSummary');
        const targetInfo = preview.targetRowCount != null
            ? ` | Hedef: ${preview.targetRowCount.toLocaleString()} satır`
            : ' | Hedef tablo henüz yok veya erişilemedi';
        summary.innerHTML = `
            <strong>${preview.sourceTable}</strong> → <strong>${preview.targetTable}</strong><br/>
            Kaynak satır: <strong>${(preview.rowCount ?? 0).toLocaleString()}</strong>${targetInfo}<br/>
            Kolon: <strong>${preview.foundColumnCount ?? cols.length}</strong> / ${preview.expectedColumnCount ?? 17}
            <span class="text-info ms-2">${preview.locationMigration.note}</span>
        `;

        const cols = preview.columns || [];
        if (preview.missingColumns && preview.missingColumns.length > 0) {
            summary.innerHTML += `<br/><span class="text-danger">Eksik kolonlar: ${preview.missingColumns.join(', ')}</span>`;
        } else if (preview.locationFound && preview.locationIsSpatial) {
            summary.innerHTML += '<br/><span class="text-success">LOCATION (SDO_GEOMETRY) → geography WGS84 hazır.</span>';
        }

        const locationCol = cols.find(c => c.isWgs84Location || (c.columnName || '').toUpperCase() === 'LOCATION');
        if (!locationCol) {
            summary.innerHTML += '<br/><span class="text-warning">Uyarı: LOCATION kolonu Oracle şemasında bulunamadı.</span>';
        } else if (!locationCol.isSpatial) {
            summary.innerHTML += '<br/><span class="text-warning">Uyarı: LOCATION spatial olarak işaretlenmedi.</span>';
        }

        const tbody = document.getElementById('previewColumns');
        if (!cols.length) {
            tbody.innerHTML = '<tr><td colspan="4" class="text-muted p-3">Kolon bulunamadı</td></tr>';
            return;
        }

        tbody.innerHTML = cols.map(c => {
            const rowClass = c.isWgs84Location ? 'table-info' : '';
            return `<tr class="${rowClass}">
                <td><code>${c.columnName}</code></td>
                <td>${c.oracleType || c.dataType || '—'}</td>
                <td><strong>${c.mssqlTargetType || '—'}</strong></td>
                <td>${c.nullable ? 'Evet' : 'Hayır'}</td>
            </tr>`;
        }).join('');
    }

    document.getElementById('btnTestOracle').addEventListener('click', async () => {
        const status = document.getElementById('oracleTestStatus');
        status.textContent = 'Test ediliyor…';
        status.className = 'small ms-2 text-muted';
        try {
            const def = collectDefinition();
            const res = await fetch('/api/wizard/test-oracle', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    host: document.getElementById('oracleHost').value.trim(),
                    port: document.getElementById('oraclePort').value.trim(),
                    service: document.getElementById('oracleService').value.trim(),
                    username: document.getElementById('oracleUser').value.trim(),
                    password: document.getElementById('oraclePassword').value,
                    schema: document.getElementById('oracleSchema').value.trim()
                })
            });
            const data = await res.json();
            if (data.success) {
                status.textContent = `OK — ${data.tableCount} tablo`;
                status.className = 'small ms-2 text-success';
            } else {
                status.textContent = data.error || 'Başarısız';
                status.className = 'small ms-2 text-danger';
            }
        } catch (e) {
            status.textContent = e.message;
            status.className = 'small ms-2 text-danger';
        }
    });

    document.getElementById('btnTestMssql').addEventListener('click', async () => {
        const status = document.getElementById('mssqlTestStatus');
        status.textContent = 'Test ediliyor…';
        status.className = 'small ms-2 text-muted';
        try {
            const res = await fetch('/api/wizard/test-mssql', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    server: document.getElementById('mssqlServer').value.trim(),
                    database: document.getElementById('mssqlDatabase').value.trim(),
                    authType: 'sql',
                    username: document.getElementById('mssqlUser').value.trim(),
                    password: document.getElementById('mssqlPassword').value,
                    trustCert: true
                })
            });
            const data = await res.json();
            if (data.success) {
                status.textContent = `OK — ${data.databaseName}`;
                status.className = 'small ms-2 text-success';
            } else {
                status.textContent = data.error || 'Başarısız';
                status.className = 'small ms-2 text-danger';
            }
        } catch (e) {
            status.textContent = e.message;
            status.className = 'small ms-2 text-danger';
        }
    });

    document.getElementById('btnPreview').addEventListener('click', async () => {
        setStatus('Önizleme yükleniyor…', false);
        try {
            const res = await fetch(API + '/preview', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(collectDefinition())
            });
            const data = await res.json();
            if (!data.success) {
                setStatus(data.error || 'Önizleme başarısız', true);
                return;
            }
            renderPreview(data.preview);
            setStatus('Önizleme yüklendi.', false);
        } catch (e) {
            setStatus(e.message, true);
        }
    });

    document.getElementById('btnSave').addEventListener('click', async () => {
        try {
            const res = await fetch(API + '/definition', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(collectDefinition())
            });
            const data = await res.json();
            if (data.success)
                setStatus('Aktarım tanımı kaydedildi.', false);
            else
                setStatus(data.error || 'Kayıt başarısız', true);
        } catch (e) {
            setStatus(e.message, true);
        }
    });

    document.getElementById('btnStart').addEventListener('click', async () => {
        if (!confirm('CS_READING_PLAN aktarımını başlatmak istiyor musunuz? LOCATION WGS84 geography olarak aktarılacak.'))
            return;

        setStatus('Aktarım başlatılıyor…', false);
        try {
            const res = await fetch(API + '/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(collectDefinition())
            });
            const data = await res.json();
            if (data.success) {
                setStatus(`${data.message} (PID: ${data.pid}). Canlı panelden izleyebilirsiniz.`, false);
            } else {
                setStatus(data.error || 'Başlatma başarısız', true);
            }
        } catch (e) {
            setStatus(e.message, true);
        }
    });

    document.getElementById('btnResume').addEventListener('click', async () => {
        setStatus('Resume başlatılıyor…', false);
        try {
            const res = await fetch(API + '/resume', { method: 'POST' });
            const data = await res.json();
            if (data.success)
                setStatus(`${data.message} (PID: ${data.pid})`, false);
            else
                setStatus(data.error || 'Resume başarısız', true);
        } catch (e) {
            setStatus(e.message, true);
        }
    });

    loadDefinition();
})();
