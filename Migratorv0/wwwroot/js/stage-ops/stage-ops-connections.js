(() => {
  const el = (id) => document.getElementById(id);
  const alertBox = el('soAlert');
  let allProfiles = [];
  let profilesOracle = [];
  let profilesMssql = [];

  function showAlert(msg, kind) {
    if (!alertBox) return;
    if (!msg) { alertBox.hidden = true; return; }
    alertBox.hidden = false;
    alertBox.className = 'so-alert' + (kind === 'ok' ? ' so-alert-ok' : kind === 'warn' ? ' so-alert-warn' : '');
    alertBox.textContent = msg;
  }

  function escapeHtml(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function fillSelect(sel, profiles, emptyLabel) {
    sel.innerHTML = `<option value="">${emptyLabel || '— profil seç —'}</option>` +
      profiles.map(p => {
        const kind = p.connectionType === 'Migration' ? 'Wizard' : (p.connectionType || '');
        const label = `#${p.id} ${p.name || p.profileName || ''} · ${kind} · ${p.host || p.databaseName || p.serviceName || ''}`.trim();
        return `<option value="${p.id}">${escapeHtml(label)}</option>`;
      }).join('');
  }

  function renderStatus(st) {
    const box = el('connStatus');
    if (!box || !st) return;
    const chip = (ok, label) =>
      `<div class="so-stat"><div class="label">${label}</div><div class="value" style="font-size:1rem;color:${ok ? 'var(--so-ok)' : 'var(--so-danger)'}">${ok ? 'OK' : 'Eksik'}</div></div>`;
    box.innerHTML =
      chip(st.oracleCtas, 'CTAS Oracle') +
      chip(st.mssqlStage1, 'MSSQL Stage 1') +
      chip(st.mssqlStage2, 'MSSQL Stage 2') +
      chip(st.mssqlProd, 'PROD');
  }

  function parseConnParam(connectionString, ...keys) {
    if (!connectionString) return '';
    const wanted = new Set(keys.map(k => k.toLowerCase()));
    for (const part of String(connectionString).split(';')) {
      const trimmed = part.trim();
      if (!trimmed) continue;
      const idx = trimmed.indexOf('=');
      if (idx < 0) continue;
      const key = trimmed.slice(0, idx).trim().toLowerCase();
      if (wanted.has(key)) return trimmed.slice(idx + 1).trim();
    }
    return '';
  }

  function parseConfigJson(raw) {
    if (!raw || !String(raw).trim()) return null;
    try { return JSON.parse(raw); } catch { return null; }
  }

  function parseOracleDataSource(dataSource) {
    if (!dataSource) return {};
    const s = String(dataSource).replace(/^\/\//, '');
    const simple = s.match(/^([^:/]+)(?::(\d+))?\/(.+)$/);
    if (simple) return { host: simple[1], port: simple[2] || '1521', service: simple[3] };
    return {};
  }

  function profileHasOracle(p) {
    if (!p) return false;
    const t = (p.connectionType || '').toLowerCase();
    if (t === 'oracle') return true;
    const cfg = parseConfigJson(p.configJson);
    if (cfg?.oracleConnectionString || cfg?.OracleConnectionString || cfg?.oraclePassword) return true;
    if (p.connectionString && /User Id|Data Source/i.test(p.connectionString) && !/Initial Catalog|Database=/i.test(p.connectionString))
      return true;
    return !!(p.serviceName || (p.host && t === 'migration'));
  }

  function profileHasMssql(p) {
    if (!p) return false;
    const t = (p.connectionType || '').toLowerCase();
    if (t === 'mssql') return true;
    const cfg = parseConfigJson(p.configJson);
    if (cfg?.mssqlConnectionString || cfg?.MssqlConnectionString || cfg?.mssqlPassword || cfg?.mssqlHost) return true;
    if (p.connectionString && /Initial Catalog|Database=/i.test(p.connectionString)) return true;
    return !!(p.databaseName && t === 'migration');
  }

  function extractOraclePassword(p) {
    const fromCs = parseConnParam(p?.connectionString, 'Password', 'Pwd');
    if (fromCs) return fromCs;
    const cfg = parseConfigJson(p?.configJson);
    if (cfg?.oraclePassword) return cfg.oraclePassword;
    const oraCs = cfg?.oracleConnectionString || cfg?.OracleConnectionString;
    return parseConnParam(oraCs, 'Password', 'Pwd');
  }

  function extractMssqlPassword(p) {
    const fromCs = parseConnParam(p?.connectionString, 'Password', 'Pwd');
    if (fromCs) return fromCs;
    const cfg = parseConfigJson(p?.configJson);
    if (cfg?.mssqlPassword) return cfg.mssqlPassword;
    const msCs = cfg?.mssqlConnectionString || cfg?.MssqlConnectionString;
    return parseConnParam(msCs, 'Password', 'Pwd');
  }

  function resolveOracleOdp(p) {
    if (p?.connectionString && /User Id/i.test(p.connectionString) && !/Initial Catalog|Database=/i.test(p.connectionString))
      return p.connectionString;
    const cfg = parseConfigJson(p?.configJson);
    const fromCfg = cfg?.oracleConnectionString || cfg?.OracleConnectionString;
    if (fromCfg && /User Id/i.test(fromCfg)) return fromCfg;
    return '';
  }

  function buildSqlplusConnect(user, password, host, port, service) {
    if (!user || !password || !host || !service) return '';
    return `${user}/${password}@${host}:${port || '1521'}/${service}`;
  }

  async function fetchProfile(id) {
    const res = await fetch(`/api/History/profiles/${id}`);
    if (!res.ok) throw new Error(`Profil #${id} yüklenemedi`);
    return res.json();
  }

  function applyMssqlProfile(prefix, p) {
    if (!p) return { ok: false, reason: 'Profil yok' };
    const cfg = parseConfigJson(p.configJson);
    const cs = p.connectionString && /Initial Catalog|Database=/i.test(p.connectionString)
      ? p.connectionString
      : (cfg?.mssqlConnectionString || cfg?.MssqlConnectionString || p.connectionString || '');
    const server = p.host || parseConnParam(cs, 'Server', 'Data Source') || cfg?.mssqlHost || '';
    const database = p.databaseName || p.database || parseConnParam(cs, 'Database', 'Initial Catalog') || cfg?.mssqlDatabase || '';
    const user = p.username || parseConnParam(cs, 'User Id', 'UID', 'User') || cfg?.mssqlUsername || '';
    const integ = parseConnParam(cs, 'Integrated Security');
    const authType = p.authType || cfg?.mssqlAuthType ||
      (integ && /^(true|yes|sspi)$/i.test(integ) ? 'Windows' : 'Sql');
    const password = extractMssqlPassword({ ...p, connectionString: cs });

    el(prefix + 'Server').value = server;
    el(prefix + 'Database').value = database || el(prefix + 'Database').value;
    el(prefix + 'User').value = user;
    el(prefix + 'Auth').value = (authType === 'Windows' || authType === 'Integrated') ? 'Windows' : 'Sql';
    el(prefix + 'Password').value = password;
    el(prefix + 'Password').placeholder = password ? 'Profilden yüklendi' : 'Profilde şifre yok — elle girin';

    if (!server) return { ok: false, reason: 'Server bulunamadı' };
    return { ok: true, hasPassword: !!password };
  }

  function applyOracleProfile(p) {
    if (!p) return { ok: false, reason: 'Profil yok' };
    const odp = resolveOracleOdp(p);
    if (odp) el('oraOdp').value = odp;

    const cs = odp || p.connectionString || '';
    const cfg = parseConfigJson(p.configJson);
    const ds = parseOracleDataSource(parseConnParam(cs, 'Data Source'));
    const host = p.host || ds.host || '';
    const port = p.port || ds.port || '1521';
    const service = p.serviceName || ds.service || '';
    const user = p.username || parseConnParam(cs, 'User Id', 'UID') || '';
    const password = extractOraclePassword({ ...p, connectionString: cs || cfg?.oracleConnectionString });
    const sqlplus = buildSqlplusConnect(user, password, host, port, service);

    if (sqlplus) {
      el('oraSqlplus').value = sqlplus;
      return { ok: true, hasPassword: true };
    }
    if (user && host && service) {
      el('oraSqlplus').value = `${user}/<PASSWORD>@${host}:${port}/${service}`;
      return { ok: false, reason: 'Şifre profilde yok — sqlplus satırına yazın' };
    }
    return { ok: false, reason: 'Oracle user/host/service çıkarılamadı' };
  }

  function profileNameById(id, list) {
    const p = list.find(x => x.id === id);
    return p ? (p.name || p.profileName || '') : null;
  }

  async function loadProfiles() {
    try {
      const res = await fetch('/api/History/profiles?limit=200');
      const data = await res.json();
      allProfiles = Array.isArray(data) ? data : [];
      profilesOracle = allProfiles.filter(profileHasOracle);
      profilesMssql = allProfiles.filter(profileHasMssql);
      fillSelect(el('oraProfile'), profilesOracle, '— Oracle / Wizard profil —');
      fillSelect(el('s1Profile'), profilesMssql, '— MSSQL / Wizard profil —');
      fillSelect(el('s2Profile'), profilesMssql, '— MSSQL / Wizard profil —');
      fillSelect(el('prodProfile'), profilesMssql, '— MSSQL / Wizard profil —');

      if (!allProfiles.length) {
        showAlert('Kayıtlı profil yok. Wizard veya Admin → Profiller’den ekleyin, ya da alanları elle doldurun.', 'warn');
      } else if (!profilesOracle.length && !profilesMssql.length) {
        showAlert(`${allProfiles.length} profil var ama Oracle/MSSQL içeriği bulunamadı.`, 'warn');
      }
    } catch (e) {
      showAlert('Profiller yüklenemedi: ' + (e.message || e), 'err');
    }
  }

  async function loadConnections() {
    const data = await (await fetch('/api/stage-ops/connections')).json();
    const c = data.connections;
    renderStatus(data.status);

    el('oraSqlplus').value = c.oracleCtas?.sqlplusConnect || '';
    el('oraOdp').value = '';
    el('oraOdp').placeholder = c.oracleCtas?.odpConfigured ? '*** kayıtlı — değiştirmek için yeni yazın' : 'User Id=...;Password=...;Data Source=...';
    if (c.oracleCtas?.profileId) el('oraProfile').value = String(c.oracleCtas.profileId);

    const s1 = c.mssqlStage1 || {};
    el('s1Server').value = s1.server || '';
    el('s1Database').value = s1.database || 'izgazMGR';
    el('s1User').value = s1.user || '';
    el('s1Auth').value = s1.authType || 'Sql';
    el('s1Password').value = '';
    el('s1Password').placeholder = s1.passwordConfigured ? '*** kayıtlı — boş bırakınca aynı kalır' : 'Password';
    if (s1.profileId) el('s1Profile').value = String(s1.profileId);

    const s2 = c.mssqlStage2 || {};
    el('s2Server').value = s2.server || '';
    el('s2Database').value = s2.database || 'energy';
    el('s2User').value = s2.user || '';
    el('s2Auth').value = s2.authType || 'Sql';
    el('s2Password').value = '';
    el('s2Password').placeholder = s2.passwordConfigured ? '*** kayıtlı — boş bırakınca aynı kalır' : 'Password';
    if (s2.profileId) el('s2Profile').value = String(s2.profileId);

    const prod = c.mssqlProd || {};
    el('prodServer').value = prod.server || '';
    el('prodDatabase').value = prod.database || '';
    el('prodUser').value = prod.user || '';
    el('prodAuth').value = prod.authType || 'Sql';
    el('prodPassword').value = '';
    el('prodPassword').placeholder = prod.passwordConfigured ? '*** kayıtlı — boş bırakınca aynı kalır' : 'Password';
    if (prod.profileId && el('prodProfile')) el('prodProfile').value = String(prod.profileId);
  }

  function collectBody() {
    const oraId = el('oraProfile').value ? parseInt(el('oraProfile').value, 10) : null;
    const s1Id = el('s1Profile').value ? parseInt(el('s1Profile').value, 10) : null;
    const s2Id = el('s2Profile').value ? parseInt(el('s2Profile').value, 10) : null;
    const prodId = el('prodProfile')?.value ? parseInt(el('prodProfile').value, 10) : null;

    return {
      oracleCtas: {
        sqlplusConnect: el('oraSqlplus').value.trim(),
        odpConnectionString: el('oraOdp').value.trim(),
        profileId: oraId,
        profileName: oraId ? profileNameById(oraId, profilesOracle) : null
      },
      mssqlStage1: {
        server: el('s1Server').value.trim(),
        database: el('s1Database').value.trim(),
        user: el('s1User').value.trim(),
        password: el('s1Password').value,
        authType: el('s1Auth').value,
        trustCert: true,
        profileId: s1Id,
        profileName: s1Id ? profileNameById(s1Id, profilesMssql) : null
      },
      mssqlStage2: {
        server: el('s2Server').value.trim(),
        database: el('s2Database').value.trim(),
        user: el('s2User').value.trim(),
        password: el('s2Password').value,
        authType: el('s2Auth').value,
        trustCert: true,
        profileId: s2Id,
        profileName: s2Id ? profileNameById(s2Id, profilesMssql) : null
      },
      mssqlProd: {
        server: el('prodServer').value.trim(),
        database: el('prodDatabase').value.trim(),
        user: el('prodUser').value.trim(),
        password: el('prodPassword').value,
        authType: el('prodAuth').value,
        trustCert: true,
        profileId: prodId,
        profileName: prodId ? profileNameById(prodId, profilesMssql) : null
      }
    };
  }

  async function applySelectedOracle() {
    const id = parseInt(el('oraProfile').value, 10);
    if (!id) { showAlert('Önce bir Oracle / Wizard profili seçin.', 'warn'); return; }
    try {
      const p = await fetchProfile(id);
      const r = applyOracleProfile(p);
      showAlert(r.ok ? 'Oracle profili uygulandı (şifre dahil).' : (r.reason || 'Eksik alan'), r.ok ? 'ok' : 'warn');
    } catch (e) {
      showAlert(e.message || String(e), 'err');
    }
  }

  async function applySelectedMssql(prefix, selectId) {
    const id = parseInt(el(selectId).value, 10);
    if (!id) { showAlert('Önce bir MSSQL / Wizard profili seçin.', 'warn'); return; }
    try {
      const p = await fetchProfile(id);
      const r = applyMssqlProfile(prefix, p);
      showAlert(r.ok
        ? (r.hasPassword ? `${prefix.toUpperCase()} profili uygulandı (şifre dahil).` : `${prefix.toUpperCase()} uygulandı — şifreyi kontrol edin.`)
        : (r.reason || 'Uygulanamadı'),
        r.ok ? 'ok' : 'warn');
    } catch (e) {
      showAlert(e.message || String(e), 'err');
    }
  }

  async function testSlot(slot, btn) {
    const body = collectBody();
    const payload = { slot };
    if (slot === 'oracleCtas') {
      payload.oracle = body.oracleCtas;
    } else if (slot === 'mssqlStage1') {
      payload.mssql = body.mssqlStage1;
    } else if (slot === 'mssqlStage2') {
      payload.mssql = body.mssqlStage2;
    } else if (slot === 'mssqlProd') {
      payload.mssql = body.mssqlProd;
    }

    const prev = btn?.textContent;
    if (btn) { btn.disabled = true; btn.textContent = 'Test…'; }
    try {
      const res = await fetch('/api/stage-ops/connections/test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      if (data.success) {
        showAlert(data.message || 'Bağlantı OK', 'ok');
        if (window.Swal) {
          Swal.fire({ icon: 'success', title: 'Bağlantı OK', text: data.message || '', background: '#121a2b', color: '#e8eef7' });
        }
      } else {
        showAlert(data.error || 'Test başarısız', 'err');
        if (window.Swal) {
          Swal.fire({ icon: 'error', title: 'Bağlantı hatası', text: data.error || '', background: '#121a2b', color: '#e8eef7' });
        }
      }
    } catch (e) {
      showAlert(e.message || String(e), 'err');
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = prev; }
    }
  }

  el('btnApplyOraProfile').addEventListener('click', applySelectedOracle);
  el('btnApplyS1').addEventListener('click', () => applySelectedMssql('s1', 's1Profile'));
  el('btnApplyS2').addEventListener('click', () => applySelectedMssql('s2', 's2Profile'));
  el('btnApplyProd')?.addEventListener('click', () => applySelectedMssql('prod', 'prodProfile'));

  // Select değişince otomatik uygula
  el('oraProfile').addEventListener('change', () => { if (el('oraProfile').value) applySelectedOracle(); });
  el('s1Profile').addEventListener('change', () => { if (el('s1Profile').value) applySelectedMssql('s1', 's1Profile'); });
  el('s2Profile').addEventListener('change', () => { if (el('s2Profile').value) applySelectedMssql('s2', 's2Profile'); });
  el('prodProfile')?.addEventListener('change', () => { if (el('prodProfile').value) applySelectedMssql('prod', 'prodProfile'); });

  el('btnTestOra')?.addEventListener('click', (ev) => testSlot('oracleCtas', ev.currentTarget));
  el('btnTestS1')?.addEventListener('click', (ev) => testSlot('mssqlStage1', ev.currentTarget));
  el('btnTestS2')?.addEventListener('click', (ev) => testSlot('mssqlStage2', ev.currentTarget));
  el('btnTestProd')?.addEventListener('click', (ev) => testSlot('mssqlProd', ev.currentTarget));

  el('connForm').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    try {
      const body = collectBody();
      if (!body.oracleCtas.sqlplusConnect) {
        showAlert('CTAS için sqlplus connect zorunlu (user/pass@host:port/SERVICE).', 'err');
        return;
      }
      if (body.oracleCtas.sqlplusConnect.includes('<PASSWORD>')) {
        showAlert('sqlplus satırındaki <PASSWORD> yerine gerçek şifreyi yazın.', 'err');
        return;
      }
      const r = await fetch('/api/stage-ops/connections', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const data = await r.json();
      if (!r.ok) throw new Error(data.error || r.statusText);
      renderStatus(data.status);
      showAlert(data.message || 'Kaydedildi', 'ok');
      if (window.Swal) {
        Swal.fire({ icon: 'success', title: 'Kaydedildi', text: 'CTAS / Stage1 / Stage2 bağlantıları güncellendi.', background: '#121a2b', color: '#e8eef7' });
      }
      await loadConnections();
    } catch (e) {
      showAlert(e.message || String(e), 'err');
    }
  });

  el('btnReloadConn').addEventListener('click', () => loadConnections());

  loadProfiles().then(loadConnections);
})();
