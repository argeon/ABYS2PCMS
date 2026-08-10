# Zorunlu revizyon backlog — atlama YASAK

**Kural:** Canlıda öğrenilen fix `_tmp`’te kalmaz. Aynı gün `prodREADY_*` + snapshot sync + 195 kopya.  
**Bu cutover’da kaçanlar** aşağıda; kapanmadan “DONE” yazma.

Son güncelleme: 2026-08-09 (R15 + sonraki aktarım hazırlık notu)

---

## HARD RULES (her deploy’da)

1. `#temp` yok → `MIG_*_STG_*`
2. Hot path MGR MAP UPDATE yok → `20a` offline
3. Filtered IX / debt: `IOCODE = 0` (`ISNULL(IOCODE,0)` yasak)
4. Scalar `FN_SAFE_*` hot path yok
5. `IMPLICIT_TRANSACTIONS OFF`; dış BEGIN TRAN yok
6. FULL: 20b NCIX OFF → load → GATE → 20c / 572
7. Overlay sadece `*_ALL`
8. `sqlcmd -f 65001`
9. `RAISERROR` parametresi: sadece INT/string değişken — **BIT / CAST ifade YASAK**
10. Ağır UPDATE/INSERT: `OPTION (MAXDOP 8)` (sunucu max 48 CXSYNC öldürür)
11. 613 kuyruk: **sadece açık borçlu AGR** (`pending_open_debt`)
12. Paket yolu: `prodREADY_*` → `_sync_snapshot` → `_deploy_195` → 195 `MIGRATION_SCR_*` (**yalnız** CTAS/ENERGY/REPORT; `SRC_*` yasak)
13. 613 canonic: `prodREADY_ENERGY3007/613_INSTALLMENT_DEBT_SPLIT__pilot_agr.sql` (v6+)
14. 597 adopt: hint LREF sadece **`IOCODE<>0`** (borç collide → identity); aksi R15
15. FULL 597 öncesi: **20b NCIX OFF** zorunlu; bitince **20c** — açıken 30M INSERT ölür
16. Bad PAY map varken **`@CLEAN=1` YASAK** (map→PT DELETE borç siler) → önce `20e`
17. Scalar bank FN / FULL INV DRY mismatch tarama YASAK (`35` R13)
18. MGR `LS_OV_ID_MAP` HEAP: `UPDATE TOP+IS NULL` rescan YASAK → `20a` keyset

---

## SONRAKI AKTARIM — hazırlık (zorunlu okuma)

Bu cutover’da pahalıya öğrenildi; **bir sonraki FULL başlamadan** aşağıdakiler pakette + runbook’ta olmalı.

### A) Deploy / paket (P0 — FULL öncesi)

| # | İş | Neden |
|---|-----|--------|
| A1 | `28_DEPLOY_597` = adopt `IOCODE<>0` gövde (R15) sunucuda | Eski adopt → 30M sahte MAP, saatlerce 0 ilerleme |
| A2 | `20e` + `NOTES_597_OPS_HEAL` R15 sırası pakette / 195 SRC | Belirti tekrarında heal yolu hazır |
| A3 | `20a` keyset (`MIG_20A_STG_KEYS`) deploy | MGR HEAP null-fill |
| A4 | `35` JOIN-only DRY (FULL’da INV COUNT/TOP yok) | Scalar FN / 140M tarama |
| A5 | `613` v6 + `00e` (`MIG_613_ERR`) + open-debt `50e` | 81k boş tur + CXSYNC |
| A6 | `_sync_snapshot` + `_deploy_195` → 195 CTAS/ENERGY/REPORT = repo | Eski `SRC_*` / drift tuzağı |
| A7 | **R12** bitir: 35/40/92 → SP + `10f` EXEC | Dosya/@DRY_RUN karışıklığı |

### B) FULL run sırası (değiştirme)

