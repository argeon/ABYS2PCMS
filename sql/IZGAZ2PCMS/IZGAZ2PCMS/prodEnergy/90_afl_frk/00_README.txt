90_afl_frk — AFL master vs energy FRK

Grain: FATURAID = CS_ACCOUNT.ID = INVOICE.ABYS_ACCOUNT_ID
Master: izgazMGR.LS_AFL_OPEN_DEBT (Oracle prod2/50_ls_afl_open_debt.sql)

Sira
----
1) Oracle: @50_ls_afl_open_debt.sql
2) Dump → izgazMGR.LS_AFL_OPEN_DEBT
3) prodEnergy/00_pre_indexes.sql (AFL index)
4) 91_afl_frk_compare_log.sql
5) Incele: energy.dbo.MIG_AFL_FRK_LOG (KIND <> MATCH)

KIND: MATCH | AMT_DIFF | ONLY_AFL | ONLY_EN
@OnlyMig=1 → ACCRUE<>14 (MIG_IN_SCOPE)
