/*
  28_DEPLOY_597.sql — 597 v5 paket deploy (energy)
  ---------------------------------------------------------------
  Klasör: prodREADY_ENERGY/
  Çalıştır (bu klasörden):
    sqlcmd -S <srv> -d energy -C -I -b -i 28_DEPLOY_597.sql

  KURALLAR
  - Dış BEGIN TRAN / IMPLICIT_TRANSACTIONS YASAK
  - Çalışan SP_MIG_597_* varken ALTER YAPMA (session 82 vb.)
  - Overlay EXEC sadece SP_MIG_597_ALL (tek INSERT yasak)
  - v5: CANCEL_REV AFL-gate + WIRE AFL heal + GATE; mevcut DB: WIRE-only heal

  PAKET
  00f  indexes (TAH/PAY SRC, MAP ELREF, STG)
  20   INSERT v5 (CANCEL_REV sadece AFL acik)
  21   WIRE v5 (CANCEL_REV soft-cancel + PAID/CLOSED)
  00g  BANKREF covering indexes (21 DDL sonrası — staging kolonları)
  22   GATE (+ CANCEL_REV/AFL)
  29   ALL

  OPS (deploy dışı, runbook):
  20b  PAYTRANS NCIX DISABLE — INSERT FULL öncesi
  20c  PAYTRANS NCIX REBUILD — GATE sonrası
  20a  TAH MAP fast fill — sadece resume

  Detay: NOTES_597_PERF_SAFE.md | README.md | RUN_ORDER.sql
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET IMPLICIT_TRANSACTIONS OFF;

USE energy;
GO

IF EXISTS (
    SELECT 1 FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID AND t.text LIKE N'%SP_MIG_597%'
)
BEGIN
    RAISERROR('SP_MIG_597_* RUNNING — 28_DEPLOY iptal (ALTER YASAK)', 16, 1);
    RETURN;
END
GO

RAISERROR('========== 28_DEPLOY_597 START ==========', 0, 1) WITH NOWAIT;
GO

:r 00f_597_v4_indexes.sql
GO

:r 20_597_INSERT.sql
GO

:r 21_597_WIRE.sql
GO

:r 00g_597_bankref_indexes.sql
GO

:r 22_597_GATE.sql
GO

:r 29_597_ALL.sql
GO

RAISERROR('========== 28_DEPLOY_597 SP CHECK ==========', 0, 1) WITH NOWAIT;

SELECT o.name,
       OBJECTPROPERTY(o.object_id, 'ExecIsQuotedIdentOn') AS QI,
       OBJECTPROPERTY(o.object_id, 'ExecIsAnsiNullsOn') AS AN,
       o.modify_date
FROM sys.objects o
WHERE o.name IN (
    'SP_MIG_597_INSERT',
    'SP_MIG_597_WIRE',
    'SP_MIG_597_GATE',
    'SP_MIG_597_ALL'
)
ORDER BY o.name;

IF OBJECT_DEFINITION(OBJECT_ID('dbo.SP_MIG_597_INSERT')) LIKE N'%UPDATE TOP (500000)%'
    RAISERROR('INSERT: fast TAH MAP resume OK', 0, 1) WITH NOWAIT;
ELSE
    RAISERROR('INSERT: fast TAH MAP resume marker YOK — 20_597_INSERT kontrol et', 16, 1);

IF OBJECT_DEFINITION(OBJECT_ID('dbo.SP_MIG_597_WIRE')) LIKE N'%TAH BANKREF keyset%'
    RAISERROR('WIRE: TAH BANKREF keyset OK', 0, 1) WITH NOWAIT;
ELSE
    RAISERROR('WIRE: TAH keyset marker YOK — 21_597_WIRE kontrol et', 16, 1);

IF COL_LENGTH('dbo.MIG_597_STG_TAH_BANK', 'BANK_LREF') IS NOT NULL
    RAISERROR('DDL: STG_TAH_BANK.BANK_LREF OK', 0, 1) WITH NOWAIT;
ELSE
    RAISERROR('DDL: STG_TAH_BANK.BANK_LREF YOK', 16, 1);
GO

RAISERROR('========== 28_DEPLOY_597 DONE ==========', 0, 1) WITH NOWAIT;
RAISERROR('FULL:   20b NCIX off → EXEC SP_MIG_597_ALL @CLEAN=1 @BatchSize=250000 → 20c rebuild', 0, 1) WITH NOWAIT;
RAISERROR('RESUME: EXEC SP_MIG_597_ALL @CLEAN=0 @BatchSize=250000  (gerekirse once 20a)', 0, 1) WITH NOWAIT;
RAISERROR('WIRE-only (BANKREF): EXEC SP_MIG_597_WIRE @AGR_ID=NULL @DEBUG=1 @BatchSize=200000', 0, 1) WITH NOWAIT;
GO