```text
… → 590_ALL
  → 20b (INV+PT NCIX OFF)     ★ atlama = 597 ölüm
  → 597_ALL @CLEAN=1|0 (ilk yük CLEAN=1; resume/heal sonrası CLEAN=0)
  → GATE (E597G otorite; ALL FAIL panik yok)
  → 20c / 572
  → probe: PAY_PT map→IOCODE=0 count  ( >0 ise 20e → redeploy → 20b → ALL CLEAN=0 )
  → 35 → 611 → 611b → 613 open-debt → 40 → 92 → validate
  → 20a offline (TAH MGR MAP; cutover bloklamaz)
```

### C) Probe (597 ortası / sonrası — 2 dk)

```sql
-- Bad map (0 beklenir). >0 → 20e, CLEAN=1 YOK
SELECT COUNT_BIG(*) AS pay_map_to_debt
FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
WHERE m.OV_KIND = 'PAY_PT' AND m.ENERGY_LREF IS NOT NULL AND pt.IOCODE = 0;

SELECT
  SUM(CASE WHEN IOCODE <> 0 THEN 1 ELSE 0 END) AS pt_pay,
  SUM(CASE WHEN IOCODE = 0 THEN 1 ELSE 0 END) AS pt_debt
FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
WHERE ISNULL(CANCELED,0)=0;
-- Beklenen band: pt_pay ≈ LS_OV_PAY_PT (~66M); map filled ≈ pt_pay
```

### D) Bu aktarım semptom → aksiyon (cheat sheet)

| Semptom | Aksiyon |
|---------|---------|
| 597 LOADED saatlerce artmıyor; MAP dolu | Probe bad map → `20e` → adopt deploy → 20b → ALL **CLEAN=0** |
| `E597=FAIL` + sonra `E597G=GATE_PASS` | Otorite GATE; ALL log’una bakma |
| 35 DRY 100M+ read / FN_MIG_RESOLVE | Dosya R13 mi? KILL; FULL DRY INV skip |
| 20a 5k batch / 15 sn tur | `@Batch=500000` + keyset dosya; Implicit OFF |
| 613 60k+ pending, INST yok | open-debt filter; `MIG_613_ERR` |
| CXSYNC_PORT DOP 48 | `MAXDOP 8`; Implicit OFF; NCIX kapalı mı |
| IPP 721k aday / 78k update | Beklenen join miss; blocker değil |

### E) Bilinçli residual (sonraki FULL’da da gelebilir)

- 613 inactive / borçsuz plan AGR  
- IPP join miss (split yok / MAIN_LREF)  
- Plan `INVOICE_REF` NULL (~10k band)  
- MGR `LS_OV_ID_MAP` HEAP (clustered SRC_KEY = sonraki CTAS/DDL adayı — R16 TODO)

| ID | Durum | İş |
|----|--------|-----|
| R16 | TODO — sonraki FULL öncesi | MGR `LS_OV_ID_MAP` HEAP → clustered `SRC_KEY` (003/CTAS hizası); 20a/MAP sync hızı |
| R17 | TODO — sonraki FULL öncesi | `SSMS_TAHSILAT` / `RUN_ORDER`: 20b→597→probe→20e branch + CLEAN=0 kuralı gömülü |
| R18 | TODO — sonraki FULL öncesi | 597 INSERT kalan `MAXDOP 24` → 8 (CLEAN/delete path) |

---

## BACKLOG (kod — ana dosyaya göm)

