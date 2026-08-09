logs/ — manuel kosu ciktilari (PROD)

Yapi:
  01_oracle_ctas/   prodREADY O0..O50  (tee)
  02_dump/          D1..D5
  03_energy/        prodREADY_ENERGY   (sqlcmd -o)
  04_hotfix/        sadece kaza

Ornek:
  sqlplus ... @20_ls_eksilten_overlay.sql | tee logs/01_oracle_ctas/O20_20260724_2030.log
  sqlcmd ... -i 19_590_ALL.sql -o logs/03_energy/E590_ALL_20260724_2100.log

Asil takip (DB):
  Oracle: MIGRATION.MIG_CTAS_LOG     → @oracleCTAS/prodREADY/99_log_status.sql
  Energy: energy.dbo.MIG_STEP_LOG    → EXEC SP_MIG_LOG_STATUS

Paket: oracleCTAS/prodREADY + prodEnergy/prodREADY_ENERGY
Eski prod2 / 590__full cutover'da KULLANMA.
