using MigrationShared.Enums;

namespace MigrationShared.Models;

public class MigrationConfig
{
    public string OracleConnectionString { get; set; } = string.Empty;
    public string MssqlConnectionString { get; set; } = string.Empty;
    public string OracleSchema { get; set; } = string.Empty;
    /// <summary>
    /// Per-table Oracle extract slice count (PK/ROWID partition plan). Wizard: "Oracle paralel".
    /// Does <b>not</b> control how many tables run at once — see <see cref="TableParallelism"/>.
    /// </summary>
    public int DegreeOfParallelism { get; set; } = 56;

    /// <summary>
    /// Explicit alias for <see cref="DegreeOfParallelism"/> (Oracle slice count). When &gt; 0, preferred at bind time.
    /// </summary>
    public int OracleParallel { get; set; } = 56;

    /// <summary>
    /// How many transfer packages (tables) migrate concurrently. Independent of Oracle parallel / SQL MAXDOP.
    /// Default 2 — keeps Oracle pool healthy when partition workers are high.
    /// </summary>
    public int TableParallelism { get; set; } = 2;

    public int BatchSize { get; set; } = 50000;
    public int FetchSizeMB { get; set; } = 50;

    /// <summary>
    /// When false, the engine exits immediately unless started with <c>--run</c> (or the web UI passes it).
    /// appsettings'te <c>Migration:AutoStart</c> yoksa motor varsayılan olarak beklemede kalır.
    /// </summary>
    public bool AutoStart { get; set; } = false;

    public List<string> Tables { get; set; } = new();
    public List<string> ExcludeTables { get; set; } = new();
    
    // Schema migration options - Default: false (sadece data migration)
    public bool MigrateIndexes { get; set; } = false;
    public bool MigrateTriggers { get; set; } = false;
    public bool MigrateForeignKeys { get; set; } = false;
    public bool MigratePrimaryKeys { get; set; } = true;  // PK genelde gerekli, default true
    public bool MigrateUniqueConstraints { get; set; } = false;
    public bool MigrateCheckConstraints { get; set; } = false;

    /// <summary>How aggressively to run non-count validation gates (PK aggregates, min/max, etc.).</summary>
    public ValidationMode ValidationMode { get; set; } = ValidationMode.Balanced;

    /// <summary>Above this row count, extended gates are skipped in Balanced mode (RowCount always runs).</summary>
    public long ValidationMaxRowsForExtendedGates { get; set; } = 5_000_000;

    /// <summary>When true, run planned validation immediately after each table's data load.</summary>
    public bool ValidatePerTableAfterLoad { get; set; }

    /// <summary>When true with per-table validation, cancel remaining work after the first failed gate.</summary>
    public bool ValidationFailFast { get; set; }

    /// <summary>Reserved: composite-PK content hash (not implemented; planner ignores).</summary>
    public bool EnableCompositePkHash { get; set; }

    /// <summary>
    /// When true, all partitions of a single table are loaded in parallel instead of sequentially.
    /// Useful for large tables where I/O or network is the bottleneck.
    /// </summary>
    public bool ParallelPartitionLoad { get; set; } = true;

    /// <summary>
    /// Max concurrent partition writers per table when <see cref="ParallelPartitionLoad"/> is true
    /// (wizard: "SQL MAXDOP"). Independent of <see cref="OracleParallel"/> / <see cref="TableParallelism"/>.
    /// </summary>
    public int PartitionDegreeOfParallelism { get; set; } = 48;

    /// <summary>
    /// Wizard/UI alias for <see cref="PartitionDegreeOfParallelism"/>. When &gt; 0, preferred at bind time.
    /// </summary>
    public int SqlMaxDop { get; set; } = 48;

    /// <summary>
    /// When true, each partition is loaded into a dedicated staging table on MSSQL instead
    /// of writing directly to the final table. After all partitions complete, staging tables
    /// are merged into the target (smallest-first) and then dropped. This eliminates lock
    /// contention when multiple threads write to the same target table simultaneously.
    /// </summary>
    public bool UseStagingMerge { get; set; } = false;