| ID | Durum | Dosya | İş |
|----|--------|-------|-----|
| R01 | DONE | `20_597_INSERT.sql` | PAY hint MERGE OUTPUT + MAP_OUT; batch-first FORCE ORDER; adopt |
| R02 | DONE | `22_597_GATE.sql` | CROSSREF `IOCODE<>0`; MAXDOP 8 |
| R03 | DONE | `50e_TAKSIT_EXECS.sql` | open-debt pending filter |
| R04 | DONE | `50e_613_RESUME_OPEN_DEBT_ONLY.sql` | resume-only script |
| R05 | DONE | `40_…pay_apply.sql` | RAISERROR BIT → `@DryRunInt` |
| R06 | DONE | `40_…pay_apply.sql` | UPDATEs: `IOCODE=0`, `INST_NR>0`, `OPTION (MAXDOP 8)` |
| R07 | DONE | `613…v6` + `00e` + `50e` | MAXDOP/IOCODE; `MIG_613_ERR`; CATCH→tablo; canonic 3007 path |
| R08 | DONE | `NOTES_597_OPS_HEAL.md` | E597 FAIL vs E597G GATE_PASS |
| R09 | DONE | `20d_597_LOADED_MAP_HEAL.sql` + notes | LOADED↔MAP NCIX-off kalıbı |
| R10 | DONE | `35_bankref_resolve_abys.sql` | `@DryRunInt`; MAXDOP 8; `IOCODE=0`; dış TRAN kaldırıldı |
| R11 | DONE | `92_stg_inv_pay_close_apply.sql` | physical `MIG_92_STG_*`; MAXDOP 8; `IOCODE=0` |
| R12 | TODO — **cutover bitince** | 35 / 40 / 92 (+ opsiyonel 20c) | Script → `CREATE OR ALTER PROCEDURE`; `10f` checklist; `SSMS_POST` sadece `EXEC @DRY_RUN,@AGR_ID` |
| R13 | DONE (2026-08-09) | `35_bankref…` | DRY sayım: scalar `FN_MIG_RESOLVE_BANK_LREF` → `LS_BANK.ABYS_ID` JOIN (RBAR öldürdü) |
| R14 | DONE (2026-08-09) | `20a_…FAST_FILL` | MGR HEAP: `UPDATE TOP+IS NULL` rescan → energy `SRC_KEY` keyset + `MIG_20A_STG_KEYS` |
| R15 | DONE (2026-08-09) | `20`/`20d` adopt + `20e` heal + ops notes | PAY hint adopt IOCODE<>0; bad map→borç null heal; `@CLEAN=1` borç silme uyarısı |

### R12 not (cutover bitince)

- Amaç: sunucu gövdesi = paket; DRY/APPLY parametre; “hangi dosya / DRY=0 unuttuk” yok.
- Kalıp: `NN_xxx.sql` → `SP_MIG_35_BANKREF_RESOLVE` / `SP_MIG_40_IPP_APPLY` / `SP_MIG_92_STG_CLOSE`.
- Driver: `EXEC … @DRY_RUN=1|0, @AGR_ID=NULL|-1|>0`.
- Mid-cutover’da **yapma** — 35/92 script ile bitsin; sonra taşı.

---

## Bu aktarımda yapılan hatalar (tekrarlama)

1. Fix’i sadece canlı/session’da bırakmak → sonraki koşu eski gövde  
2. Snapshot sync unutmak → 195 eski dosya  
3. 613’te 81k boş tur (borçsuz AGR)  
4. DOP 48 + CXSYNC → “yavaşladı” panik  
5. GATE IOCODE=0 false FAIL  
6. `RAISERROR(..., @BIT)` / `CAST` parametre  
7. `_tmp` heal’i paket sanmak  
8. ALL FAIL log’una bakıp işi bitmiş saymamak / GATE’i atlamak  
9. Revizyonu “sonra” deyip atlamak  
10. Bad map ile 597 resume / adopt IOCODE bakmadan → 30M sahte LOADED  
11. 20a `@Batch=5000` veya Implicit Transactions ON  
12. FULL 597’yi NCIX açıkken koşmak  

---

## Kapanış checklist (cutover END öncesi)

- [x] R06–R11 kodlandı  
- [x] `_sync_snapshot.ps1` (`MIGRATION_SCR_20260708`) — 2026-08-09  
- [x] 195 temiz mirror: `_deploy_195.ps1` (CTAS/ENERGY/REPORT; `SRC_*` kaldırıldı)  
- [ ] `28_DEPLOY_597` (GATE MAXDOP sonrası — opsiyonel bu cutover)  
- [ ] 613 SP deploy (`00e` + `613…v6`) — sonraki 613 koşusunda  
- [ ] G1–G9 kabul kapıları (`NOTES_CUTOVER_DEV_PLAN_20260809.md`)  

---

## Referans

- Plan: `NOTES_CUTOVER_DEV_PLAN_20260809.md`  
- Ops heal: `NOTES_597_OPS_HEAL.md`  
- Perf: `NOTES_597_PERF_SAFE.md`  
- Exit: `../prodREADY_ENERGY3007/EXIT_MAP.md`  
