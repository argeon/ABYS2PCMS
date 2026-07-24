using MigrationEngine.Schema;
using Oracle.ManagedDataAccess.Client;
using Serilog;
using System.Data;
using System.Globalization;

namespace MigrationEngine.Extractors;

public class OracleParallelExtractor
{
    private readonly string _connectionString;
    private readonly int _fetchSizeMB;
    private const int MaxRetries = 3;
    private const int RetryDelayMs = 5000;

    public OracleParallelExtractor(string connectionString, int fetchSizeMB = 50)
    {
        _connectionString = connectionString;
        _fetchSizeMB = fetchSizeMB;
    }

    public async Task<IDataReader> ExtractPartitionAsync(
        string schemaName,
        string tableName,
        IReadOnlyList<OracleColumnSelect> columns,
        string? startRowId,
        string? endRowId,
        long? startPkValue,
        long? endPkValue,
        string? pkColumnName,
        CancellationToken ct,
        bool endRowIdInclusive = false)
    {
        if (columns == null || columns.Count == 0)
            throw new ArgumentException("At least one column is required for extraction.", nameof(columns));

        var connection = new OracleConnection(_connectionString);
        var columnList = string.Join(", ",
            columns.Select(c => $"{c.SelectExpression} AS {QuoteOracleIdentifier(c.Alias)}"));
        const string tableAlias = "t";
        var fromClause = $"{schemaName}.{tableName} {tableAlias}";
        
        for (int attempt = 1; attempt <= MaxRetries; attempt++)
        {
            try
            {
                await connection.OpenAsync(ct);

                var cmd = connection.CreateCommand();
                cmd.FetchSize = _fetchSizeMB * 1024 * 1024;
                cmd.CommandTimeout = 0;

                var hasSpatial = columns.Any(c =>
                    c.SelectExpression.Contains("SDO_UTIL.TO_WKTGEOMETRY", StringComparison.OrdinalIgnoreCase)
                    || c.SelectExpression.Contains("GIS_TO_WKTGEOMETRY", StringComparison.OrdinalIgnoreCase));
                if (hasSpatial)
                {
                    cmd.InitialLOBFetchSize = -1;
                    Log.Information(
                        "Oracle spatial extract starting for {Schema}.{Table} (partition {StartPk}-{EndPk}) — WKT conversion may take several minutes",
                        schemaName, tableName,
                        startPkValue?.ToString() ?? startRowId ?? "*",
                        endPkValue?.ToString() ?? endRowId ?? "*");
                }

                if (!string.IsNullOrEmpty(pkColumnName) && startPkValue.HasValue && endPkValue.HasValue)
                {
                    var pk = $"{tableAlias}.{QuoteOracleIdentifier(pkColumnName)}";
                    cmd.CommandText = $"SELECT {columnList} FROM {fromClause} WHERE {pk} >= :startPk AND {pk} < :endPk";
                    cmd.Parameters.Add("startPk", OracleDbType.Int64).Value = startPkValue.Value;
                    cmd.Parameters.Add("endPk", OracleDbType.Int64).Value = endPkValue.Value;
                }
                else if (!string.IsNullOrEmpty(startRowId) && !string.IsNullOrEmpty(endRowId))
                {
                    // Last partition must use <= MAX(ROWID); intermediate partitions keep < next
                    // boundary so the shared boundary row is not loaded twice.
                    var endOp = endRowIdInclusive ? "<=" : "<";
                    cmd.CommandText = $"SELECT {columnList} FROM {fromClause} WHERE {tableAlias}.ROWID >= CHARTOROWID(:startRowId) AND {tableAlias}.ROWID {endOp} CHARTOROWID(:endRowId)";
                    cmd.Parameters.Add("startRowId", OracleDbType.Varchar2).Value = startRowId;
                    cmd.Parameters.Add("endRowId", OracleDbType.Varchar2).Value = endRowId;
                }
                else
                {
                    cmd.CommandText = $"SELECT {columnList} FROM {fromClause}";
                }

                // CloseConnection: reader dispose olunca bağlantı kapanır.
                // OwnedOracleDataReader: cmd referansını tutar — ODP.NET cmd GC/dispose olursa
                // reader ORA-50045 (Invalid operation on a closed object) verir.
                var reader = (OracleDataReader)await cmd.ExecuteReaderAsync(CommandBehavior.CloseConnection, ct);
                if (hasSpatial)
                {
                    Log.Information(
                        "Oracle spatial reader opened for {Schema}.{Table} — streaming rows",
                        schemaName, tableName);
                }
                return new OwnedOracleDataReader(cmd, reader);
            }
            catch (Exception ex) when (attempt < MaxRetries)
            {
                Log.Warning(ex, "Attempt {Attempt}/{MaxRetries} failed for table {Table}. Retrying in {Delay}ms", 
                    attempt, MaxRetries, tableName, RetryDelayMs);
                
                await connection.DisposeAsync();
                connection = new OracleConnection(_connectionString);
                await Task.Delay(RetryDelayMs * (1 << (attempt - 1)), ct); // 5s, 10s, 20s
            }
            catch (Exception ex)
            {
                Log.Error(ex, "All {MaxRetries} attempts failed for table {Table}", MaxRetries, tableName);
                await connection.DisposeAsync();
                throw;
            }
        }

        throw new InvalidOperationException("Extraction failed after all retries");
    }