    /// <summary>
    /// When true (and the table has a numeric PK), uses MSSQL Partition Switch instead of
    /// INSERT...SELECT for the merge phase. The target table is recreated as a partitioned heap,
    /// each staging table is switched into its corresponding partition (metadata-only, instant),
    /// and partition objects are cleaned up afterwards.
    /// Requires the target to have no clustered index (i.e. MigratePrimaryKeys = false, or PK
    /// not yet created). Falls back to INSERT/SELECT merge if that condition is not met.
    /// Implicitly enables UseStagingMerge.
    /// </summary>
    public bool UsePartitionSwitch { get; set; } = false;

    /// <summary>
    /// When true, sets the target database to BULK_LOGGED recovery before data load and
    /// restores the original recovery model afterwards. Dramatically reduces transaction log
    /// growth during bulk operations. Default: true.
    /// </summary>
    public bool UseBulkLoggedRecovery { get; set; } = true;

    /// <summary>
    /// Tablo başına yeniden aktarım modu. Anahtar: tablo adı (büyük/küçük harf duyarsız).
    /// Belirtilmeyen tablolar için varsayılan davranış geçerlidir (checkpoint varsa devam eder).
    /// </summary>
    public Dictionary<string, TableRetryMode> TableRetryModes { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// When true, MDSYS.SDO_GEOMETRY columns are migrated via WKT bridge (Oracle SDO_UTIL → NVARCHAR staging → geometry/geography).
    /// </summary>
    public bool MigrateSpatial { get; set; } = true;

    /// <summary>
    /// Oracle kaynak EPSG when ALL_SDO_GEOM_METADATA is missing. Key: TABLE.COLUMN (case-insensitive).
    /// </summary>
    public Dictionary<string, int> SpatialSridOverrides { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// When Oracle metadata/geometry SRID is missing (NULL/0) and no per-column override exists,
    /// use this EPSG as source for DotSpatial reproject. İzgaz LOCATION columns are typically Web Mercator (3857).
    /// Set null/0 to disable the fallback (conversion will fail clearly instead of using EPSG:0).
    /// </summary>
    public int? DefaultSpatialSourceSridWhenMissing { get; set; } = 3857;

    /// <summary>
    /// MSSQL hedef EPSG (varsayılan 4326 WGS84 geography). Key: TABLE.COLUMN.
    /// </summary>
    public Dictionary<string, int> SpatialTargetSridOverrides { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// When true, Oracle SELECT uses SDO_CS.TRANSFORM before WKT export (slow on large polygon tables).
    /// When false, WKT is exported as-is and CRS conversion uses DotSpatial at MSSQL post-load (recommended).
    /// </summary>
    public bool TransformSpatialInOracle { get; set; }

    /// <summary>
    /// TABLE.COLUMN keys that rebuild SDO_GEOMETRY with <see cref="SpatialSridOverrides"/> SRID,
    /// transform to target SRID in Oracle via SDO_CS.TRANSFORM, and export WKT via {OracleSchema}.GIS_TO_WKTGEOMETRY.
    /// WKT staging is already in target CRS — MSSQL post-load skips DotSpatial reproject.
    /// </summary>
    public HashSet<string> SpatialReconstructAndTransformInOracle { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// TABLE.COLUMN keys (e.g. CS_READING_PLAN.LOCATION) whose {column}__wkt staging column is kept after post-load.
    /// Required when a downstream migration reads raw Oracle WKT (e.g. energy mgg_cbs_okuma_bolge KonumWkt SRID 3857).
    /// </summary>
    public HashSet<string> KeepSpatialWktStagingColumns { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Extra MSSQL columns not present on the Oracle base table (computed / joined).
    /// Added to DDL; optionally filled after load via Oracle SELECT (see <see cref="ExtraColumnDefinition.FillAfterLoad"/>).
    /// </summary>
    public List<ExtraColumnDefinition> ExtraColumns { get; set; } = new();
}
