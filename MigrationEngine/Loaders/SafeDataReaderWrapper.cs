using System.Collections;
using System.Data;
using System.Data.Common;
using MigrationEngine.Schema;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;
using Serilog;

namespace MigrationEngine.Loaders;

/// <summary>
/// Wraps an IDataReader to safely handle invalid DateTime values from Oracle.
/// Converts invalid dates to NULL to prevent ArgumentOutOfRangeException.
/// Uses schema-derived CLR types so SqlBulkCopy never calls Oracle GetFieldType (UDT / GET_TYPE_SHAPE).
/// Inherits DbDataReader so SqlBulkCopy uses our typed value conversions.
/// </summary>
public sealed class SafeDataReaderWrapper : DbDataReader
{
    private readonly DbDataReader _innerReader;
    private readonly string _tableName;
    private readonly Type[] _fieldTypes;
    private readonly bool[] _useDateTimeOffset;
    private readonly bool _leaveOpen;
    private static readonly DateTime SqlDateTimeMin = new(1753, 1, 1);
    private static readonly DateTime SqlDateTimeMax = new(9999, 12, 31, 23, 59, 59, 997);
    public long RowsRead { get; private set; }

    public SafeDataReaderWrapper(
        IDataReader innerReader,
        string tableName,
        IReadOnlyList<ColumnSchema>? expectedColumns = null,
        IReadOnlyDictionary<string, string>? sourceToDestinationSqlType = null,
        bool leaveOpen = false)
    {
        _innerReader = innerReader as DbDataReader
            ?? throw new ArgumentException("SafeDataReaderWrapper requires a DbDataReader (e.g. OracleDataReader).", nameof(innerReader));
        _tableName = tableName;
        _leaveOpen = leaveOpen;
        _fieldTypes = new Type[_innerReader.FieldCount];
        _useDateTimeOffset = new bool[_innerReader.FieldCount];

        for (var i = 0; i < _innerReader.FieldCount; i++)
        {
            var readerName = _innerReader.GetName(i);
            var schemaColumn = expectedColumns?.FirstOrDefault(c =>
                string.Equals(c.ColumnName, readerName, StringComparison.OrdinalIgnoreCase));

            string? destinationSqlType = null;
            sourceToDestinationSqlType?.TryGetValue(readerName, out destinationSqlType);
            var bulkCopyType = ResolveBulkCopyClrType(schemaColumn, destinationSqlType);
            _fieldTypes[i] = bulkCopyType;
            _useDateTimeOffset[i] = bulkCopyType == typeof(DateTimeOffset);

            if (bulkCopyType == typeof(DateTime) || bulkCopyType == typeof(DateTimeOffset))
            {
                Log.Debug(
                    "SafeDataReader: [{Table}].[{Column}] Oracle={OracleType} destSql={DestSql} clr={ClrType}",
                    tableName,
                    readerName,
                    schemaColumn?.DataType ?? "?",
                    destinationSqlType ?? "?",
                    bulkCopyType.Name);
            }
        }

        var temporalCount = _fieldTypes.Count(t => t == typeof(DateTime) || t == typeof(DateTimeOffset));
        if (temporalCount > 0)
        {
            Log.Information("SafeDataReader: Protecting {Count} temporal columns in table {Table}",
                temporalCount, tableName);
        }
    }

    public override object GetValue(int ordinal)
    {
        var value = ReadValue(ordinal);
        return NormalizeForBulkCopy(ordinal, value);
    }

    public override Type GetFieldType(int ordinal) => _fieldTypes[ordinal];

    public override string GetDataTypeName(int ordinal) => ClrTypeToDataTypeName(_fieldTypes[ordinal]);

    public override DateTime GetDateTime(int ordinal)
    {
        var value = GetValue(ordinal);
        if (value is DBNull)
            throw new InvalidCastException($"Column {ordinal} is NULL");
        return value is DateTimeOffset dto ? dto.DateTime : (DateTime)value;
    }

