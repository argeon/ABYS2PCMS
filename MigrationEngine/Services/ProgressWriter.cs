using MigrationEngine.Checkpoint;
using MigrationShared.Enums;
using MigrationShared.Models;
using Serilog;

namespace MigrationEngine.Services;

public class ProgressWriter
{
    private readonly CheckpointRepository _checkpoint;
    private readonly int _runId;

    public ProgressWriter(CheckpointRepository checkpoint, int runId)
    {
        _checkpoint = checkpoint;
        _runId = runId;
    }

    public void WriteProgress(string tableName, string partitionKey, string phase, 
        MigrationStatus status, long rowsProcessed, long totalRows, double rowsPerSecond, string message, string? warning = null)
    {
        var evt = new ProgressEvent
        {
            TableName = tableName,
            PartitionKey = partitionKey,
            Phase = phase,
            Status = status,
            RowsProcessed = rowsProcessed,
            TotalRows = totalRows,
            PercentComplete = totalRows > 0 ? (rowsProcessed * 100.0 / totalRows) : 0,
            RowsPerSecond = rowsPerSecond,
            Message = message,
            Timestamp = DateTime.UtcNow,
            Warning = warning
        };

        _checkpoint.WriteProgressEvent(_runId, evt);
    }

    public void WritePhaseStart(string phase, string message)
    {
        var evt = new ProgressEvent
        {
            Phase = phase,
            Status = MigrationStatus.Running,
            Message = message,
            Timestamp = DateTime.UtcNow
        };

        _checkpoint.WriteProgressEvent(_runId, evt);
        Log.Information("[{Phase}] {Message}", phase, message);
    }

    public void WritePhaseComplete(string phase, string message)
    {
        var evt = new ProgressEvent
        {
            Phase = phase,
            Status = MigrationStatus.Done,
            Message = message,
            Timestamp = DateTime.UtcNow
        };

        _checkpoint.WriteProgressEvent(_runId, evt);
        Log.Information("[{Phase}] {Message}", phase, message);
    }

    public void WriteWarning(string tableName, string message, string? warning = null)
    {
        var evt = new ProgressEvent
        {
            TableName = tableName,
            Status = MigrationStatus.Running,
            Message = message,
            Warning = warning,
            Timestamp = DateTime.UtcNow
        };

        _checkpoint.WriteProgressEvent(_runId, evt);
        Log.Warning("[{Table}] {Message}", tableName, message);
    }
}
