# Oracle to MSSQL Migration Tool

A production-grade database migration tool for migrating Oracle databases to Microsoft SQL Server with real-time monitoring and progress tracking.

**GitHub sürüm logu:** [`VERSION_LOG.md`](VERSION_LOG.md) (`master` / `deploy` / `hotfix`, tag `vX.Y.Z`)

---

## ⭐ TEK SOLUTION - TÜM PROJELER BİRLİKTE!

**CEVAP: EVET!** Tüm projeler `OracleMssqlMigration.sln` içinde!

```
OracleMssqlMigration.sln
├── MigrationShared     ← Ortak modeller
├── MigrationEngine     ← Console app (Migration)
└── Migratorv0          ← Web UI (Monitoring)
```

**Tek Komutla Başlat:**
- 🚀 PowerShell: `.\start-all.ps1`
- 🚀 Visual Studio: F5 (Multiple Startup Projects)
- 🚀 VS Code: F5

📖 **Detaylı Bilgi:** [TEK_SOLUTION_BILGI.md](TEK_SOLUTION_BILGI.md) | [BASLANGIC.md](BASLANGIC.md) | [INDEX.md](INDEX.md)

---

## Features

### Core Migration Features
- **Interactive Wizard**: 4-step visual configuration wizard with connection testing
- **🚀 One-Click Engine Start** ⭐⭐⭐ NEW!: Start Migration Engine from Web UI with a single button click (no terminal needed!)
- **Table Selection**: Visual table picker showing row counts and schema details
- **Parallel Data Extraction**: Configurable degree of parallelism for high-speed data migration
- **Intelligent Type Mapping**: Automatic Oracle to MSSQL type conversion with warning system
- **Real-time Monitoring**: Web-based dashboard with SignalR for live progress updates
- **Checkpoint/Resume Support**: Automatic checkpoint system allows resuming interrupted migrations
- **Schema Migration**: Complete schema migration including tables, constraints, indexes, and foreign keys
- **Data Validation**: Automatic validation of row counts and checksums post-migration
- **Architecture Visualization**: Built-in Mermaid diagrams showing system architecture and flow
- **Optimized Performance**: Streaming data transfer, bulk copy operations, and index optimization

### NEW: History & Analytics Features ⭐
- **Migration History**: Complete history of all past migrations with detailed stats
- **Connection Profiles**: Save and reuse connection settings with one click
- **Thread Monitoring**: Real-time monitoring of active threads with ETA calculations
- **Performance Metrics**: Detailed performance tracking and analysis
- **Run Comparison**: Compare two migration runs to measure improvements
- **Metrics Tracking**: Track throughput, duration, errors, and efficiency over time
- **Error Analysis** ⭐⭐⭐ NEW!: Comprehensive error tracking and analysis
  - Automatic error logging to SQLite
  - Error dashboard with statistics (total, unresolved, resolved, affected tables)
  - Filter by run, table, error type, status
  - Interactive charts (error type distribution, errors by table)
  - Detailed error view with stack traces
  - Mark errors as resolved (single or batch)
  - CSV export for reporting
  - 8 REST API endpoints for error management

## Prerequisites

- .NET 8 SDK or later
- Oracle database (source)
- Microsoft SQL Server (target)
- Oracle Client libraries (included via NuGet)
- Sufficient disk space (recommend 2x source database size)
- Network connectivity between source and target databases

## Solution Structure

**TÜM PROJELER TEK BİR SOLUTION'DA!** (`OracleMssqlMigration.sln`)

```
OracleMssqlMigration.sln      # ← 3 proje tek solution'da
├── MigrationShared/          # Shared models and enums
├── MigrationEngine/          # Console app for data migration
└── Migratorv0/               # ASP.NET Core web UI (MigrationWeb)
```

**Tek Komutla Tüm Projeleri Build Et:**
```bash
dotnet build OracleMssqlMigration.sln -c Release
```

## Installation

1. Clone or download this repository
2. Open the solution in Visual Studio or your preferred IDE
3. Restore NuGet packages:
   ```bash
   dotnet restore
   ```

## Configuration

### Option 1: Interactive Wizard (Recommended)

The easiest way to configure and start a migration:

1. Start the Web UI:
   ```bash
   cd MigrationWeb
   dotnet run
   ```

2. Open browser: `http://localhost:5000/wizard`

