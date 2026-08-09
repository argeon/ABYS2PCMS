# =============================================================================
# Transfer-OracleCTAS-Parallel.ps1
# Oracle CTAS tablolarını izgazMGR (MSSQL) staging'e parallel transfer
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$OracleServer,          # Oracle TNS name
    
    [Parameter(Mandatory=$true)]
    [string]$OracleUser,
    
    [Parameter(Mandatory=$true)]
    [string]$OraclePassword,
    
    [Parameter(Mandatory=$true)]
    [string]$MssqlServer,           # MSSQL server
    
    [Parameter(Mandatory=$true)]
    [string]$MssqlDatabase = "izgazMGR",
    
    [Parameter(Mandatory=$true)]
    [string]$MssqlUser,
    
    [Parameter(Mandatory=$true)]
    [string]$MssqlPassword,
    
    [string]$WorkDir = "C:\CTAS_Transfer",
    
    [int]$MaxParallel = 8,
    
    [ValidateSet("LS_INVOICE", "LS_INVLINES", "LS_DEBT_PAYTRANS", "LS_TAHSILAT_OVERLAY", "LS_TAHSILAT_LOG", "LS_PAYMENT", "ALL")]
    [string]$TableName = "ALL",
    
    [int]$TotalPartitions = 150,    # LS_INVOICE için
    
    [switch]$SkipExport,            # Export'u atla (CSV'ler hazırsa)
    [switch]$SkipImport,            # Import'u atla (test için)
    [switch]$ValidateOnly           # Sadece validation yap
)

# =============================================================================
# Configuration
# =============================================================================

$ErrorActionPreference = "Stop"

$TableConfigs = @{
    "LS_INVOICE" = @{
        Partitions = 150
        PartitionCol = "OWNERREF"
        EstimatedRows = 75000000
        BatchSize = 500000
    }
    "LS_INVLINES" = @{
        Partitions = 175
        PartitionCol = "INVOICE_ID_MOD"  # Derived: MOD(INVOICE_ID, 175)
        EstimatedRows = 350000000
        BatchSize = 2000000
    }
    "LS_DEBT_PAYTRANS" = @{
        Partitions = 100
        PartitionCol = "INVOICEREF"
        EstimatedRows = 150000000
        BatchSize = 1500000
    }
    "LS_TAHSILAT_OVERLAY" = @{
        Partitions = 100
        PartitionCol = "ACCOUNT_ID"
        EstimatedRows = 100000000
        BatchSize = 1000000
    }
    "LS_TAHSILAT_LOG" = @{
        Partitions = 100
        PartitionCol = "ACCOUNT_ID"
        EstimatedRows = 75000000
        BatchSize = 750000
    }
    "LS_PAYMENT" = @{
        Partitions = 100
        PartitionCol = "PT_ID"
        EstimatedRows = 75000000
        BatchSize = 750000
    }
}

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    Add-Content -Path "$WorkDir\transfer.log" -Value $logMsg
}

function Log-Progress {
    param(
        [string]$TableName,
        [int]$PartitionId,
        [string]$Phase,
        [string]$Status,
        [long]$RowCount = 0,
        [string]$ErrorMsg = ""
    )
    
    $connStr = "Server=$MssqlServer;Database=$MssqlDatabase;User Id=$MssqlUser;Password=$MssqlPassword;TrustServerCertificate=True"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()
    
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @"
        INSERT INTO dbo.CTAS_TRANSFER_LOG
            (TABLE_NAME, PARTITION_ID, PHASE, START_TIME, STATUS, ROW_COUNT, ERROR_MESSAGE)
        VALUES
            (@table, @partition, @phase, GETDATE(), @status, @rowCount, @error)
"@
    $cmd.Parameters.AddWithValue("@table", $TableName) | Out-Null
    $cmd.Parameters.AddWithValue("@partition", $PartitionId) | Out-Null
    $cmd.Parameters.AddWithValue("@phase", $Phase) | Out-Null
    $cmd.Parameters.AddWithValue("@status", $Status) | Out-Null
    $cmd.Parameters.AddWithValue("@rowCount", $RowCount) | Out-Null
    $cmd.Parameters.AddWithValue("@error", $ErrorMsg) | Out-Null
    
    try {
        $cmd.ExecuteNonQuery() | Out-Null
    } catch {
        Write-Log "Failed to log progress: $_" "ERROR"
    } finally {
        $conn.Close()
    }
}

