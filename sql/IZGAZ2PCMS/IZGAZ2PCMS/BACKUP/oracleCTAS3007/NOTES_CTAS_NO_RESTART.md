# CTAS — baştan alma YASAK (resume disiplini)

**Neden bu not:** Geçen cutover’da Oracle CTAS “çalışır çalışmaz patladı”, her seferinde `00_run_all` baştan → saatler boşa.  
**Kural:** FAIL = **o adımdan devam**; master/okuma OK ise **A01’den silme**.

Canlı: `BACKUP/oracleCTAS3007/` · Paket: `MIGRATION_SCR_20260708/CTAS/`  
Sıra: `SCHEMA_CTAS_ORDER.md` · Log: `MIG_CTAS_LOG` · Özet: `@99_log_status.sql`

---

## 0) Ne oldu / ne yanlıştı

| Yanlış | Doğru |
|--------|--------|
| `WHENEVER SQLERROR EXIT` → panik → `@00_run_all` yeniden | Son OK adımı bul → yalnız o adım + sonrası |
| TEMP/PGA/DOP 56 ile kör FULL | Preflight → gerekirse DOP **48** |
| Gate FAIL → dump + master wipe | Gate FAIL → **dump yok**; master/O10–O26 durur |
| Pilot’süz FULL | Önce pilot overlay / küçük AGR; sonra FULL |
| Tek oturum 8 saat, ortada kopunca başa | **Fazlı koşu** (aşağı) + her faz sonunda `99_log_status` |

`00_run_all.sql` üstünde `WHENEVER SQLERROR EXIT FAILURE` var → **ilk ORA tüm zinciri öldürür**. Bu “her şey bozuk” demek değil; sadece sqlplus çıktı.

---

## 1) Preflight (O0 öncesi — 10 dk, atlama = yeniden patlama)

```text
[ ] sqlplus MIGRATION (+ SMS okuma yetkisi) OK
[ ] Tablespace MIGRATION / USERS free — büyük CTAS’lar için GB mertebesi boş
[ ] TEMP yeterli (DOP 56 açlığında ORA-01652 klasik)
[ ] Undo retention / undo TS — uzun PQ’da ORA-01555 riski
[ ] Tee log: logs/oracleCTAS3007/FULL_YYYYMMDD_HHMM.log
[ ] MIG_CTAS_LOG kuruldu (@00_mig_ctas_log) — yoksa kör uçuş
[ ] DOP kararı: varsayılan 56; TEMP baskısı / ORA-12801 → 00_session_parallel’da 48
[ ] _skip/* zincire karışmaz (O30h/40/31/diag)
```

Hızlı Oracle kontrol (örnek):

```sql
SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024/1024,1) GB
FROM dba_free_space
WHERE tablespace_name IN ('TEMP','UNDOTBS1','MIGRATION','USERS')
GROUP BY tablespace_name;

-- Son koşu özeti
@99_log_status.sql
```

---

## 2) Fazlı koşu (cutover gecesi önerilen)

Kör `@00_run_all` yerine **faz + checkpoint**. Her faz OK olmadan sonrakine geçme.

```text
FAZ 0  Preflight + @00_mig_ctas_log + @00_session_parallel + @00_mig_param_full
FAZ A  Master A01–A19          → 99_log  (FLAT…PROJECTLINE)
FAZ R  O09 + READING + SYNTH + HHD + HHDg★  → GATE PASS
FAZ B1 O10→O14                 → INV/IL/DEBT prefab OK
FAZ B2 O20 → O27★              → GATE_PASS (FAIL=DUR, dump yok)
FAZ B3 O30→O35 → O41★          → GATE_PASS
FAZ C  O50→O61 + O59 + O98     → 99_log FAIL=0
       → DUMP_MANIFEST
```

Pilot (dakikalar, FULL öncesi duman testi):

```text
@00_mig_param_pilot.sql → @00_run_pilot_overlay.sql
```

---

## 3) Patladı — ne yap (cheat sheet)

### 3a) Önce log

