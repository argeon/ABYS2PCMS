let historyData = [];

document.addEventListener('DOMContentLoaded', () => {
    loadHistory();
});

async function loadHistory() {
    const limit = document.getElementById('limitFilter').value;
    
    showLoading();

    try {
        const response = await fetch(`/api/wizard/migration-history?limit=${limit}`);
        const data = await response.json();

        if (data.success) {
            historyData = data.history;
            displayHistory(data.history);
        } else {
            showError('Failed to load history: ' + data.error);
        }
    } catch (error) {
        showError('Error loading history: ' + error.message);
    }
}

function displayHistory(history) {
    const loadingDiv = document.getElementById('loadingHistory');
    const tableDiv = document.getElementById('historyTable');
    const noHistoryDiv = document.getElementById('noHistory');
    const tbody = document.getElementById('historyBody');

    loadingDiv.classList.add('d-none');

    if (history.length === 0) {
        tableDiv.classList.add('d-none');
        noHistoryDiv.classList.remove('d-none');
        return;
    }

    noHistoryDiv.classList.add('d-none');
    tableDiv.classList.remove('d-none');

    const searchTerm = document.getElementById('searchFilter').value.toLowerCase();
    const statusFilter = document.getElementById('statusFilter').value;

    const filtered = history.filter(h => {
        const matchesSearch = !searchTerm || 
            h.migrationName.toLowerCase().includes(searchTerm) ||
            h.sourceSchema.toLowerCase().includes(searchTerm);
        const matchesStatus = !statusFilter || h.status === statusFilter;
        return matchesSearch && matchesStatus;
    });

    tbody.innerHTML = '';

    filtered.forEach(h => {
        const row = document.createElement('tr');
        row.style.cursor = 'pointer';
        
        const statusBadge = getStatusBadge(h.status);
        const duration = h.durationSeconds ? formatDuration(h.durationSeconds) : 'Running';
        const started = new Date(h.startedAt).toLocaleString();

        row.innerHTML = `
            <td><strong>#${h.runId}</strong></td>
            <td>${h.migrationName}</td>
            <td><small>${h.sourceSchema} @ ${extractHost(h.sourceConnection)}</small></td>
            <td>${h.tableCount}</td>
            <td>${formatNumber(h.totalRows)}</td>
            <td>${started}</td>
            <td>${duration}</td>
            <td>${statusBadge}</td>
            <td>
                <button class="btn btn-sm btn-outline-primary" onclick="event.stopPropagation(); showDetails(${h.runId})">
                    <svg width="14" height="14" fill="currentColor" class="bi bi-eye" viewBox="0 0 16 16">
                        <path d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.133 13.133 0 0 1 1.66-2.043C4.12 4.668 5.88 3.5 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.133 13.133 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755C11.879 11.332 10.119 12.5 8 12.5c-2.12 0-3.879-1.168-5.168-2.457A13.134 13.134 0 0 1 1.172 8z"/>
                        <path d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/>
                    </svg>
                    Details
                </button>
            </td>
        `;

        row.onclick = () => showDetails(h.runId);
        tbody.appendChild(row);
    });

    // Populate comparison dropdowns
    populateComparisonDropdowns(filtered);
}

function getStatusBadge(status) {
    const badges = {
        'COMPLETED': '<span class="badge bg-success">Completed</span>',
        'RUNNING': '<span class="badge bg-primary">Running</span>',
        'FAILED': '<span class="badge bg-danger">Failed</span>',
        'PENDING': '<span class="badge bg-secondary">Pending</span>'
    };
    return badges[status] || '<span class="badge bg-secondary">' + status + '</span>';
}