function Export-OraclePartition {
    param(
        [string]$Table,
        [int]$PartitionId,
        [int]$TotalParts,
        [string]$PartitionCol
    )
    
    $csvFile = "$WorkDir\${Table}_p$($PartitionId.ToString("000")).csv"
    $logFile = "$WorkDir\${Table}_p$($PartitionId.ToString("000")).log"
    
    Write-Log "Exporting $Table partition $PartitionId/$TotalParts..."
    Log-Progress -TableName $Table -PartitionId $PartitionId -Phase "EXPORT" -Status "RUNNING"
    
    # SQL script for partition export
    $sqlScript = @"
SET ECHO OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TRIMSPOOL ON
SET HEADSEP OFF
SET COLSEP '|'
SET SERVEROUTPUT OFF
SPOOL $csvFile
SELECT /*+ PARALLEL(16) */
    *
FROM MIG_IZGAZPR.$Table
WHERE MOD($PartitionCol, $TotalParts) = $PartitionId
ORDER BY 1;
SPOOL OFF
EXIT;
"@
    
    $sqlFile = "$WorkDir\export_${Table}_p${PartitionId}.sql"
    $sqlScript | Out-File -FilePath $sqlFile -Encoding ASCII
    
    try {
        # Execute sqlplus
        $proc = Start-Process -FilePath "sqlplus" `
            -ArgumentList "-S", "${OracleUser}/${OraclePassword}@${OracleServer}", "@$sqlFile" `
            -RedirectStandardOutput $logFile `
            -RedirectStandardError "${logFile}.err" `
            -Wait -PassThru -NoNewWindow
        
        if ($proc.ExitCode -eq 0) {
            $rowCount = (Get-Content $csvFile | Measure-Object -Line).Lines
            Write-Log "Exported $rowCount rows from $Table partition $PartitionId" "SUCCESS"
            Log-Progress -TableName $Table -PartitionId $PartitionId -Phase "EXPORT" -Status "SUCCESS" -RowCount $rowCount
            return $csvFile
        } else {
            $errMsg = Get-Content "${logFile}.err" -Raw
            throw "Export failed: $errMsg"
        }
    } catch {
        Write-Log "Export failed for $Table partition $PartitionId: $_" "ERROR"
        Log-Progress -TableName $Table -PartitionId $PartitionId -Phase "EXPORT" -Status "FAILED" -ErrorMsg $_.Exception.Message
        return $null
    } finally {
        Remove-Item $sqlFile -ErrorAction SilentlyContinue
    }
}

function Import-MssqlPartition {
    param(
        [string]$Table,
        [int]$PartitionId,
        [string]$CsvFile
    )
    
    if (-not (Test-Path $CsvFile)) {
        Write-Log "CSV file not found: $CsvFile" "ERROR"
        return $false
    }
    
    Write-Log "Importing $Table partition $PartitionId to MSSQL..."
    Log-Progress -TableName $Table -PartitionId $PartitionId -Phase "IMPORT" -Status "RUNNING"
    
    $errFile = "$CsvFile.import.err"
    
    try {
        # BCP import
        $bcpArgs = @(
            "$MssqlDatabase.dbo.$Table",
            "in",
            $CsvFile,
            "-S", $MssqlServer,
            "-U", $MssqlUser,
            "-P", $MssqlPassword,
            "-t", "|",
            "-c",
            "-b", "100000",
            "-h", "TABLOCK",
            "-e", $errFile,
            "-m", "10"
        )
        
        $proc = Start-Process -FilePath "bcp" `
            -ArgumentList $bcpArgs `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput "$CsvFile.import.log"
        
        if ($proc.ExitCode -eq 0) {
            # Parse BCP output for row count
            $logContent = Get-Content "$CsvFile.import.log" -Raw
            if ($logContent -match "(\d+) rows copied") {
                $rowCount = [long]$matches[1]
                Write-Log "Imported $rowCount rows to $Table partition $PartitionId" "SUCCESS"
                Log-Progress -TableName $Table -PartitionId $PartitionId -Phase "IMPORT" -Status "SUCCESS" -RowCount $rowCount
                
                # Clean up CSV after successful import
                Remove-Item $CsvFile -ErrorAction SilentlyContinue
                return $true
            }
        }
        
        $errContent = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        throw "BCP import failed: $errContent"
        
    } catch {
        Write-Log "Import failed for $Table partition $PartitionId: $_" "ERROR"
        Log-Progress -TableName $Table -PartitionId $PartitionId -Phase "IMPORT" -Status "FAILED" -ErrorMsg $_.Exception.Message
        return $false
    }
}

