(() => {
  const root = document.getElementById('stageOpsBoard');
  if (!root) return;
  const surface = root.dataset.surface;
  const api = `/api/stage-ops/${surface}`;

  let stages = [];
  let selected = new Set();
  let activeRunId = null;
  let pollTimer = null;

  const el = (id) => document.getElementById(id);

  function fmtRows(n) {
    if (n == null) return '—';
    if (n >= 1e9) return (n / 1e9).toFixed(2) + 'B';
    if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
    if (n >= 1e3) return (n / 1e3).toFixed(0) + 'K';
    return String(n);
  }

  function statusClass(s) {
    return 'so-status so-st-' + (s || 'Ready');
  }

  function escapeHtml(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function showAlert(message, kind) {
    const box = el('soAlert');
    if (!box) return;
    if (!message) {
      box.hidden = true;
      box.textContent = '';
      return;
    }
    box.hidden = false;
    box.className = 'so-alert' + (kind === 'ok' ? ' so-alert-ok' : kind === 'warn' ? ' so-alert-warn' : '');
    box.textContent = message;
  }

  function toastError(title, text) {
    showAlert((title ? title + '\n' : '') + (text || ''), 'err');
    if (window.Swal) {
      Swal.fire({
        icon: 'error',
        title: title || 'Hata',
        html: `<pre style="text-align:left;white-space:pre-wrap;font-size:0.82rem;max-height:280px;overflow:auto">${escapeHtml(text || '')}</pre>`,
        confirmButtonText: 'Tamam',
        background: '#121a2b',
        color: '#e8eef7'
      });
    } else {
      alert((title || 'Hata') + '\n' + (text || ''));
    }
  }

  async function confirmStart(resume, stageNames, maxParallel) {
    const title = resume ? 'Resume onayı' : 'Başlatma onayı';
    const list = stageNames.map(n => `• ${n}`).join('\n');
    const html = `<div style="text-align:left;font-size:0.9rem">
      <p><strong>${stageNames.length}</strong> stage çalışacak${surface === 'ctas' ? ` · parallel=<strong>${maxParallel}</strong>` : ''}.</p>
      <pre style="white-space:pre-wrap;max-height:180px;overflow:auto;background:#0f172a;padding:0.6rem;border-radius:8px;font-size:0.8rem">${escapeHtml(list)}</pre>
      <p style="color:#94a3b8;margin-top:0.5rem">Mevcut script/SP olduğu gibi çalıştırılır. Devam edilsin mi?</p>
    </div>`;

    if (window.Swal) {
      const r = await Swal.fire({
        icon: 'question',
        title,
        html,
        showCancelButton: true,
        confirmButtonText: resume ? 'Resume' : 'Başlat',
        cancelButtonText: 'Vazgeç',
        reverseButtons: true,
        background: '#121a2b',
        color: '#e8eef7',
        confirmButtonColor: '#14b8a6',
        cancelButtonColor: '#475569'
      });
      return r.isConfirmed;
    }
    return confirm(`${title}\n\n${list}\n\nDevam?`);
  }

  async function fetchJson(url, opts) {
    const r = await fetch(url, opts);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.error || data.message || r.statusText);
    return data;
  }

  function parseAnalysis(s) {
    const base = {
      syntaxOk: s.syntaxStatus === 'Ok' || s.syntaxStatus === 'OK',
      syntaxErrors: [],
      writes: Array.isArray(s.writes) ? s.writes : [],
      reads: Array.isArray(s.reads) ? s.reads : [],
      calls: [],
      suggestedDependsOn: Array.isArray(s.dependsOn) ? s.dependsOn : [],
      warnings: []
    };
    if (!s.analysisJson) return base;
    try {
      const j = typeof s.analysisJson === 'string' ? JSON.parse(s.analysisJson) : s.analysisJson;
      return {
        syntaxOk: j.syntaxOk ?? j.SyntaxOk ?? base.syntaxOk,
        syntaxErrors: j.syntaxErrors || j.SyntaxErrors || [],
        writes: j.writes || j.Writes || base.writes,
        reads: j.reads || j.Reads || base.reads,
        calls: j.calls || j.Calls || [],
        suggestedDependsOn: j.suggestedDependsOn || j.SuggestedDependsOn || base.suggestedDependsOn,
        warnings: j.warnings || j.Warnings || []
      };
    } catch {
      return base;
    }
  }

  function analysisSummaryHtml(a) {
    const syn = a.syntaxOk ? '<span style="color:var(--so-ok)">OK</span>' : '<span style="color:var(--so-danger)">FAIL</span>';
    const w = (a.writes || []).slice(0, 3).join(', ') || '—';
    const r = (a.reads || []).slice(0, 2).join(', ');
    const c = (a.calls || []).slice(0, 2).join(', ');
    return `<div style="font-size:.75rem;line-height:1.35">
      <div>syn ${syn}</div>
      <div title="${escapeHtml((a.writes || []).join(', '))}"><span style="color:var(--so-muted)">W</span> ${escapeHtml(w)}</div>
      ${r ? `<div title="${escapeHtml((a.reads || []).join(', '))}"><span style="color:var(--so-muted)">R</span> ${escapeHtml(r)}</div>` : ''}
      ${c ? `<div><span style="color:var(--so-muted)">EXEC</span> ${escapeHtml(c)}</div>` : ''}
    </div>`;
  }

  function renderAnalysisPanel() {
    const box = el('uploadResults');
    if (!box) return;
    const withAnalysis = stages.filter(s =>
      s.analysisJson || (s.writes && s.writes.length) || (s.reads && s.reads.length) || s.domain === 'UPLOAD');
    if (!withAnalysis.length) {
      box.innerHTML = '.sql dosyası yükleyin — syntax ve ilişki analizi otomatik çalışır.';
      box.style.color = 'var(--so-muted)';
      return;
    }
    box.style.color = '';
    box.innerHTML = withAnalysis.map(s => {
      const a = parseAnalysis(s);
      const ok = a.syntaxOk ? '✓' : '✗';
      const warns = (a.warnings || []).join('; ');
      const deps = (a.suggestedDependsOn || []).join(', ');
      const synErr = (a.syntaxErrors || []).join(', ');
      return `<div style="margin-bottom:.75rem;padding-bottom:.55rem;border-bottom:1px solid var(--so-line)">
        <strong>${ok} ${escapeHtml(s.name || s.id)}</strong>
        <div style="color:var(--so-muted);font-size:.72rem;font-family:var(--so-mono)">${escapeHtml(s.id)}</div>
        <div>syntax: ${a.syntaxOk ? 'OK' : 'FAIL'}${synErr ? ' — ' + escapeHtml(synErr) : ''}</div>
        <div>writes: ${escapeHtml((a.writes || []).slice(0, 8).join(', ') || '—')}</div>
        <div>reads: ${escapeHtml((a.reads || []).slice(0, 8).join(', ') || '—')}</div>
        ${(a.calls || []).length ? `<div>calls: ${escapeHtml(a.calls.slice(0, 6).join(', '))}</div>` : ''}
        ${deps ? `<div>dependsOn: ${escapeHtml(deps)}</div>` : ''}
        ${warns ? `<div style="color:var(--so-warn)">${escapeHtml(warns)}</div>` : ''}
      </div>`;
    }).join('');
  }

  async function loadStages() {
    try {
      stages = await fetchJson(`${api}/stages`);
      el('stTotal').textContent = stages.length;
      renderStages();
      renderAnalysisPanel();
    } catch (e) {
      toastError('Stage listesi yüklenemedi', e.message || String(e));
    }
  }

  function renderStages() {
    const body = el('stageBody');
    if (!stages.length) {
      body.innerHTML = '<tr><td colspan="7" style="color:var(--so-muted);padding:1rem">Stage yok — .sql yükleyin</td></tr>';
      return;
    }
    body.innerHTML = stages.map(s => {
      const disabled = s.status === 'Invalid' || s.status === 'Running';
      const checked = selected.has(s.id) ? 'checked' : '';
      const failRow = s.status === 'Failed' || s.status === 'Invalid' ? ' style="background:rgba(251,113,133,0.06)"' : '';
      const a = parseAnalysis(s);
      return `<tr${failRow}>
        <td><input type="checkbox" data-id="${s.id}" ${checked} ${disabled ? 'disabled' : ''} /></td>
        <td>
          <div style="font-weight:600">${escapeHtml(s.name)}</div>
          <div style="color:var(--so-muted);font-size:.75rem;font-family:var(--so-mono)">${escapeHtml(s.id)}</div>
        </td>
        <td>${escapeHtml(s.domain || '')}</td>
        <td>${analysisSummaryHtml(a)}</td>
        <td><span class="${statusClass(s.status)}">${escapeHtml(s.status)}</span></td>
        <td>${fmtRows(s.estimatedRows)}</td>
        <td>
          <button type="button" class="so-btn so-btn-ghost" data-mark="${s.id}" data-st="Done">Done</button>
          <button type="button" class="so-btn so-btn-ghost" data-mark="${s.id}" data-st="Skipped">Skip</button>
        </td>
      </tr>`;
    }).join('');

    body.querySelectorAll('input[type=checkbox]').forEach(cb => {
      cb.addEventListener('change', () => {
        if (cb.checked) selected.add(cb.dataset.id);
        else selected.delete(cb.dataset.id);
        el('stSelected').textContent = selected.size;
      });
    });
    body.querySelectorAll('[data-mark]').forEach(btn => {
      btn.addEventListener('click', async () => {
        try {
          await fetchJson(`${api}/stages/${btn.dataset.mark}/status`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ status: btn.dataset.st })
          });
          await loadStages();
        } catch (e) {
          toastError('Durum güncellenemedi', e.message || String(e));
        }
      });
    });
    el('boardMeta').textContent = `${stages.filter(s => s.status === 'Done').length} done · ${stages.filter(s => s.status === 'Failed').length} failed`;
    el('stSelected').textContent = selected.size;
  }

  function extractErrorText(item) {
    const parts = [];
    if (item.exitCode != null && item.exitCode !== 0)
      parts.push(`exit=${item.exitCode}`);

    // Prefer real log file content (not the PS1 JSON summary on stdout)
    const logText = (item.logText || '').trim();
    if (logText) {
      parts.push(logText);
      return parts.join('\n\n');
    }

    if (!item.detailJson) return parts.join(' · ') || item.status;
    try {
      const d = JSON.parse(item.detailJson);
      if (typeof d === 'string') {
        parts.push(d);
        return parts.join('\n\n');
      }
      const log = (d.log || '').trim();
      const stderr = (d.stderr || '').trim();
      const stdout = (d.stdout || '').trim();
      if (log) parts.push(log);
      else if (stderr) parts.push(stderr);
      else if (stdout) {
        // Ignore PS1 result JSON line if present
        const cleaned = stdout
          .split(/\r?\n/)
          .filter(l => !(l.trim().startsWith('{') && l.includes('"exitCode"')))
          .join('\n')
          .trim();
        if (cleaned) {
          const lines = cleaned.split(/\r?\n/).filter(l => /ORA-|ERROR|Exception|failed|hata|missing|throw/i.test(l));
          parts.push(lines.length ? lines.slice(-20).join('\n') : cleaned.slice(-1200));
        } else {
          parts.push(stdout.slice(-800));
        }
      }
    } catch {
      const raw = String(item.detailJson);
      if (!(raw.trim().startsWith('{') && raw.includes('exitCode')))
        parts.push(raw.slice(0, 1200));
    }
    return parts.join('\n\n') || 'Detay yok — log indirin';
  }

  function renderErrors(items, events) {
    const body = el('errorsBody');
    const count = el('errorsCount');
    const failedItems = (items || []).filter(i => i.status === 'Failed');
    const errorEvents = (events || []).filter(e => e.level === 'Error');

    if (!failedItems.length && !errorEvents.length) {
      count.textContent = '';
      body.innerHTML = '<span style="color:var(--so-ok)">Seçili run’da hata yok.</span>';
      return;
    }

    count.textContent = `${failedItems.length} stage · ${errorEvents.length} olay`;
    const cards = failedItems.map(i => {
      const text = extractErrorText(i);
      const logLink = i.logPath
        ? `<a class="so-btn so-btn-ghost" href="/api/stage-ops/runs/${i.runId}/items/${i.id}/log" style="margin-top:0.35rem;display:inline-block">Log indir</a>`
        : '';
      return `<div class="so-error-card">
        <strong>${escapeHtml(i.stageName || i.stageId)}</strong>
        <span class="${statusClass('Failed')}">Failed</span>
        <div style="color:var(--so-muted);font-size:0.75rem;margin-top:0.2rem">${escapeHtml(i.stageId)} · ${i.elapsedMs || 0} ms</div>
        <pre>${escapeHtml(text)}</pre>
        ${logLink}
      </div>`;
    }).join('');

    const evHtml = errorEvents.length
      ? `<div style="margin-top:0.5rem;color:var(--so-danger)">${errorEvents.slice(0, 20).map(e =>
          `<div>[${new Date(e.createdAt).toLocaleTimeString()}] ${escapeHtml(e.stageId || '')} ${escapeHtml(e.message)}</div>`
        ).join('')}</div>`
      : '';

    body.innerHTML = (cards || '') + evHtml;

    if (failedItems.length) {
      const first = failedItems[0];
      showAlert(`${failedItems.length} stage başarısız. Örnek: ${first.stageId}\n${extractErrorText(first).slice(0, 400)}`, 'err');
    }
  }

  async function startRun(resume) {
    if (!selected.size) {
      toastError('Seçim yok', 'En az bir stage seçin');
      return;
    }
    const maxParallel = parseInt(el('maxParallel').value || '1', 10);
    const selectedStages = stages.filter(s => selected.has(s.id));
    const names = selectedStages.map(s => s.name || s.id);

    const ok = await confirmStart(resume, names, maxParallel);
    if (!ok) return;

    showAlert(null);
    try {
      const res = await fetchJson(`${api}/runs`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          stageIds: [...selected],
          maxParallel,
          resume: !!resume,
          hardReset: false,
          skipSchemaGate: false
        })
      });
      activeRunId = res.runId;
      el('stRun').textContent = '#' + res.runId;
      showAlert(`Run #${res.runId} başlatıldı (${names.length} stage).`, 'ok');
      await loadRuns();
      await selectRun(res.runId);
      startPoll();
    } catch (e) {
      toastError('Run başlatılamadı', e.message || String(e));
    }
  }

  async function loadRuns() {
    try {
      const runs = await fetchJson(`${api}/runs?limit=20`);
      const body = el('runsBody');
      if (!runs.length) {
        body.innerHTML = '<tr><td colspan="5" style="color:var(--so-muted);padding:.8rem">Henüz run yok</td></tr>';
        return;
      }
      body.innerHTML = runs.map(r => `<tr data-run="${r.id}" style="cursor:pointer${r.failedCount ? ';background:rgba(251,113,133,0.05)' : ''}">
        <td>#${r.id}</td>
        <td><span class="${statusClass(r.status)}">${escapeHtml(r.status)}</span></td>
        <td>${r.doneCount}</td>
        <td style="${r.failedCount ? 'color:var(--so-danger);font-weight:700' : ''}">${r.failedCount}</td>
        <td style="font-size:.78rem;color:var(--so-muted)">${new Date(r.startedAt).toLocaleString()}</td>
      </tr>`).join('');
      body.querySelectorAll('tr[data-run]').forEach(tr => {
        tr.addEventListener('click', () => selectRun(parseInt(tr.dataset.run, 10)));
      });
    } catch (e) {
      toastError('Run listesi yüklenemedi', e.message || String(e));
    }
  }

  async function selectRun(runId) {
    activeRunId = runId;
    try {
      const data = await fetchJson(`/api/stage-ops/runs/${runId}`);
      el('selectedRunLabel').textContent = `Run #${runId}`;
      const r = data.run;
      const pct = r.totalStages ? Math.round(100 * (r.doneCount + r.failedCount) / r.totalStages) : 0;
      el('runBar').style.width = pct + '%';
      el('runBarLabel').textContent = `${r.doneCount}/${r.totalStages} tamam · ${r.failedCount} hata · ${r.runningCount} çalışıyor (${pct}%)`;
      el('stProgress').textContent = pct + '%';
      el('stRun').textContent = '#' + runId;

      const list = el('eventList');
      const events = (data.events || []).slice().reverse();
      list.innerHTML = events.length
        ? events.map(e => `<li class="${e.level === 'Error' ? 'err' : 'info'}">[${new Date(e.createdAt).toLocaleTimeString()}] ${escapeHtml(e.stageId || '')} ${escapeHtml(e.message)}</li>`).join('')
        : '<li>Olay yok</li>';

      renderErrors(data.items || [], data.events || []);

      if (r.status === 'Failed' || (r.failedCount > 0 && (r.status === 'Done' || r.status === 'Failed'))) {
        // keep banner from renderErrors
      } else if (r.status === 'Done') {
        showAlert(`Run #${runId} tamamlandı — ${r.doneCount} OK, ${r.failedCount} hata.`, r.failedCount ? 'warn' : 'ok');
      }

      await loadStages();
    } catch (e) {
      toastError('Run detayı alınamadı', e.message || String(e));
    }
  }

  function startPoll() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(async () => {
      if (!activeRunId) return;
      try {
        await selectRun(activeRunId);
        const data = await fetchJson(`/api/stage-ops/runs/${activeRunId}`);
        if (data.run.status === 'Done' || data.run.status === 'Failed') {
          clearInterval(pollTimer);
          pollTimer = null;
          if (data.run.failedCount > 0) {
            const failed = (data.items || []).filter(i => i.status === 'Failed');
            if (failed.length && window.Swal) {
              Swal.fire({
                icon: 'error',
                title: `${failed.length} stage başarısız`,
                html: `<div style="text-align:left;font-size:0.85rem">${failed.map(f =>
                  `<div style="margin-bottom:0.5rem"><b>${escapeHtml(f.stageId)}</b><pre style="white-space:pre-wrap;font-size:0.75rem;max-height:100px;overflow:auto">${escapeHtml(extractErrorText(f).slice(0, 600))}</pre></div>`
                ).join('')}</div>`,
                confirmButtonText: 'Tamam',
                background: '#121a2b',
                color: '#e8eef7'
              });
            }
          }
        }
      } catch (e) {
        showAlert('Poll hatası: ' + (e.message || e), 'err');
      }
    }, 4000);
  }

  el('btnStart').addEventListener('click', () => startRun(false));
  el('btnResume').addEventListener('click', () => startRun(true));
  el('btnRefresh').addEventListener('click', () => { loadStages(); loadRuns(); loadMig(); });
  el('btnRefreshRuns').addEventListener('click', loadRuns);
  el('btnClear').addEventListener('click', () => { selected.clear(); renderStages(); });
  el('btnSelectReady').addEventListener('click', () => {
    selected = new Set(stages.filter(s => s.status === 'Ready' || s.status === 'Failed').map(s => s.id));
    renderStages();
  });

  el('btnSchemaCheck')?.addEventListener('click', async () => {
    if (!selected.size) {
      toastError('Seçim yok', 'Kontrol için stage seçin');
      return;
    }
    const lines = [];
    let anyFail = false;
    for (const id of selected) {
      try {
        const r = await fetchJson(`${api}/stages/${id}/schema-check`, { method: 'POST' });
        lines.push(`${id}: ${r.compatible ? 'OK' : 'FAIL'} — ${r.detail || ''}`);
        if (!r.compatible) anyFail = true;
        if (r.drift?.length) lines.push(...r.drift.slice(0, 8).map(d => `  · ${d.column}: ${d.issue}`));
      } catch (e) {
        anyFail = true;
        lines.push(`${id}: hata ${e.message}`);
      }
    }
    showAlert(lines.join('\n'), anyFail ? 'err' : 'ok');
    if (window.Swal) {
      Swal.fire({
        icon: anyFail ? 'warning' : 'success',
        title: 'Şema kontrol',
        html: `<pre style="text-align:left;white-space:pre-wrap;font-size:0.8rem;max-height:320px;overflow:auto">${escapeHtml(lines.join('\n'))}</pre>`,
        background: '#121a2b',
        color: '#e8eef7'
      });
    }
  });

  async function loadMig() {
    const panel = el('migLogPanel');
    if (!panel) return;
    try {
      const data = await fetchJson('/api/stage-ops/transfer-sql/mig-log');
      if (!data.available) {
        panel.textContent = data.message || 'MIG bağlantısı yok';
        return;
      }
      const runs = (data.runs || []).slice(0, 8).map(r =>
        `<div style="margin-bottom:.45rem"><strong>${escapeHtml(r.migrationCode)}</strong>
         <span class="${statusClass(r.status)}">${escapeHtml(r.status)}</span>
         ${r.pct != null ? ` · %${r.pct}` : ''} · ins=${r.inserted}${r.sourceRows != null ? '/' + r.sourceRows : ''}
         ${r.errors ? ` · err=${r.errors}` : ''}</div>`).join('');
      const errs = (data.batchErrors || []).slice(0, 5).map(e =>
        `<div style="color:var(--so-danger)">${escapeHtml(e.migrationCode)} b${e.batchNo}: ${escapeHtml((e.error || '').slice(0, 120))}</div>`).join('');
      panel.innerHTML = (runs || '<div>Run yok</div>') + (errs ? '<hr style="border-color:var(--so-line)">' + errs : '');
    } catch (e) {
      panel.textContent = e.message || String(e);
    }
  }

  el('btnMigRefresh')?.addEventListener('click', loadMig);

  el('fileUpload').addEventListener('change', async (ev) => {
    const files = ev.target.files;
    if (!files?.length) return;
    const fd = new FormData();
    [...files].forEach(f => fd.append('files', f));
    try {
      const res = await fetch(`${api}/upload`, { method: 'POST', body: fd });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || data.message || 'Upload failed');
      if (!Array.isArray(data) || data.length === 0) {
        throw new Error('Hiç .sql işlenmedi — dosya uzantısını kontrol edin');
      }
      const failed = data.filter(u => !u.accepted);
      if (failed.length) {
        toastError('Yükleme hataları', failed.map(u =>
          `${u.fileName}: ${(u.analysis?.syntaxErrors || u.analysis?.SyntaxErrors || []).join(', ')}`).join('\n'));
      } else {
        showAlert(`${data.length} script yüklendi ve analiz edildi.`, 'ok');
      }
      await loadStages();
    } catch (e) {
      toastError('Upload başarısız', e.message || String(e));
    }
    ev.target.value = '';
  });

  async function checkConnections() {
    const banner = el('connBanner');
    if (!banner) return;
    try {
      const st = await fetchJson('/api/stage-ops/connections/status');
      const missing = [];
      if (surface === 'ctas' && !st.oracleCtas)
        missing.push('CTAS Oracle sqlplus bağlantısı eksik');
      if (surface === 'transfer-sql' && !st.mssqlStage2)
        missing.push('MSSQL Stage 2 (energy) bağlantısı eksik');
      if (surface === 'transfer-sql' && !st.mssqlStage1)
        missing.push('MSSQL Stage 1 (izgazMGR) önerilir');
      if (surface === 'prod-sql' && !st.mssqlProd && !st.mssqlStage2)
        missing.push('PROD veya Stage 2 MSSQL bağlantısı eksik');
      if (missing.length) {
        banner.hidden = false;
        banner.innerHTML = `${escapeHtml(missing.join(' · '))} — <a href="/stage-ops/connections" style="color:inherit;font-weight:700">Bağlantılar</a>`;
      } else {
        banner.hidden = true;
      }
    } catch {
      banner.hidden = true;
    }
  }

  loadStages();
  loadRuns();
  loadMig();
  checkConnections();
})();
