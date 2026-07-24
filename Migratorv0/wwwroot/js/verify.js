let currentProfileId = null;
let currentProfile = null;
let comparisonData = [];
let selectedTables = new Set();

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    // Get profileId from URL
    const urlParams = new URLSearchParams(window.location.search);
    currentProfileId = urlParams.get('profileId');
    
    if (currentProfileId) {
        loadProfile(currentProfileId);
    } else {
        showError('No profile selected. Please select a profile from History page.');
    }
});

async function loadProfile(profileId) {
    try {
        const response = await fetch(`/api/history/profiles/${profileId}`);
        currentProfile = await response.json();
        
        if (!currentProfile) {
            showError('Profile not found');
            return;
        }
        
        // Display profile info
        document.getElementById('profileName').textContent = currentProfile.name || 'Unknown';
        document.getElementById('oracleSchema').textContent = currentProfile.oracleSchema || '-';
        document.getElementById('totalTables').textContent = currentProfile.tables?.length || 0;
        document.getElementById('lastUsed').textContent = currentProfile.lastUsedAt 
            ? new Date(currentProfile.lastUsedAt).toLocaleString('tr-TR')
            : 'Never';
        
        // Load comparison
        await loadComparison();
        
    } catch (error) {
        console.error('Failed to load profile:', error);
        showError('Failed to load profile: ' + error.message);
    }
}

async function loadComparison() {
    if (!currentProfile || !currentProfile.tables) {
        showError('No tables in profile');
        return;
    }
    
    try {
        const tbody = document.getElementById('comparisonTableBody');
        tbody.innerHTML = '<tr><td colspan="9" class="text-center"><div class="spinner-border"></div></td></tr>';
        
        // Fetch comparison data for each table
        const tables = currentProfile.tables;
        const comparisons = [];
        
        for (const tableName of tables) {
            try {
                const response = await fetch(`/api/verify/compare?table=${encodeURIComponent(tableName)}&oracleConn=${encodeURIComponent(currentProfile.oracleConnectionString)}&mssqlConn=${encodeURIComponent(currentProfile.mssqlConnectionString)}&schema=${encodeURIComponent(currentProfile.oracleSchema)}`);
                const data = await response.json();
                comparisons.push(data);
            } catch (err) {
                console.error(`Failed to compare ${tableName}:`, err);
                comparisons.push({
                    tableName: tableName,
                    oracleRows: -1,
                    mssqlRows: -1,
                    error: err.message
                });
            }
        }
        
        comparisonData = comparisons;
        renderComparisonTable(comparisons);
        updateSummary(comparisons);
        
        // Enable buttons
        document.getElementById('dropAllBtn').disabled = false;
        document.getElementById('retryMigrationBtn').disabled = false;
        
    } catch (error) {
        console.error('Failed to load comparison:', error);
        showError('Failed to load comparison: ' + error.message);
    }
}

