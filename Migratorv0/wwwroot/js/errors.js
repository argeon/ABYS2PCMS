// Error Analysis Page JavaScript

let allErrors = [];
let currentErrorId = null;
let errorTypeChart = null;
let errorTableChart = null;

const numberTr = new Intl.NumberFormat('tr-TR');
const CHART_COLORS = [
    '#dc3545', '#0d6efd', '#ffc107', '#198754', '#6f42c1',
    '#fd7e14', '#20c997', '#6610f2', '#0dcaf0', '#6c757d'
];

/** @param {number} n */
function formatMetric(n) {
    return numberTr.format(n);
}

function truncateLabel(s, max = 34) {
    if (s == null || s === '') return '(boş)';
    const t = String(s);
    return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

/** Çubuk üzerinde sayı göster (Chart.js plugin) */
const barValueLabelsPlugin = {
    id: 'barValueLabels',
    afterDatasetsDraw(chart) {
        const { ctx, data } = chart;
        const meta = chart.getDatasetMeta(0);
        if (!meta?.data?.length) return;
        ctx.save();
        ctx.font = '600 12px system-ui, "Segoe UI", sans-serif';
        ctx.fillStyle = '#343a40';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'bottom';
        data.datasets[0].data.forEach((value, i) => {
            const el = meta.data[i];
            if (!el || value === 0) return;
            const x = el.x;
            const y = el.y - 6;
            ctx.fillText(formatMetric(value), x, y);
        });
        ctx.restore();
    }
};

// Load errors on page load
document.addEventListener('DOMContentLoaded', () => {
    loadErrors();
    setupEventListeners();
});

function setupEventListeners() {
    document.getElementById('runFilter').addEventListener('change', filterErrors);
    document.getElementById('tableFilter').addEventListener('change', filterErrors);
    document.getElementById('errorTypeFilter').addEventListener('change', filterErrors);
    document.getElementById('resolvedFilter').addEventListener('change', filterErrors);
    document.getElementById('selectAll').addEventListener('change', toggleSelectAll);
}

async function loadErrors() {
    try {
        const response = await fetch('/api/errors');
        if (!response.ok) throw new Error('Failed to load errors');
        
        allErrors = await response.json();
        populateFilters();
        const filtered = getFilteredErrors();
        updateStats(filtered);
        displayErrors(filtered);
        updateCharts(filtered);
    } catch (error) {
        console.error('Error loading errors:', error);
        showError('Hatalar yüklenemedi: ' + error.message);
    }
}

/**
 * @param {typeof allErrors} errors
 */
function updateStats(errors) {
    const list = errors ?? allErrors;
    const total = list.length;
    const unresolved = list.filter(e => !e.resolved).length;
    const resolved = list.filter(e => e.resolved).length;
    const affectedTables = new Set(list.map(e => e.tableName).filter(Boolean)).size;
    const runCount = new Set(list.map(e => e.runId)).size;

    document.getElementById('totalErrors').textContent = formatMetric(total);
    document.getElementById('unresolvedErrors').textContent = formatMetric(unresolved);
    document.getElementById('resolvedErrors').textContent = formatMetric(resolved);
    document.getElementById('affectedTables').textContent = formatMetric(affectedTables);

    document.getElementById('totalErrorsSub').textContent = total
        ? `${formatMetric(runCount)} migration run`
        : 'Kayıt yok';

    document.getElementById('unresolvedErrorsSub').textContent = total
        ? `Toplamın %${((unresolved / total) * 100).toFixed(1)}'i açık`
        : '—';

    document.getElementById('resolvedErrorsSub').textContent = total
        ? `Toplamın %${((resolved / total) * 100).toFixed(1)}'i kapalı`
        : '—';

    const byTable = {};
    list.forEach(e => {
        if (e.tableName) byTable[e.tableName] = (byTable[e.tableName] || 0) + 1;
    });
    const top = Object.entries(byTable).sort((a, b) => b[1] - a[1])[0];
    document.getElementById('affectedTablesSub').textContent = top
        ? `En yoğun: ${truncateLabel(top[0], 28)} (${formatMetric(top[1])} hata)`
        : total ? 'Tablo adı yok' : '—';
}

function populateFilters() {
    const runFilter = document.getElementById('runFilter');
    const tableFilter = document.getElementById('tableFilter');
    const typeFilter = document.getElementById('errorTypeFilter');

    [runFilter, tableFilter, typeFilter].forEach(sel => {
        const first = sel.options[0];
        sel.innerHTML = '';
        sel.appendChild(first);
    });

    const runs = [...new Set(allErrors.map(e => e.runId))].sort((a, b) => Number(b) - Number(a));
    runs.forEach(runId => {
        const option = document.createElement('option');
        option.value = runId;
        option.textContent = `Run ${runId}`;
        runFilter.appendChild(option);
    });

    const tables = [...new Set(allErrors.map(e => e.tableName).filter(Boolean))].sort();
    tables.forEach(table => {
        const option = document.createElement('option');
        option.value = table;
        option.textContent = table;
        tableFilter.appendChild(option);
    });

    const types = [...new Set(allErrors.map(e => e.errorType))].sort();
    types.forEach(type => {
        const option = document.createElement('option');
        option.value = type;
        option.textContent = type;
        typeFilter.appendChild(option);
    });
}

function getFilteredErrors() {
    const runId = document.getElementById('runFilter').value;
    const table = document.getElementById('tableFilter').value;
    const errorType = document.getElementById('errorTypeFilter').value;
    const resolved = document.getElementById('resolvedFilter').value;

    let filtered = allErrors;
    if (runId) filtered = filtered.filter(e => e.runId == runId);
    if (table) filtered = filtered.filter(e => e.tableName === table);
    if (errorType) filtered = filtered.filter(e => e.errorType === errorType);
    if (resolved !== '') filtered = filtered.filter(e => e.resolved === (resolved === 'true'));
    return filtered;
}

function filterErrors() {
    const filtered = getFilteredErrors();
    updateStats(filtered);
    displayErrors(filtered);
    updateCharts(filtered);
}

function displayErrors(errors) {
    const tbody = document.getElementById('errorTableBody');
    tbody.innerHTML = '';
    
    if (errors.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="10" class="text-center text-muted">
                    <i class="fas fa-check-circle text-success"></i>
                    Hata bulunamadı
                </td>
            </tr>
        `;
        return;
    }
    
    errors.forEach(error => {
        const row = document.createElement('tr');
        row.className = error.resolved ? 'table-success' : 'table-danger';
        row.innerHTML = `
            <td><input type="checkbox" class="error-checkbox" data-id="${error.id}"></td>
            <td>${formatDateTime(error.occurredAt)}</td>
            <td><span class="badge bg-info">${error.runId}</span></td>
            <td>${error.tableName || '-'}</td>
            <td>${error.partitionId || '-'}</td>
            <td><span class="badge bg-warning text-dark">${error.errorType}</span></td>
            <td class="text-truncate" style="max-width: 220px;">${error.errorMessage}</td>
            <td>${error.retryAttempt}</td>
            <td>
                ${error.resolved 
                    ? '<span class="badge bg-success"><i class="fas fa-check"></i> Çözüldü</span>' 
                    : '<span class="badge bg-danger"><i class="fas fa-times"></i> Aktif</span>'}
            </td>
            <td>
                <button class="btn btn-sm btn-primary" onclick="showErrorDetail(${error.id})">
                    <i class="fas fa-eye"></i> Detay
                </button>
            </td>
        `;
        tbody.appendChild(row);
    });
}

/**
 * @param {typeof allErrors} errors
 */
function updateCharts(errors) {
    const list = errors ?? allErrors;

    if (errorTypeChart) {
        errorTypeChart.destroy();
        errorTypeChart = null;
    }
    if (errorTableChart) {
        errorTableChart.destroy();
        errorTableChart = null;
    }

    const ctx1 = document.getElementById('errorTypeChart').getContext('2d');
    const ctx2 = document.getElementById('errorTableChart').getContext('2d');

    if (!list.length) {
        errorTypeChart = new Chart(ctx1, {
            type: 'doughnut',
            data: {
                labels: ['Veri yok'],
                datasets: [{ data: [1], backgroundColor: ['#e9ecef'], borderWidth: 0 }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: { enabled: false }
                }
            }
        });
        errorTableChart = new Chart(ctx2, {
            type: 'bar',
            data: {
                labels: ['—'],
                datasets: [{ data: [0], backgroundColor: '#e9ecef' }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false }, tooltip: { enabled: false } },
                scales: {
                    x: { ticks: { font: { size: 12 } } },
                    y: { beginAtZero: true, max: 1, ticks: { font: { size: 12 } } }
                }
            }
        });
        return;
    }

    const errorTypes = {};
    list.forEach(e => {
        const k = e.errorType || '(tip yok)';
        errorTypes[k] = (errorTypes[k] || 0) + 1;
    });
    const typeKeys = Object.keys(errorTypes);
    const typeValues = Object.values(errorTypes);
    const typeTotal = typeValues.reduce((a, b) => a + b, 0);
    const typeColors = typeKeys.map((_, i) => CHART_COLORS[i % CHART_COLORS.length]);

    errorTypeChart = new Chart(ctx1, {
        type: 'doughnut',
        data: {
            labels: typeKeys.map(k => truncateLabel(k, 40)),
            datasets: [{
                data: typeValues,
                backgroundColor: typeColors,
                borderWidth: 2,
                borderColor: '#fff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '52%',
            layout: { padding: 8 },
            plugins: {
                legend: {
                    position: 'bottom',
                    align: 'start',
                    labels: {
                        usePointStyle: true,
                        pointStyle: 'circle',
                        maxWidth: 520,
                        boxWidth: 10,
                        boxHeight: 10,
                        padding: 12,
                        font: { size: 12, family: "system-ui, 'Segoe UI', sans-serif" },
                        generateLabels(chart) {
                            const ds = chart.data.datasets[0];
                            return chart.data.labels.map((label, i) => {
                                const v = ds.data[i];
                                const pct = typeTotal ? ((v / typeTotal) * 100).toFixed(1) : '0';
                                return {
                                    text: `${truncateLabel(label, 36)} — ${formatMetric(v)} (%${pct})`,
                                    fillStyle: Array.isArray(ds.backgroundColor)
                                        ? ds.backgroundColor[i]
                                        : ds.backgroundColor,
                                    hidden: false,
                                    index: i
                                };
                            });
                        }
                    }
                },
                tooltip: {
                    bodyFont: { size: 13 },
                    titleFont: { size: 13 },
                    callbacks: {
                        label(ctx) {
                            const v = ctx.raw;
                            const pct = typeTotal ? ((v / typeTotal) * 100).toFixed(1) : '0';
                            return ` ${formatMetric(v)} kayıt (%${pct})`;
                        }
                    }
                }
            }
        }
    });

    const errorTables = {};
    list.filter(e => e.tableName).forEach(e => {
        errorTables[e.tableName] = (errorTables[e.tableName] || 0) + 1;
    });
    let top5Tables = Object.entries(errorTables)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5);

    if (top5Tables.length === 0 && list.length > 0) {
        top5Tables = [['(tablo belirtilmemiş)', list.length]];
    }

    errorTableChart = new Chart(ctx2, {
        type: 'bar',
        data: {
            labels: top5Tables.map(t => truncateLabel(t[0], 22)),
            datasets: [{
                label: 'Hata sayısı',
                data: top5Tables.map(t => t[1]),
                backgroundColor: 'rgba(220, 53, 69, 0.85)',
                borderColor: 'rgba(185, 28, 60, 1)',
                borderWidth: 1,
                borderRadius: 4,
                maxBarThickness: 48
            }]
        },
        plugins: [barValueLabelsPlugin],
        options: {
            responsive: true,
            maintainAspectRatio: false,
            layout: { padding: { top: 28, right: 8, bottom: 4, left: 4 } },
            plugins: {
                legend: { display: false },
                tooltip: {
                    bodyFont: { size: 13 },
                    callbacks: {
                        label(ctx) {
                            return ` ${formatMetric(ctx.raw)} hata`;
                        }
                    }
                }
            },
            scales: {
                x: {
                    ticks: {
                        font: { size: 11 },
                        maxRotation: 45,
                        minRotation: 0
                    },
                    grid: { display: false }
                },
                y: {
                    beginAtZero: true,
                    ticks: {
                        font: { size: 12 },
                        precision: 0,
                        callback: (v) => formatMetric(v)
                    },
                    title: {
                        display: true,
                        text: 'Hata sayısı',
                        font: { size: 12, weight: '600' }
                    }
                }
            }
        }
    });
}

function showErrorDetail(errorId) {
    const error = allErrors.find(e => e.id === errorId);
    if (!error) return;
    
    currentErrorId = errorId;
    
    document.getElementById('detailErrorType').textContent = error.errorType;
    document.getElementById('detailOccurredAt').textContent = formatDateTime(error.occurredAt);
    document.getElementById('detailRunId').textContent = error.runId;
    document.getElementById('detailTableName').textContent = error.tableName || '-';
    document.getElementById('detailPartitionId').textContent = error.partitionId || '-';
    document.getElementById('detailErrorMessage').textContent = error.errorMessage;
    
    const stackTraceRow = document.getElementById('stackTraceRow');
    if (error.stackTrace) {
        document.getElementById('detailStackTrace').textContent = error.stackTrace;
        stackTraceRow.style.display = 'block';
    } else {
        stackTraceRow.style.display = 'none';
    }
    
    const modal = new bootstrap.Modal(document.getElementById('errorDetailModal'));
    modal.show();
}

async function markAsResolved() {
    if (!currentErrorId) return;
    
    try {
        const response = await fetch(`/api/errors/${currentErrorId}/resolve`, {
            method: 'POST'
        });
        
        if (!response.ok) throw new Error('Failed to mark as resolved');
        
        // Update local state
        const error = allErrors.find(e => e.id === currentErrorId);
        if (error) error.resolved = true;
        
        // Refresh display (metrik + tablo + grafikler)
        filterErrors();

        // Close modal
        const modal = bootstrap.Modal.getInstance(document.getElementById('errorDetailModal'));
        modal.hide();
        
        showSuccess('Hata çözüldü olarak işaretlendi');
    } catch (error) {
        console.error('Error marking as resolved:', error);
        showError('Hata güncellenemedi: ' + error.message);
    }
}

function toggleSelectAll(event) {
    const checkboxes = document.querySelectorAll('.error-checkbox');
    checkboxes.forEach(cb => cb.checked = event.target.checked);
}

async function resolveSelected() {
    const selected = Array.from(document.querySelectorAll('.error-checkbox:checked'))
        .map(cb => parseInt(cb.dataset.id));
    
    if (selected.length === 0) {
        showError('Lütfen en az bir hata seçin');
        return;
    }
    
    try {
        await Promise.all(selected.map(id => 
            fetch(`/api/errors/${id}/resolve`, { method: 'POST' })
        ));
        
        // Update local state
        selected.forEach(id => {
            const error = allErrors.find(e => e.id === id);
            if (error) error.resolved = true;
        });
        
        filterErrors();

        showSuccess(`${selected.length} hata çözüldü olarak işaretlendi`);
    } catch (error) {
        console.error('Error resolving selected:', error);
        showError('Hatalar güncellenemedi: ' + error.message);
    }
}

function exportErrors() {
    const csv = convertToCSV(allErrors);
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `migration-errors-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
    window.URL.revokeObjectURL(url);
}

function convertToCSV(data) {
    const headers = ['ID', 'Run ID', 'Tablo', 'Partition', 'Hata Tipi', 'Mesaj', 'Zaman', 'Retry', 'Çözüldü'];
    const rows = data.map(e => [
        e.id,
        e.runId,
        e.tableName || '',
        e.partitionId || '',
        e.errorType,
        `"${e.errorMessage.replace(/"/g, '""')}"`,
        formatDateTime(e.occurredAt),
        e.retryAttempt,
        e.resolved ? 'Evet' : 'Hayır'
    ]);
    
    return [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
}

function formatDateTime(dateStr) {
    const date = new Date(dateStr);
    return date.toLocaleString('tr-TR');
}

function showSuccess(message) {
    alert(message); // Replace with a proper toast notification
}

function showError(message) {
    alert('HATA: ' + message); // Replace with a proper toast notification
}
