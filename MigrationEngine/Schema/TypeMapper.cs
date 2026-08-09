using MigrationShared.Models;

namespace MigrationEngine.Schema;

public record TypeMapping(string SqlType, bool HasWarning, string? WarningMessage);

public class TypeMapper
{
    /// <summary>
    /// Oracle ALL_TAB_COLUMNS.DATA_LENGTH for TIMESTAMP is byte size, not fractional-second precision.
    /// For NUMBER, DATA_LENGTH is always the internal byte size (typically 22) — never use it as precision
    /// (that produced DECIMAL(22,0) and truncated kuruş on unconstrained NUMBER columns).
    /// </summary>
    public static int? ResolvePrecisionArgument(string dataType, int? dataPrecision, int? dataLength)
    {
        var t = dataType.ToUpperInvariant();
        if (t.StartsWith("TIMESTAMP"))
            return dataPrecision;
        if (t is "NUMBER" or "FLOAT" or "BINARY_FLOAT" or "BINARY_DOUBLE")
            return dataPrecision;
        return dataPrecision ?? dataLength;
    }

    /// <summary>SQL Server datetime2/datetimeoffset/time allow 0–7 fractional digits; Oracle allows up to 9.</summary>
    private static int ClampSqlDateTimeFractionalDigits(int? oracleFractionalDigits)
    {
        var n = oracleFractionalDigits ?? 7;
        return Math.Clamp(n, 0, 7);
    }

    public TypeMapping MapType(
        string oracleType,
        int? precision,
        int? scale,
        string columnName,
        bool isSpatial = false,
        int? srid = null)
    {
        if (isSpatial || string.Equals(oracleType, "SDO_GEOMETRY", StringComparison.OrdinalIgnoreCase))
        {
            return new TypeMapping(
                "NVARCHAR(MAX)",
                true,
                "Oracle SDO_GEOMETRY — WKT staged in {column}__wkt; target geography/geometry set at DDL");
        }

        var upperType = oracleType.ToUpper();

        return upperType switch
        {
            "NUMBER" => MapNumber(precision, scale, columnName),
            "FLOAT" => new TypeMapping("FLOAT(53)", true, "FLOAT type may cause precision loss for financial data"),
            "BINARY_FLOAT" => new TypeMapping("REAL", false, null),
            "BINARY_DOUBLE" => new TypeMapping("FLOAT(53)", false, null),
            var t when t.StartsWith("VARCHAR2") => MapVarchar(precision),
            var t when t.StartsWith("NVARCHAR2") => MapNVarchar(precision),
            var t when t.StartsWith("CHAR") && !t.Contains("VARYING") => MapChar(precision),
            "CLOB" => new TypeMapping("NVARCHAR(MAX)", false, null),
            "NCLOB" => new TypeMapping("NVARCHAR(MAX)", false, null),
            "BLOB" => new TypeMapping("VARBINARY(MAX)", false, null),
            var t when t.StartsWith("RAW") => MapRaw(precision),
            "LONG RAW" => new TypeMapping("VARBINARY(MAX)", true, "LONG RAW type may exceed VARBINARY(MAX) 2GB limit"),
            "DATE" => new TypeMapping("DATETIME2(0)", true, "Oracle DATE includes time component (precision to seconds)"),
            var t when t.StartsWith("TIMESTAMP") && t.Contains("TIME ZONE") && !t.Contains("LOCAL") =>
                new TypeMapping($"DATETIMEOFFSET({ClampSqlDateTimeFractionalDigits(precision)})", false, null),
            var t when t.StartsWith("TIMESTAMP") && t.Contains("LOCAL TIME ZONE") =>
                new TypeMapping($"DATETIME2({ClampSqlDateTimeFractionalDigits(precision)})", true, "Local timezone information will be lost"),
            var t when t.StartsWith("TIMESTAMP") =>
                new TypeMapping($"DATETIME2({ClampSqlDateTimeFractionalDigits(precision)})", false, null),
            "XMLTYPE" => new TypeMapping("XML", false, null),
            var t when t.StartsWith("INTERVAL YEAR") => 
                new TypeMapping("NVARCHAR(50)", true, "INTERVAL YEAR TO MONTH mapped to string - manual conversion required"),
            var t when t.StartsWith("INTERVAL DAY") => 
                new TypeMapping("NVARCHAR(50)", true, "INTERVAL DAY TO SECOND mapped to string - manual conversion required"),
            "ROWID" or "UROWID" => 
                new TypeMapping("SKIP", true, "ROWID/UROWID column will be skipped - not portable"),
            "LONG" => new TypeMapping("NVARCHAR(MAX)", true, "LONG type deprecated in Oracle - consider CLOB"),
            _ => new TypeMapping("NVARCHAR(MAX)", true, $"Unknown Oracle type '{oracleType}' - defaulting to NVARCHAR(MAX)")
        };
    }

