using MigrationWeb.Models.Staging;

namespace MigrationWeb.Services.Staging;

/// <summary>
/// Run-scoped structured log + gap store.
/// CRITICAL severity is informational only — does not lock APPLY.
/// Passwords / connection strings must never be written here.
/// </summary>
public sealed class AgreementTahsilatRunLog
{
    private readonly object _gate = new();
    private readonly Dictionary<string, List<TahsilatLogEvent>> _events = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<TahsilatGapItem>> _gaps = new(StringComparer.OrdinalIgnoreCase);

    public void Append(string runId, TahsilatLogEvent ev)
    {
        lock (_gate)
        {
            if (!_events.TryGetValue(runId, out var list))
            {
                list = [];
                _events[runId] = list;
            }
            list.Add(ev);
        }
    }

    public void AppendGaps(string runId, IEnumerable<TahsilatGapItem> gaps)
    {
        lock (_gate)
        {
            if (!_gaps.TryGetValue(runId, out var list))
            {
                list = [];
                _gaps[runId] = list;
            }
            foreach (var g in gaps)
            {
                // Eski kendini kilitleyen mesaj — store'a yazma (gürültü)
                if (string.Equals(g.Code, "APPLY_LOCKED", StringComparison.OrdinalIgnoreCase))
                    continue;

                var key = $"{g.Code}|{g.Message}";
                if (!list.Any(x => $"{x.Code}|{x.Message}" == key))
                    list.Add(g);
            }
        }
    }

    /// <summary>Belirli kodları run gap listesinden düş (örn. FRK yeniden MATCH olduğunda).</summary>
    public void RemoveGapsByCodes(string runId, params string[] codes)
    {
        if (codes.Length == 0) return;
        var set = new HashSet<string>(codes, StringComparer.OrdinalIgnoreCase);
        lock (_gate)
        {
            if (!_gaps.TryGetValue(runId, out var list)) return;
            list.RemoveAll(g => set.Contains(g.Code));
        }
    }

    /// <summary>Eski API — APPLY kilidi kaldırıldı; her zaman false.</summary>
    public bool HasCritical(string runId) => false;

    /// <summary>Eski API — APPLY kilidi yok; boş liste.</summary>
    public IReadOnlyList<TahsilatGapItem> GetApplyBlockingCriticals(string runId) => [];

    public IReadOnlyList<TahsilatGapItem> GetCriticals(string runId)
    {
        lock (_gate)
        {
            if (!_gaps.TryGetValue(runId, out var list))
                return [];
            return list.Where(g => g.Severity == "CRITICAL").ToList();
        }
    }

    public IReadOnlyList<TahsilatGapItem> GetGaps(string runId)
    {
        lock (_gate)
        {
            return _gaps.TryGetValue(runId, out var list) ? list.ToList() : [];
        }
    }
}
