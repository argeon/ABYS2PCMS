using MigrationShared.Enums;

namespace MigrationShared.Models;

public class MigrationSummary
{
    public int RunId { get; set; }
    public int TotalTables { get; set; }
    public int CompletedTables { get; set; }
    public int RunningTables { get; set; }
    public int PendingTables { get; set; }
    public int FailedTables { get; set; }
    public double OverallPercentComplete { get; set; }
    public TimeSpan ElapsedTime { get; set; }
    public TimeSpan? EstimatedRemaining { get; set; }
    public double CurrentRowsPerSecond { get; set; }
    public long TotalRowsProcessed { get; set; }
    public long TotalRowsExpected { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime? EstimatedCompletionTime { get; set; }
    public MigrationStatus Status { get; set; }

    /// <summary>Frozen when run is terminal (COMPLETED/FAILED); wall-clock stop time.</summary>
    public DateTime? EndTime { get; set; }

    /// <summary>Tables listed in the run config (all planned transfers).</summary>
    public List<string> ConfiguredTables { get; set; } = new();
    
    // Row count comparison
    public long TotalRowsSource { get; set; }  // Oracle toplam kayıt
    public long TotalRowsLoaded { get; set; }  // MSSQL'e yüklenen kayıt
}