```sql
-- Son durumlar
SELECT STEP_ID, STEP_NAME, STATUS, NOTE, LOG_TS
FROM MIGRATION.MIG_CTAS_LOG
ORDER BY LOG_TS DESC
FETCH FIRST 40 ROWS ONLY;

-- FAIL / GATE_FAIL
SELECT * FROM MIGRATION.MIG_CTAS_LOG
WHERE STATUS IN ('FAIL','GATE_FAIL')
ORDER BY LOG_TS DESC;
```

`@99_log_status.sql` → FAIL satırı = **resume noktası**.

### 3b) Resume matrisi (baştan YOK)

| Son OK | Sonraki başlat | Yeniden koşma |
|--------|----------------|---------------|
| A19 / master | O09 → READING… | A01–A19 **yok** |
| HHDg PASS | O10 | master/okuma **yok** |
| O14 OK | O20 | O10–O14 yok (O20 DROP+CREATE kendi OV) |
| O27 PASS | O30 | O20 yeniden **yalnız** O27 bozulduysa |
| O30 FAIL | O30 (tekrar) | O11 silme |
| O41 FAIL | ilgili O32–O35 veya O30 | O10 baştan yok |
| O50+ FAIL | o adım | tahsilat gate’e dokunma |
| TEMP/PGA mid-step | DOP 48 → **aynı adım** tekrar | `00_run_all` baştan yok |

Her adım scripti genelde **DROP+CREATE** → o adımı tekrar koşmak güvenli; **bağımlı sonraki adımları** da yeniden koş (örn. O11 değiştiyse O12+).

### 3c) Bağımlılık (kısa)

```text
O10 → O11 → O12 → O13 / O14
O11+ → O20 → O27★
O11+O14+ → O30 → O32 → O34 → O33 → O14b → O35 → O41★
O41 → O50 → O51 → …
O20 → O53
O11 → O54
O30 → O55
O60 bağımsız ama dump listesinde — yoksa Energy E610 ATLA
```

### 3d) Yaygın ORA → aksiyon

| Belirti | Aksiyon |
|---------|---------|
| ORA-01652 unable to extend TEMP | DOP 48; TEMP büyüt; **aynı adım** |
| ORA-12801 / parallel query server | DOP düşür; session yeniden O0 |
| ORA-01555 snapshot too old | undo; uzun adımı yeniden; SMS yükünü azalt |
| ORA-01653 / 01654 tablespace | free space; **aynı adım** |
| ORA-00942 / eksik kaynak | SMS yetki / synonym; master önkoşul |
| ORA-01790 datatype | ilgili LS_* script (AGR_GUARANTY tipi) — fix + o adım |
| GATE_FAIL O27/O41/O58 | dump **YOK**; overlay düzelt; gate’e kadar dar yeniden |
| sqlplus koptu / VPN | `MIG_CTAS_LOG` son START/OK; START kalmışsa o adım yarım → **tekrar o dosya** |

---

## 4) Cutover gecesi operatör kartı

```text
1) Preflight §1
2) Faz A → log OK
3) Faz R (HHD gate) → PASS
4) Faz B1–B2 → O27 PASS
5) Faz B3 → O41 PASS
6) Faz C → 99_log FAIL=0
7) Dump → izgazMGR
8) Energy: CUTOVER_ONE_PAGE (00b → 571…)

PATLAYINCA:
  - 99_log_status
  - FAIL adımı not et
  - §3b resume — 00_run_all BAŞTAN YASAK
  - DOP/TEMP ise önce altyapı, sonra aynı adım
```

---

## 5) Energy’ye geçiş kapısı

Dump ancak:

- `MIG_CTAS_LOG`’da **FAIL/GATE_FAIL = 0**
- O27 + O41 (+ O58) **PASS**
- `DUMP_MANIFEST` tabloları mevcut

Sonra Energy one-page — CTAS patlamasını Energy’de “baştan 571” ile telafi etme.

---

## Referans

- `00_run_all.sql` · `00_run_pilot_overlay.sql` · `00_session_parallel.sql` (DOP)
- `MANUAL_CHECKLIST_ORACLE.txt` · `SCHEMA_CTAS_ORDER.md` · `INDEX.md`
- Energy: `prodREADY_ENERGY/CUTOVER_ONE_PAGE.md`
