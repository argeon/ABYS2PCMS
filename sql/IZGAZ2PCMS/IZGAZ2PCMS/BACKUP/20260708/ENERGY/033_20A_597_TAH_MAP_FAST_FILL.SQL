/*
  20a_597_TAH_MAP_FAST_FILL.sql
  ---------------------------------------------------------------
  TAH_INV MAP hızlı doldurma (resume / CLEAN sonrası).
  - INV join YOK (LREF_HINT = energy INVOICE.LREF varsayımı)
  - Batch 500000, dış BEGIN TRAN YASAK
  - EN MAP önce; MGR MAP sync sonda
  Kullanım (energy):
    sqlcmd -I -d energy -i 20a_597_TAH_MAP_FAST_FILL.sql
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET IMPLICIT_TRANSACTIONS OFF;

USE energy;
GO

DECLARE @Batch INT = 500000;
DECLARE @N INT, @Total BIGINT = 0;
DECLARE @Msg NVARCHAR(400);
DECLARE @t0 DATETIME2 = SYSDATETIME();

RAISERROR('========== 597 TAH MAP FAST FILL START ==========', 0, 1) WITH NOWAIT;

/* ---- energy MIG_OV_ID_MAP ---- */
SET @Total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (@Batch) m
    SET m.ENERGY_LREF = CAST(s.LREF_HINT AS INT)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
        ON s.SRC_KEY = m.SRC_KEY
    WHERE m.OV_KIND = 'TAH_INV'
      AND m.ENERGY_LREF IS NULL
      AND s.LREF_HINT BETWEEN 1 AND 2147483647
    OPTION (RECOMPILE, MAXDOP 8);

    SET @N = @@ROWCOUNT;
    IF @N = 0 BREAK;

    SET @Total = @Total + @N;
    SET @Msg = N'EN TAH MAP +' + CAST(@N AS VARCHAR(20))
             + N' total=' + CAST(@Total AS VARCHAR(20))
             + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END

SET @Msg = N'EN TAH MAP done total=' + CAST(@Total AS VARCHAR(20))
         + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* ---- izgazMGR MIG_OV_ID_MAP sync ---- */
DECLARE @t1 DATETIME2 = SYSDATETIME();
SET @Total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (@Batch) mgr
    SET mgr.ENERGY_LREF = m.ENERGY_LREF
    FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
    INNER JOIN dbo.MIG_OV_ID_MAP m
        ON m.SRC_KEY = mgr.SRC_KEY
       AND m.OV_KIND = 'TAH_INV'
    WHERE mgr.OV_KIND = 'TAH_INV'
      AND mgr.ENERGY_LREF IS NULL
      AND m.ENERGY_LREF IS NOT NULL
    OPTION (RECOMPILE, MAXDOP 8);

    SET @N = @@ROWCOUNT;
    IF @N = 0 BREAK;

    SET @Total = @Total + @N;
    SET @Msg = N'MGR TAH MAP +' + CAST(@N AS VARCHAR(20))
             + N' total=' + CAST(@Total AS VARCHAR(20))
             + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t1, SYSDATETIME()) AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END

SET @Msg = N'MGR TAH MAP done total=' + CAST(@Total AS VARCHAR(20))
         + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t1, SYSDATETIME()) AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT
    (SELECT COUNT_BIG(*) FROM dbo.MIG_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = 'TAH_INV' AND ENERGY_LREF IS NOT NULL) AS en_map_tah,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = 'TAH_INV' AND ENERGY_LREF IS NOT NULL) AS mgr_map_tah,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_TAH_INVOICE WITH (NOLOCK)) AS mgr_tah,
    (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK) WHERE [TYPE] = 101) AS en_tah;

RAISERROR('========== 597 TAH MAP FAST FILL DONE ==========', 0, 1) WITH NOWAIT;
GO