3. Follow the 4-step wizard:
   - **Step 1**: Enter Oracle connection details and test
   - **Step 2**: Enter MSSQL connection details and test
   - **Step 3**: Select tables from Oracle schema (with row counts)
   - **Step 4**: Configure performance settings and schema options

4. The wizard will:
   - Test both connections before proceeding
   - Display available tables with estimated row counts
   - Generate and save configuration automatically
   - Redirect you to the Start page

5. 🚀 **NEW: One-Click Start!**
   - Click **"Start Engine Now"** button on the Start page
   - Engine automatically builds and starts
   - Redirects to Dashboard for real-time monitoring
   - **No terminal commands needed!**

### Option 2: Manual Configuration

Edit `MigrationEngine/appsettings.json` directly:

```json
{
  "Migration": {
    "OracleConnectionString": "User Id=YOUR_USER;Password=YOUR_PASSWORD;Data Source=localhost:1521/ORCL;",
    "MssqlConnectionString": "Server=localhost;Database=TargetDB;User Id=sa;Password=YOUR_PASSWORD;TrustServerCertificate=true;",
    "OracleSchema": "YOUR_SCHEMA_NAME",
    "DegreeOfParallelism": 8,
    "BatchSize": 50000,
    "FetchSizeMB": 50,
    "Tables": [],
    "ExcludeTables": ["TEMP_*", "LOG_*"]
  }
}
```

**Configuration Options:**

- `OracleConnectionString`: Connection string for source Oracle database
- `MssqlConnectionString`: Connection string for target SQL Server database
- `OracleSchema`: Oracle schema name to migrate (case-sensitive)
- `DegreeOfParallelism`: Number of parallel workers (default: 8, recommended: CPU cores)
- `BatchSize`: Rows per batch for SqlBulkCopy (default: 50000)
- `FetchSizeMB`: Oracle fetch buffer size in MB (default: 50)
- `Tables`: Specific tables to migrate (empty = all tables)
- `ExcludeTables`: Table name patterns to exclude (supports wildcards)

### MigrationWeb Configuration

Edit `MigrationWeb/appsettings.json` to point to the same checkpoint database:

```json
{
  "Checkpoint": {
    "SqlitePath": "migration_checkpoint.db"
  }
}
```

## Running the Migration

### 🎯 TEK KOMUTLA TÜM SİSTEMİ ÇALIŞTIR

**CEVAP: EVET! Tek solution, 3 farklı yöntemle çalıştırabilirsiniz:**

### 🚀 Yöntem 1: PowerShell Script (EN KOLAY)

```powershell
# Her iki projeyi de otomatik başlatır
.\start-all.ps1
```

Bu script:
- ✅ Tüm 3 projeyi tek komutla build eder (`OracleMssqlMigration.sln`)
- ✅ Web UI'ı bir pencerede başlatır
- ✅ Migration Engine'i başka pencerede başlatır
- ✅ Browser'ı otomatik açar
- ✅ Tek PowerShell komutla her şey çalışır!

### 🚀 Yöntem 2: VS Code (F5)

Visual Studio Code'da açın ve F5'e basın:
- `.vscode/launch.json` hazır
- "Web UI + Engine" konfigürasyonu ile her ikisi de başlar
- Tek tuşla debug modunda çalışır!

### 🚀 Yöntem 3: Visual Studio

`OracleMssqlMigration.sln` dosyasını açın:
1. Solution Explorer'da her iki projeye sağ tıklayın
2. "Set as Startup Project" → "Multiple Startup Projects"
3. `MigrationEngine` ve `Migratorv0` için Action = "Start"
4. F5'e basın - her ikisi de başlar!

### 📋 Alternatif: Adım Adım (İlk Kurulum)

**Adım 1: İlk Konfigürasyon**
```powershell
.\start-migration.ps1
```

**Adım 2: Wizard'dan Ayarları Yap**
- Browser otomatik açılır
- Wizard'da connectionları gir
- Tabloları seç
- "Save & Continue"

**Adım 3: Engine'i Başlat**
- Script size komutu verir veya
- VS Code** (F5)
- Press F5
- Select "Web UI + Engine" from compound configurations

See [QUICK_START.md](QUICK_START.md) for detailed instructions.

---

### Manual Startup

If you prefer manual control:

### Step 1: Start the Migration Engine

```bash
cd MigrationEngine
dotnet run
```

