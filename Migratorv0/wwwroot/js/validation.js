// Validation Page JavaScript

let currentProfile = null;
let currentRun = null;
let selectedTables = new Set();

// Load profiles on page load
document.addEventListener('DOMContentLoaded', () => {
    loadProfiles();
});

// Load all profiles
async function loadProfiles() {
    try {
        const response = await fetch('/api/history/profiles');
        const profiles = await response.json();
        
        const select = document.getElementById('profileSelect');
        select.innerHTML = '<option value="">Profil seçin...</option>';
        
        profiles.forEach(profile => {
            const option = document.createElement('option');
            option.value = profile.id;
            option.textContent = `${profile.name} (${new Date(profile.createdAt).toLocaleDateString('tr-TR')})`;
            select.appendChild(option);
        });
    } catch (error) {
        console.error('Failed to load profiles:', error);
        showAlert('danger', 'Profiller yüklenemedi: ' + error.message);
    }
}

// Load profile and its runs
async function loadProfile() {
    const profileId = document.getElementById('profileSelect').value;
    if (!profileId) {
        document.getElementById('runSelect').innerHTML = '<option value="">Run seçin...</option>';
        return;
    }
    
    try {
        // Load profile details
        const profileResponse = await fetch(`/api/history/profiles/${profileId}`);
        currentProfile = await profileResponse.json();
        
        // Load runs for this profile
        const runsResponse = await fetch(`/api/history/migrations?profileId=${profileId}`);
        const runs = await runsResponse.json();
        
        const select = document.getElementById('runSelect');
        select.innerHTML = '<option value="">Run seçin...</option>';
        
        runs.forEach(run => {
            const option = document.createElement('option');
            option.value = run.id;
            const status = run.status || 'Unknown';
            const date = new Date(run.startedAt).toLocaleString('tr-TR');
            option.textContent = `Run #${run.id} - ${status} (${date})`;
            select.appendChild(option);
        });
        
    } catch (error) {
        console.error('Failed to load profile:', error);
        showAlert('danger', 'Profil yüklenemedi: ' + error.message);
    }
}

// Load tables for selected run
async function loadRunTables() {
    const runId = document.getElementById('runSelect').value;
    if (!runId) {
        hideSection('summarySection');
        hideSection('comparisonSection');
        return;
    }
    
    currentRun = parseInt(runId);
    
    try {
        // Get table checkpoints from this run
        const response = await fetch(`/api/validation/run/${runId}/tables`);
        const tables = await response.json();
        
        if (!tables || tables.length === 0) {
            showAlert('warning', 'Bu run için tablo bilgisi bulunamadı.');
            return;
        }
        
        // Update summary
        updateSummary(tables);
        
        // Update comparison grid
        updateComparisonGrid(tables);
        
        showSection('summarySection');
        showSection('comparisonSection');
        
    } catch (error) {
        console.error('Failed to load run tables:', error);
        showAlert('danger', 'Tablo bilgileri yüklenemedi: ' + error.message);
    }
}

// Update summary statistics
function updateSummary(tables) {
    let matched = 0;
    let partial = 0;
    let mismatch = 0;
    
    tables.forEach(table => {
        const matchPercent = table.sourceRows > 0 
            ? (table.destinationRows / table.sourceRows) * 100 
            : 0;
            
        if (matchPercent >= 100) {
            matched++;
        } else if (matchPercent >= 95) {
            partial++;
        } else {
            mismatch++;
        }
    });
    
    document.getElementById('totalTables').textContent = tables.length;
    document.getElementById('matchedTables').textContent = matched;
    document.getElementById('partialTables').textContent = partial;
    document.getElementById('mismatchTables').textContent = mismatch;
}

// Update comparison grid
function updateComparisonGrid(tables) {
    const tbody = document.getElementById('comparisonTableBody');
    tbody.innerHTML = '';
    
    tables.forEach(table => {
        const row = createTableRow(table);
        tbody.appendChild(row);
    });
}

// Create table row
function createTableRow(table) {
    const row = document.createElement('tr');
    
    const sourceRows = table.sourceRows || table.totalRows || 0;
    const destRows = table.destinationRows || table.rowsProcessed || 0;
    const difference = sourceRows - destRows;
    const matchPercent = sourceRows > 0 ? ((destRows / sourceRows) * 100).toFixed(2) : 0;
    
    let statusBadge, statusClass;
    if (matchPercent >= 100) {
        statusBadge = '<span class="badge bg-success">✓ Tam Eşleşme</span>';
        statusClass = 'table-success';
    } else if (matchPercent >= 95) {
        statusBadge = '<span class="badge bg-warning">⚠ Kısmi</span>';
        statusClass = 'table-warning';
    } else {
        statusBadge = '<span class="badge bg-danger">✗ Eşleşmiyor</span>';
        statusClass = 'table-danger';
    }
    
    row.className = statusClass;
    row.innerHTML = `
        <td><input type="checkbox" class="table-checkbox" value="${table.tableName}" onchange="updateSelection()"></td>
        <td><strong>${escapeHtml(table.tableName)}</strong></td>
        <td class="text-end">${formatNumber(sourceRows)}</td>
        <td class="text-end">${formatNumber(destRows)}</td>
        <td class="text-end ${difference !== 0 ? 'text-danger' : 'text-success'}">${formatNumber(Math.abs(difference))}</td>
        <td class="text-end">
            <span class="badge ${matchPercent >= 100 ? 'bg-success' : matchPercent >= 95 ? 'bg-warning' : 'bg-danger'}">
                ${matchPercent}%
            </span>
        </td>
        <td>${statusBadge}</td>
        <td>
            <div class="btn-group btn-group-sm">
                <button class="btn btn-outline-primary" onclick="validateTable('${table.tableName}')" title="Doğrula">
                    <i class="fas fa-sync"></i>
                </button>
                <button class="btn btn-outline-info" onclick="showTableDetails('${table.tableName}')" title="Detaylar">
                    <i class="fas fa-info-circle"></i>
                </button>
            </div>
        </td>
    `;
    
    return row;
}