    public override bool GetBoolean(int ordinal) => _innerReader.GetBoolean(ordinal);
    public override byte GetByte(int ordinal) => _innerReader.GetByte(ordinal);
    public override long GetBytes(int ordinal, long dataOffset, byte[]? buffer, int bufferOffset, int length)
        => _innerReader.GetBytes(ordinal, dataOffset, buffer, bufferOffset, length);
    public override char GetChar(int ordinal) => _innerReader.GetChar(ordinal);
    public override long GetChars(int ordinal, long dataOffset, char[]? buffer, int bufferOffset, int length)
        => _innerReader.GetChars(ordinal, dataOffset, buffer, bufferOffset, length);
    public override decimal GetDecimal(int ordinal) => _innerReader.GetDecimal(ordinal);
    public override double GetDouble(int ordinal) => _innerReader.GetDouble(ordinal);
    public override float GetFloat(int ordinal) => _innerReader.GetFloat(ordinal);
    public override Guid GetGuid(int ordinal) => _innerReader.GetGuid(ordinal);
    public override short GetInt16(int ordinal) => _innerReader.GetInt16(ordinal);
    public override int GetInt32(int ordinal) => _innerReader.GetInt32(ordinal);
    public override long GetInt64(int ordinal) => _innerReader.GetInt64(ordinal);
    public override string GetString(int ordinal)
    {
        var value = ReadValue(ordinal);
        return value is DBNull ? throw new InvalidCastException($"Column {ordinal} is NULL") : (string)value;
    }

    public override int GetValues(object[] values)
    {
        for (var i = 0; i < FieldCount; i++)
            values[i] = GetValue(i);
        return FieldCount;
    }

    public override bool IsDBNull(int ordinal) => _innerReader.IsDBNull(ordinal);
    public override int FieldCount => _innerReader.FieldCount;
    public override string GetName(int ordinal) => _innerReader.GetName(ordinal);
    public override int GetOrdinal(string name) => _innerReader.GetOrdinal(name);
    public override bool Read()
    {
        var result = _innerReader.Read();
        if (result) RowsRead++;
        return result;
    }

    public override int Depth => _innerReader.Depth;
    public override bool IsClosed => _innerReader.IsClosed;
    public override int RecordsAffected => _innerReader.RecordsAffected;
    public override bool NextResult() => _innerReader.NextResult();
    public override bool HasRows => _innerReader.HasRows;
    public override object this[int ordinal] => GetValue(ordinal);
    public override object this[string name] => GetValue(GetOrdinal(name));
    public override IEnumerator GetEnumerator() => _innerReader.GetEnumerator();

    protected override void Dispose(bool disposing)
    {
        if (disposing && !_leaveOpen)
            _innerReader.Dispose();
        base.Dispose(disposing);
    }

    private object ReadValue(int ordinal)
    {
        var targetType = _fieldTypes[ordinal];
        if (targetType == typeof(DateTime) || targetType == typeof(DateTimeOffset))
            return ReadTemporalValue(ordinal, _useDateTimeOffset[ordinal]);

        if (targetType == typeof(string))
            return ReadStringValue(ordinal);

        return CoerceToTargetType(_innerReader.GetValue(ordinal), targetType);
    }

    private object NormalizeForBulkCopy(int ordinal, object value)
    {
        if (value is DBNull or null)
            return DBNull.Value;

        if (!_useDateTimeOffset[ordinal] && value is DateTimeOffset dto)
            return dto.DateTime;

        return value;
    }

    private static Type ResolveBulkCopyClrType(ColumnSchema? schemaColumn, string? destinationSqlType)
    {
        var dest = NormalizeSqlTypeName(destinationSqlType);
        if (dest is "DATETIME2" or "DATETIME" or "SMALLDATETIME" or "DATE")
            return typeof(DateTime);
        if (dest == "DATETIMEOFFSET")
            return typeof(DateTimeOffset);

        if (schemaColumn != null && IsTemporalOracleType(schemaColumn.DataType))
            return typeof(DateTime);

        return schemaColumn != null
            ? TypeMapper.MapToClrType(schemaColumn)
            : typeof(string);
    }

    private static bool IsTemporalOracleType(string oracleType)
    {
        var t = oracleType.ToUpperInvariant();
        return t == "DATE" || t.StartsWith("TIMESTAMP", StringComparison.Ordinal);
    }

    private static string? NormalizeSqlTypeName(string? sqlType)
    {
        if (string.IsNullOrWhiteSpace(sqlType))
            return null;

        var normalized = sqlType.ToUpperInvariant();
        var paren = normalized.IndexOf('(');
        return paren >= 0 ? normalized[..paren] : normalized;
    }

    private object ReadStringValue(int ordinal)
    {
        if (_innerReader.IsDBNull(ordinal))
            return DBNull.Value;