    public async Task<List<(string startRowId, string endRowId)>> CalculateRowIdPartitionsAsync(
        string schemaName,
        string tableName,
        int partitionCount,
        CancellationToken ct)
    {
        using var connection = new OracleConnection(_connectionString);
        await connection.OpenAsync(ct);

        var sql = $@"
            SELECT ROWIDTOCHAR(ROWID) as row_id
            FROM (
                SELECT ROWID, ROW_NUMBER() OVER (ORDER BY ROWID) as rn,
                       COUNT(*) OVER() as total_count
                FROM {schemaName}.{tableName}
            )
            WHERE MOD(rn - 1, CEIL(total_count / {partitionCount})) = 0
            ORDER BY ROWID";

        var boundaries = new List<string>();
        using (var cmd = new OracleCommand(sql, connection))
        {
            using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                boundaries.Add(reader.GetString(0));
            }
        }

        if (boundaries.Count == 0)
        {
            Log.Warning("No rows found in table {Schema}.{Table}", schemaName, tableName);
            return new List<(string, string)>();
        }

        var lastRowIdSql = $"SELECT ROWIDTOCHAR(MAX(ROWID)) FROM {schemaName}.{tableName}";
        using (var cmd = new OracleCommand(lastRowIdSql, connection))
        {
            var lastRowId = await cmd.ExecuteScalarAsync(ct);
            if (lastRowId != null && lastRowId != DBNull.Value)
            {
                boundaries.Add(lastRowId.ToString()!);
            }
        }

        var partitions = new List<(string, string)>();
        for (int i = 0; i < boundaries.Count - 1; i++)
        {
            partitions.Add((boundaries[i], boundaries[i + 1]));
        }

