namespace MigrationShared.Models;

/// <summary>
/// Oracle SMS.CS_READING_PLAN → MSSQL aktarım tanımı (tek tablo, LOCATION WGS84).
/// </summary>
public class CsReadingPlanMigrationDefinition
{
    public const string SourceTable = "CS_READING_PLAN";
    public const string DefaultOracleSchema = "SMS";
    public const string LocationColumn = "LOCATION";
    /// <summary>Oracle LOCATION bileşenleri EPSG:3857 (Web Mercator) olarak yeniden oluşturulur.</summary>
    public const int DefaultSourceSrid = 3857;
    public const int Wgs84Srid = 4326;
    public const string OkumaBolgeAdiColumn = "OKUMA_BOLGE_ADI";
    public const string DefaultReadingPeriod = "202607";

    /// <summary>Oracle kaynak EPSG; boşsa metadata → SDO_SRID → DefaultSourceSrid (3857).</summary>
    public int? SourceSrid { get; set; }

    /// <summary>CS_READING_PERIOD.PERIOD filtresi (OkumaBolgeAdi hesabı).</summary>
    public string ReadingPeriod { get; set; } = DefaultReadingPeriod;

    public string OracleConnectionString { get; set; } = string.Empty;
    public string OracleSchema { get; set; } = DefaultOracleSchema;

    public string MssqlConnectionString { get; set; } = string.Empty;

    /// <summary>Hedef tablo adı (varsayılan: CS_READING_PLAN).</summary>
    public string TargetTableName { get; set; } = SourceTable;

    public int DegreeOfParallelism { get; set; } = 4;
    public int BatchSize { get; set; } = 50_000;
    public int FetchSizeMB { get; set; } = 50;

    public bool MigratePrimaryKeys { get; set; } = true;
    public bool MigrateForeignKeys { get; set; } = false;
    public bool MigrateIndexes { get; set; } = false;
    public bool MigrateUniqueConstraints { get; set; } = false;
    public bool MigrateCheckConstraints { get; set; } = false;

    /// <summary>True ise hedef tablo silinip yeniden oluşturulur.</summary>
    public bool HardReset { get; set; }

    public DateTime? UpdatedAtUtc { get; set; }
}