        if (_innerReader is OracleDataReader oracleReader)
        {
            var oracleValue = oracleReader.GetOracleValue(ordinal);
            return oracleValue switch
            {
                OracleClob clob when clob.IsNull => DBNull.Value,
                OracleClob clob => clob.Value,
                OracleString s when s.IsNull => DBNull.Value,
                OracleString s => s.Value,
                _ => CoerceToTargetType(oracleValue, typeof(string))
            };
        }

        return CoerceToTargetType(_innerReader.GetValue(ordinal), typeof(string));
    }

    private object ReadTemporalValue(int ordinal, bool useDateTimeOffset)
    {
        var columnName = _innerReader.GetName(ordinal);

        try
        {
            var value = _innerReader.GetValue(ordinal);
            if (value is null or DBNull)
                return DBNull.Value;

            var dateTime = value switch
            {
                DateTime dt => dt,
                DateTimeOffset offset => offset.DateTime,
                _ => throw new InvalidCastException($"Expected temporal value, got {value.GetType().Name}")
            };

            var clamped = ClampSqlDateTime(dateTime, columnName);
            return useDateTimeOffset
                ? new DateTimeOffset(clamped, TimeSpan.Zero)
                : clamped;
        }
        catch (ArgumentOutOfRangeException ex)
        {
            Log.Warning(ex,
                "ArgumentOutOfRangeException for temporal column in table {Table}, column {Column}. Using safe default.",
                _tableName, columnName);
            return useDateTimeOffset
                ? new DateTimeOffset(SqlDateTimeMin, TimeSpan.Zero)
                : SqlDateTimeMin;
        }
        catch (Exception ex)
        {
            Log.Warning(ex,
                "Error reading temporal column in table {Table}, column {Column}. Using safe default.",
                _tableName, columnName);
            return useDateTimeOffset
                ? new DateTimeOffset(SqlDateTimeMin, TimeSpan.Zero)
                : SqlDateTimeMin;
        }
    }

    private DateTime ClampSqlDateTime(DateTime value, string columnName)
    {
        if (value < SqlDateTimeMin)
        {
            Log.Warning(
                "DateTime value {Value} too old in table {Table}, column {Column}. Clamping to {SafeDate}.",
                value, _tableName, columnName, SqlDateTimeMin);
            return SqlDateTimeMin;
        }

        if (value > SqlDateTimeMax)
        {
            Log.Warning(
                "DateTime value {Value} too far in future in table {Table}, column {Column}. Clamping to {SafeDate}.",
                value, _tableName, columnName, SqlDateTimeMax);
            return SqlDateTimeMax;
        }

        return value;
    }

    private static object CoerceToTargetType(object value, Type targetType)
    {
        if (value is null or DBNull)
            return DBNull.Value;

        if (targetType.IsInstanceOfType(value))
            return value;

        if (targetType == typeof(string))
        {
            if (value is OracleClob clob)
                return clob.IsNull ? DBNull.Value : clob.Value;
            if (value is OracleString s)
                return s.IsNull ? DBNull.Value : s.Value;
            return value.ToString() ?? (object)DBNull.Value;
        }

        if (targetType == typeof(byte[]) && value is byte[] bytes)
            return bytes;

        if (targetType == typeof(DateTime) && value is DateTime dt)
            return dt;

        if (targetType == typeof(DateTime) && value is DateTimeOffset dto)
            return dto.DateTime;

        if (targetType == typeof(DateTimeOffset) && value is DateTimeOffset offset)
            return offset;

        if (targetType == typeof(DateTimeOffset) && value is DateTime dateTime)
            return new DateTimeOffset(dateTime, TimeSpan.Zero);

        try
        {
            return Convert.ChangeType(value, Nullable.GetUnderlyingType(targetType) ?? targetType);
        }
        catch
        {
            return value.ToString() ?? (object)DBNull.Value;
        }
    }

    private static string ClrTypeToDataTypeName(Type type) =>
        type == typeof(DateTime) ? "datetime2"
        : type == typeof(DateTimeOffset) ? "datetimeoffset"
        : type == typeof(byte[]) ? "varbinary"
        : type == typeof(int) ? "int"
        : type == typeof(long) ? "bigint"
        : type == typeof(short) ? "smallint"
        : type == typeof(decimal) ? "decimal"
        : type == typeof(double) ? "float"
        : type == typeof(float) ? "real"
        : "nvarchar";
}
