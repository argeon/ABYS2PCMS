logs/ — manuel kosu ciktilari (opsiyonel)

Yapi (faz → adim klasoru):
  01_oracle_ctas/   O0, O0b, O10..O14, O20, O27, O30/O31, O40, O41, O50
  02_dump/          D1..D5
  03_energy/        L0, E0, E570..E581, E10/E20, E590/E597, E60, E70, E91, E80a/b
  04_hotfix/        A01..A04  (sadece delta / kaza sonrasi)

Ornek adlandirma (dosya adinda tarih):
  01_oracle_ctas/O20_eksilten_overlay/O20_20260724_0915.log
  01_oracle_ctas/O31_pay_alloc_only/O31_20260724_1030.log
  03_energy/E0_pre_indexes/E0_20260724_1100.log
  03_energy/E590_eksilten_overlay/E590_20260724_1110.log
  03_energy/E597_tahsilat_overlay/E597_20260724_1400.log
  03_energy/E91_afl_frk/E91_AFL_FRK_20260724.log

Kullanim:
  sqlplus ... @20_... | tee logs/01_oracle_ctas/O20_eksilten_overlay/O20_20260724.log
  sqlcmd ... -i 00_pre_indexes.sql -o logs/03_energy/E0_pre_indexes/E0_20260724.log

Asil sira takibi: energy.dbo.MIG_STEP_LOG (00_mig_step_log_*)
Bu klasore sqlplus/sqlcmd -o / tee ile yazin; otomatik runner yok.
.gitkeep sadece bos klasorleri git'te tutmak icindir — silinebilir.
