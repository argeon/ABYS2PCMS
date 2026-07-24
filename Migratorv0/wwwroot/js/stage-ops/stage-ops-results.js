(() => {
  const body = document.getElementById('resultsBody');
  const detail = document.getElementById('resultDetail');
  const events = document.getElementById('resultEvents');
  const filter = document.getElementById('filterSurface');
  if (!body) return;

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function st(s) { return `so-status so-st-${s || 'Ready'}`; }

  async function load() {
    const q = filter.value ? `?surface=${encodeURIComponent(filter.value)}&limit=100` : '?limit=100';
    const runs = await (await fetch('/api/stage-ops/results' + q)).json();
    if (!runs.length) {
      body.innerHTML = '<tr><td colspan="5" style="color:var(--so-muted);padding:1rem">Kayıt yok</td></tr>';
      return;
    }
    body.innerHTML = runs.map(r => `<tr data-id="${r.id}" style="cursor:pointer">
      <td>#${r.id}</td>
      <td>${esc(r.surface)}</td>
      <td><span class="${st(r.status)}">${esc(r.status)}</span></td>
      <td>${r.doneCount} / ${r.failedCount}</td>
      <td style="font-size:.78rem;color:var(--so-muted)">${new Date(r.startedAt).toLocaleString()}</td>
    </tr>`).join('');
    body.querySelectorAll('tr[data-id]').forEach(tr => {
      tr.addEventListener('click', () => show(parseInt(tr.dataset.id, 10)));
    });
  }

  async function show(id) {
    const data = await (await fetch(`/api/stage-ops/runs/${id}`)).json();
    document.getElementById('detailLabel').textContent = `Run #${id} · ${data.run.surface}`;
    const items = data.items || [];
    detail.innerHTML = items.length ? `<table class="so-table"><thead><tr>
      <th>Stage</th><th>Durum</th><th>Süre</th><th>Satır</th><th>Log</th>
    </tr></thead><tbody>${items.map(i => `<tr>
      <td>${esc(i.stageName)}<div style="font-size:.7rem;color:var(--so-muted)">${esc(i.stageId)}</div></td>
      <td><span class="${st(i.status)}">${esc(i.status)}</span></td>
      <td>${i.elapsedMs || 0} ms</td>
      <td>${i.rows ?? '—'}</td>
      <td>${i.logPath ? `<a class="so-btn so-btn-ghost" href="/api/stage-ops/runs/${id}/items/${i.id}/log">indir</a>` : '—'}</td>
    </tr>`).join('')}</tbody></table>` : '<div>Stage item yok</div>';

    const ev = (data.events || []).slice().reverse();
    events.innerHTML = ev.length
      ? ev.map(e => `<li class="${e.level === 'Error' ? 'err' : 'info'}">[${new Date(e.createdAt).toLocaleTimeString()}] ${esc(e.message)}</li>`).join('')
      : '<li>Olay yok</li>';
  }

  filter.addEventListener('change', load);
  document.getElementById('btnRefreshResults').addEventListener('click', load);
  load();
})();
