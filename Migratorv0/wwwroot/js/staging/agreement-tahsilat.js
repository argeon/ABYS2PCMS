(function () {
    const API = '/api/staging/tahsilat';
    const LS_KEY = 'tahsilat.wizard.conn.v1';
    const state = {
        steps: [],
        selected: null,
        gaps: [],
        logs: [],
        stepMeta: {}
    };

    const CONN_FIELDS = [
        'agrId', 'energyNr', 'energyPeriod', 'migrationSchema', 'smsSchema',
        'oracleHost', 'oraclePort', 'oracleService', 'oracleUser',
        'mssqlServer', 'mssqlDatabase', 'mssqlUser', 'mssqlAuth'
    ];

    function loadSavedConn() {
        try {
            const raw = localStorage.getItem(LS_KEY);
            if (!raw) return;
            const o = JSON.parse(raw);
            CONN_FIELDS.forEach(id => {
                if (o[id] != null && document.getElementById(id))
                    document.getElementById(id).value = o[id];
            });
            if (typeof o.mssqlTrust === 'boolean')
                document.getElementById('mssqlTrust').checked = o.mssqlTrust;
            if (o.oraclePassword != null) document.getElementById('oraclePassword').value = o.oraclePassword;
            if (o.mssqlPassword != null) document.getElementById('mssqlPassword').value = o.mssqlPassword;
            toggleMssqlAuth();
            refreshPreviews();
        } catch { /* ignore */ }
    }

    function saveConn() {
        const o = {};
        CONN_FIELDS.forEach(id => { o[id] = document.getElementById(id)?.value ?? ''; });
        o.mssqlTrust = document.getElementById('mssqlTrust').checked;
        o.oraclePassword = document.getElementById('oraclePassword').value;
        o.mssqlPassword = document.getElementById('mssqlPassword').value;
        localStorage.setItem(LS_KEY, JSON.stringify(o));
        setConnStatus('Bağlantı tarayıcıya kaydedildi. ENERGY Test ile doğrula.', false);
        refreshPreviews();
    }

    function oracleCs() {
        const host = document.getElementById('oracleHost').value.trim();
        const port = document.getElementById('oraclePort').value.trim() || '1521';
        const service = document.getElementById('oracleService').value.trim();
        const user = document.getElementById('oracleUser').value.trim();
        const password = document.getElementById('oraclePassword').value;
        return `User Id=${user};Password=${password};Data Source=${host}:${port}/${service};`;
    }

    function mssqlCs() {
        const server = document.getElementById('mssqlServer').value.trim();
        const db = document.getElementById('mssqlDatabase').value.trim() || 'energy';
        const trust = document.getElementById('mssqlTrust').checked ? 'True' : 'False';
        const auth = document.getElementById('mssqlAuth')?.value || 'Sql';
        if (auth === 'Windows') {
            return `Server=${server};Database=${db};Integrated Security=True;TrustServerCertificate=${trust};Encrypt=True;`;
        }
        const user = document.getElementById('mssqlUser').value.trim();
        const password = document.getElementById('mssqlPassword').value;
        return `Server=${server};Database=${db};User Id=${user};Password=${password};TrustServerCertificate=${trust};Encrypt=True;`;
    }

    function toggleMssqlAuth() {
        const win = (document.getElementById('mssqlAuth')?.value || 'Sql') === 'Windows';
        document.getElementById('mssqlUserWrap').style.display = win ? 'none' : '';
        document.getElementById('mssqlPasswordWrap').style.display = win ? 'none' : '';
        refreshPreviews();
    }

    function refreshPreviews() {
        const oh = document.getElementById('oracleHost').value.trim();
        const op = document.getElementById('oraclePort').value.trim() || '1521';
        const os = document.getElementById('oracleService').value.trim();
        const ou = document.getElementById('oracleUser').value.trim();
        const oraEl = document.getElementById('oraclePreview');
        if (oraEl) {
            oraEl.textContent = (oh && os && ou)
                ? `Özet: ${ou}@${oh}:${op}/${os}  | mig/sms şema ← ekran veya kullanıcı '${ou}'  (şifre gizli)`
                : 'Eksik alan var — Host / Service / User doldurun.';
        }

        const ms = document.getElementById('mssqlServer').value.trim();
        const md = document.getElementById('mssqlDatabase').value.trim() || 'energy';
        const auth = document.getElementById('mssqlAuth')?.value || 'Sql';
        const mu = document.getElementById('mssqlUser').value.trim();
        const mssqlEl = document.getElementById('mssqlPreview');
        if (mssqlEl) {
            if (!ms) {
                mssqlEl.textContent = 'Eksik: Server doldurun (örn. 10.x.x.x veya HOST\\SQLEXPRESS).';
            } else if (auth === 'Windows') {
                mssqlEl.textContent = `Özet: ${ms} / DB=${md} / Windows Auth  (şifre yok)`;
            } else if (!mu) {
                mssqlEl.textContent = 'Eksik: SQL kullanıcı (Login failed alıyorsan pcms yerine doğru login yaz).';
            } else {
                mssqlEl.textContent = `Özet: ${ms} / DB=${md} / User=${mu}  (şifre gizli)`;
            }
        }
    }

    function explainConnError(side, detail) {
        const d = String(detail || '');
        if (/Login failed/i.test(d)) {
            const m = d.match(/Login failed for user '([^']+)'/i);
            const u = m ? m[1] : '(user)';
            return `ENERGY giriş reddedildi (user='${u}'). Server doğru mu? SQL Auth şifresi doğru mu? Windows Auth denemelisin? ` + d;
        }
        if (/network|timeout|server was not found|named pipes|provider/i.test(d)) {
            return `Sunucuya ulaşılamıyor — Server/Instance ve firewall kontrol et. ${d}`;
        }
        if (/ORA-/i.test(d)) {
            return `SMS/Oracle hata: ${d}`;
        }
        return d;
    }

    function requestBody() {
        const oraUser = document.getElementById('oracleUser').value.trim();
        const migRaw = document.getElementById('migrationSchema').value.trim();
        const smsRaw = document.getElementById('smsSchema').value.trim();
        return {
            oracleConnectionString: oracleCs(),
            mssqlConnectionString: mssqlCs(),
            agreementId: parseInt(document.getElementById('agrId').value, 10) || 0,
            // Boş = sunucu bağlı Oracle kullanıcısını kullanır (MIGRATION hardcoded değil)
            migrationSchema: migRaw || oraUser || '',
            smsSchema: smsRaw || oraUser || '',
            energyNr: document.getElementById('energyNr').value.trim() || '005',
            energyPeriod: document.getElementById('energyPeriod').value.trim() || '01',
            runId: document.getElementById('runId').value.trim() || null,
            dryRun: document.getElementById('dryRun').checked,
            includeCloseEps: document.getElementById('includeEps').checked,
            cleanBeforePilot: document.getElementById('cleanBeforePilot')?.checked !== false
        };
    }

    function setConnStatus(msg, isErr) {
        const el = document.getElementById('connStatus');
        el.textContent = msg;
        el.className = 'small mt-2 ' + (isErr ? 'text-danger' : 'text-success');
    }

    function setStepStatus(msg, isErr) {
        const el = document.getElementById('stepStatus');
        el.textContent = msg;
        el.className = 'small mb-2 ' + (isErr ? 'text-danger' : 'text-success');
    }

    async function post(url, body) {
        const res = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        const text = await res.text();
        let json;
        try {
            json = text ? JSON.parse(text) : {};
        } catch {
            throw new Error(`API JSON değil (HTTP ${res.status}): ${text.slice(0, 240)}`);
        }
        if (!res.ok && json.success == null) {
            throw new Error(json.error || json.title || `HTTP ${res.status}`);
        }
        return json;
    }

    function appendLogs(logs) {
        if (!logs?.length) return;
        state.logs.push(...logs);
        const panel = document.getElementById('logPanel');
        const lines = logs.map(e => {
            const ts = (e.atUtc || '').toString().replace('T', ' ').slice(0, 19);
            return `[${ts}] ${e.side}/${e.op} step=${e.step} rows=${e.rowCount ?? '-'} ${e.outcome} ${e.detail || ''} (ms=${e.elapsedMs})`;
        });
        panel.textContent = (panel.textContent ? panel.textContent + '\n' : '') + lines.join('\n');
        panel.scrollTop = panel.scrollHeight;
    }

    function mergeGaps(gaps) {
        if (!gaps?.length) return;
        gaps.forEach(g => {
            const key = `${g.code}|${g.message}`;
            if (!state.gaps.some(x => `${x.code}|${x.message}` === key))
                state.gaps.push(g);
        });
        renderGaps();
    }

    function renderGaps() {
        const ul = document.getElementById('gapList');
        if (!state.gaps.length) {
            ul.innerHTML = '<li class="list-group-item text-muted">Henüz yok</li>';
            return;
        }
        ul.innerHTML = state.gaps.map(g => {
            const cls = g.severity === 'CRITICAL' ? 'text-danger' : (g.severity === 'WARN' ? 'text-warning' : 'text-muted');
            return `<li class="list-group-item ${cls}"><span class="badge bg-secondary me-1">${escapeHtml(g.severity)}</span>` +
                `<code>${escapeHtml(g.code)}</code> [${escapeHtml(g.side || '')}] ${escapeHtml(g.message)}</li>`;
        }).join('');
    }

    function escapeHtml(s) {
        return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    function renderTable(tableId, rows) {
        const table = document.getElementById(tableId);
        const thead = table.querySelector('thead');
        const tbody = table.querySelector('tbody');
        if (!rows?.length) {
            thead.innerHTML = '';
            tbody.innerHTML = '<tr><td class="text-muted p-2">Kayıt yok</td></tr>';
            return;
        }
        const cols = Object.keys(rows[0]);
        thead.innerHTML = '<tr>' + cols.map(c => `<th>${escapeHtml(c)}</th>`).join('') + '</tr>';
        tbody.innerHTML = rows.slice(0, 200).map(r =>
            '<tr>' + cols.map(c => `<td>${escapeHtml(r[c])}</td>`).join('') + '</tr>'
        ).join('');
    }

    function selectStep(step) {
        state.selected = step;
        document.getElementById('stepTitle').textContent = `${step.ordinal}. ${step.title}`;
        document.getElementById('stepExplain').textContent = step.explanation;
        document.getElementById('btnRunStep').disabled = false;
        document.querySelectorAll('#stepList .list-group-item').forEach(el => {
            el.classList.toggle('active', el.dataset.stepId === step.id);
        });
        const dryWrap = document.getElementById('dryRun').closest('.form-check');
        if (dryWrap) dryWrap.style.display = step.writesEnergy ? '' : 'none';
        const cleanWrap = document.getElementById('cleanBeforePilot')?.closest('.form-check');
        if (cleanWrap) {
            const showClean = step.id === 'pilotEnergyChain' || step.id === 'pilotFullChain';
            cleanWrap.style.display = showClean ? '' : 'none';
        }
    }

    function stepBadge(stepId) {
        const m = state.stepMeta[stepId];
        if (!m) return '';
        const cls = m.ok ? 'bg-success' : 'bg-danger';
        return `<span class="badge ${cls}">${escapeHtml(m.label)}</span>`;
    }

    function renderSteps() {
        const list = document.getElementById('stepList');
        const selectedId = state.selected?.id;
        list.innerHTML = state.steps.map(s => `
            <button type="button" class="list-group-item list-group-item-action ${selectedId === s.id ? 'active' : ''}" data-step-id="${escapeHtml(s.id)}">
                <div class="d-flex justify-content-between gap-2">
                    <span><strong>${s.ordinal}.</strong> ${escapeHtml(s.title)}</span>
                    <span class="d-flex gap-1 align-items-start">
                      ${stepBadge(s.id)}
                      ${s.writesEnergy ? '<span class="badge bg-warning text-dark">WRITE</span>' : '<span class="badge bg-secondary">READ</span>'}
                    </span>
                </div>
                <div class="small text-muted text-truncate">${escapeHtml(s.explanation)}</div>
            </button>`).join('');
        list.querySelectorAll('[data-step-id]').forEach(btn => {
            btn.addEventListener('click', () => {
                const step = state.steps.find(x => x.id === btn.dataset.stepId);
                if (step) selectStep(step);
            });
        });
    }

    async function loadCatalog() {
        const res = await fetch(`${API}/catalog`);
        const json = await res.json();
        state.steps = json.data?.steps || [];
        renderSteps();
        if (state.steps[0]) selectStep(state.steps[0]);
    }

    async function runStep(stepId, overrides) {
        setStepStatus(`Çalışıyor: ${stepId}...`, false);
        const body = Object.assign(requestBody(), overrides || {});
        let json;
        try {
            json = await post(`${API}/step/${encodeURIComponent(stepId)}`, body);
        } catch (e) {
            const err = { success: false, error: String(e?.message || e) };
            setStepStatus(err.error, true);
            state.stepMeta[stepId] = { ok: false, label: 'ERR' };
            renderSteps();
            return err;
        }
        if (json.data?.runId)
            document.getElementById('runId').value = json.data.runId;

        if (!json.success && !json.data) {
            setStepStatus(json.error || 'Hata', true);
            state.stepMeta[stepId] = { ok: false, label: 'ERR' };
            renderSteps();
            return json;
        }

        const data = json.data || {};
        appendLogs(data.logs || []);
        mergeGaps(data.gaps || []);
        renderTable('tblSms', data.rows || []);
        renderTable('tblEnergy', data.energyRows || []);
        document.getElementById('summaryBox').textContent = JSON.stringify(data.summary || {}, null, 2);
        setStepStatus(data.message || (json.success ? 'OK' : json.error), !json.success);

        const logDir = data.summary?.pilotLogDir || data.summary?.energy_pilotLogDir || data.summary?.dump_pilotLogDir;
        const hint = document.getElementById('pilotLogHint');
        if (hint && logDir) {
            hint.textContent = `Doğrulama paketi: ${logDir}  (SHARE.md + validation.json + gaps.jsonl)`;
        }

        const smsN = (data.rows || []).length;
        const enN = (data.energyRows || []).length;
        const label = enN || data.summary?.energyCount != null
            ? `${smsN}/${enN || data.summary?.energyCount || 0}`
            : String(data.summary?.count ?? smsN);
        state.stepMeta[stepId] = { ok: !!json.success, label };
        renderSteps();
        return json;
    }

    function setOneClickStatus(msg, isErr) {
        const el = document.getElementById('oneClickStatus');
        if (!el) return;
        el.textContent = msg;
        el.className = 'small mt-1 ' + (isErr ? 'text-danger fw-semibold' : 'text-success');
        appendLogs([{
            atUtc: new Date().toISOString(),
            side: 'UI',
            op: isErr ? 'FAIL' : 'INFO',
            step: 'oneClickEnergy',
            rowCount: 0,
            outcome: isErr ? 'FAIL' : 'OK',
            detail: msg,
            elapsedMs: 0
        }]);
    }

    async function runOneClickEnergy() {
        const agr = parseInt(document.getElementById('agrId').value, 10) || 0;
        if (agr <= 0) {
            setOneClickStatus('Sözleşme ID gerekli.', true);
            return;
        }
        if (!document.getElementById('mssqlServer').value.trim() ||
            !document.getElementById('oracleHost').value.trim()) {
            setOneClickStatus('SMS + ENERGY bağlantı alanlarını doldurun / kaydedin.', true);
            return;
        }
        if (!document.getElementById('oraclePassword').value) {
            setOneClickStatus('Oracle şifre boş.', true);
            return;
        }
        const auth = document.getElementById('mssqlAuth')?.value || 'Sql';
        if (auth !== 'Windows' && !document.getElementById('mssqlPassword').value) {
            setOneClickStatus('ENERGY SQL şifre boş.', true);
            return;
        }

        const clean = document.getElementById('oneClickClean')?.checked !== false;
        const msg =
            `AGR=${agr} için APPLY (DRY_RUN kapalı):\n` +
            `1) Bağlantı testi\n` +
            `2) izgazMGR dump\n` +
            `3) ENERGY zinciri${clean ? ' + temizle' : ''}\n\nDevam?`;
        if (!confirm(msg)) {
            setOneClickStatus('İptal edildi (onay penceresi).', true);
            return;
        }

        const btn = document.getElementById('btnOneClickEnergy');
        if (btn) btn.disabled = true;
        document.getElementById('dryRun').checked = false;
        const cleanEl = document.getElementById('cleanBeforePilot');
        if (cleanEl) cleanEl.checked = clean;

        state.gaps = [];
        state.stepMeta = {};
        renderGaps();

        const applyOpts = { dryRun: false, cleanBeforePilot: clean };

        try {
            setOneClickStatus('1/3 Bağlantı testi...', false);
            const conn = await runStep('connTest', applyOpts);
            if (!conn.success) {
                setOneClickStatus('Bağlantı FAIL: ' + (conn.error || conn.data?.message || '?'), true);
                return;
            }

            const full = state.steps.find(s => s.id === 'pilotFullChain');
            if (!full) {
                setOneClickStatus('Catalog’da pilotFullChain yok — uygulamayı yeniden başlatın.', true);
                return;
            }
            selectStep(full);

            setOneClickStatus('2/3 Dump → ENERGY APPLY (uzun sürebilir)...', false);
            const t0 = Date.now();
            const json = await runStep('pilotFullChain', applyOpts);
            const sec = Math.round((Date.now() - t0) / 1000);
            const s = json.data?.summary || {};
            if (json.success) {
                setOneClickStatus(
                    `OK (${sec}s): dump=${s.dumpOk ?? '?'} energy=${s.energyOk ?? '?'} ` +
                    `taksitPt=${s.energy_taksitPtInserted ?? s.taksitPtInserted ?? '-'} ` +
                    `tahsilatInv=${s.energy_tahsilatInv ?? s.tahsilatInv ?? '-'} | ${json.data?.message || 'OK'}`,
                    false
                );
            } else {
                const err =
                    json.data?.message ||
                    json.error ||
                    (json.data?.gaps || []).filter(g => g.severity === 'CRITICAL').map(g => g.message).join('; ') ||
                    'Aktarım başarısız.';
                setOneClickStatus(`FAIL (${sec}s): ${err}`, true);
            }
        } catch (e) {
            setOneClickStatus('JS hata: ' + String(e?.message || e), true);
        } finally {
            if (btn) btn.disabled = false;
        }
    }

    // Global — onclick / konsol: tahsilatOneClick()
    window.tahsilatOneClick = runOneClickEnergy;

    document.getElementById('btnRunStep').addEventListener('click', async () => {
        if (!state.selected) return;
        if (state.selected.writesEnergy && !document.getElementById('dryRun').checked) {
            let msg = 'DRY_RUN kapalı — ENERGY üzerinde PAID/CLOSED güncellenecek. Devam?';
            if (state.selected.id === 'pilotDumpMgr') {
                msg = 'DRY_RUN kapalı — izgazMGR\'de bu AGR silinip Oracle CTAS + SMS taksit yüklenecek. Devam?';
            } else if (state.selected.id === 'pilotEnergyChain') {
                msg = 'DRY_RUN kapalı — ENERGY\'ye tek AGR için INVOICE/INVLINES/PAYTRANS/INSTALLMENT_PLAN yazılacak (gerekirse temizlenir). Devam?';
            } else if (state.selected.id === 'pilotFullChain') {
                msg = 'DRY_RUN kapalı — önce izgazMGR dump, sonra ENERGY zinciri APPLY. Devam?';
            }
            if (!confirm(msg)) return;
        }
        await runStep(state.selected.id);
    });

    const oneBtn = document.getElementById('btnOneClickEnergy');
    if (oneBtn) {
        oneBtn.addEventListener('click', (ev) => {
            ev.preventDefault();
            runOneClickEnergy();
        });
        setOneClickStatus('Hazır — ENERGY’ye aktar ile dump+ENERGY APPLY.', false);
    } else {
        console.warn('btnOneClickEnergy yok — sayfayı yenileyin.');
    }

    document.getElementById('btnRunAll').addEventListener('click', async () => {
        document.getElementById('dryRun').checked = true;
        state.gaps = [];
        state.stepMeta = {};
        renderGaps();
        for (const s of state.steps) {
            selectStep(s);
            const json = await runStep(s.id);
            if (s.id === 'connTest' && !json.success) {
                setConnStatus('Bağlantı başarısız — durdu.', true);
                break;
            }
        }
    });

    document.getElementById('btnTestBoth').addEventListener('click', () => runStep('connTest').then(j => {
        const msg = explainConnError('BOTH', j.data?.message || j.error || '');
        setConnStatus(msg, !j.success);
    }));
    document.getElementById('btnTestSms').addEventListener('click', () => runStep('connTest').then(j => {
        const sms = (j.data?.logs || []).find(l => l.side === 'SMS');
        const raw = sms?.detail || j.data?.message || j.error || '';
        setConnStatus(explainConnError('SMS', raw), sms?.outcome === 'FAIL' || !j.success);
    }));
    document.getElementById('btnTestEnergy').addEventListener('click', () => runStep('connTest').then(j => {
        const en = (j.data?.logs || []).find(l => l.side === 'ENERGY');
        const raw = en?.detail || j.data?.message || j.error || '';
        setConnStatus(explainConnError('ENERGY', raw), en?.outcome === 'FAIL' || !j.success);
    }));

    document.getElementById('btnClearLog').addEventListener('click', () => {
        state.logs = [];
        document.getElementById('logPanel').textContent = '';
    });

    document.getElementById('btnPilotLogs')?.addEventListener('click', async () => {
        const runId = document.getElementById('runId').value.trim();
        try {
            if (runId) {
                const res = await fetch(`${API}/pilot-logs/${encodeURIComponent(runId)}`);
                const json = await res.json();
                if (!json.success) {
                    setConnStatus(json.error || 'Log yok', true);
                    return;
                }
                const d = json.data;
                setConnStatus(`Log: ${d.path} | events=${d.eventsLines} gaps=${d.gapsLines} steps=${(d.stepFiles || []).length}`, false);
                document.getElementById('summaryBox').textContent =
                    (d.shareMd || '') + '\n\n--- validation ---\n' + (d.validation || d.latestStep || '{}');
            } else {
                const res = await fetch(`${API}/pilot-logs`);
                const json = await res.json();
                const runs = json.data?.runs || [];
                setConnStatus(`Kök: ${json.data?.root || '?'} — ${runs.length} run`, false);
                document.getElementById('summaryBox').textContent = JSON.stringify(json.data, null, 2);
            }
        } catch (e) {
            setConnStatus(String(e), true);
        }
    });

    document.getElementById('btnSaveConn').addEventListener('click', saveConn);
    document.getElementById('mssqlAuth')?.addEventListener('change', toggleMssqlAuth);
    [
        'oracleHost', 'oraclePort', 'oracleService', 'oracleUser',
        'mssqlServer', 'mssqlDatabase', 'mssqlUser', 'mssqlAuth'
    ].forEach(id => document.getElementById(id)?.addEventListener('input', refreshPreviews));
    document.getElementById('mssqlAuth')?.addEventListener('change', refreshPreviews);

    document.getElementById('btnExportGaps').addEventListener('click', async () => {
        const payload = {
            agreementId: parseInt(document.getElementById('agrId').value, 10) || 0,
            runId: document.getElementById('runId').value || null,
            exportedAt: new Date().toISOString(),
            gaps: state.gaps,
            stepMeta: state.stepMeta
        };
        try {
            await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
            setConnStatus(`Gap JSON kopyalandı (${state.gaps.length} madde).`, false);
        } catch {
            setConnStatus('Kopyalama başarısız.', true);
        }
    });

    loadSavedConn();
    toggleMssqlAuth();
    refreshPreviews();
    loadCatalog().catch(err => setConnStatus(String(err), true));
})();
