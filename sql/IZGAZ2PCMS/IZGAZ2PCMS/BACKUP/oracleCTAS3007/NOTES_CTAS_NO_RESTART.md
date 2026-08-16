# CTAS — baştan alma YASAK (resume)

**Kural:** FAIL = o **NNN** dosyadan devam. `00_RUN_ALL` baştan **YASAK**.

Paket: `MIGRATION_SCR_20260708/CTAS/`  
Canlı kaynak: `BACKUP/oracleCTAS3007/` (adlar eski; paket `NNN_NAME_Vnn`)  
Tek giriş: `00_RUN_ALL.SQL` · Map: `_ctas_nnn_map.ps1`

---

## Operatör

```text
cd ...\MIGRATION_SCR_20260708\CTAS
sqlplus ... @00_RUN_ALL.SQL
```

Patlayınca:

```text
1) @251_LOG_STATUS_V01.SQL   (veya @99_log_status canlida)
2) MIG_CTAS_LOG son OK NNN
3) @@NNN_..._V01.SQL ve sonrasi
```

**FAIL kontrolü:** `251` “BU KOSU (otorite)” — aynı STEP_ID için sonra `GATE_PASS` geldiyse eski `GATE_FAIL` satırı **blok değil**. Tarihsiz `WHERE STATUS IN ('FAIL','GATE_FAIL')` kullanma.

---

## Paket hazır (kod + 195) — 2026-08-11 ~07:57

```text
[x] 026 GUAR: 23032 TOTAL/MUSTTL dışı
[x] 024 FEE_COLLECTED: güvence 5/6 + bağlantı 4/27/28/544
[x] 130–132 DV: ACCRUE 5/6/21/341 → TOTAL_DV
[x] 135 O20: tah.tut ACTION_TYPE IN (1,3,10,41)
[x] 137 O30: LS_OV_TAH_INVLINES mahsup 162/1936
[x] 925_DIAG_DV_TYPE109 pakette (EXTRA)
[x] _deploy_195 CTAS=84 ENERGY=266 REPORT=38
[x] Tutar DECIMAL: CAST NUMBER(18,3) — koşuldu 2026-08-11 (~09:20+)
```

## Preflight (10 dk) — koşu anı

```text
[ ] TEMP / undo / tablespace
[ ] DOP 56 | TEMP → 48 (011_SESSION_PARALLEL)
[ ] Tee log
[ ] 900+ EXTRA/PILOT RUNALL'da YOK
```

---

## NNN bantları

```text
010–019  SETUP
020–099  MASTER
100–129  OKUMA/HHD
130–199  FATURA/OVERLAY/GATE
200–259  POST + IX + LOG
900+     PILOT/EXTRA — RUNALL disi
```

---

## Yaygın ORA

| Belirti | Aksiyon |
|---------|---------|
| ORA-01652 TEMP | DOP 48 → **aynı NNN** |
| GATE_FAIL | dump yok; gate adımına kadar dar |
| sqlplus koptu | son START/OK → o NNN tekrar |

## DV (TYPE 109/111) — bu koşu

Kod: `130` TOTAL_DV (ACCRUE 5/6/21/341) · `131` INV.DV · `132` damga satırı · soft `@925_DIAG_DV_TYPE109_V01`.

```text
[x] 130 henüz gelmediyse → güncel 10_/130_ dosyası (TOTAL_DV) diskte olsun  ← paket+195 OK
[ ] 130–132 ZATEN OK (eski kodla) → @@130 … @@132 TEKRAR (baştan RUNALL YASAK)
[ ] 134 (O14) de OK ise → @@134 de TEKRAR (borc PT inv.DV kopyalar)
[ ] soft: @925_DIAG_DV_TYPE109_V01.SQL
      BAD_DV0_WITH_DAMGA=0 · IL_STILL_IN_TL=0
```

Canlı ad: `diag_dv_type109.sql` · paket: `925_DIAG_DV_TYPE109_V01.SQL`  
Energy dump sonrası: `92_INV_DV_FROM_INCOME_HEAL` (Faz B CROSSREF tahsilat — CTAS doğru olsa bile gerekebilir).

## AGR_GUARANTY — damga TOTAL’de olmasın

`026` / `LS_AGR_GUARANTY`: GTYPE39 **TOTAL/MUSTTL** = güvence asıl; **23032 hariç** (spot AGR 1200078: 4387.20→4346).

```text
[x] 026 kod: 23032 hariç — paket+195 (2026-08-11)
[ ] 026 ZATEN OK (eski, 23032 dahil) → @@026_LS_AGR_GUARANTY_V01.SQL TEKRAR
      (DROP+CTAS; sonraki Oracle adımları buna bağlı değil — dump öncesi yeter)
```

**PARTIAL (R21):** CTAS kod DONE; Oracle re-run + Energy 311 + PCMS spot → `NOTES_CANLI…` §2b0 (DONE yazma).

Detay sıra: `000_RUN_ORDER.MD`
