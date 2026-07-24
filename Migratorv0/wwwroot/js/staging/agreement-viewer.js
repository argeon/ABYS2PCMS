(function () {
    const API = '/api/staging/agreement';
    const TAHAKKUK_KINDS = new Set(['MAIN', 'GECIKME', 'ARTTIRAN']);

    const INV_KIND_LABELS = {
        MAIN: 'Tüketim Tahakkuku',
        GECIKME: 'Gecikme Zammı',
        ARTTIRAN: 'Arttıran Tahakkuk',
        TAHSILAT: 'Tahsilat Faturası',
        IADE: 'İade Faturası (IADE FATURASI)'
    };

    let state = { payload: null, expandedL1: new Set(), expandedL2: new Set() };

    function connStr() {
        const host = document.getElementById('oracleHost').value.trim();
        const port = document.getElementById('oraclePort').value.trim() || '1521';
        const service = document.getElementById('oracleService').value.trim();
        const user = document.getElementById('oracleUser').value.trim();
        const password = document.getElementById('oraclePassword').value;
        return `User Id=${user};Password=${password};Data Source=${host}:${port}/${service};`;
    }

    function requestBody() {
        return {
            oracleConnectionString: connStr(),
            stagingSchema: document.getElementById('stagingSchema').value.trim() || 'SMS_AUDIT',
            agreementId: parseInt(document.getElementById('agrId').value, 10) || 0
        };
    }

    function fmtNum(v) {
        if (v == null || v === '') return '—';
        const n = Number(v);
        if (Number.isNaN(n)) return String(v);
        return n.toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    function fmtInt(v) {
        if (v == null) return '0';
        return Number(v).toLocaleString('tr-TR');
    }

    function num(v) {
        const n = Number(v);
        return Number.isNaN(n) ? 0 : n;
    }

    function energyCfg() {
        const nr = (document.getElementById('energyNr')?.value || '001').trim() || '001';
        const period = (document.getElementById('energyPeriod')?.value || '01').trim() || '01';
        return { nr, period, prefix: `energy.dbo.LS_${nr}_${period}` };
    }

    function sqlStr(v) {
        if (v == null || v === '') return 'NULL';
        return `'${String(v).replace(/'/g, "''")}'`;
    }

    function sqlNum(v) {
        if (v == null || v === '') return 'NULL';
        const n = Number(v);
        return Number.isNaN(n) ? 'NULL' : String(n);
    }

    function sqlDate(v) {
        if (v == null || v === '') return 'NULL';
        const s = String(v).trim();
        if (!s) return 'NULL';
        if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return `'${s} 00:00:00.000'`;
        return sqlStr(s);
    }

    function insertLine(table, cols, vals) {
        return `INSERT INTO ${table} (${cols.join(', ')})\nVALUES (${vals.join(', ')});`;
    }

    function invoiceByLref(payload, lref) {
        return (payload.invoices || []).find(r => String(val(r, 'LREF')) === String(lref));
    }

    function buildInsertSql(payload) {
        const { prefix } = energyCfg();
        const lines = [];
        const agrId = payload.summary?.agreementId ?? '';

        lines.push('-- =================================================================');
        lines.push(`-- PCMS INSERT önizleme | AGREEMENT_ID=${agrId} | ${new Date().toISOString()}`);
        lines.push(`-- Hedef: ${prefix}_*`);
        lines.push('-- Staging -> MSSQL; IDENTITY/DBCC CHECKIDENT çalıştırmadan önce doğrulayın.');
        lines.push('-- =================================================================');
        lines.push('USE energy;');
        lines.push('GO');
        lines.push('');

        lines.push(`-- ---------- ${prefix}_INVOICE (${(payload.invoices || []).length} satır) ----------`);
        (payload.invoices || []).forEach(inv => {
            const kind = String(val(inv, 'INV_KIND') || '').toUpperCase();
            const ownerRef = val(inv, 'OWNERREF') ?? val(inv, 'SRC_AGREEMENT_ID');
            const clientRef = val(inv, 'CLIENTREF') ?? ownerRef;
            const cols = ['LREF', 'IOCODE', 'FICHENO', 'DATE_', 'DUEDATE', 'TYPE', 'CLIENTREF', 'TLTOTAL', 'TAX', 'GRANDTOTAL', 'PAYABLETOTAL', 'EXPLAIN', 'CANCELED', 'OWNERREF', 'OWNERTYPE', 'FITNO', 'CLOSED'];
            const vals = [
                sqlNum(val(inv, 'LREF')),
                sqlNum(val(inv, 'IOCODE')),
                kind === 'TAHSILAT' ? sqlStr('TAHSİLAT') : 'NULL',
                sqlDate(val(inv, 'DATE_')),
                sqlDate(val(inv, 'DATE_')),
                sqlNum(val(inv, 'INV_TYPE')),
                sqlNum(clientRef),
                sqlNum(val(inv, 'TLTOTAL')),
                sqlNum(val(inv, 'TAX')),
                sqlNum(val(inv, 'GRANDTOTAL')),
                sqlNum(val(inv, 'PAYABLETOTAL')),
                sqlStr(val(inv, 'EXPLAIN')),
                sqlNum(val(inv, 'CANCELED')),
                sqlNum(ownerRef),
                sqlNum(val(inv, 'OWNERTYPE') ?? 91),
                sqlNum(val(inv, 'FITNO')),
                sqlNum(val(inv, 'CLOSED'))
            ];
            if (val(inv, 'INVOICECROSSREF') != null) { cols.push('INVOICECROSSREF'); vals.push(sqlNum(val(inv, 'INVOICECROSSREF'))); }
            if (val(inv, 'RETURN_SOURCE_INVREF') != null) { cols.push('RETURN_SOURCE_INVREF'); vals.push(sqlNum(val(inv, 'RETURN_SOURCE_INVREF'))); }
            if (val(inv, 'RETURN_TARGET_INVREF') != null) { cols.push('RETURN_TARGET_INVREF'); vals.push(sqlNum(val(inv, 'RETURN_TARGET_INVREF'))); }
            if (val(inv, 'LAWDETAILREF') != null) { cols.push('LAWDETAILREF'); vals.push(sqlNum(val(inv, 'LAWDETAILREF'))); }
            lines.push(insertLine(`${prefix}_INVOICE`, cols, vals));
        });
        lines.push('');

        const activeLines = (payload.invLines || []).filter(il =>
            Number(val(il, 'SRC_INCOME_ID')) !== -1 && Number(val(il, 'CANCELED') || 0) !== 1);
        lines.push(`-- ---------- ${prefix}_INVLINES (${activeLines.length} satır) ----------`);
        activeLines.forEach(il => {
            const inv = invoiceByLref(payload, val(il, 'INVOICEREF'));
            const ownerRef = inv ? (val(inv, 'OWNERREF') ?? val(inv, 'SRC_AGREEMENT_ID')) : null;
            const clientRef = inv ? (val(inv, 'CLIENTREF') ?? ownerRef) : null;
            const amt = num(val(il, 'AMOUNT'));
            const cols = ['LREF', 'INVOICEREF', 'DATE_', 'LINETYPE', 'TRANSTYPE', 'TLTOTAL', 'GRANDTOTAL', 'PAYABLETOTAL', 'EXPLAIN', 'CLIENTREF', 'CLIENT_TYPE', 'IOCODE', 'CANCELED'];
            const vals = [
                sqlNum(val(il, 'LREF')),
                sqlNum(val(il, 'INVOICEREF')),
                inv ? sqlDate(val(inv, 'DATE_')) : 'NULL',
                sqlNum(val(il, 'LINE_TYPE')),
                sqlNum(val(il, 'TRANSTYPE')),
                sqlNum(amt),
                sqlNum(amt),
                sqlNum(amt),
                sqlStr(val(il, 'LINEEXP')),
                sqlNum(clientRef),
                sqlNum(91),
                sqlNum(0),
                sqlNum(val(il, 'CANCELED') ?? 0)
            ];
            lines.push(insertLine(`${prefix}_INVLINES`, cols, vals));
        });
        lines.push('');

        lines.push(`-- ---------- ${prefix}_PAYTRANS (${(payload.payTrans || []).length} satır) ----------`);
        (payload.payTrans || []).forEach(pt => {
            const cols = ['LREF', 'INVOICEREF', 'TYPE', 'IOCODE', 'CROSSREF', 'PAYTYPE', 'INST_NR', 'DATE_', 'PAYABLETOTAL', 'PAID', 'CANCELED'];
            const vals = [
                sqlNum(val(pt, 'LREF')),
                sqlNum(val(pt, 'INVOICEREF')),
                sqlNum(val(pt, 'PT_TYPE')),
                sqlNum(val(pt, 'IOCODE')),
                sqlNum(val(pt, 'CROSSREF')),
                sqlNum(val(pt, 'PAYTYPE')),
                sqlNum(val(pt, 'INST_NR')),
                sqlDate(val(pt, 'DATE_')),
                sqlNum(val(pt, 'PAYABLETOTAL')),
                sqlNum(val(pt, 'PAID')),
                sqlNum(val(pt, 'CANCELED'))
            ];
            lines.push(insertLine(`${prefix}_PAYTRANS`, cols, vals));
        });
        lines.push('');

        lines.push(`-- ---------- ${prefix}_PAYTRANS_INCOME (${(payload.payTransIncome || []).length} satır) ----------`);
        (payload.payTransIncome || []).forEach(pi => {
            const cols = ['LREF', 'PAYTRANSREF', 'LINENR', 'DEBT_INVOICEREF', 'DEBT_PAYTRANSREF', 'INCOME_AMOUNT', 'SRC_INCOME_ID'];
            const vals = [
                sqlNum(val(pi, 'LREF')),
                sqlNum(val(pi, 'PAYTRANSREF')),
                sqlNum(val(pi, 'LINENR')),
                sqlNum(val(pi, 'DEBT_INVOICEREF')),
                sqlNum(val(pi, 'DEBT_PAYTRANSREF')),
                sqlNum(val(pi, 'INCOME_AMOUNT')),
                sqlNum(val(pi, 'SRC_INCOME_ID'))
            ];
            lines.push(insertLine(`${prefix}_PAYTRANS_INCOME`, cols, vals));
        });
        lines.push('');

        lines.push(`-- ---------- ${prefix}_SPEFEE (${(payload.speFee || []).length} satır) ----------`);
        (payload.speFee || []).forEach(sp => {
            const cols = ['LREF', 'INVOICEREF', 'INVLINEREF', 'LINEEXP', 'TLTOTAL', 'GRANDTOTAL', 'STATUS', 'SRC_INCOME_ID', 'SOURCE_ORACLE_INCOME_ID'];
            const vals = [
                sqlNum(val(sp, 'LREF')),
                sqlNum(val(sp, 'INVOICEREF')),
                sqlNum(val(sp, 'INVLINEREF')),
                sqlStr(val(sp, 'LINEEXP')),
                sqlNum(val(sp, 'GRANDTOTAL')),
                sqlNum(val(sp, 'GRANDTOTAL')),
                sqlNum(val(sp, 'STATUS') ?? 2),
                sqlNum(val(sp, 'SRC_INCOME_ID')),
                sqlNum(val(sp, 'SOURCE_ORACLE_INCOME_ID'))
            ];
            lines.push(insertLine(`${prefix}_SPEFEE`, cols, vals));
        });
        lines.push('');

        lines.push(`-- ---------- ${prefix}_ADVANCE_LEDGER (${(payload.advanceLedger || []).length} satır) ----------`);
        (payload.advanceLedger || []).forEach(led => {
            const cols = ['LREF', 'DIRECTION', 'AMOUNT', 'STATUS_NET', 'TRANS_DATE', 'ACTION_TYPE', 'CAUSE_CODE',
                'SRC_AGREEMENT_ID', 'SRC_REGISTER_ID', 'PARENT_LREF', 'REF_ACC_ID', 'REF_ACT_ID', 'CANCELED',
                'SOURCE_ORACLE_ACCOUNT_ID', 'SOURCE_ORACLE_ACTION_ID'];
            const vals = [
                sqlNum(val(led, 'LREF')),
                sqlNum(val(led, 'DIRECTION')),
                sqlNum(val(led, 'AMOUNT')),
                sqlNum(val(led, 'STATUS_NET')),
                sqlDate(val(led, 'TRANS_DATE')),
                sqlNum(val(led, 'SOURCE_ACTION_TYPE')),
                sqlNum(val(led, 'CAUSE_CODE')),
                sqlNum(val(led, 'SRC_AGREEMENT_ID')),
                sqlNum(val(led, 'SRC_REGISTER_ID')),
                sqlNum(val(led, 'PARENT_LREF')),
                sqlNum(val(led, 'REF_ACC_ID')),
                sqlNum(val(led, 'REF_ACT_ID')),
                sqlNum(val(led, 'CANCELED')),
                sqlNum(val(led, 'SOURCE_ORACLE_ACCOUNT_ID')),
                sqlNum(val(led, 'SOURCE_ORACLE_ACTION_ID'))
            ];
            lines.push(insertLine(`${prefix}_ADVANCE_LEDGER`, cols, vals));
        });
        lines.push('');

        lines.push(`-- ---------- ${prefix}_ADV_LEDGER_INCOME (${(payload.advanceLedgerIncome || []).length} satır) ----------`);
        (payload.advanceLedgerIncome || []).forEach(li => {
            const cols = ['LREF', 'LEDGER_LREF', 'DIRECTION', 'SRC_INCOME_ID', 'AMOUNT',
                'SOURCE_ORACLE_ACCOUNT_ID', 'SOURCE_ORACLE_ACTION_ID', 'SOURCE_ORACLE_INCOME_ID'];
            const vals = [
                sqlNum(val(li, 'LREF')),
                sqlNum(val(li, 'LEDGER_LREF')),
                sqlNum(val(li, 'DIRECTION')),
                sqlNum(val(li, 'SRC_INCOME_ID')),
                sqlNum(val(li, 'AMOUNT')),
                sqlNum(val(li, 'SOURCE_ORACLE_ACCOUNT_ID')),
                sqlNum(val(li, 'SOURCE_ORACLE_ACTION_ID')),
                sqlNum(val(li, 'SOURCE_ORACLE_INCOME_ID'))
            ];
            lines.push(insertLine(`${prefix}_ADV_LEDGER_INCOME`, cols, vals));
        });

        return lines.join('\n');
    }

    function renderInsertSql() {
        const panel = document.getElementById('insertSqlPanel');
        const targetLbl = document.getElementById('insertSqlTarget');
        const { prefix } = energyCfg();
        if (targetLbl) targetLbl.textContent = `${prefix}_*`;
        if (!panel) return;
        if (!state.payload) {
            panel.textContent = 'Sözleşme yükleyin.';
            return;
        }
        panel.textContent = buildInsertSql(state.payload);
    }

    function val(row, key) {
        if (!row) return null;
        const k = Object.keys(row).find(x => x.toLowerCase() === key.toLowerCase());
        return k ? row[k] : null;
    }

    function escapeHtml(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    function invKindLabel(kind) {
        const k = String(kind || '').toUpperCase();
        return INV_KIND_LABELS[k] || k;
    }

    function setStatus(msg, isErr) {
        const el = document.getElementById('loadStatus');
        el.textContent = msg;
        el.className = 'small mt-2 ' + (isErr ? 'text-danger' : 'text-success');
    }

    async function post(url, body) {
        const res = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        return res.json();
    }

    function renderTable(tableId, rows, columns, rowClassFn, onRowClick) {
        const table = document.getElementById(tableId);
        if (!table) return;
        const thead = table.querySelector('thead');
        const tbody = table.querySelector('tbody');
        thead.innerHTML = '<tr>' + columns.map(c => `<th class="${c.numeric ? 'text-end-num' : ''}">${c.label}</th>`).join('') + '</tr>';
        if (!rows.length) {
            tbody.innerHTML = `<tr><td colspan="${columns.length}" class="text-muted p-3">Kayıt yok</td></tr>`;
            return;
        }
        tbody.innerHTML = rows.map((row, idx) => {
            const cls = rowClassFn ? rowClassFn(row) : '';
            return `<tr data-idx="${idx}" class="${cls}">` +
                columns.map(c => {
                    const v = c.render ? c.render(row) : val(row, c.key);
                    const tdCls = c.numeric ? 'text-end-num' : '';
                    return `<td class="${tdCls}">${v == null ? '' : escapeHtml(String(v))}</td>`;
                }).join('') +
                '</tr>';
        }).join('');

        if (onRowClick) {
            tbody.querySelectorAll('tr[data-idx]').forEach(tr => {
                tr.style.cursor = 'pointer';
                tr.addEventListener('click', () => {
                    const idx = parseInt(tr.dataset.idx, 10);
                    onRowClick(rows[idx], tr);
                });
            });
        }
    }

    function getDebtPtForInvoice(inv) {
        const lref = val(inv, 'LREF');
        return state.payload.payTrans.find(r =>
            String(val(r, 'PT_KIND')).toUpperCase() === 'ACCRUE' &&
            String(val(r, 'INVOICEREF')) === String(lref));
    }

    function getInvoiceBalance(inv) {
        const pt = getDebtPtForInvoice(inv);
        if (!pt) return { paid: 0, balance: num(val(inv, 'PAYABLETOTAL')), payable: num(val(inv, 'PAYABLETOTAL')) };
        const payable = num(val(pt, 'PAYABLETOTAL'));
        const paid = num(val(pt, 'PAID'));
        return { paid, balance: Math.max(0, payable - paid), payable };
    }

    function getMahsupRowsForDebtPt(debtPtLref) {
        const pool = state.payload.mahsupPool || [];
        return pool.filter(r =>
            String(val(r, 'DURUM')).toUpperCase() === 'ESLESTI' &&
            String(val(r, 'TARGET_DEBT_PT')) === String(debtPtLref));
    }

    /** Inline SVG icons (Bootstrap Icons paths) — no CDN dependency. */
    const ICO = {
        eksilten: '<svg class="inv-ico" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 3a5 5 0 1 1-4.546 2.914.5.5 0 0 0-.908-.417A6 6 0 1 0 8 2z"/><path fill="currentColor" d="M8 4.466V.534a.25.25 0 0 0-.41-.212L5.23 2.308a.25.25 0 0 0 0 .424l2.36 1.986A.25.25 0 0 0 8 4.466"/></svg>',
        mahsup: '<svg class="inv-ico" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" fill-rule="evenodd" d="M1 11.5a.5.5 0 0 0 .5.5h11.793l-3.147 3.146a.5.5 0 0 0 .708.708l4-4a.5.5 0 0 0 0-.708l-4-4a.5.5 0 0 0-.708.708L13.293 11H1.5a.5.5 0 0 0-.5.5m14-7a.5.5 0 0 1-.5.5H2.707l3.147 3.146a.5.5 0 1 1-.708.708l-4-4a.5.5 0 0 1 0-.708l4-4a.5.5 0 1 1 .708.708L2.707 4H14.5a.5.5 0 0 1 .5.5"/></svg>',
        iade: '<svg class="inv-ico" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 15A7 7 0 1 1 8 1a7 7 0 0 1 0 14m0 1A8 8 0 1 0 8 0a8 8 0 0 0 0 16"/><path fill="currentColor" d="M4.646 4.646a.5.5 0 0 1 .708 0L8 7.293l2.646-2.647a.5.5 0 0 1 .708.708L8.707 8l2.647 2.646a.5.5 0 0 1-.708.708L8 8.707l-2.646 2.647a.5.5 0 0 1-.708-.708L7.293 8 4.646 5.354a.5.5 0 0 1 0-.708"/></svg>',
        taksit: '<svg class="inv-ico" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M14 3a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM2 2a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2z"/><path fill="currentColor" d="M2 5.5a.5.5 0 0 1 .5-.5h11a.5.5 0 0 1 0 1h-11a.5.5 0 0 1-.5-.5m0 2a.5.5 0 0 1 .5-.5h6a.5.5 0 0 1 0 1h-6a.5.5 0 0 1-.5-.5m0 2a.5.5 0 0 1 .5-.5h6a.5.5 0 0 1 0 1h-6a.5.5 0 0 1-.5-.5"/></svg>'
    };

    function iconBadge(kind, title, label) {
        const map = {
            eksilten: { cls: 'inv-badge-eksilten', ico: ICO.eksilten },
            mahsup: { cls: 'inv-badge-mahsup', ico: ICO.mahsup },
            iade: { cls: 'inv-badge-iade', ico: ICO.iade },
            taksit: { cls: 'inv-badge-taksit', ico: ICO.taksit }
        };
        const m = map[kind];
        if (!m) return '';
        return `<span class="inv-badge ${m.cls}" title="${escapeHtml(title)}">${m.ico}<span class="inv-badge-lbl">${escapeHtml(label)}</span></span>`;
    }

    function getInvoiceFlags(inv) {
        const p = state.payload;
        const lref = String(val(inv, 'LREF'));
        const accId = String(val(inv, 'SOURCE_ORACLE_ACCOUNT_ID'));
        const debtPt = getDebtPtForInvoice(inv);
        const debtPtLref = debtPt ? String(val(debtPt, 'LREF')) : null;

        const mahsupRows = debtPtLref ? getMahsupRowsForDebtPt(debtPtLref) : [];
        const hasMahsup = mahsupRows.length > 0
            || (!(p.mahsupPool || []).length && (p.payTrans || []).some(r =>
                String(val(r, 'PT_KIND')).toUpperCase() === 'PAYMENT'
                && Number(val(r, 'SRC_ACTION_TYPE')) === 12
                && String(val(r, 'CROSSREF')) === debtPtLref));

        const hasIadeLink = !!val(inv, 'RETURN_TARGET_INVREF')
            || (p.invoices || []).some(r =>
                String(val(r, 'INV_KIND')).toUpperCase() === 'IADE'
                && String(val(r, 'RETURN_SOURCE_INVREF')) === lref);

        const hasEksiltenLine = (p.invLines || []).some(r =>
            String(val(r, 'INVOICEREF')) === lref
            && /EKSILTEN/i.test(String(val(r, 'LINEEXP') || '')));

        const hasEksilten = hasIadeLink || hasEksiltenLine
            || String(val(inv, 'INV_KIND')).toUpperCase() === 'IADE';

        const hasTaksit = (p.installmentPlan || []).some(r =>
            String(val(r, 'POOL_ID')) === lref || String(val(r, 'POOL_ID')) === accId);

        const mahsupAmt = mahsupRows.reduce((s, r) => s + num(val(r, 'PAY_APPLIED')), 0);
        const eksKind = hasIadeLink
            ? (String(val(inv, 'INV_KIND')).toUpperCase() === 'IADE' ? 'IADE (ters kayıt)' : 'Tam eksilten (IADE)')
            : (hasEksiltenLine ? 'Kısmi eksilten' : 'Eksilten');

        return {
            hasMahsup,
            hasEksilten,
            hasIadeLink,
            hasTaksit,
            mahsupAmt,
            eksKind,
            mahsupCount: mahsupRows.length
        };
    }

    function renderInvoiceIcons(flags) {
        let html = '<span class="inv-badges">';
        if (flags.hasEksilten) {
            html += iconBadge('eksilten', flags.eksKind, flags.hasIadeLink ? 'IADE' : 'EKS');
        }
        if (flags.hasMahsup) {
            const t = flags.mahsupCount
                ? `Mahsup / emanet çıkışı (${flags.mahsupCount} satır, ${fmtNum(flags.mahsupAmt)} TL)`
                : 'Mahsup / emanet çıkışı';
            html += iconBadge('mahsup', t, 'MHŞ');
        }
        if (flags.hasTaksit) {
            html += iconBadge('taksit', 'Taksit planı bağlı', 'TKS');
        }
        html += '</span>';
        return html;
    }

    function getIslemlerForInvoice(inv) {
        const lref = val(inv, 'LREF');
        const debtPt = getDebtPtForInvoice(inv);
        const islemler = [];

        if (debtPt) {
            islemler.push({
                key: `accrue-${val(debtPt, 'LREF')}`,
                tur: 'TAHAKKUK',
                tarih: val(debtPt, 'DATE_') || val(inv, 'DATE_'),
                tutar: num(val(debtPt, 'PAYABLETOTAL')),
                paid: num(val(debtPt, 'PAID')),
                row: debtPt,
                kind: 'accrue',
                gelirSource: 'invlines',
                gelirRef: lref
            });
        }

        const debtPtLref = debtPt ? String(val(debtPt, 'LREF')) : null;
        if (debtPtLref) {
            state.payload.payTrans
                .filter(r => String(val(r, 'PT_KIND')).toUpperCase() === 'PAYMENT' &&
                    String(val(r, 'CROSSREF')) === debtPtLref &&
                    Number(val(r, 'SRC_ACTION_TYPE')) !== 12)
                .forEach(pt => {
                    islemler.push({
                        key: `pay-${val(pt, 'LREF')}`,
                        tur: 'TAHSİLAT',
                        tarih: val(pt, 'DATE_'),
                        tutar: -num(val(pt, 'PAYABLETOTAL')),
                        paid: 0,
                        row: pt,
                        kind: 'payment',
                        gelirSource: 'payincome',
                        gelirRef: val(pt, 'LREF')
                    });
                });

            getMahsupRowsForDebtPt(debtPtLref).forEach((poolRow, idx) => {
                const mahAct = val(poolRow, 'SOURCE_ORACLE_ACTION_ID');
                const srcAcc = val(poolRow, 'SOURCE_ORACLE_ACCOUNT_ID');
                const tgtAcc = val(poolRow, 'TARGET_ACCOUNT_ID');
                const pt = state.payload.payTrans.find(p => String(val(p, 'LREF')) === String(mahAct));
                const applied = num(val(poolRow, 'PAY_APPLIED'));
                islemler.push({
                    key: `mahsup-${mahAct}-${debtPtLref}-${idx}`,
                    tur: 'EMANET ÇIKIŞI',
                    tarih: pt ? val(pt, 'DATE_') : '',
                    tutar: -applied,
                    paid: 0,
                    row: pt || poolRow,
                    kind: 'mahsup',
                    gelirSource: 'payincome',
                    gelirRef: mahAct,
                    mahsupNote: `src hesap ${srcAcc} → ref ${tgtAcc || debtPtLref}`
                });
            });

            if (!(state.payload.mahsupPool || []).length) {
                state.payload.payTrans
                    .filter(r => String(val(r, 'PT_KIND')).toUpperCase() === 'PAYMENT' &&
                        Number(val(r, 'SRC_ACTION_TYPE')) === 12 &&
                        String(val(r, 'CROSSREF')) === debtPtLref)
                    .forEach(pt => {
                        islemler.push({
                            key: `pay-${val(pt, 'LREF')}`,
                            tur: 'MAHSUP TAHSİLATI',
                            tarih: val(pt, 'DATE_'),
                            tutar: -num(val(pt, 'PAYABLETOTAL')),
                            paid: 0,
                            row: pt,
                            kind: 'mahsup',
                            gelirSource: 'payincome',
                            gelirRef: val(pt, 'LREF')
                        });
                    });
            }
        }

        // Tam eksilten: bağlı IADE faturası işlem satırı olarak
        (state.payload.invoices || [])
            .filter(r => String(val(r, 'INV_KIND')).toUpperCase() === 'IADE'
                && String(val(r, 'RETURN_SOURCE_INVREF')) === String(lref))
            .forEach(iade => {
                islemler.push({
                    key: `iade-${val(iade, 'LREF')}`,
                    tur: 'EKSİLTEN / IADE',
                    tarih: val(iade, 'DATE_'),
                    tutar: -num(val(iade, 'PAYABLETOTAL')),
                    paid: 0,
                    row: iade,
                    kind: 'eksilten',
                    gelirSource: 'invlines',
                    gelirRef: val(iade, 'LREF')
                });
            });

        return islemler;
    }

    function getGelirSatirlari(islem) {
        if (islem.gelirSource === 'invlines') {
            return state.payload.invLines
                .filter(r => String(val(r, 'INVOICEREF')) === String(islem.gelirRef))
                .map(r => ({
                    kod: val(r, 'GELIR_KODU') || val(r, 'TRANSTYPE'),
                    adi: val(r, 'GELIR_ADI') || `Gelir ${val(r, 'TRANSTYPE')}`,
                    tutar: num(val(r, 'AMOUNT')),
                    bakiye: num(val(r, 'AMOUNT')),
                    neg: num(val(r, 'AMOUNT')) < 0
                }));
        }
        return state.payload.payTransIncome
            .filter(r => String(val(r, 'PAYTRANSREF')) === String(islem.gelirRef))
            .map(r => ({
                kod: val(r, 'SRC_INCOME_ID'),
                adi: `Gelir ${val(r, 'SRC_INCOME_ID')}`,
                tutar: num(val(r, 'INCOME_AMOUNT')),
                bakiye: 0
            }));
    }

    function renderNestedTree() {
        const wrap = document.getElementById('nestedInvoiceTree');
        const p = state.payload;
        if (!p) {
            wrap.innerHTML = '<p class="text-muted p-3 mb-0">Sözleşme yükleyin.</p>';
            return;
        }

        const tahakkuklar = p.invoices.filter(r => TAHAKKUK_KINDS.has(String(val(r, 'INV_KIND')).toUpperCase()));
        document.getElementById('invBadge').textContent = tahakkuklar.length;

        if (!tahakkuklar.length) {
            wrap.innerHTML = '<p class="text-muted p-3 mb-0">Tahakkuk kaydı yok.</p>';
            return;
        }

        let html = `<table class="table table-sm table-dark table-hover nested-grid mb-0">
            <thead><tr>
                <th></th>
                <th>Tahakkuk / İşlem</th>
                <th>Hesap</th>
                <th>Action</th>
                <th>Tarih</th>
                <th class="text-end-num">Tutar</th>
                <th class="text-end-num">Ödenen</th>
                <th class="text-end-num">Bakiye</th>
                <th>Durum</th>
            </tr></thead><tbody>`;

        tahakkuklar.forEach(inv => {
            const lref = val(inv, 'LREF');
            const l1Key = `l1-${lref}`;
            const bal = getInvoiceBalance(inv);
            const hasDebt = bal.balance > 0.01;
            const isOpen = val(inv, 'CLOSED') !== 1 && hasDebt;
            const islemler = getIslemlerForInvoice(inv);
            const flags = getInvoiceFlags(inv);
            const l1Open = state.expandedL1.has(l1Key);
            const flagCls = [
                flags.hasEksilten ? 'has-eksilten' : '',
                flags.hasMahsup ? 'has-mahsup' : ''
            ].filter(Boolean).join(' ');

            html += `<tr class="row-l1 ${isOpen ? 'row-open-debt' : ''} ${flagCls}" data-l1="${escapeHtml(l1Key)}">
                <td><button type="button" class="btn btn-outline-secondary btn-expand" data-expand-l1="${escapeHtml(l1Key)}">${l1Open ? '−' : '+'}</button></td>
                <td>
                    <span class="text-info">${escapeHtml(String(lref))}</span>
                    <span class="text-muted ms-1">${escapeHtml(invKindLabel(val(inv, 'INV_KIND')))}</span>
                    ${renderInvoiceIcons(flags)}
                    <div class="small text-secondary">${escapeHtml(val(inv, 'ACCRUE_TYPE_NAME') || '')}</div>
                    ${val(inv, 'EXPLAIN') ? `<div class="small text-info">${escapeHtml(val(inv, 'EXPLAIN'))}</div>` : ''}
                </td>
                <td>${escapeHtml(val(inv, 'SOURCE_ORACLE_ACCOUNT_ID'))}</td>
                <td>${escapeHtml(val(inv, 'SOURCE_ORACLE_ACTION_ID'))}</td>
                <td>${escapeHtml(val(inv, 'DATE_'))}</td>
                <td class="text-end-num">${fmtNum(val(inv, 'PAYABLETOTAL'))}</td>
                <td class="text-end-num">${fmtNum(bal.paid)}</td>
                <td class="text-end-num ${hasDebt ? 'text-warning' : ''}">${fmtNum(bal.balance)}</td>
                <td>${hasDebt ? '<span class="badge bg-danger">Borçlu</span>' : '<span class="badge bg-success">Kapalı</span>'}</td>
            </tr>`;

            if (l1Open) {
                const plans = (p.installmentPlan || []).filter(r =>
                    String(val(r, 'POOL_ID')) === String(lref) ||
                    String(val(r, 'POOL_ID')) === String(val(inv, 'SOURCE_ORACLE_ACCOUNT_ID')));
                if (plans.length) {
                    const byInst = new Map();
                    plans.forEach(r => {
                        const id = String(val(r, 'INSTALLMENT_ID'));
                        if (!byInst.has(id)) byInst.set(id, []);
                        byInst.get(id).push(r);
                    });
                    byInst.forEach((rows, instId) => {
                        rows.sort((a, b) => num(val(a, 'INST_NR')) - num(val(b, 'INST_NR')));
                        rows.forEach(r => {
                            const paid = val(r, 'PAYMENT_DATE') ? num(val(r, 'AMOUNT')) : 0;
                            const amt = num(val(r, 'AMOUNT'));
                            html += `<tr class="row-l2 row-l2-payment row-l2-taksit">
                                <td></td>
                                <td colspan="2">${iconBadge('taksit', 'Taksit', 'TKS')} <strong>TAKSİT</strong>
                                    <span class="text-muted ms-1">plan ${escapeHtml(instId)} / ${escapeHtml(val(r, 'INST_NR'))}</span>
                                    <div class="small text-secondary">Müşteri talebi taksitlendirme</div>
                                </td>
                                <td>${escapeHtml(val(r, 'PLAN_ROW_ID'))}</td>
                                <td>${escapeHtml(val(r, 'DUE_DATE'))}</td>
                                <td class="text-end-num">${fmtNum(amt)}</td>
                                <td class="text-end-num">${fmtNum(paid)}</td>
                                <td class="text-end-num">${fmtNum(Math.max(0, amt - paid))}</td>
                                <td>${val(r, 'PAYMENT_DATE') ? '<span class="badge bg-success">Ödendi</span>' : '<span class="badge bg-warning text-dark">Açık</span>'}</td>
                            </tr>`;
                        });
                    });
                }

                islemler.forEach(islem => {
                    const l2Key = islem.key;
                    const l2Open = state.expandedL2.has(l2Key);
                    let l2Cls = 'row-l2-payment';
                    let prefixIco = '';
                    if (islem.kind === 'accrue') l2Cls = 'row-l2-accrue';
                    else if (islem.kind === 'mahsup') {
                        l2Cls = 'row-l2-mahsup';
                        prefixIco = iconBadge('mahsup', islem.mahsupNote || 'Mahsup', 'MHŞ');
                    } else if (islem.kind === 'eksilten') {
                        l2Cls = 'row-l2-eksilten';
                        prefixIco = iconBadge('eksilten', 'Eksilten / İade', 'EKS');
                    }

                    html += `<tr class="row-l2 ${l2Cls}" data-l2="${escapeHtml(l2Key)}">
                        <td><button type="button" class="btn btn-outline-secondary btn-expand" data-expand-l2="${escapeHtml(l2Key)}">${l2Open ? '−' : '+'}</button></td>
                        <td colspan="2">${prefixIco}<strong>${escapeHtml(islem.tur)}</strong> <span class="text-muted">PT ${escapeHtml(val(islem.row, 'LREF') || val(islem.row, 'SOURCE_ORACLE_ACTION_ID') || '')}</span>${islem.mahsupNote ? `<span class="text-info ms-1 small">${escapeHtml(islem.mahsupNote)}</span>` : ''}</td>
                        <td>${escapeHtml(val(islem.row, 'SOURCE_ORACLE_ACTION_ID') || val(islem.row, 'LREF'))}</td>
                        <td>${escapeHtml(islem.tarih)}</td>
                        <td class="text-end-num">${fmtNum(islem.tutar)}</td>
                        <td class="text-end-num">${islem.kind === 'accrue' ? fmtNum(islem.paid) : '—'}</td>
                        <td class="text-end-num">—</td>
                        <td></td>
                    </tr>`;

                    if (l2Open) {
                        const gelirler = getGelirSatirlari(islem);
                        if (!gelirler.length) {
                            html += `<tr class="row-l3"><td></td><td colspan="8" class="text-muted">Gelir satırı yok</td></tr>`;
                        } else {
                            html += `<tr class="row-l3 nested-subtable"><td></td><td colspan="8" class="p-0">
                                <table class="table table-sm table-dark mb-0 nested-grid">
                                    <thead><tr>
                                        <th>Gelir Kodu</th><th>Gelir Adı</th>
                                        <th class="text-end-num">Tutar</th><th class="text-end-num">Bakiye</th>
                                    </tr></thead><tbody>`;
                            gelirler.forEach(g => {
                                const amtCls = g.neg ? 'text-warning' : '';
                                html += `<tr>
                                    <td>${escapeHtml(g.kod)}</td>
                                    <td>${escapeHtml(g.adi)}</td>
                                    <td class="text-end-num ${amtCls}">${fmtNum(g.tutar)}</td>
                                    <td class="text-end-num ${amtCls}">${fmtNum(g.bakiye)}</td>
                                </tr>`;
                            });
                            html += '</tbody></table></td></tr>';
                        }
                    }
                });

                if (!islemler.length) {
                    const gelirler = state.payload.invLines
                        .filter(r => String(val(r, 'INVOICEREF')) === String(lref))
                        .map(r => ({
                            kod: val(r, 'GELIR_KODU') || val(r, 'TRANSTYPE'),
                            adi: val(r, 'GELIR_ADI'),
                            tutar: num(val(r, 'AMOUNT')),
                            bakiye: num(val(r, 'AMOUNT')),
                            neg: num(val(r, 'AMOUNT')) < 0
                        }));
                    if (gelirler.length) {
                        html += `<tr class="row-l3 nested-subtable"><td></td><td colspan="8" class="p-0">
                            <table class="table table-sm table-dark mb-0 nested-grid">
                                <thead><tr><th>Gelir Kodu</th><th>Gelir Adı</th><th class="text-end-num">Tutar</th><th class="text-end-num">Bakiye</th></tr></thead><tbody>`;
                        gelirler.forEach(g => {
                            html += `<tr><td>${escapeHtml(g.kod)}</td><td>${escapeHtml(g.adi)}</td>
                                <td class="text-end-num">${fmtNum(g.tutar)}</td><td class="text-end-num">${fmtNum(g.bakiye)}</td></tr>`;
                        });
                        html += '</tbody></table></td></tr>';
                    }
                }
            }
        });

        html += '</tbody></table>';
        wrap.innerHTML = html;

        wrap.querySelectorAll('[data-expand-l1]').forEach(btn => {
            btn.addEventListener('click', e => {
                e.stopPropagation();
                const key = btn.dataset.expandL1;
                if (state.expandedL1.has(key)) state.expandedL1.delete(key);
                else state.expandedL1.add(key);
                renderNestedTree();
            });
        });
        wrap.querySelectorAll('[data-expand-l2]').forEach(btn => {
            btn.addEventListener('click', e => {
                e.stopPropagation();
                const key = btn.dataset.expandL2;
                if (state.expandedL2.has(key)) state.expandedL2.delete(key);
                else state.expandedL2.add(key);
                renderNestedTree();
            });
        });

        const openCount = tahakkuklar.filter(inv => getInvoiceBalance(inv).balance > 0.01).length;
        let eksCnt = 0, mahCnt = 0;
        tahakkuklar.forEach(inv => {
            const f = getInvoiceFlags(inv);
            if (f.hasEksilten) eksCnt++;
            if (f.hasMahsup) mahCnt++;
        });
        document.getElementById('invFooter').textContent =
            `Tahakkuk: ${tahakkuklar.length} | Borçlu: ${openCount} | Eksilten: ${eksCnt} | Mahsup: ${mahCnt} | Toplam: ${fmtNum(p.summary.invoiceGrandTotal)} TL`;
    }

    function updateSummary(s) {
        const badge = document.getElementById('debtBadge');
        const hasDebt = s.hasInvoiceDebt;
        badge.textContent = hasDebt ? 'BORÇ VAR' : 'BORÇ YOK';
        badge.className = 'badge ' + (hasDebt ? 'bg-danger' : 'bg-success');

        const kvDebt = document.getElementById('kvHasDebt');
        kvDebt.textContent = hasDebt ? 'EVET' : 'HAYIR';
        kvDebt.className = 'text-end fw-semibold ' + (hasDebt ? 'debt-yes' : 'debt-no');

        document.getElementById('kvTotalDebt').textContent = fmtNum(s.totalDebtBalance);
        document.getElementById('kvOpenDebt').textContent = fmtInt(s.openDebtCount);
        document.getElementById('kvTahakkuk').textContent = fmtInt(s.tahakkukCount);
        document.getElementById('kvPaidTah').textContent = `${fmtInt(s.paidTahakkukCount)} / ${fmtInt(s.tahakkukCount)}`;
        document.getElementById('kvPayment').textContent = fmtNum(s.paymentTotal);
        document.getElementById('kvLedgerCredit').textContent = fmtNum(s.ledgerCreditNet);
        document.getElementById('kvRecon').textContent = fmtInt(s.reconCount);
        renderAbysCompare(s);
    }

    function renderAbysCompare(s) {
        const panel = document.getElementById('abysComparePanel');
        const body = document.getElementById('abysCompareBody');
        if (!panel || !body || !s.abys) {
            if (panel) panel.style.display = 'none';
            return;
        }
        const a = s.abys;
        const rows = [
            ['Toplam Borç', a.toplamBorc, s.totalDebtBalance],
            ['Gecikmiş borç adedi', a.gecikmisBorcAdet, s.openDebtCount],
            ['Fatura adet', a.faturaAdet, s.tahakkukCount],
            ['Ödenmiş fatura', a.odenmisFaturaAdet, s.paidTahakkukCount],
            ['Depozito', a.depozitoTutar, null],
            ['Emanet', a.emanetTutar, s.ledgerCreditNet]
        ];
        body.innerHTML = rows.map(([label, abysVal, stgVal]) => {
            const diff = stgVal == null ? null : Number(stgVal) - Number(abysVal);
            const diffCls = diff != null && Math.abs(diff) > 0.02 ? 'text-warning' : 'text-success';
            const diffTxt = diff == null ? '—' : fmtNum(diff);
            return `<tr><td>${label}</td><td class="text-end-num">${fmtNum(abysVal)}</td>` +
                `<td class="text-end-num">${stgVal == null ? '—' : (Number.isInteger(stgVal) ? fmtInt(stgVal) : fmtNum(stgVal))}</td>` +
                `<td class="text-end-num ${diffCls}">${diffTxt}</td></tr>`;
        }).join('');
        panel.style.display = 'block';
    }

    function renderDetails() {
        const p = state.payload;
        if (!p) return;

        renderTable('tblPayTrans', p.payTrans, [
            { key: 'LREF', label: 'LREF' },
            { key: 'PT_KIND', label: 'Kind' },
            { key: 'INVOICEREF', label: 'InvRef' },
            { key: 'CROSSREF', label: 'CrossRef' },
            { key: 'INST_NR', label: 'Inst' },
            { key: 'PAYABLETOTAL', label: 'Tutar', numeric: true, render: r => fmtNum(val(r, 'PAYABLETOTAL')) },
            { key: 'PAID', label: 'PAID', numeric: true, render: r => fmtNum(val(r, 'PAID')) },
            { key: 'DATE_', label: 'Tarih' }
        ], r => {
            const k = String(val(r, 'PT_KIND')).toUpperCase();
            let c = k === 'ACCRUE' ? 'row-accrue' : 'row-payment';
            if (k === 'ACCRUE' && num(val(r, 'PAID')) > num(val(r, 'PAYABLETOTAL')) + 0.01) c += ' row-warn';
            return c;
        });

        renderTable('tblPayIncome', p.payTransIncome, [
            { key: 'PAYTRANSREF', label: 'PayPT' },
            { key: 'LINENR', label: '#' },
            { key: 'SRC_INCOME_ID', label: 'Gelir' },
            { key: 'INCOME_AMOUNT', label: 'Tutar', numeric: true, render: r => fmtNum(val(r, 'INCOME_AMOUNT')) },
            { key: 'DEBT_PAYTRANSREF', label: 'BorçPT' },
            { key: 'DEBT_INVOICEREF', label: 'BorçInv' }
        ]);

        renderTable('tblSpeFee', p.speFee, [
            { key: 'INVOICEREF', label: 'InvRef' },
            { key: 'INVLINEREF', label: 'InvLine' },
            { key: 'LINEEXP', label: 'Açıklama' },
            { key: 'SRC_INCOME_ID', label: '958/1929' },
            { key: 'GRANDTOTAL', label: 'Tutar', numeric: true, render: r => fmtNum(val(r, 'GRANDTOTAL')) },
            { key: 'SOURCE_ORACLE_ACTION_ID', label: 'Action' }
        ]);

        renderTable('tblLedger', p.advanceLedger, [
            { key: 'LREF', label: 'LREF' },
            { key: 'DIRECTION', label: 'Yön', render: r => num(val(r, 'DIRECTION')) === 1 ? 'Giriş' : 'Çıkış' },
            { key: 'AMOUNT', label: 'Tutar', numeric: true, render: r => fmtNum(val(r, 'AMOUNT')) },
            { key: 'STATUS_NET', label: 'Alacak', numeric: true, render: r => fmtNum(val(r, 'STATUS_NET')) },
            { key: 'TRANS_DATE', label: 'Tarih' },
            { key: 'SOURCE_ACTION_TYPE', label: 'ActionType' },
            { key: 'CAUSE_CODE', label: 'Cause' },
            { key: 'PARENT_LREF', label: 'Parent' },
            { key: 'SOURCE_ORACLE_ACTION_ID', label: 'Action' }
        ]);

        renderTable('tblLedgerIncome', p.advanceLedgerIncome || [], [
            { key: 'LEDGER_LREF', label: 'Ledger' },
            { key: 'SRC_INCOME_ID', label: 'Gelir' },
            { key: 'AMOUNT', label: 'Tutar', numeric: true, render: r => fmtNum(val(r, 'AMOUNT')) },
            { key: 'DIRECTION', label: 'Yön' },
            { key: 'SOURCE_ORACLE_INCOME_ID', label: 'SrcInc' }
        ]);

        renderTable('tblInstall', p.installmentPlan, [
            { key: 'INSTALLMENT_ID', label: 'Plan' },
            { key: 'INST_NR', label: 'Taksit' },
            { key: 'POOL_ID', label: 'Kaynak Hesap' },
            { key: 'AMOUNT', label: 'Tutar', numeric: true, render: r => fmtNum(val(r, 'AMOUNT')) },
            { key: 'DUE_DATE', label: 'Vade' },
            { key: 'PAYMENT_DATE', label: 'Ödeme' },
            { key: 'PAYMENT_ACTION_ID', label: 'CashAct' }
        ]);

        const installBadge = document.getElementById('installBadge');
        if (installBadge) installBadge.textContent = (p.installmentPlan || []).length;

        renderTable('tblRecon', p.reconDiff, [
            { key: 'SEVERITY', label: 'Sev' },
            { key: 'KATEGORI', label: 'Kategori' },
            { key: 'ACCOUNT_ID', label: 'Account ID' },
            { key: 'KAYNAK_NET', label: 'Kaynak', numeric: true, render: r => fmtNum(val(r, 'KAYNAK_NET')) },
            { key: 'STAGING_NET', label: 'Staging', numeric: true, render: r => fmtNum(val(r, 'STAGING_NET')) },
            { key: 'FARK', label: 'Fark', numeric: true, render: r => fmtNum(val(r, 'FARK')) },
            { key: 'SEBEP', label: 'Sebep' }
        ], r => {
            const s = String(val(r, 'SEVERITY')).toUpperCase();
            if (s === 'CRITICAL') return 'row-critical';
            if (s === 'WARN') return 'row-warn';
            return '';
        });

        renderInsertSql();
    }

    async function load() {
        setStatus('Yükleniyor...', false);
        document.getElementById('loadWarnings').textContent = '';
        state.expandedL1.clear();
        state.expandedL2.clear();

        const json = await post(`${API}/load`, requestBody());
        if (!json.success) {
            setStatus(json.error || 'Yükleme hatası', true);
            return;
        }

        state.payload = json.data;
        updateSummary(json.data.summary);
        if (json.data.warnings?.length)
            document.getElementById('loadWarnings').textContent = json.data.warnings.join(' | ');

        renderNestedTree();
        renderDetails();
        setStatus(`Sözleşme ${json.data.summary.agreementId} yüklendi — ${json.data.summary.tahakkukCount} tahakkuk`, false);
    }

    document.getElementById('btnLoad').addEventListener('click', load);
    document.getElementById('btnCopyInsertSql')?.addEventListener('click', async () => {
        const text = document.getElementById('insertSqlPanel')?.textContent || '';
        if (!text || text === 'Sözleşme yükleyin.') return;
        try {
            await navigator.clipboard.writeText(text);
            setStatus('INSERT SQL panoya kopyalandı.', false);
        } catch {
            setStatus('Kopyalama başarısız.', true);
        }
    });
    ['energyNr', 'energyPeriod'].forEach(id => {
        document.getElementById(id)?.addEventListener('input', () => {
            if (state.payload) renderInsertSql();
        });
    });
    document.getElementById('btnTest').addEventListener('click', async () => {
        const json = await post(`${API}/test`, requestBody());
        setStatus(json.message || json.error, !json.success);
    });
    document.getElementById('agrId').addEventListener('keydown', e => {
        if (e.key === 'Enter') load();
    });
})();