The engine will:
1. Read Oracle schema metadata
2. Generate and execute MSSQL DDL statements
3. Migrate data in parallel with progress tracking
4. Create indexes and foreign keys
5. Validate data integrity
6. Write progress to SQLite checkpoint database

**Important**: The engine sets the database recovery model to `BULK_LOGGED` during migration and restores it to `FULL` afterward. **Take a full backup** of the target database after migration completes.

### Step 2: Monitor via Web Dashboard

In a separate terminal:

```bash
cd MigrationWeb
dotnet run
```

Open your browser to: `http://localhost:5000`

The dashboard displays:
- Overall migration progress
- Per-table status and progress
- Real-time throughput (rows/sec)
- Live log stream
- Type mapping warnings
- Export report functionality

### Step 3: Resume Interrupted Migrations

If the migration is interrupted (network issue, system restart, etc.), simply restart the MigrationEngine:

```bash
cd MigrationEngine
dotnet run
```

The engine will:
- Detect the existing checkpoint database
- Skip completed tables and partitions
- Resume from where it stopped
- Continue with pending or failed partitions

## Migration Phases

The migration executes in 6 phases:

### Phase 1: Schema Discovery
- Queries Oracle metadata (tables, columns, constraints, indexes)
- Applies table filters (include/exclude)
- Builds in-memory schema model

### Phase 2: DDL Generation
- Maps Oracle types to MSSQL types
- Generates CREATE TABLE statements
- Generates constraint and index definitions
- Collects type mapping warnings
- Detects circular foreign key dependencies

### Phase 3: DDL Execution
- Creates tables (without indexes or foreign keys)
- Creates primary keys and unique constraints
- Sets recovery model to BULK_LOGGED

### Phase 4: Data Migration (Parallel)
- Calculates partitions per table (by ROWID or numeric PK)
- Extracts data in parallel from Oracle
- Streams data via SqlBulkCopy to MSSQL
- Updates checkpoint after each partition
- Logs progress every 50K rows

### Phase 5: Post-Load DDL
- Creates all indexes with compression and parallelism
- Adds foreign key constraints (with error handling)

### Phase 6: Validation
- Compares row counts (Oracle vs MSSQL)
- Compares checksums for numeric primary keys
- Logs validation results
- Restores recovery model to FULL

## Type Mapping

The tool automatically maps Oracle data types to MSSQL equivalents:

| Oracle Type | MSSQL Type | Notes |
|-------------|------------|-------|
| NUMBER(p,0) | SMALLINT, INT, BIGINT, or DECIMAL(p,0) | Based on precision |
| NUMBER(p,s) | DECIMAL(p,s) | Preserves precision and scale |
| NUMBER | DECIMAL(38,10) | Warning: Review precision requirements |
| VARCHAR2(n) | NVARCHAR(n) | Max 4000 |
| CLOB | NVARCHAR(MAX) | |
| BLOB | VARBINARY(MAX) | |
| DATE | DATETIME2(0) | Warning: Oracle DATE includes time |
| TIMESTAMP(n) | DATETIME2(n) | |
| TIMESTAMP WITH TIME ZONE | DATETIMEOFFSET(n) | |
| ROWID/UROWID | SKIPPED | Warning: Not portable |

**Warnings** are generated for:
- Loss of precision or data
- Type conversions requiring review
- Deprecated or non-portable types

View all warnings in the web dashboard under the Warnings panel.

## Performance Tuning

### Recommended Settings

**Small databases (< 10GB):**
```json
{
  "DegreeOfParallelism": 4,
  "BatchSize": 25000,
  "FetchSizeMB": 25
}
```

**Medium databases (10-100GB):**
```json
{
  "DegreeOfParallelism": 8,
  "BatchSize": 50000,
  "FetchSizeMB": 50
}
```

**Large databases (> 100GB):**
```json
{
  "DegreeOfParallelism": 16,
  "BatchSize": 100000,
  "FetchSizeMB": 100
}
```

### Performance Tips

1. **Network**: Ensure low-latency, high-bandwidth connection between Oracle and MSSQL
2. **Disk I/O**: Use fast storage (SSD) for target SQL Server
3. **Memory**: Allocate sufficient memory to both databases
4. **Parallelism**: Start with CPU core count, adjust based on throughput
5. **Batch Size**: Larger batches = fewer transactions but more memory
6. **Indexes**: Created post-load to avoid overhead during bulk insert

