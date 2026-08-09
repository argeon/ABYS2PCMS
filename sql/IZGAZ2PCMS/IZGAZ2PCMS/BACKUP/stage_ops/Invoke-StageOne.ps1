<#
.SYNOPSIS
  Runs a single Stage Ops stage (existing script/SP unchanged).
  Connections: stage_ops.connections.json (UI) > stage_ops.config.json > env.
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('ctas', 'transfer-sql', 'prod-sql')][string]$Surface,
    [Parameter(Mandatory = $true)][string]$StageJson,
    [string]$ConfigPath = "",
    [string]$RunUuid = "adhoc",
    [switch]$Resume,
    [switch]$HardReset,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $here 'stage_ops.config.json' }

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$stage = $StageJson | ConvertFrom-Json
$sqlRoot = if ([IO.Path]::IsPathRooted($config.sqlRoot)) { $config.sqlRoot } else { Join-Path $here $config.sqlRoot }
$sqlRoot = [IO.Path]::GetFullPath($sqlRoot)

$connectionsPath = Join-Path $here 'stage_ops.connections.json'
$connections = $null
if (Test-Path $connectionsPath) {
    $connections = Get-Content $connectionsPath -Raw | ConvertFrom-Json
}

$logRoot = Join-Path (Join-Path (Join-Path $here $config.logsRoot) $Surface) $RunUuid
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$logFile = Join-Path $logRoot "$($stage.id).log"

function Resolve-Env([string]$direct, [string]$envName) {
    if ($direct) { return $direct }
    if ($envName) { return [Environment]::GetEnvironmentVariable($envName) }
    return $null
}

function Get-OracleSqlplusConnect {
    if ($connections -and $connections.oracleCtas -and $connections.oracleCtas.sqlplusConnect) {
        return [string]$connections.oracleCtas.sqlplusConnect
    }
    $c = Resolve-Env $config.oracle.connectString $config.oracle.connectStringEnv
    if ($c) { return $c }
    return [Environment]::GetEnvironmentVariable('STAGEOPS_ORACLE_CONN')
}

function Get-MssqlEndpoint([string]$role) {
    # role: stage1 | stage2 | prod
    $saved = $null
    if ($connections) {
        if ($role -eq 'stage1') { $saved = $connections.mssqlStage1 }
        elseif ($role -eq 'stage2') { $saved = $connections.mssqlStage2 }
        elseif ($role -eq 'prod') { $saved = $connections.mssqlProd }
    }
    if ($saved -and $saved.server -and $saved.database) {
        return @{
            Server   = [string]$saved.server
            Database = [string]$saved.database
            User     = [string]$saved.user
            Password = [string]$saved.password
            AuthType = if ($saved.authType) { [string]$saved.authType } else { 'Sql' }
        }
    }

    if ($role -eq 'prod') {
        $cfg = $config.prod
        $prefix = 'STAGEOPS_PROD'
    }
    elseif ($role -eq 'stage1') {
        $cfg = $config.mssql
        $prefix = 'STAGEOPS_MSSQL_STAGE1'
        # fallback to generic if stage1-specific empty
    }
    else {
        $cfg = $config.mssql
        $prefix = 'STAGEOPS_MSSQL'
    }

    $server = Resolve-Env $cfg.server $cfg.serverEnv
    if (-not $server) { $server = [Environment]::GetEnvironmentVariable("${prefix}_SERVER") }
    $database = Resolve-Env $cfg.database $cfg.databaseEnv
    if (-not $database) { $database = [Environment]::GetEnvironmentVariable("${prefix}_DATABASE") }
    $user = Resolve-Env $cfg.user $cfg.userEnv
    if (-not $user) { $user = [Environment]::GetEnvironmentVariable("${prefix}_USER") }
    $pass = Resolve-Env $cfg.password $cfg.passwordEnv
    if (-not $pass) { $pass = [Environment]::GetEnvironmentVariable("${prefix}_PASSWORD") }

    return @{
        Server   = $server
        Database = $database
        User     = $user
        Password = $pass
        AuthType = 'Sql'
    }
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$exitCode = 0

try {
    if ($stage.kind -eq 'Manual') {
        "MANUAL stage $($stage.id) — mark Done in UI" | Set-Content $logFile
        $exitCode = 0
    }
    elseif ($Surface -eq 'ctas') {
        $conn = Get-OracleSqlplusConnect
        if (-not $conn) {
            throw "Oracle CTAS bağlantısı yok. Stage Ops → Bağlantılar sayfasından sqlplus connect tanımlayın (veya STAGEOPS_ORACLE_CONN)."
        }
        $scriptPath = Join-Path $sqlRoot $stage.path
        if (-not (Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }
        $sqlplus = $config.oracle.sqlplusPath
        if ($DryRun) {
            "[DRY] $sqlplus -L *** @$scriptPath" | Set-Content $logFile
        }
        else {
            $p = Start-Process -FilePath $sqlplus -ArgumentList @('-L', $conn, "@$scriptPath") `
                -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err" `
                -NoNewWindow -PassThru -Wait
            $exitCode = $p.ExitCode
            if (Test-Path "$logFile.err") { Get-Content "$logFile.err" -ErrorAction SilentlyContinue | Add-Content $logFile }
        }
    }
    else {
        $role = if ($Surface -eq 'prod-sql') { 'prod' } else { 'stage2' }
        $ep = Get-MssqlEndpoint $role
        if (-not $ep.Server) {
            $label = if ($role -eq 'prod') { 'PROD (mssqlProd)' } else { 'MSSQL Stage 2 / energy (mssqlStage2)' }
            throw "MSSQL bağlantısı yok ($label). Stage Ops → Bağlantılar sayfasından tanımlayın."
        }
        $database = if ($ep.Database) { $ep.Database } else { 'energy' }

        $sqlcmd = $config.mssql.sqlcmdPath
        $auth = if ($ep.User -and $ep.AuthType -ne 'Windows') { @('-U', $ep.User, '-P', $ep.Password) } else { @('-E') }
        $args = @('-S', $ep.Server, '-d', $database, '-C', '-I', '-b') + $auth

        if ($stage.procedureName) {
            $resumeBit = if ($Resume) { 1 } else { 0 }
            $hardBit = if ($HardReset) { 1 } else { 0 }
            $query = "EXEC $($stage.procedureName) @RESUME = $resumeBit, @HARD_RESET = $hardBit;"
            $args += @('-Q', $query)
        }
        elseif ($stage.path) {
            $scriptPath = Join-Path $sqlRoot $stage.path
            if (-not (Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }
            $args += @('-i', $scriptPath)
        }
        else {
            throw "Stage $($stage.id) has no procedureName/path"
        }

        if ($DryRun) {
            "[DRY] $sqlcmd -S $($ep.Server) -d $database ..." | Set-Content $logFile
        }
        else {
            $p = Start-Process -FilePath $sqlcmd -ArgumentList $args `
                -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err" `
                -NoNewWindow -PassThru -Wait
            $exitCode = $p.ExitCode
            if (Test-Path "$logFile.err") { Get-Content "$logFile.err" -ErrorAction SilentlyContinue | Add-Content $logFile }
        }
    }
}
catch {
    $_ | Out-String | Set-Content $logFile
    $exitCode = 1
}

$sw.Stop()
$result = [ordered]@{
    stageId   = $stage.id
    name      = $stage.name
    status    = if ($exitCode -eq 0) { 'Done' } else { 'Failed' }
    exitCode  = $exitCode
    elapsedMs = [int64]$sw.ElapsedMilliseconds
    logPath   = $logFile
}
$result | ConvertTo-Json -Compress
exit $exitCode