        return partitions;
    }

    /// <summary>
    /// PK aralığını eşit bölmek (min–max / N) satır sayısında büyük dengesizliğe yol açar.
    /// NTILE ile sıralı PK üzerinde yaklaşık <b>eşit satır</b> kovaları üretir; uç durumlarda min–max yöntemine düşer.
    /// </summary>
    public async Task<List<(long startPk, long endPk)>> CalculatePkPartitionsAsync(
        string schemaName,
        string tableName,
        string pkColumnName,
        int partitionCount,
        CancellationToken ct)
    {
        partitionCount = Math.Max(1, partitionCount);

        using var connection = new OracleConnection(_connectionString);
        await connection.OpenAsync(ct);

        var countSql = $"SELECT COUNT(*) FROM {schemaName}.{tableName}";
        long rowCount;
        using (var cmd = new OracleCommand(countSql, connection))
        {
            var scalar = await cmd.ExecuteScalarAsync(ct);
            rowCount = scalar == null || scalar == DBNull.Value
                ? 0
                : Convert.ToInt64(scalar, CultureInfo.InvariantCulture);
        }

        if (rowCount == 0)
            return new List<(long, long)>();

        var ntile = (int)Math.Min(partitionCount, rowCount);

        var ntileSql = $@"
            WITH numbered AS (
                SELECT {pkColumnName} AS pk_val, NTILE(:nt) OVER (ORDER BY {pkColumnName}) AS bkt
                FROM {schemaName}.{tableName}
            ),
            bounds AS (
                SELECT bkt, MIN(pk_val) AS lo, MAX(pk_val) AS hi
                FROM numbered
                GROUP BY bkt
            ),
            ordered AS (
                SELECT bkt, lo, hi, LEAD(lo) OVER (ORDER BY bkt) AS next_lo
                FROM bounds
            )
            SELECT lo, NVL(next_lo, hi + 1) AS end_pk FROM ordered ORDER BY bkt";

        try
        {
            var partitions = new List<(long, long)>();
            using (var cmd = new OracleCommand(ntileSql, connection))
            {
                cmd.BindByName = true;
                cmd.Parameters.Add("nt", OracleDbType.Int32).Value = ntile;
                using var reader = await cmd.ExecuteReaderAsync(ct);
                while (await reader.ReadAsync(ct))
                {
                    var lo = Convert.ToInt64(reader.GetValue(0), CultureInfo.InvariantCulture);
                    var endPk = Convert.ToInt64(reader.GetValue(1), CultureInfo.InvariantCulture);
                    partitions.Add((lo, endPk));
                }
            }

            if (partitions.Count > 0)
            {
                Log.Information(
                    "PK partitions (NTILE ~equal rows) for {Schema}.{Table}: {Buckets} buckets, NTILE={Nt}",
                    schemaName, tableName, partitions.Count, ntile);
                return partitions;
            }
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "NTILE partition plan failed for {Schema}.{Table}; falling back to min–max ranges", schemaName, tableName);
        }

        return await CalculatePkPartitionsByKeyRangeFallbackAsync(
            connection, schemaName, tableName, pkColumnName, partitionCount, ct);
    }

    private static async Task<List<(long startPk, long endPk)>> CalculatePkPartitionsByKeyRangeFallbackAsync(
        OracleConnection connection,
        string schemaName,
        string tableName,
        string pkColumnName,
        int partitionCount,
        CancellationToken ct)
    {
        var minMaxSql = $"SELECT MIN({pkColumnName}), MAX({pkColumnName}) FROM {schemaName}.{tableName}";
        long minPk, maxPk;

        using (var cmd = new OracleCommand(minMaxSql, connection))
        {
            using var reader = await cmd.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct) || reader.IsDBNull(0))
                return new List<(long, long)>();

            minPk = Convert.ToInt64(reader.GetValue(0), CultureInfo.InvariantCulture);
            maxPk = Convert.ToInt64(reader.GetValue(1), CultureInfo.InvariantCulture);
        }

        var partitions = new List<(long, long)>();
        var range = maxPk - minPk + 1;
        var partitionSize = Math.Max(1, range / partitionCount);

        for (var i = 0; i < partitionCount; i++)
        {
            var start = minPk + i * partitionSize;
            var end = i == partitionCount - 1 ? maxPk + 1 : start + partitionSize;
            partitions.Add((start, end));
        }

        Log.Information(
            "PK partitions (min–max key ranges) for {Schema}.{Table}: {Count} buckets",
            schemaName, tableName, partitions.Count);

        return partitions;
    }

    private static string QuoteOracleIdentifier(string name)
    {
        if (string.IsNullOrEmpty(name))
            return name;

        if (name.All(c => char.IsLetterOrDigit(c) || c == '_' || c == '$' || c == '#'))
            return name.ToUpperInvariant();

        return $"\"{name.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
    }
}
