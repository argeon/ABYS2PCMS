using System.Text;
using System.Text.RegularExpressions;
using Oracle.ManagedDataAccess.Client;

static class OracleSqlRunner
{
    const string Schema = "SMS_AUDIT";
    static readonly string[] StagingObjects =
    [
        "MIG_PARAM", "MIG_UNMAPPED", "MIG_SKIPPED",
        "STG_PILOT_ACC", "STG_ACTION_MAP", "STG_INCOME_ROUTE", "STG_EKSILTEN_CLASS",
        "STG_INVOICE", "STG_INVLINES", "STG_SPEFEE", "STG_PAYTRANS", "STG_PAYTRANS_INCOME",
        "STG_ADVANCE_LEDGER", "STG_ADV_LEDGER_INCOME", "STG_MAHSUP_POOL", "STG_CANCEL_POOL",
        "STG_DEVIR_NET", "STG_INCOME_COVERAGE", "STG_RECON_DIFF", "STG_INSTALLMENT", "STG_INSTALLMENT_PLAN",
        "STG_EKSILTEN_ADJ", "STG_AGR_CONTEXT", "V_REF_CHAIN"
    ];

    public static string AdaptForSmsAudit(string sql)
    {
        sql = sql.Replace("FROM USER_TABLES WHERE TABLE_NAME IN",
            $"FROM ALL_TABLES WHERE OWNER='{Schema}' AND TABLE_NAME IN");
        sql = sql.Replace("FROM USER_VIEWS WHERE VIEW_NAME='V_REF_CHAIN'",
            $"FROM ALL_VIEWS WHERE OWNER='{Schema}' AND VIEW_NAME='V_REF_CHAIN'");
        sql = sql.Replace("DROP TABLE '||T.TABLE_NAME||' PURGE",
            $"DROP TABLE {Schema}.'||T.TABLE_NAME||' PURGE");
        sql = sql.Replace("DROP VIEW '||V.VIEW_NAME",
            $"DROP VIEW {Schema}.'||V.VIEW_NAME");

        sql = sql.Replace(
            "  FOR V IN (SELECT VIEW_NAME FROM ALL_VIEWS WHERE OWNER='SMS_AUDIT' AND VIEW_NAME='V_REF_CHAIN')",
            $@"  FOR I IN (SELECT OWNER, INDEX_NAME FROM ALL_INDEXES WHERE TABLE_OWNER='{Schema}' AND TABLE_NAME IN
    ('MIG_PARAM','STG_PILOT_ACC','STG_ACTION_MAP','STG_INCOME_ROUTE','STG_EKSILTEN_CLASS',
     'STG_INVOICE','STG_INVLINES','STG_SPEFEE','STG_PAYTRANS','STG_PAYTRANS_INCOME',
     'STG_ADVANCE_LEDGER','STG_ADV_LEDGER_INCOME','STG_MAHSUP_POOL','STG_CANCEL_POOL',
     'STG_DEVIR_NET','STG_INCOME_COVERAGE','STG_RECON_DIFF','STG_INSTALLMENT','STG_INSTALLMENT_PLAN',
     'STG_EKSILTEN_ADJ','MIG_UNMAPPED','MIG_SKIPPED'))
  LOOP BEGIN EXECUTE IMMEDIATE 'DROP INDEX '||I.OWNER||'.'||I.INDEX_NAME; EXCEPTION WHEN OTHERS THEN NULL; END; END LOOP;
  FOR V IN (SELECT VIEW_NAME FROM ALL_VIEWS WHERE OWNER='{Schema}' AND VIEW_NAME='V_REF_CHAIN')");

        foreach (var obj in StagingObjects.OrderByDescending(o => o.Length))
        {
            var esc = Regex.Escape(obj);
            var notPrefixed = $"(?<!{Schema}\\.)";

            sql = Regex.Replace(sql, $@"{notPrefixed}CREATE\s+TABLE\s+{esc}\b", $"CREATE TABLE {Schema}.{obj}", RegexOptions.IgnoreCase);
            sql = Regex.Replace(sql, $@"{notPrefixed}INSERT\s+INTO\s+{esc}\b", $"INSERT INTO {Schema}.{obj}", RegexOptions.IgnoreCase);
            sql = Regex.Replace(sql, $@"{notPrefixed}UPDATE\s+{esc}\b", $"UPDATE {Schema}.{obj}", RegexOptions.IgnoreCase);
            sql = Regex.Replace(sql, $@"{notPrefixed}ALTER\s+TABLE\s+{esc}\b", $"ALTER TABLE {Schema}.{obj}", RegexOptions.IgnoreCase);
            sql = Regex.Replace(sql, $@"{notPrefixed}CREATE\s+VIEW\s+{esc}\b", $"CREATE VIEW {Schema}.{obj}", RegexOptions.IgnoreCase);
            sql = Regex.Replace(sql, $@"{notPrefixed}CREATE\s+(UNIQUE\s+)?INDEX\s+(IX_[A-Z0-9_]+)\s+ON\s+{esc}\b", $"CREATE $1INDEX {Schema}.$2 ON {Schema}.{obj}", RegexOptions.IgnoreCase);
            sql = Regex.Replace(sql, $@"{notPrefixed}(FROM|JOIN)\s+{esc}\b", $"$1 {Schema}.{obj}", RegexOptions.IgnoreCase);
        }

        return sql;
    }