function Validate-Transfer {
    param([string]$Table)
    
    Write-Log "Validating transfer for $Table..."
    
    # Oracle row count
    $oraCount = & sqlplus -S "${OracleUser}/${OraclePassword}@${OracleServer}" <<EOF
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT COUNT(*) FROM MIG_IZGAZPR.$Table;
EXIT;
EOF
    $oraCount = [long]$oraCount.Trim()
    
    # MSSQL row count
    $connStr = "Server=$MssqlServer;Database=$MssqlDatabase;User Id=$MssqlUser;Password=$MssqlPassword;TrustServerCertificate=True"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT COUNT_BIG(*) FROM dbo.$Table"
    $mssqlCount = [long]$cmd.ExecuteScalar()
    $conn.Close()
    
    $diff = $oraCount - $mssqlCount
    
    if ($diff -eq 0) {
        Write-Log "$Table validation: PASS (Oracle=$oraCount, MSSQL=$mssqlCount)" "SUCCESS"
        return $true
    } else {
        Write-Log "$Table validation: FAIL (Oracle=$oraCount, MSSQL=$mssqlCount, Diff=$diff)" "ERROR"
        return $false
    }
}

# =============================================================================
# Main Transfer Logic
# =============================================================================

function Transfer-Table {
    param([string]$Table)
    
    $config = $TableConfigs[$Table]
    $totalParts = $config.Partitions
    $partCol = $config.PartitionCol
    
    Write-Log "========== Starting transfer for $Table ($totalParts partitions) =========="
    
    $jobs = @()
    
    for ($i = 0; $i -lt $totalParts; $i++) {
        # Start parallel job for each partition
        $job = Start-Job -ScriptBlock {
            param($p, $table, $parts, $col, $workDir, $oraS, $oraU, $oraP, $mssqlS, $mssqlDb, $mssqlU, $mssqlP, $skipExp, $skipImp)
            
            # Re-import functions in job context
            . $using:PSCommandPath
            
            # Export
            if (-not $skipExp) {
                $csv = Export-OraclePartition -Table $table -PartitionId $p -TotalParts $parts -PartitionCol $col
                if (-not $csv) { return $false }
            } else {
                $csv = "$workDir\${table}_p$($p.ToString("000")).csv"
            }
            
            # Import
            if (-not $skipImp) {
                $success = Import-MssqlPartition -Table $table -PartitionId $p -CsvFile $csv
                return $success
            }
            
            return $true
            
        } -ArgumentList $i, $Table, $totalParts, $partCol, $WorkDir, 
                         $OracleServer, $OracleUser, $OraclePassword,
                         $MssqlServer, $MssqlDatabase, $MssqlUser, $MssqlPassword,
                         $SkipExport.IsPresent, $SkipImport.IsPresent
        
        $jobs += $job
        
        # Throttle parallel jobs
        while (($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $MaxParallel) {
            Start-Sleep -Seconds 5
            
            # Show progress
            $completed = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
            $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
            Write-Progress -Activity "Transferring $Table" `
                -Status "$completed/$totalParts completed, $running running" `
                -PercentComplete (($completed / $totalParts) * 100)
        }
    }
    
    # Wait for all jobs
    Write-Log "Waiting for all $Table partition jobs to complete..."
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    
    $successCount = ($results | Where-Object { $_ -eq $true }).Count
    Write-Log "$Table transfer: $successCount/$totalParts partitions succeeded"
    
    # Validate
    if ($successCount -eq $totalParts) {
        Validate-Transfer -Table $Table
    }
}

# =============================================================================
# Execution
# =============================================================================

# Create work directory
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

Write-Log "========== CTAS Parallel Transfer Started =========="
Write-Log "Oracle: $OracleServer, MSSQL: $MssqlServer/$MssqlDatabase"
Write-Log "Max Parallel: $MaxParallel"
Write-Log "Work Directory: $WorkDir"

if ($ValidateOnly) {
    Write-Log "Validation-only mode"
    if ($TableName -eq "ALL") {
        foreach ($table in $TableConfigs.Keys) {
            Validate-Transfer -Table $table
        }
    } else {
        Validate-Transfer -Table $TableName
    }
    exit
}

# Transfer tables
if ($TableName -eq "ALL") {
    # Transfer in priority order
    $priority1 = @("LS_INVOICE", "LS_INVLINES", "LS_DEBT_PAYTRANS")
    $priority2 = @("LS_TAHSILAT_OVERLAY", "LS_TAHSILAT_LOG", "LS_PAYMENT")
    
    foreach ($table in $priority1) {
        Transfer-Table -Table $table
    }
    
    foreach ($table in $priority2) {
        Transfer-Table -Table $table
    }
} else {
    Transfer-Table -Table $TableName
}

Write-Log "========== CTAS Parallel Transfer Completed =========="