## Troubleshooting

### Issue: ORA-01017: invalid username/password

**Solution**: Check Oracle connection string credentials. Ensure schema name is correct and case-sensitive.

### Issue: Migration Engine stops with "Connection timeout"

**Solution**:
- Check network connectivity to Oracle/MSSQL
- Increase timeout in connection strings: `Connection Timeout=300;`
- Review firewall rules

### Issue: Type mapping warnings

**Solution**: Review warnings in the dashboard. Most are informational. Critical warnings require schema review:
- `NUMBER` without precision → Review financial columns
- `FLOAT` type → Use DECIMAL for financial data
- `ROWID` columns → These are skipped (internal Oracle identifiers)

### Issue: Validation failures (row count mismatch)

**Solution**:
1. Check if tables are still being written to during migration
2. Review failed partition logs in checkpoint database
3. Re-run migration (will skip completed partitions)
4. Check for triggers or constraints causing silent row rejections

### Issue: Foreign key creation errors

**Solution**:
- Check for circular FK dependencies (logged during DDL generation)
- Review FK constraint names (must be unique)
- Ensure referenced tables migrated successfully
- Foreign keys can be manually created post-migration if needed

### Issue: Out of memory errors

**Solution**:
- Reduce `BatchSize` (e.g., from 50000 to 25000)
- Reduce `FetchSizeMB` (e.g., from 50 to 25)
- Reduce `DegreeOfParallelism`
- Increase SQL Server memory allocation

## Logs and Checkpoint Database

### Log Files

Logs are written to: `MigrationEngine/logs/migration-YYYY-MM-DD.log`

Log levels:
- **INFO**: Phase transitions, milestones, success messages
- **WARNING**: Type mapping issues, retries, slow operations
- **ERROR**: Failures, validation errors, critical issues

### Checkpoint Database

Location: `migration_checkpoint.db` (SQLite)

Tables:
- `migration_runs`: Overall migration metadata
- `table_checkpoints`: Per-table/partition status
- `progress_events`: Time-series progress data

Query checkpoint database directly:
```bash
sqlite3 migration_checkpoint.db
sqlite> SELECT table_name, status, rows_processed FROM table_checkpoints;
```

## Post-Migration Checklist

1. **Backup**: Take FULL backup of target SQL Server database
2. **Statistics**: Update statistics on all tables
   ```sql
   EXEC sp_MSforeachtable 'UPDATE STATISTICS ? WITH FULLSCAN';
   ```
3. **Index Optimization**: Review and optimize indexes if needed
4. **Application Testing**: Test application compatibility with MSSQL
5. **Performance Testing**: Compare query performance
6. **Review Warnings**: Address any critical type mapping warnings
7. **Cleanup**: Remove checkpoint database and logs after validation

## Architecture

### Communication Flow

```
MigrationEngine (Console) → SQLite Checkpoint DB
                                    ↓
MigrationWeb (ASP.NET)     → Polls SQLite every 2s
                                    ↓
SignalR Hub                 → Broadcasts to Browsers
```

This decoupled architecture allows:
- Engine and Web to run independently
- Web UI to restart without affecting migration
- Multiple Web instances for load balancing
- Easy debugging via SQLite inspection

## Security Considerations

1. **Connection Strings**: Store credentials securely (Azure Key Vault, environment variables)
2. **Network**: Use VPN or private network for database connections
3. **Permissions**: Grant minimal required permissions:
   - Oracle: SELECT on source schema
   - MSSQL: CREATE TABLE, INSERT, CREATE INDEX
4. **Checkpoint DB**: Protect SQLite file (contains connection strings in `config_json`)

## Known Limitations

1. **Oracle-specific features**: PL/SQL, packages, sequences not migrated
2. **Partitioned tables**: Migrated as regular tables (partitioning not preserved)
3. **Materialized views**: Not migrated (create as tables or views in MSSQL)
4. **Synonyms**: Not migrated
5. **Oracle Jobs**: Not migrated (recreate as SQL Server Agent jobs)
6. **XML Schema Collections**: Limited support
7. **LOB data > 2GB**: May fail (VARBINARY(MAX) limit)

## Support and Contributing

For issues, questions, or contributions, please contact the development team.

## License

Proprietary - All rights reserved.