async function showDetails(runId) {
    const modal = new bootstrap.Modal(document.getElementById('detailModal'));
    const modalBody = document.getElementById('modalBody');

    modalBody.innerHTML = '<div class="text-center"><div class="spinner-border"></div></div>';
    modal.show();

    try {
        // Load performance summary
        const perfResponse = await fetch(`/api/wizard/performance/${runId}`);
        const perfData = await perfResponse.json();

        // Load active threads
        const threadsResponse = await fetch(`/api/wizard/active-threads/${runId}`);
        const threadsData = await threadsResponse.json();

        // Find history item
        const history = historyData.find(h => h.runId === runId);

        let html = `
            <div class="row">
                <div class="col-md-6">
                    <h6>Migration Info</h6>
                    <table class="table table-sm">
                        <tr><td>Name:</td><td><strong>${history.migrationName}</strong></td></tr>
                        <tr><td>Schema:</td><td>${history.sourceSchema}</td></tr>
                        <tr><td>Tables:</td><td>${history.tableCount}</td></tr>
                        <tr><td>Total Rows:</td><td>${formatNumber(history.totalRows)}</td></tr>
                        <tr><td>Started:</td><td>${new Date(history.startedAt).toLocaleString()}</td></tr>
                        ${history.completedAt ? `<tr><td>Completed:</td><td>${new Date(history.completedAt).toLocaleString()}</td></tr>` : ''}
                    </table>
                </div>
                <div class="col-md-6">
                    <h6>Performance</h6>
        `;

        if (perfData.success && perfData.summary) {
            const perf = perfData.summary;
            html += `
                <table class="table table-sm">
                    <tr><td>Avg Throughput:</td><td><strong>${formatNumber(Math.round(perf.avgRowsPerSecond))} rows/sec</strong></td></tr>
                    <tr><td>Peak Throughput:</td><td>${formatNumber(Math.round(perf.peakRowsPerSecond))} rows/sec</td></tr>
                    <tr><td>Parallel Efficiency:</td><td>${(perf.parallelEfficiency * 100).toFixed(1)}%</td></tr>
                    <tr><td>Schema Phase:</td><td>${formatDuration(perf.schemaPhaseDuration)}</td></tr>
                    <tr><td>Load Phase:</td><td>${formatDuration(perf.loadPhaseDuration)}</td></tr>
                    <tr><td>Index Phase:</td><td>${formatDuration(perf.indexPhaseDuration)}</td></tr>
                    <tr><td>Validation Phase:</td><td>${formatDuration(perf.validationPhaseDuration)}</td></tr>
                </table>
            `;
        } else {
            html += '<p class="text-muted">Performance data not available</p>';
        }

        html += '</div></div>';

        // Active threads
        if (threadsData.success && threadsData.threads.length > 0) {
            html += `
                <hr>
                <h6>Active Threads (${threadsData.threads.length})</h6>
                <div class="table-responsive">
                    <table class="table table-sm table-striped">
                        <thead>
                            <tr>
                                <th>Thread</th>
                                <th>Table</th>
                                <th>Progress</th>
                                <th>Speed</th>
                                <th>ETA</th>
                            </tr>
                        </thead>
                        <tbody>
            `;

            threadsData.threads.forEach(t => {
                const percent = t.totalRows > 0 ? (t.rowsProcessed / t.totalRows * 100).toFixed(1) : 0;
                const eta = t.estimatedCompletion ? new Date(t.estimatedCompletion).toLocaleTimeString() : 'Calculating...';

                html += `
                    <tr>
                        <td>#${t.threadId}</td>
                        <td>${t.tableName}</td>
                        <td>
                            <div class="progress" style="height: 20px;">
                                <div class="progress-bar" style="width: ${percent}%">${percent}%</div>
                            </div>
                            <small>${formatNumber(t.rowsProcessed)} / ${formatNumber(t.totalRows)}</small>
                        </td>
                        <td>${formatNumber(Math.round(t.currentSpeed))} rows/sec</td>
                        <td><small>${eta}</small></td>
                    </tr>
                `;
            });

            html += '</tbody></table></div>';
        }

        // Configuration
        html += `
            <hr>
            <h6>Configuration</h6>
            <pre class="bg-dark text-light p-3" style="max-height: 300px; overflow-y: auto;"><code>${JSON.stringify(JSON.parse(history.configJson), null, 2)}</code></pre>
        `;

        modalBody.innerHTML = html;
    } catch (error) {
        modalBody.innerHTML = `<div class="alert alert-danger">Error loading details: ${error.message}</div>`;
    }
}

function populateComparisonDropdowns(history) {
    const select1 = document.getElementById('compareRun1');
    const select2 = document.getElementById('compareRun2');

    const completed = history.filter(h => h.status === 'COMPLETED');

    select1.innerHTML = '<option value="">Select run...</option>';
    select2.innerHTML = '<option value="">Select run...</option>';

    completed.forEach(h => {
        const option = `<option value="${h.runId}">#${h.runId} - ${h.migrationName} (${new Date(h.startedAt).toLocaleDateString()})</option>`;
        select1.innerHTML += option;
        select2.innerHTML += option;
    });
}

