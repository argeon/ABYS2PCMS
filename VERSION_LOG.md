# VERSION_LOG — ABYS2PCMS

Repo: [argeon/ABYS2PCMS](https://github.com/argeon/ABYS2PCMS) · branch: `master` / `deploy` / `hotfix`

| Branch | Rol |
|--------|-----|
| `master` | Geliştirme |
| `deploy` | Release / tag hattı |
| `hotfix` | Canlı acil yama |

Paket: `prodEnergy/` · CTAS: `BACKUP/oracleCTAS3007/` · Harita: `CANONICAL/`

---

## Unreleased

_(boş)_

---

## v0.1.2 — 2026-08-09

**Tag:** `v0.1.2`

**Konu:** Arşiv sadeleştirme

- `BACKUP/20260809_CTAS_PRE_IX_RULE` kaldırıldı (içerik `v0.1.0` git history’de)
- Tiny `_backup_*` / `backup_hhd_*` temizlendi
- Lokal dated `sql/IZGAZ2PCMS/BACKUP/IZGAZ2PCMS_*` disk yedekleri silindi (gitignore)
- CANONICAL haritası güncel

---

## v0.1.1 — 2026-08-09

**Tag:** `v0.1.1` · **Commit:** `5ec3400`

**Konu:** CTAS terminal-DUMP no-IX + O61 custody + paket haritası

- Terminal DUMP tablolarda Oracle INDEX/STATS yok
- O61 `LS_CUSTODY`; O50 `GECIKME_BEDELI` = `F_GET_COMMISSION_CALC`
- `CANONICAL/` tek çalışma haritası

---

## v0.1.0 — 2026-08-09

**Tag:** `v0.1.0` · **Commit:** `64eb2aa`

GitHub bootstrap baseline.
