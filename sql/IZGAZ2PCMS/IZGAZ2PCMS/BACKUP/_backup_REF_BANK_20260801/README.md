# REF_BANK backup — 2026-08-01

Replaced multi-file bank bridge (MIG_LS_BANK_MAP + SP_MIGRATE_LS_BANK) with single MERGE script:

`121_REF_BANK__migrate.sql` (v2)

## Removed (backed up here)

| File | Role |
|------|------|
| 120_REF_BANK__setup.sql | MIG_LS_BANK_MAP, validate, load-from-ABYS |
| 121_REF_BANK__migrate.sql | SP_MIGRATE_LS_BANK (v1) |
| 122_REF_BANK__post.sql | SP_MIG_LS_BANK_LOAD_FROM_ABYS |
| 123_REF_BANK__check.sql | map-based checks |

`prodENERGY/` mirror copies are under `prodENERGY/`.