// Validate all tables
async function validateAll() {
    if (!currentRun) {
        showAlert('warning', 'Lütfen önce bir run seçin.');
        return;
    }
    
    showAlert('info', 'Tüm tablolar doğrulanıyor...');
    
    try {
        const response = await fetch(`/api/validation/run/${currentRun}/validate-all`, {
            method: 'POST'
        });
        const result = await response.json();
        
        if (result.success) {
            showAlert('success', `${result.validated} tablo doğrulandı.`);
            loadRunTables(); // Refresh
        } else {
            showAlert('danger', 'Doğrulama hatası: ' + result.error);
        }
    } catch (error) {
        console.error('Validation failed:', error);
        showAlert('danger', 'Doğrulama başarısız: ' + error.message);
    }
}

// Validate single table
async function validateTable(tableName) {
    try {
        const response = await fetch(`/api/validation/run/${currentRun}/validate/${tableName}`, {
            method: 'POST'
        });
        const result = await response.json();
        
        if (result.success) {
            showAlert('success', `${tableName} doğrulandı: ${result.sourceRows} → ${result.destinationRows}`);
            loadRunTables(); // Refresh
        } else {
            showAlert('danger', `${tableName} doğrulama hatası: ` + result.error);
        }
    } catch (error) {
        console.error('Table validation failed:', error);
        showAlert('danger', 'Tablo doğrulama başarısız: ' + error.message);
    }
}

// Show drop modal
function showDropModal() {
    if (selectedTables.size === 0) {
        showAlert('warning', 'Lütfen en az bir tablo seçin.');
        return;
    }
    
    const list = document.getElementById('dropTablesList');
    list.innerHTML = '';
    selectedTables.forEach(table => {
        const li = document.createElement('li');
        li.textContent = table;
        list.appendChild(li);
    });
    
    document.getElementById('confirmDrop').checked = false;
    document.getElementById('dropConfirmBtn').disabled = true;
    
    const modal = new bootstrap.Modal(document.getElementById('dropModal'));
    modal.show();
}

// Enable/disable drop button based on confirmation
document.getElementById('confirmDrop')?.addEventListener('change', (e) => {
    document.getElementById('dropConfirmBtn').disabled = !e.target.checked;
});

// Drop selected tables
async function dropSelectedTables() {
    const modal = bootstrap.Modal.getInstance(document.getElementById('dropModal'));
    modal.hide();
    
    showAlert('info', `${selectedTables.size} tablo siliniyor...`);
    
    try {
        const response = await fetch('/api/validation/drop-tables', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                tables: Array.from(selectedTables),
                connectionString: currentProfile?.connectionString
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            showAlert('success', `${result.dropped} tablo silindi.`);
            selectedTables.clear();
            loadRunTables(); // Refresh
        } else {
            showAlert('danger', 'Silme hatası: ' + result.error);
        }
    } catch (error) {
        console.error('Drop failed:', error);
        showAlert('danger', 'Tablo silme başarısız: ' + error.message);
    }
}

// Show remigration modal
function showRemigrationModal() {
    if (selectedTables.size === 0) {
        showAlert('warning', 'Lütfen en az bir tablo seçin.');
        return;
    }
    
    const list = document.getElementById('remigrationTablesList');
    list.innerHTML = '';
    selectedTables.forEach(table => {
        const li = document.createElement('li');
        li.textContent = table;
        list.appendChild(li);
    });
    
    const modal = new bootstrap.Modal(document.getElementById('remigrationModal'));
    modal.show();
}

// Start remigration
async function startRemigration() {
    const dropBefore = document.getElementById('dropBeforeRemigration').checked;
    const modal = bootstrap.Modal.getInstance(document.getElementById('remigrationModal'));
    modal.hide();
    
    const tables = Array.from(selectedTables);
    
    // Save remigration context to session storage
    sessionStorage.setItem('remigration', JSON.stringify({
        profileId: currentProfile.id,
        tables: tables,
        dropBefore: dropBefore
    }));
    
    // Redirect to wizard with profile
    window.location.href = `/wizard?profileId=${currentProfile.id}&remigration=true`;
}

// Selection management
function toggleSelectAll() {
    const checked = document.getElementById('selectAll').checked;
    document.querySelectorAll('.table-checkbox').forEach(cb => {
        cb.checked = checked;
    });
    updateSelection();
}

function updateSelection() {
    selectedTables.clear();
    document.querySelectorAll('.table-checkbox:checked').forEach(cb => {
        selectedTables.add(cb.value);
    });
    
    // Update select all checkbox
    const total = document.querySelectorAll('.table-checkbox').length;
    const selected = selectedTables.size;
    document.getElementById('selectAll').checked = total > 0 && selected === total;
}

// Utility functions
function showSection(id) {
    document.getElementById(id)?.classList.remove('d-none');
}

function hideSection(id) {
    document.getElementById(id)?.classList.add('d-none');
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

function formatNumber(num) {
    return new Intl.NumberFormat('tr-TR').format(num);
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function showTableDetails(tableName) {
    // TODO: Implement detailed view
    showAlert('info', `${tableName} detayları gösteriliyor...`);
}