function showComparisonModal() {
    const modal = new bootstrap.Modal(document.getElementById('comparisonModal'));
    modal.show();
}

async function compareRuns() {
    const runId1 = document.getElementById('compareRun1').value;
    const runId2 = document.getElementById('compareRun2').value;
    const resultsDiv = document.getElementById('comparisonResults');

    if (!runId1 || !runId2) {
        resultsDiv.innerHTML = '<div class="alert alert-warning">Please select both runs</div>';
        return;
    }

    if (runId1 === runId2) {
        resultsDiv.innerHTML = '<div class="alert alert-warning">Please select different runs</div>';
        return;
    }

    resultsDiv.innerHTML = '<div class="text-center"><div class="spinner-border"></div></div>';

    try {
        const response = await fetch(`/api/wizard/compare/${runId1}/${runId2}`);
        const data = await response.json();

        if (data.success && data.comparison) {
            const comp = data.comparison;
            let html = '<div class="row g-3">';

            Object.keys(comp).forEach(key => {
                const metric = comp[key];
                const improvement = metric.improvement;
                const improvementClass = improvement > 0 ? 'text-success' : improvement < 0 ? 'text-danger' : 'text-muted';
                const improvementIcon = improvement > 0 ? '↑' : improvement < 0 ? '↓' : '=';

                html += `
                    <div class="col-md-6">
                        <div class="card">
                            <div class="card-body">
                                <h6 class="card-title">${formatMetricName(key)}</h6>
                                <div class="d-flex justify-content-between">
                                    <div>
                                        <small class="text-muted">Run ${runId1}</small><br>
                                        <strong>${formatMetricValue(key, metric.run1)}</strong>
                                    </div>
                                    <div class="text-center ${improvementClass}">
                                        <div style="font-size: 2rem;">${improvementIcon}</div>
                                        <strong>${Math.abs(improvement).toFixed(1)}%</strong>
                                    </div>
                                    <div class="text-end">
                                        <small class="text-muted">Run ${runId2}</small><br>
                                        <strong>${formatMetricValue(key, metric.run2)}</strong>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                `;
            });

            html += '</div>';
            resultsDiv.innerHTML = html;
        } else {
            resultsDiv.innerHTML = '<div class="alert alert-danger">Comparison failed</div>';
        }
    } catch (error) {
        resultsDiv.innerHTML = `<div class="alert alert-danger">Error: ${error.message}</div>`;
    }
}

function formatMetricName(key) {
    const names = {
        'duration': 'Total Duration',
        'avgThroughput': 'Average Throughput',
        'peakThroughput': 'Peak Throughput',
        'parallelEfficiency': 'Parallel Efficiency'
    };
    return names[key] || key;
}

function formatMetricValue(key, value) {
    if (key === 'duration') {
        return formatDuration(value);
    } else if (key.includes('Throughput')) {
        return formatNumber(Math.round(value)) + ' rows/sec';
    } else if (key === 'parallelEfficiency') {
        return (value * 100).toFixed(1) + '%';
    }
    return value.toFixed(2);
}

function showLoading() {
    document.getElementById('loadingHistory').classList.remove('d-none');
    document.getElementById('historyTable').classList.add('d-none');
    document.getElementById('noHistory').classList.add('d-none');
}

function showError(message) {
    document.getElementById('loadingHistory').classList.add('d-none');
    document.getElementById('historyTable').classList.add('d-none');
    document.getElementById('noHistory').classList.remove('d-none');
    document.getElementById('noHistory').innerHTML = `
        <div class="alert alert-danger">${message}</div>
    `;
}

function formatNumber(num) {
    return new Intl.NumberFormat().format(num);
}

function formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    
    if (hours > 0) {
        return `${hours}h ${minutes}m ${secs}s`;
    } else if (minutes > 0) {
        return `${minutes}m ${secs}s`;
    } else {
        return `${secs}s`;
    }
}

function extractHost(connectionString) {
    const match = connectionString.match(/Data Source=([^;]+)/i);
    return match ? match[1] : 'Unknown';
}

// Filter listeners
document.getElementById('searchFilter').addEventListener('input', () => {
    displayHistory(historyData);
});

document.getElementById('statusFilter').addEventListener('change', () => {
    displayHistory(historyData);
});
