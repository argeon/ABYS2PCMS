(function () {
    let profiles = [];
    let selectedId = null;

    const els = {
        body: document.getElementById('profilesTableBody'),
        count: document.getElementById('profileCount'),
        search: document.getElementById('filterSearch'),
        type: document.getElementById('filterType'),
        deleted: document.getElementById('filterDeleted'),
        form: document.getElementById('profileForm'),
        formTitle: document.getElementById('formTitle'),
        deletedBadge: document.getElementById('formDeletedBadge'),
        meta: document.getElementById('formMeta'),
        id: document.getElementById('profileId'),
        name: document.getElementById('profileName'),
        connectionType: document.getElementById('connectionType'),
        authType: document.getElementById('authType'),
        host: document.getElementById('host'),
        port: document.getElementById('port'),
        serviceName: document.getElementById('serviceName'),
        databaseName: document.getElementById('databaseName'),
        username: document.getElementById('username'),
        schemaName: document.getElementById('schemaName'),
        trustCert: document.getElementById('trustCert'),
        connectionString: document.getElementById('connectionString'),
        configJson: document.getElementById('configJsonEditor'),
        btnSave: document.getElementById('btnSaveProfile'),
        btnSoftDelete: document.getElementById('btnSoftDelete'),
        btnRestore: document.getElementById('btnRestore'),
        btnClear: document.getElementById('btnClearForm'),
        btnRefresh: document.getElementById('btnRefreshProfiles'),
        btnFormatJson: document.getElementById('btnFormatJson')
    };

    function toast(icon, title) {
        if (window.Swal) {
            Swal.fire({ toast: true, position: 'top-end', icon, title, showConfirmButton: false, timer: 2200 });
        } else {
            alert(title);
        }
    }

    function typeBadge(p) {
        if (p.isWizard || p.connectionType === 'Migration') {
            return '<span class="badge badge-wizard">Wizard</span>';
        }
        if (p.connectionType === 'Oracle') {
            return '<span class="badge badge-oracle">Oracle</span>';
        }
        if (p.connectionType === 'MSSQL') {
            return '<span class="badge badge-mssql">MSSQL</span>';
        }
        return `<span class="badge text-bg-secondary">${escapeHtml(p.connectionType || '')}</span>`;
    }

    function targetCell(p) {
        const parts = [p.host, p.databaseName || p.serviceName, p.schemaName].filter(Boolean);
        return escapeHtml(parts.join(' / ') || '—');
    }

    function escapeHtml(s) {
        return String(s ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function filteredProfiles() {
        const q = (els.search.value || '').trim().toLowerCase();
        const type = els.type.value;
        const deletedMode = els.deleted.value;

        return profiles.filter(p => {
            if (deletedMode === 'active' && p.isDeleted) return false;
            if (deletedMode === 'deleted' && !p.isDeleted) return false;

            if (type === 'wizard') {
                if (!(p.isWizard || p.connectionType === 'Migration')) return false;
            } else if (type && p.connectionType !== type) {
                return false;
            }

            if (!q) return true;
            const hay = [
                p.name, p.host, p.databaseName, p.serviceName, p.schemaName, p.username, p.connectionType
            ].join(' ').toLowerCase();
            return hay.includes(q);
        });
    }

    function renderTable() {
        const rows = filteredProfiles();
        els.count.textContent = String(rows.length);

        if (!rows.length) {
            els.body.innerHTML = '<tr><td colspan="6" class="text-muted p-3">Kayıt yok</td></tr>';
            return;
        }

        els.body.innerHTML = rows.map(p => {
            const selected = p.id === selectedId ? 'table-active' : '';
            const deleted = p.isDeleted ? 'deleted-row' : '';
            return `<tr class="${selected} ${deleted}" data-id="${p.id}" style="cursor:pointer">
                <td>${p.id}</td>
                <td>${escapeHtml(p.name)}${p.isDeleted ? ' <span class="badge text-bg-secondary">silindi</span>' : ''}</td>
                <td>${typeBadge(p)}</td>
                <td class="small">${targetCell(p)}</td>
                <td class="small">${p.useCount ?? 0}</td>
                <td class="text-end">
                    <button type="button" class="btn btn-outline-light btn-sm py-0 px-2 btn-edit" data-id="${p.id}">Düzenle</button>
                </td>
            </tr>`;
        }).join('');
    }

    function clearForm() {
        selectedId = null;
        els.form.reset();
        els.id.value = '';
        els.configJson.value = '';
        els.formTitle.textContent = 'Profil düzenle';
        els.deletedBadge.classList.add('d-none');
        els.btnSoftDelete.classList.remove('d-none');
        els.btnRestore.classList.add('d-none');
        els.btnSave.disabled = false;
        els.meta.textContent = '';
        setFormDisabled(false);
        renderTable();
    }

    function setFormDisabled(disabled) {
        [
            els.name, els.connectionType, els.authType, els.host, els.port,
            els.serviceName, els.databaseName, els.username, els.schemaName,
            els.trustCert, els.connectionString, els.configJson, els.btnSave
        ].forEach(el => { el.disabled = disabled; });
    }

    function fillForm(p) {
        selectedId = p.id;
        els.id.value = String(p.id);
        els.name.value = p.name || '';
        els.connectionType.value = p.connectionType || 'Oracle';
        els.authType.value = p.authType || '';
        els.host.value = p.host || '';
        els.port.value = p.port || '';
        els.serviceName.value = p.serviceName || '';
        els.databaseName.value = p.databaseName || '';
        els.username.value = p.username || '';
        els.schemaName.value = p.schemaName || '';
        els.trustCert.checked = !!p.trustCert;
        els.connectionString.value = p.connectionString || '';
        els.configJson.value = formatJsonPretty(p.configJson || '');

        const kind = p.isWizard || p.connectionType === 'Migration' ? 'Wizard' : 'Profil';
        els.formTitle.textContent = `${kind} #${p.id}`;
        els.meta.textContent = [
            `Oluşturulma: ${formatDate(p.createdAt)}`,
            p.lastUsedAt ? `Son kullanım: ${formatDate(p.lastUsedAt)}` : null,
            p.deletedAt ? `Silinme: ${formatDate(p.deletedAt)}` : null
        ].filter(Boolean).join(' · ');

        if (p.isDeleted) {
            els.deletedBadge.classList.remove('d-none');
            els.btnSoftDelete.classList.add('d-none');
            els.btnRestore.classList.remove('d-none');
            setFormDisabled(true);
        } else {
            els.deletedBadge.classList.add('d-none');
            els.btnSoftDelete.classList.remove('d-none');
            els.btnRestore.classList.add('d-none');
            setFormDisabled(false);
        }

        renderTable();
    }

    function formatDate(v) {
        if (!v) return '—';
        try { return new Date(v).toLocaleString('tr-TR'); } catch { return String(v); }
    }

    function formatJsonPretty(raw) {
        if (!raw || !String(raw).trim()) return '';
        try { return JSON.stringify(JSON.parse(raw), null, 2); }
        catch { return String(raw); }
    }

    function parseConfigJson() {
        const raw = (els.configJson.value || '').trim();
        if (!raw) return null;
        try {
            JSON.parse(raw);
            return raw;
        } catch (e) {
            throw new Error('Config JSON geçersiz: ' + e.message);
        }
    }

    async function loadProfiles() {
        const mode = els.deleted.value;
        const includeDeleted = mode === 'deleted' || mode === 'all';
        const type = els.type.value;
        const params = new URLSearchParams({
            limit: '500',
            includeDeleted: includeDeleted ? 'true' : 'false'
        });
        if (type && type !== 'wizard') params.set('type', type);

        els.body.innerHTML = '<tr><td colspan="6" class="text-muted p-3">Yükleniyor…</td></tr>';
        try {
            const res = await fetch('/api/history/profiles?' + params.toString());
            profiles = await res.json();
            if (!Array.isArray(profiles)) profiles = [];
            renderTable();
            if (selectedId) {
                const current = profiles.find(p => p.id === selectedId);
                if (current) fillForm(current);
            }
        } catch (e) {
            els.body.innerHTML = `<tr><td colspan="6" class="text-danger p-3">${escapeHtml(e.message)}</td></tr>`;
        }
    }

    async function saveProfile(e) {
        e.preventDefault();
        const id = Number(els.id.value);
        if (!id) {
            toast('info', 'Önce listeden bir kayıt seçin');
            return;
        }

        let configJson;
        try {
            configJson = parseConfigJson();
        } catch (err) {
            toast('error', err.message);
            return;
        }

        const payload = {
            profileName: els.name.value.trim(),
            connectionType: els.connectionType.value,
            host: els.host.value.trim() || null,
            port: els.port.value.trim() || null,
            serviceName: els.serviceName.value.trim() || null,
            databaseName: els.databaseName.value.trim() || null,
            username: els.username.value.trim() || null,
            schemaName: els.schemaName.value.trim() || null,
            authType: els.authType.value.trim() || null,
            trustCert: els.trustCert.checked,
            connectionString: els.connectionString.value.trim() || null,
            configJson
        };

        try {
            const res = await fetch(`/api/history/profiles/${id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            const data = await res.json();
            if (!res.ok || data.success === false) {
                throw new Error(data.error || 'Kaydetme başarısız');
            }
            toast('success', 'Profil güncellendi');
            await loadProfiles();
            if (data.profile) fillForm(data.profile);
        } catch (err) {
            toast('error', err.message);
        }
    }

    async function softDelete() {
        const id = Number(els.id.value);
        if (!id) return;

        const confirm = window.Swal
            ? await Swal.fire({
                title: 'Soft delete?',
                text: 'Kayıt silinmiş olarak işaretlenecek; geri alınabilir.',
                icon: 'warning',
                showCancelButton: true,
                confirmButtonText: 'Sil',
                cancelButtonText: 'Vazgeç'
            })
            : { isConfirmed: window.confirm('Soft delete yapılsın mı?') };

        if (!confirm.isConfirmed) return;

        try {
            const res = await fetch(`/api/history/profiles/${id}`, { method: 'DELETE' });
            const data = await res.json();
            if (!res.ok || !data.success) throw new Error(data.error || 'Silme başarısız');
            toast('success', 'Soft delete uygulandı');
            clearForm();
            await loadProfiles();
        } catch (err) {
            toast('error', err.message);
        }
    }

    async function restore() {
        const id = Number(els.id.value);
        if (!id) return;

        try {
            const res = await fetch(`/api/history/profiles/${id}/restore`, { method: 'POST' });
            const data = await res.json();
            if (!res.ok || !data.success) throw new Error(data.error || 'Geri alma başarısız');
            toast('success', 'Profil geri alındı');
            await loadProfiles();
            if (data.profile) fillForm(data.profile);
        } catch (err) {
            toast('error', err.message);
        }
    }

    els.body.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-id]');
        if (!btn) return;
        const id = Number(btn.getAttribute('data-id'));
        const p = profiles.find(x => x.id === id);
        if (p) fillForm(p);
    });

    els.form.addEventListener('submit', saveProfile);
    els.btnSoftDelete.addEventListener('click', softDelete);
    els.btnRestore.addEventListener('click', restore);
    els.btnClear.addEventListener('click', clearForm);
    els.btnRefresh.addEventListener('click', loadProfiles);
    els.search.addEventListener('input', renderTable);
    els.type.addEventListener('change', loadProfiles);
    els.deleted.addEventListener('change', loadProfiles);
    els.btnFormatJson.addEventListener('click', () => {
        els.configJson.value = formatJsonPretty(els.configJson.value);
    });

    loadProfiles();
})();