    public static List<string> SplitStatements(string sql)
    {
        var lines = sql.Split(["\r\n", "\n"], StringSplitOptions.None);
        var chunks = new List<string>();
        var sb = new StringBuilder();
        var inPlsql = false;

        foreach (var rawLine in lines)
        {
            var line = rawLine;
            var trimmed = line.Trim();
            var codeLine = Regex.Replace(line, @"--.*$", string.Empty).Trim();

            if (trimmed == "/")
            {
                if (sb.Length > 0)
                {
                    chunks.Add(sb.ToString().Trim());
                    sb.Clear();
                }
                inPlsql = false;
                continue;
            }

            if (Regex.IsMatch(codeLine, @"^(BEGIN|DECLARE)\b", RegexOptions.IgnoreCase))
                inPlsql = true;

            sb.AppendLine(line);

            if (trimmed.StartsWith("--"))
                continue;

            if (inPlsql)
            {
                if (Regex.IsMatch(codeLine, @"^END\s*;\s*$", RegexOptions.IgnoreCase))
                {
                    chunks.Add(sb.ToString().Trim());
                    sb.Clear();
                    inPlsql = false;
                }
                continue;
            }

            if (!inPlsql && codeLine.Count(ch => ch == ';') > 1)
            {
                var full = StripSqlComments(sb.ToString());
                sb.Clear();
                foreach (var part in full.Split(';', StringSplitOptions.RemoveEmptyEntries))
                {
                    var stmt = part.Trim();
                    if (stmt.Length > 0) chunks.Add(stmt);
                }
                continue;
            }

            if (codeLine.EndsWith(';'))
            {
                chunks.Add(sb.ToString().Trim());
                sb.Clear();
            }
        }

        if (sb.Length > 0)
        {
            var tail = sb.ToString().Trim();
            if (tail.Length > 0) chunks.Add(tail);
        }

        return chunks
            .Where(c => c.Length > 0 && !IsCommentOnly(c))
            .ToList();
    }

    static bool IsCommentOnly(string sql)
    {
        foreach (var line in sql.Split('\n'))
        {
            var t = line.Trim();
            if (t.Length == 0) continue;
            if (!t.StartsWith("--")) return false;
        }
        return true;
    }

    static string NormalizeSql(string sql)
    {
        sql = sql.Trim();
        var stripped = StripSqlComments(sql).Trim();
        if (Regex.IsMatch(stripped, @"^(BEGIN|DECLARE)\b", RegexOptions.IgnoreCase | RegexOptions.Singleline))
            return stripped;
        if (stripped.EndsWith(';'))
            stripped = stripped[..^1].TrimEnd();
        return stripped;
    }

    static string StripSqlComments(string sql) =>
        string.Join(Environment.NewLine,
            sql.Split(["\r\n", "\n"], StringSplitOptions.None)
               .Select(l => Regex.Replace(l, @"--.*$", string.Empty)));

    public static async Task<int> RunFileAsync(string connStr, string sqlPath, bool saveAdapted, CancellationToken ct = default)
    {
        var raw = await File.ReadAllTextAsync(sqlPath, ct);
        var adapted = AdaptForSmsAudit(raw);
        if (saveAdapted)
        {
            var outPath = Path.Combine(Path.GetDirectoryName(sqlPath)!,
                Path.GetFileNameWithoutExtension(sqlPath) + "_sms_audit.sql");
            await File.WriteAllTextAsync(outPath, adapted, ct);
            Console.WriteLine($"Adapted script saved: {outPath}");
        }

        var blocks = SplitStatements(adapted);
        Console.WriteLine($"Statements/blocks: {blocks.Count}");

        await using var conn = new OracleConnection(connStr);
        await conn.OpenAsync(ct);
        Console.WriteLine("CONNECTED");

        var idx = 0;
        foreach (var block in blocks)
        {
            ct.ThrowIfCancellationRequested();
            idx++;
            var preview = block.Replace('\n', ' ').Trim();
            if (preview.Length > 100) preview = preview[..100] + "...";
            Console.WriteLine($"\n[{idx}/{blocks.Count}] {preview}");

            await using var cmd = new OracleCommand(NormalizeSql(block), conn) { BindByName = true };
            cmd.CommandTimeout = 0;

            var normalized = NormalizeSql(block);
            var isQuery = Regex.IsMatch(normalized, @"^(SELECT|WITH)\b", RegexOptions.IgnoreCase);
            if (isQuery)
            {
                await using var reader = await cmd.ExecuteReaderAsync(ct);
                PrintReader(reader);
            }
            else
            {
                try
                {
                    await cmd.ExecuteNonQueryAsync(ct);
                    Console.WriteLine("  OK");
                }
                catch (OracleException ex)
                {
                    Console.WriteLine($"  ERROR ORA-{ex.Number}: {ex.Message}");
                    throw;
                }
            }
        }

        return blocks.Count;
    }

    static void PrintReader(OracleDataReader reader)
    {
        var cols = Enumerable.Range(0, reader.FieldCount).Select(reader.GetName).ToArray();
        Console.WriteLine("  " + string.Join(" | ", cols));
        var rows = 0;
        while (reader.Read())
        {
            var vals = new string[reader.FieldCount];
            for (var i = 0; i < reader.FieldCount; i++)
                vals[i] = reader.IsDBNull(i) ? "NULL" : Convert.ToString(reader.GetValue(i)) ?? "";
            Console.WriteLine("  " + string.Join(" | ", vals));
            if (++rows >= 50) { Console.WriteLine("  ... (truncated)"); break; }
        }
        if (rows == 0) Console.WriteLine("  (no rows)");
    }
}