function renderComparisonTable(comparisons) {
    const tbody = document.getElementById('comparisonTableBody');
    
    if (!comparisons || comparisons.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" class="text-center">No tables to compare</td></tr>';
        return;
    }
    
    tbody.innerHTML = comparisons.map(comp => {
        const oracleRows = comp.oracleRows || 0;
        const mssqlRows = comp.mssqlRows || 0;
        const difference = oracleRows - mssqlRows;
        const matchPercent = oracleRows > 0 ? ((mssqlRows / oracleRows) * 100).toFixed(2) : 0;
        
        let statusClass = '';
        let statusBadge = '';
        let statusIcon = '';
        
        if (comp.error) {
            statusClass = 'status-missing';
            statusBadge = '<span class="badge bg-danger">Error</span>';
            statusIcon = '<i class="fas fa-exclamation-circle text-danger"></i>';
        } else if (difference === 0 && oracleRows > 0) {
            statusClass = 'status-matched';
            statusBadge = '<span class="badge bg-success">Perfect Match</span>';
            statusIcon = '<i class="fas fa-check-circle text-success"></i>';
        } else if (mssqlRows === 0 || mssqlRows === -1) {
            statusClass = 'status-missing';
            statusBadge = '<span class="badge bg-danger">Missing</span>';
            statusIcon = '<i class="fas fa-times-circle text-danger"></i>';
        } else if (matchPercent >= 99) {
            statusClass = 'status-mismatch';
            statusBadge = '<span class="badge bg-warning">Close Match</span>';
            statusIcon = '<i class="fas fa-exclamation-triangle text-warning"></i>';
        } else {
            statusClass = 'status-mismatch';
            statusBadge = '<span class="badge bg-warning">Mismatch</span>';
            statusIcon = '<i class="fas fa-exclamation-triangle text-warning"></i>';
        }
        
        return `
            <tr class="${statusClass}">
                <td>
                    <input type="checkbox" class="table-checkbox" data-table="${escapeHtml(comp.tableName)}" onchange="updateSelection()">
                </td>
                <td><strong>${escapeHtml(comp.tableName)}</strong></td>
                <td class="text-end">${formatNumber(oracleRows)}</td>
                <td class="text-end">${formatNumber(mssqlRows)}</td>
                <td class="text-end ${difference !== 0 ? 'text-danger fw-bold' : ''}">${formatNumber(Math.abs(difference))}</td>
                <td class="text-end">
                    ${matchPercent >= 100 ? '<span class="badge bg-success">100%</span>' : 
                      matchPercent >= 99 ? '<span class="badge bg-warning">' + matchPercent + '%</span>' :
                      '<span class="badge bg-danger">' + matchPercent + '%</span>'}
                </td>
                <td>${statusIcon} ${statusBadge}</td>
                <td><small class="text-muted">${new Date().toLocaleTimeString('tr-TR')}</small></td>
                <td>
                    <div class="btn-group btn-group-sm">
                        <button class="btn btn-outline-info" onclick="showTableDetail('${escapeHtml(comp.tableName)}')" title="Details">
                            <i class="fas fa-info-circle"></i>
                        </button>
                        <button class="btn btn-outline-warning" onclick="dropTable('${escapeHtml(comp.tableName)}')" title="Drop">
                            <i class="fas fa-trash"></i>
                        </button>
                        <button class="btn btn-outline-success" onclick="retryTable('${escapeHtml(comp.tableName)}')" title="Retry">
                            <i class="fas fa-redo"></i>
                        </button>
                    </div>
                </td>
            </tr>
        `;
    }).join('');
}

function updateSummary(comparisons) {
    let matched = 0;
    let mismatch = 0;
    let missing = 0;
    let totalDiff = 0;
    
    comparisons.forEach(comp => {
        const oracleRows = comp.oracleRows || 0;
        const mssqlRows = comp.mssqlRows || 0;
        const difference = Math.abs(oracleRows - mssqlRows);
        
        if (comp.error || mssqlRows <= 0) {
            missing++;
        } else if (difference === 0 && oracleRows > 0) {
            matched++;
        } else {
            mismatch++;
        }
        
        totalDiff += difference;
    });
    
    document.getElementById('matchedCount').textContent = matched;
    document.getElementById('mismatchCount').textContent = mismatch;
    document.getElementById('missingCount').textContent = missing;
    document.getElementById('totalRowDiff').textContent = formatNumber(totalDiff);
}

function toggleSelectAll() {
    const selectAll = document.getElementById('selectAll').checked;
    document.querySelectorAll('.table-checkbox').forEach(cb => {
        cb.checked = selectAll;
    });
    updateSelection();
}

function updateSelection() {
    selectedTables.clear();
    document.querySelectorAll('.table-checkbox:checked').forEach(cb => {
        selectedTables.add(cb.dataset.table);
    });
}

async function refreshComparison() {
    await loadComparison();
    showSuccess('Comparison refreshed');
}

