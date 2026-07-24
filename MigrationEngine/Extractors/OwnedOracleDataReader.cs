using System.Collections;
using System.Data;
using System.Data.Common;
using Oracle.ManagedDataAccess.Client;

namespace MigrationEngine.Extractors;

/// <summary>
/// Keeps the owning <see cref="OracleCommand"/> (and connection) alive for the lifetime of the
/// reader. ODP.NET invalidates the reader if the command is disposed/finalized first (ORA-50045).
/// </summary>
internal sealed class OwnedOracleDataReader : DbDataReader
{
    private OracleCommand? _command;
    private OracleDataReader? _reader;
    private bool _disposed;

    public OwnedOracleDataReader(OracleCommand command, OracleDataReader reader)
    {
        _command = command ?? throw new ArgumentNullException(nameof(command));
        _reader = reader ?? throw new ArgumentNullException(nameof(reader));
    }

    private OracleDataReader Reader =>
        _reader ?? throw new ObjectDisposedException(nameof(OwnedOracleDataReader));

    public override int FieldCount => Reader.FieldCount;
    public override bool HasRows => Reader.HasRows;
    public override bool IsClosed => _disposed || _reader is null || _reader.IsClosed;
    public override int Depth => Reader.Depth;
    public override int RecordsAffected => Reader.RecordsAffected;

    public override object this[int ordinal] => Reader[ordinal];
    public override object this[string name] => Reader[name];

    public override string GetName(int ordinal) => Reader.GetName(ordinal);
    public override string GetDataTypeName(int ordinal) => Reader.GetDataTypeName(ordinal);
    public override Type GetFieldType(int ordinal) => Reader.GetFieldType(ordinal);
    public override object GetValue(int ordinal) => Reader.GetValue(ordinal);
    public override int GetValues(object[] values) => Reader.GetValues(values);
    public override int GetOrdinal(string name) => Reader.GetOrdinal(name);
    public override bool GetBoolean(int ordinal) => Reader.GetBoolean(ordinal);
    public override byte GetByte(int ordinal) => Reader.GetByte(ordinal);
    public override long GetBytes(int ordinal, long dataOffset, byte[]? buffer, int bufferOffset, int length)
        => Reader.GetBytes(ordinal, dataOffset, buffer, bufferOffset, length);
    public override char GetChar(int ordinal) => Reader.GetChar(ordinal);
    public override long GetChars(int ordinal, long dataOffset, char[]? buffer, int bufferOffset, int length)
        => Reader.GetChars(ordinal, dataOffset, buffer, bufferOffset, length);
    public override Guid GetGuid(int ordinal) => Reader.GetGuid(ordinal);
    public override short GetInt16(int ordinal) => Reader.GetInt16(ordinal);
    public override int GetInt32(int ordinal) => Reader.GetInt32(ordinal);
    public override long GetInt64(int ordinal) => Reader.GetInt64(ordinal);
    public override float GetFloat(int ordinal) => Reader.GetFloat(ordinal);
    public override double GetDouble(int ordinal) => Reader.GetDouble(ordinal);
    public override string GetString(int ordinal) => Reader.GetString(ordinal);
    public override decimal GetDecimal(int ordinal) => Reader.GetDecimal(ordinal);
    public override DateTime GetDateTime(int ordinal) => Reader.GetDateTime(ordinal);
    public override bool IsDBNull(int ordinal) => Reader.IsDBNull(ordinal);
    public override bool Read() => Reader.Read();
    public override bool NextResult() => Reader.NextResult();
    public override IEnumerator GetEnumerator() => ((IEnumerable)_reader!).GetEnumerator();

    protected override void Dispose(bool disposing)
    {
        if (_disposed)
            return;

        if (disposing)
        {
            try { _reader?.Dispose(); }
            catch { /* best-effort */ }
            _reader = null;

            try { _command?.Dispose(); }
            catch { /* best-effort */ }
            _command = null;
        }

        _disposed = true;
        base.Dispose(disposing);
    }
}
