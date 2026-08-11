/* =============================================================================
   prodREADY_ENERGY / 26_IX_PRECHECK.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_IX_PRECHECK  (R22 2026-08-11)

   Hard FAIL — kritik MGR/energy IX yoksa aktarıma BASLAMA.
   EXEC dbo.SP_MIG_IX_PRECHECK;
   EXEC dbo.SP_MIG_IX_PRECHECK @Require597Src = 1, @RequireMapClustered = 1;
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_IX_PRECHECK
    @Require597Src       BIT = 1,   -- UX_MIG_LS_OV_TAH_INVOICE_SRC (597 hard)
    @RequireMapClustered BIT = 1,   -- LS_OV_ID_MAP type=1 clustered
    @RequirePayLref      BIT = 1,
    @DEBUG               BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @miss INT = 0;
    DECLARE @msg NVARCHAR(400);

    IF OBJECT_ID(N'tempdb..#ix_gate') IS NOT NULL DROP TABLE #ix_gate;
    CREATE TABLE #ix_gate (
        DB_NAME   SYSNAME NOT NULL,
        OBJ_NAME  SYSNAME NOT NULL,
        IX_NAME   SYSNAME NOT NULL,
        REQUIRED  BIT NOT NULL,
        PRESENT   BIT NOT NULL,
        NOTE      NVARCHAR(120) NULL
    );

    /* ---- MGR ---- */
    INSERT INTO #ix_gate (DB_NAME, OBJ_NAME, IX_NAME, REQUIRED, PRESENT, NOTE)
    SELECT N'izgazMGR', N'LS_INVOICE', N'IX_MIG_LSINV_ACTION', 1,
           CASE WHEN EXISTS (
                SELECT 1 FROM izgazMGR.sys.indexes
                WHERE object_id = OBJECT_ID(N'izgazMGR.dbo.LS_INVOICE')
                  AND name = N'IX_MIG_LSINV_ACTION') THEN 1 ELSE 0 END,
           N'571 INDEX hint';

    INSERT INTO #ix_gate VALUES
    (N'izgazMGR', N'LS_INVLINES', N'IX_MIG_LSINVLINES_LREF', 1,
     CASE WHEN EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID(N'izgazMGR.dbo.LS_INVLINES') AND name=N'IX_MIG_LSINVLINES_LREF') THEN 1 ELSE 0 END,
     N'581'),
    (N'izgazMGR', N'LS_INVLINES', N'IX_MIG_LSIL_INVREF', 1,
     CASE WHEN EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID(N'izgazMGR.dbo.LS_INVLINES') AND name=N'IX_MIG_LSIL_INVREF') THEN 1 ELSE 0 END,
     N'581');

    IF @RequirePayLref = 1
        INSERT INTO #ix_gate VALUES
        (N'izgazMGR', N'LS_PAYMENT', N'UX_MIG_LS_PAYMENT_PAY_LREF', 1,
         CASE WHEN EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID(N'izgazMGR.dbo.LS_PAYMENT') AND name=N'UX_MIG_LS_PAYMENT_PAY_LREF') THEN 1 ELSE 0 END,
         N'00d / 35 / 597 WIRE'),
        (N'izgazMGR', N'LS_OV_TAH_INVOICE', N'IX_MIG_LS_OV_TAH_INVOICE_ABYS', 1,
         CASE WHEN EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID(N'izgazMGR.dbo.LS_OV_TAH_INVOICE') AND name=N'IX_MIG_LS_OV_TAH_INVOICE_ABYS') THEN 1 ELSE 0 END,
         N'00d');

    IF @Require597Src = 1
        INSERT INTO #ix_gate VALUES
        (N'izgazMGR', N'LS_OV_TAH_INVOICE', N'UX_MIG_LS_OV_TAH_INVOICE_SRC', 1,
         CASE WHEN EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID(N'izgazMGR.dbo.LS_OV_TAH_INVOICE') AND name=N'UX_MIG_LS_OV_TAH_INVOICE_SRC') THEN 1 ELSE 0 END,
         N'00f — 597 hard'),
        (N'izgazMGR', N'LS_OV_PAY_PT', N'UX_MIG_LS_OV_PAY_PT_SRC', 1,
         CASE WHEN EXISTS (SELECT 1 FROM izgazMGR.sys.indexes WHERE object_id=OBJECT_ID(N'izgazMGR.dbo.LS_OV_PAY_PT') AND name=N'UX_MIG_LS_OV_PAY_PT_SRC') THEN 1 ELSE 0 END,
         N'00f');

    IF @RequireMapClustered = 1
        INSERT INTO #ix_gate (DB_NAME, OBJ_NAME, IX_NAME, REQUIRED, PRESENT, NOTE)
        SELECT N'izgazMGR', N'LS_OV_ID_MAP', N'(clustered SRC_KEY)', 1,
               CASE WHEN EXISTS (
                    SELECT 1 FROM izgazMGR.sys.indexes
                    WHERE object_id = OBJECT_ID(N'izgazMGR.dbo.LS_OV_ID_MAP') AND type = 1
               ) THEN 1 ELSE 0 END,
               N'00i HEAP→PK';

    IF @DEBUG = 1
        SELECT * FROM #ix_gate ORDER BY DB_NAME, OBJ_NAME, IX_NAME;

    SELECT @miss = COUNT(*) FROM #ix_gate WHERE REQUIRED = 1 AND PRESENT = 0;

    IF @miss > 0
    BEGIN
        SET @msg = N'SP_MIG_IX_PRECHECK FAIL — missing=' + CAST(@miss AS NVARCHAR(10))
                 + N' — once EXEC SP_MIG_IX_MGR_ENSURE';
        RAISERROR('%s', 16, 1, @msg);
        RETURN;
    END

    RAISERROR('SP_MIG_IX_PRECHECK PASS', 0, 1) WITH NOWAIT;
END
GO
/* EXEC dbo.SP_MIG_IX_PRECHECK; */