    private TypeMapping MapNumber(int? precision, int? scale, string columnName)
    {
        // Unconstrained / float-like Oracle NUMBER (NULL scale, -127, or ODP.NET 127 sentinel).
        // Must keep fractional scale — DECIMAL(p,0)/BIGINT truncates kuruş (GUARANTY.TOTAL etc.).
        if (!precision.HasValue || precision == 0
            || !scale.HasValue || scale < 0 || scale > 20)
        {
            return new TypeMapping("DECIMAL(38,10)", true,
                "NUMBER unconstrained/float-scale mapped to DECIMAL(38,10) to preserve fractions");
        }

        if (scale == 0)
        {
            return precision.Value switch
            {
                <= 4 => new TypeMapping("SMALLINT", false, null),
                <= 9 => new TypeMapping("INT", false, null),
                <= 18 => new TypeMapping("BIGINT", false, null),
                <= 38 => new TypeMapping($"DECIMAL({precision},0)", false, null),
                _ => new TypeMapping("DECIMAL(38,0)", true, "Precision exceeds maximum, capped at 38")
            };
        }

        if (precision > 38)
        {
            return new TypeMapping("DECIMAL(38,10)", true, 
                $"Precision {precision} exceeds DECIMAL maximum of 38, capped to DECIMAL(38,10)");
        }

        if (scale > precision)
        {
            // SQL Server requires 0 <= scale <= precision; Oracle metadata can be inconsistent for some types.
            var p = Math.Min(38, Math.Max(precision.Value, scale.Value));
            var s = Math.Min(scale.Value, p);
            return new TypeMapping($"DECIMAL({p},{s})", true,
                $"Adjusted DECIMAL: Oracle had precision={precision} scale={scale} (invalid for SQL Server)");
        }

        return new TypeMapping($"DECIMAL({precision},{scale})", false, null);
    }

    // Oracle VARCHAR2 → MSSQL VARCHAR (CP1254 / energy bare-join).
    // Dump must land as VARCHAR so ENERGY 00b ALIGN is CHECK-only, not ALTER.
    // True Unicode (NVARCHAR2) stays NVARCHAR via MapNVarchar.
    private TypeMapping MapVarchar(int? length)
    {
        var effectiveLength = Math.Min(length ?? 4000, 4000);
        return new TypeMapping($"VARCHAR({effectiveLength})", false, null);
    }

    private TypeMapping MapNVarchar(int? length)
    {
        var effectiveLength = Math.Min(length ?? 4000, 4000);
        return new TypeMapping($"NVARCHAR({effectiveLength})", false, null);
    }

    private TypeMapping MapChar(int? length)
    {
        return new TypeMapping($"CHAR({length ?? 1})", true,
            "CHAR type preserves trailing spaces - verify application compatibility");
    }

    private TypeMapping MapRaw(int? length)
    {
        return new TypeMapping($"VARBINARY({length ?? 2000})", false, null);
    }

    public string MapDefaultValue(string? oracleDefault)
    {
        if (string.IsNullOrWhiteSpace(oracleDefault))
            return string.Empty;

        var upperDefault = oracleDefault.Trim().ToUpper();

        return upperDefault switch
        {
            "SYSDATE" => "GETDATE()",
            "SYSTIMESTAMP" => "SYSDATETIME()",
            var d when d.Contains("SYS_GUID()") => "NEWID()",
            var d when d.Contains("USER") => "SUSER_SNAME()",
            _ => oracleDefault
        };
    }

    public List<TypeMappingWarning> CollectWarnings(string tableName, List<(string columnName, string oracleType, int? precision, int? scale)> columns)
    {
        var warnings = new List<TypeMappingWarning>();

        foreach (var (columnName, oracleType, precision, scale) in columns)
        {
            var mapping = MapType(oracleType, precision, scale, columnName);
            if (mapping.HasWarning && !string.IsNullOrEmpty(mapping.WarningMessage))
            {
                warnings.Add(new TypeMappingWarning
                {
                    TableName = tableName,
                    ColumnName = columnName,
                    OracleType = oracleType,
                    MssqlType = mapping.SqlType,
                    WarningMessage = mapping.WarningMessage
                });
            }
        }

        return warnings;
    }

    /// <summary>
    /// CLR types for bulk copy — avoids Oracle ODP.NET GetFieldType UDT lookups (ORA-06550 / GET_TYPE_SHAPE).
    /// </summary>
    public static Type MapToClrType(ColumnSchema column)
    {
        if (column.IsSpatial || string.Equals(column.DataType, "SDO_GEOMETRY", StringComparison.OrdinalIgnoreCase))
            return typeof(string);

        var precision = ResolvePrecisionArgument(column.DataType, column.DataPrecision, column.DataLength);
        return MapToClrType(column.DataType, precision, column.DataScale);
    }

    public static Type MapToClrType(string oracleType, int? precision, int? scale)
    {
        var upperType = oracleType.ToUpperInvariant();

        return upperType switch
        {
            "NUMBER" => MapNumberClr(precision, scale),
            "FLOAT" or "BINARY_DOUBLE" => typeof(double),
            "BINARY_FLOAT" => typeof(float),
            var t when t.StartsWith("VARCHAR2") => typeof(string),
            var t when t.StartsWith("NVARCHAR2") => typeof(string),
            var t when t.StartsWith("CHAR") && !t.Contains("VARYING") => typeof(string),
            "CLOB" or "NCLOB" or "LONG" or "XMLTYPE" => typeof(string),
            "BLOB" or "LONG RAW" => typeof(byte[]),
            var t when t.StartsWith("RAW") => typeof(byte[]),
            "DATE" => typeof(DateTime),
            var t when t.StartsWith("TIMESTAMP") && t.Contains("TIME ZONE") && !t.Contains("LOCAL") =>
                typeof(DateTimeOffset),
            var t when t.StartsWith("TIMESTAMP") => typeof(DateTime),
            var t when t.StartsWith("INTERVAL") => typeof(string),
            _ => typeof(string)
        };
    }

    private static Type MapNumberClr(int? precision, int? scale)
    {
        // Keep CLR decimal whenever SQL mapping keeps fractional scale (unconstrained / float-scale).
        if (!precision.HasValue || precision == 0
            || !scale.HasValue || scale < 0 || scale > 20)
            return typeof(decimal);

        if (scale == 0)
        {
            return precision.Value switch
            {
                <= 4 => typeof(short),
                <= 9 => typeof(int),
                <= 18 => typeof(long),
                _ => typeof(decimal)
            };
        }

        return typeof(decimal);
    }
}
