# 20260708/CTAS — CALISTIRMA SIRASI (yenilendi 2026-08-09)

Kaynak: oracleCTAS3007 omurga + oracleCTAS/prodREADY (ayni ad varsa daha yeni kazanan).
Bu klasor KOPYA arsiv + kosulabilir orchestrator.

| Faz | NNN | Ne |
|-----|-----|----|
| DOC | 000_* | INDEX / SCHEMA / DUMP / CATALOG |
| A | 001–027 | Master CTAS (+ LS_PROJECT / LS_PROJECTLINE) |
| B | 030–060 | Tahsilat / overlay / gate |
| B-opt | 033 / 061 | pilot param / STG cleanup |
| EXTRA | 070+ | prodREADY-only / 3007-extra diag |
| ORCH | 00_RUN_ALL / 090 | tek FULL orchestrator |

## ORCH — bastan FULL

`	ext
cd ...\20260708\CTAS
sqlplus user/pass@db @00_RUN_ALL.SQL
`

Sira: SESSION → master A01–A19 → O09/READING/HHD → KFACTOR/SPEFEE → O10–O60 → IX → log
MIG_CTAS_LOG: cnt / MB / start / end / sec

Detay: ../MANIFEST_CTAS.txt · SCHEMA: 000_SCHEMA_CTAS_ORDER.MD