async function dropAllTables() {
    if (!confirm(`Are you sure you want to DROP ALL ${comparisonData.length} tables in MSSQL?\n\nThis action cannot be undone!`)) {
        return;
    }
    
    const secondConfirm = prompt('Type "DROP ALL" to confirm:');
    if (secondConfirm !== 'DROP ALL') {
        alert('Confirmation failed. Operation cancelled.');
        return;
    }
    
    const tables = comparisonData.map(c => c.tableName);
    await dropTables(tables);
}

async function dropSelectedTables() {
    if (selectedTables.size === 0) {
        alert('Please select tables first');
        return;
    }
    
    if (!confirm(`Drop ${selectedTables.size} selected tables?`)) {
        return;
    }
    
    await dropTables(Array.from(selectedTables));
}

async function dropTable(tableName) {
    if (!confirm(`Drop table "${tableName}"?`)) {
        return;
    }
    
    await dropTables([tableName]);
}

async function dropTables(tables) {
    try {
        showInfo(`Dropping ${tables.length} table(s)...`);
        
        const response = await fetch('/api/verify/drop', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                connectionString: currentProfile.mssqlConnectionString,
                tables: tables
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            showSuccess(`Successfully dropped ${result.droppedCount} table(s)`);
            await refreshComparison();
        } else {
            showError('Drop failed: ' + result.error);
        }
        
    } catch (error) {
        console.error('Drop failed:', error);
        showError('Drop failed: ' + error.message);
    }
}

async function retryMigration() {
    if (!confirm('Start migration with current profile?')) {
        return;
    }
    
    // Redirect to wizard with profile loaded
    window.location.href = `/wizard?profileId=${currentProfileId}&autoStart=true`;
}

async function retrySelectedTables() {
    if (selectedTables.size === 0) {
        alert('Please select tables first');
        return;
    }
    
    // TODO: Implement selective table migration
    showInfo('Selective migration coming soon!');
}

async function retryTable(tableName) {
    // TODO: Implement single table migration
    showInfo(`Retry migration for ${tableName} coming soon!`);
}

async function showTableDetail(tableName) {
    const comp = comparisonData.find(c => c.tableName === tableName);
    if (!comp) return;
    
    const modalBody = document.getElementById('modalBody');
    modalBody.innerHTML = `
        <h6>${tableName}</h6>
        <table class="table">
            <tr><th>Oracle Rows:</th><td>${formatNumber(comp.oracleRows || 0)}</td></tr>
            <tr><th>MSSQL Rows:</th><td>${formatNumber(comp.mssqlRows || 0)}</td></tr>
            <tr><th>Difference:</th><td class="text-danger">${formatNumber(Math.abs((comp.oracleRows || 0) - (comp.mssqlRows || 0)))}</td></tr>
            <tr><th>Error:</th><td>${comp.error || 'None'}</td></tr>
        </table>
    `;
    
    new bootstrap.Modal(document.getElementById('detailModal')).show();
}

async function verifySelectedTables() {
    if (selectedTables.size === 0) {
        alert('Please select tables first');
        return;
    }
    
    // Refresh comparison for selected tables only
    showInfo('Verifying selected tables...');
    await refreshComparison();
}

// Utilities
function formatNumber(num) {
    if (num < 0) return 'N/A';
    return new Intl.NumberFormat().format(num);
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function showSuccess(message) {
    showAlert('success', message);
}

function showError(message) {
    showAlert('danger', message);
}

function showInfo(message) {
    showAlert('info', message);
}

function showAlert(type, message) {
    const alertDiv = document.createElement('div');
    alertDiv.className = `alert alert-${type} alert-dismissible fade show position-fixed top-0 start-50 translate-middle-x m-3`;
    alertDiv.style.zIndex = '9999';
    alertDiv.innerHTML = `
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    document.body.appendChild(alertDiv);
    
    setTimeout(() => alertDiv.remove(), 5000);
}
