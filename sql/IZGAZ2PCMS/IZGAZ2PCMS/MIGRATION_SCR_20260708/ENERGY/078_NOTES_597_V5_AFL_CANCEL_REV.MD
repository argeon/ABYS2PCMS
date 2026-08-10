# NOTES — Tam aktarım (597 v5 / AFL–CANCEL_REV)

**Tarih notu:** 2026-08-06 — mevcut energy’de EXEC yok; ~2 gün sonra **tüm kayıtlar yeniden aktarılacak**.  
**Durum:** Repo revizyonu hazır. Deploy + EXEC aktarım günü yapılacak.

**Ayrıca (2026-08-07):** eksilten/TAM/ASIM/güvence-mahsup canlı revizyon listesi → `NOTES_CANLI_AKTARIM_REV_20260807.md`

---

## Kök sorun (spot: INV `66081785` / ACC `28918389`)

| Bulgu | Detay |
|-------|--------|
| `CANCEL_PAY` + `CANCEL_REV` | Overlay iptal tahsilat → ikinci borç PT (`CP=1`) |
| Sahte 2× | `PT_PAYABLE = 2 × INV` (REV dahil edilince) |
| AFL/TTK | AFL yok, TTK tah/kalan **0** → Oracle’da açık borç yok |
| Energy | `CLOSED=0`, ana PT `PAID≈5.79` → yanlış açık |

**Kural:** AFL kapalı / yoksa → `CANCEL_REV` yazma; varsa yazıp sonra heal ile `PAID=full` + `CLOSED=1`. Rapor/toplamda `CANCELLATIONPAYMENT=0`.

---

## Repo’da yapılan revizyon (v5) — EXEC gerekmez, dosyalar hazır

### SP (prodREADY_ENERGY/)
| Dosya | Ne |
|-------|----|
| `20_597_INSERT.sql` | `CANCEL_REV` yalnız `LS_AFL_OPEN_DEBT.BALANCE > 0.02` |
| `21_597_WIRE.sql` | AFL kapalı + aktif REV → soft-cancel; ana PT `PAID=PAYABLE`; INV `CLOSED=1` |
| `22_597_GATE.sql` | Aktif REV + AFL kapalı → **GATE_FAIL** |
| `28_DEPLOY_597.sql` | v5 paket notu |
| `29_597_ALL.sql` | INSERT→WIRE→GATE (değişmedi, yeni SP’leri çağırır) |

### Borç PT / UX
| Dosya | Ne |
|-------|----|
| `575_INVOICE_DEBT_PAYTRANS__migrate.sql` (+ Prod mirror) | Guard: `CANCELLATIONPAYMENT=0` |
| `576_..._post.sql` (+ Prod) | UX filter: `CP=0 OR NULL` |
| `91_debt_pt_dup_cleanup.sql` | KEEP sıralamada `CP=1` asla KEEP |
| `50e_TAKSIT_EXECS.sql`, `80_613_taksit__STANDALONE.sql` | aynı UX filter |

### Rapor
| Dosya | Ne |
|-------|----|
| `90_afl_frk/95_ttk_inv_afl_fatura_rapor.sql` | PT toplamı `CP=0`; AFL kalan farkı |

---

## Aktarım günü sıra (FULL)

Önkoşul: Oracle overlay + `LS_AFL_OPEN_DEBT` energy’de yüklü.

```
1) 571 INVOICE → 581 INVLINES → 575 DEBT PT → 576 post (UX)
2) 28_DEPLOY_597.sql          -- SP v5 ALTER
3) SP_MIG_590_ALL …           -- varsa/eksiltme
4) SP_MIG_597_ALL @AGR_ID=NULL, @CLEAN=1, @DEBUG=1, @BatchSize=…
5) GATE_PASS zorunlu
6) (opsiyonel) 91_debt_pt_dup_cleanup @DryRun=0  -- hâlâ DUP varsa
7) 95_ttk_inv_afl_fatura_rapor.sql gate
```

`RUN_ORDER.sql` ile uyumlu; overlay’den önce ana tahakkuk bitsin.

---

## Gate / kabul

1. `SP_MIG_597_GATE` → PASS  
2. Aktif `CANCEL_REV` + AFL kapalı = **0**  
3. `DUP_2X` (aynı INV, ≥2 aktif `INST_NR=0` ve `CP=0`) → **0** (veya cleanup sonrası)  
4. `95` raporu: `CP_REV_CNT>0` ve `CLOSED=0` ve `AFL_TUTAR IS NULL` → mümkün olduğunca **0**  
5. Spot: `66081785` → tek ana borç PT, `CLOSED=1`, `PAID≈PAYABLE`, AFL yok

---

## Dikkat

- **AFL dump şart** — yoksa INSERT tüm `CANCEL_REV`’i atlar; WIRE heal de skip.  
- Eski UX (`CP` filtresiz) varsa: drop + 576/91 ile yeniden create.  
- Bu ortamda heal için `WIRE-only` şu an çalıştırılmayacak; full reload v5 ile gelecek.  
- Mahsup over-close (`MAHSUP_CLOSED`) ayrı konu; CANCEL_REV ile karıştırma.

---

## Hızlı referans komutlar (aktarım günü)

```sql
-- Deploy
-- sqlcmd ... -i 28_DEPLOY_597.sql

EXEC energy.dbo.SP_MIG_597_ALL
     @AGR_ID = NULL, @CLEAN = 1, @DEBUG = 1, @BatchSize = 250000;

EXEC energy.dbo.SP_MIG_597_GATE @AGR_ID = NULL;

-- Spot
SELECT inv.LREF, inv.CLOSED,
       CONVERT(DECIMAL(18,2),inv.PAYABLETOTAL) INV_P,
       pt.LREF PT, pt.CANCELLATIONPAYMENT CP, pt.CANCELED,
       CONVERT(DECIMAL(18,2),pt.PAYABLETOTAL) P,
       CONVERT(DECIMAL(18,2),pt.PAID) PAID
FROM energy.dbo.LS_005_01_INVOICE inv
LEFT JOIN energy.dbo.LS_005_01_PAYTRANS pt
  ON pt.INVOICEREF = inv.LREF AND pt.IOCODE = 0
WHERE inv.LREF = 66081785;
```
