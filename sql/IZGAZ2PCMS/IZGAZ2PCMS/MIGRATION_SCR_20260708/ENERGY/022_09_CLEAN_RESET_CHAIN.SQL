/* =============================================================================
   prodREADY_ENERGY / 09_CLEAN_RESET_CHAIN

   Hata:
     Cannot truncate table 'LS_005_01_INVOICE' because it is being referenced
     by a FOREIGN KEY constraint.

   Neden:
     INVLINES / PAYTRANS → INVOICE FK. Parent once truncate/delete OLMAZ.
     Yanlis sirada 590/partial yukleme sonrasi sifirlamak icin once CHILD.

   Dogru temizleme sirasi:
     1) PAYTRANS  (575 HARD_RESET)
     2) INVLINES  (581 HARD_RESET)
     3) INVOICE   (571 HARD_RESET)
     4) MAP ENERGY_LREF sifirla (overlay tekrar yazilabilsin)
     sonra tekrar: 571 → 581 → 575 → 590_ALL → 597_ALL

   Onkosul: 570/574/580 setup deploy edilmis (PREPARE_LOAD / HARD_RESET SP var).
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

RAISERROR('========== CLEAN: child → parent (FK guvenli) ==========', 0, 1) WITH NOWAIT;

/* ----- 1) PAYTRANS (child) ----- */
IF OBJECT_ID('dbo.SP_MIG_DEBT_PAYTRANS_HARD_RESET', 'P') IS NULL
    RAISERROR('SP_MIG_DEBT_PAYTRANS_HARD_RESET yok — once 574+575 deploy.', 16, 1);
ELSE
BEGIN
    RAISERROR('--- 1/4 PAYTRANS HARD_RESET ---', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_DEBT_PAYTRANS_HARD_RESET
        @DELETE_BATCH = 50000,
        @AGR_ID       = NULL,
        @DEBUG        = 1;
END
GO

/* Overlay tahsilat/iade PT (IOCODE<>0) — HARD_RESET sadece borc IOCODE=0 siler.
   Full zincir reset icin ABYS isaretli tum PT: */
RAISERROR('--- 1b PAYTRANS overlay ABYS satirlar (IOCODE<>0 dahil) ---', 0, 1) WITH NOWAIT;
IF OBJECT_ID('dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD', 'P') IS NOT NULL
    EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = 1;

DECLARE @d INT, @n BIGINT = 0;
WHILE 1 = 1
BEGIN
    DELETE TOP (50000)
    FROM dbo.LS_005_01_PAYTRANS
    WHERE ABYS_ID IS NOT NULL;
    SET @d = @@ROWCOUNT;
    IF @d = 0 BREAK;
    SET @n += @d;
    RAISERROR('PAYTRANS ABYS silindi +%d (toplam %I64d)', 0, 1, @d, @n) WITH NOWAIT;
END
GO

/* ----- 2) INVLINES (child) ----- */
IF OBJECT_ID('dbo.SP_MIG_INVLINES_HARD_RESET', 'P') IS NULL
    RAISERROR('SP_MIG_INVLINES_HARD_RESET yok — once 580+581 deploy.', 16, 1);
ELSE
BEGIN
    RAISERROR('--- 2/4 INVLINES HARD_RESET ---', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INVLINES_HARD_RESET
        @DELETE_BATCH = 100000,
        @DEBUG        = 1;
END
GO

/* ----- 3) INVOICE (parent) — FK artik child yok / PREPARE_LOAD dusurur ----- */
IF OBJECT_ID('dbo.SP_MIG_INVOICE_HARD_RESET', 'P') IS NULL
    RAISERROR('SP_MIG_INVOICE_HARD_RESET yok — once 570+571 deploy.', 16, 1);
ELSE
BEGIN
    RAISERROR('--- 3/4 INVOICE HARD_RESET ---', 0, 1) WITH NOWAIT;
    EXEC dbo.SP_MIG_INVOICE_HARD_RESET
        @DELETE_BATCH = 50000,
        @DEBUG        = 1;
END
GO

/* ----- 4) Overlay MAP — ENERGY_LREF temiz (INSERT tekrar yazsin) ----- */
RAISERROR('--- 4/4 MIG_OV_ID_MAP.ENERGY_LREF NULL ---', 0, 1) WITH NOWAIT;
UPDATE dbo.MIG_OV_ID_MAP SET ENERGY_LREF = NULL WHERE ENERGY_LREF IS NOT NULL;
UPDATE izgazMGR.dbo.LS_OV_ID_MAP SET ENERGY_LREF = NULL WHERE ENERGY_LREF IS NOT NULL;
GO

/* Durum */
SELECT 'INVOICE'  AS T, COUNT(*) AS CNT, SUM(CASE WHEN ABYS_ID IS NOT NULL THEN 1 ELSE 0 END) AS ABYS_CNT
FROM dbo.LS_005_01_INVOICE
UNION ALL
SELECT 'INVLINES', COUNT(*), SUM(CASE WHEN ABYS_ID IS NOT NULL THEN 1 ELSE 0 END)
FROM dbo.LS_005_01_INVLINES
UNION ALL
SELECT 'PAYTRANS', COUNT(*), SUM(CASE WHEN ABYS_ID IS NOT NULL THEN 1 ELSE 0 END)
FROM dbo.LS_005_01_PAYTRANS
UNION ALL
SELECT 'MAP_EL', COUNT(*), SUM(CASE WHEN ENERGY_LREF IS NOT NULL THEN 1 ELSE 0 END)
FROM dbo.MIG_OV_ID_MAP;

RAISERROR('========== CLEAN OK — sonra EXEC_ALL: 571→581→575→590→597 ==========', 0, 1) WITH NOWAIT;
GO

/*
   TRUNCATE kullanma (FK patlar). Bu script DELETE + PREPARE_LOAD kullanir.

   Acil manuel (PREPARE_LOAD yoksa) — once FK drop sonra child delete:

   -- inbound FK drop (INVLINES/PAYTRANS → INVOICE)
   DECLARE @sql nvarchar(max)=N'';
   SELECT @sql=@sql+N'ALTER TABLE '+QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id))
     +N'.'+QUOTENAME(OBJECT_NAME(fk.parent_object_id))
     +N' DROP CONSTRAINT '+QUOTENAME(fk.name)+N';'
   FROM sys.foreign_keys fk
   WHERE fk.referenced_object_id=OBJECT_ID('dbo.LS_005_01_INVOICE');
   EXEC sp_executesql @sql;
*/
