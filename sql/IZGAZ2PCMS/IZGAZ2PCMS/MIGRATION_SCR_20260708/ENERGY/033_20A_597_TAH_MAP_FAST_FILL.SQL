/*
  20a_597_TAH_MAP_FAST_FILL.sql
  ---------------------------------------------------------------
  TAH_INV MAP hızlı doldurma (resume / CLEAN sonrası).
  - INV join YOK (LREF_HINT = energy INVOICE.LREF)
  - MGR LS_OV_ID_MAP = HEAP → UPDATE TOP + IS NULL rescan ÖLDÜRÜR
  - Keyset: energy SRC_KEY walk + MIG_20A_STG_KEYS (physical)
  - IMPLICIT OFF; dış BEGIN TRAN YOK; MAXDOP 8
  Kullanım (energy):
    sqlcmd -S 172.16.1.195 -d energy -C -I -f 65001 -i 20a_597_TAH_MAP_FAST_FILL.sql
    SSMS: Implicit Transactions OFF; dosyayi diskten ac (@Batch=500000)
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET IMPLICIT_TRANSACTIONS OFF;

USE energy;
GO

DECLARE @Batch INT = 500000;
DECLARE @N INT, @Upd INT, @Total BIGINT = 0;
DECLARE @Msg NVARCHAR(400);
DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @LastKey VARCHAR(80) = N'';

RAISERROR('========== 597 TAH MAP FAST FILL START ==========', 0, 1) WITH NOWAIT;

IF OBJECT_ID('dbo.MIG_20A_STG_KEYS', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_20A_STG_KEYS (
        SRC_KEY     VARCHAR(80) NOT NULL,
        ENERGY_LREF INT         NOT NULL,
        CONSTRAINT PK_MIG_20A_STG_KEYS PRIMARY KEY CLUSTERED (SRC_KEY)
    );
    RAISERROR('CREATE MIG_20A_STG_KEYS', 0, 1) WITH NOWAIT;
END

/* ---- 1) energy MAP: NULL → LREF_HINT (keyset) ---- */
SET @Total = 0;
SET @LastKey = N'';
WHILE 1 = 1
BEGIN
    TRUNCATE TABLE dbo.MIG_20A_STG_KEYS;

    INSERT INTO dbo.MIG_20A_STG_KEYS (SRC_KEY, ENERGY_LREF)
    SELECT TOP (@Batch) m.SRC_KEY, CAST(s.LREF_HINT AS INT)
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN izgazMGR.dbo.LS_OV_TAH_INVOICE s WITH (NOLOCK)
        ON s.SRC_KEY = m.SRC_KEY
    WHERE m.OV_KIND = 'TAH_INV'
      AND m.ENERGY_LREF IS NULL
      AND m.SRC_KEY > @LastKey
      AND s.LREF_HINT BETWEEN 1 AND 2147483647
    ORDER BY m.SRC_KEY
    OPTION (RECOMPILE, MAXDOP 8);

    SET @N = @@ROWCOUNT;
    IF @N = 0 BREAK;

    UPDATE m
    SET m.ENERGY_LREF = b.ENERGY_LREF
    FROM dbo.MIG_OV_ID_MAP m
    INNER JOIN dbo.MIG_20A_STG_KEYS b ON b.SRC_KEY = m.SRC_KEY
    OPTION (RECOMPILE, MAXDOP 8, FORCE ORDER);

    SET @Upd = @@ROWCOUNT;
    SELECT @LastKey = MAX(SRC_KEY) FROM dbo.MIG_20A_STG_KEYS;
    SET @Total = @Total + @Upd;
    SET @Msg = N'EN TAH MAP +' + CAST(@Upd AS VARCHAR(20))
             + N' total=' + CAST(@Total AS VARCHAR(20))
             + N' last=' + @LastKey
             + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END

SET @Msg = N'EN TAH MAP done total=' + CAST(@Total AS VARCHAR(20))
         + N' elapsed_s=' + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

/* ---- 2) MGR sync: energy SRC_KEY walk (null arama YOK) ---- */
DECLARE @t1 DATETIME2 = SYSDATETIME();
SET @Total = 0;
SET @LastKey = N'';

WHILE 1 = 1
BEGIN
    TRUNCATE TABLE dbo.MIG_20A_STG_KEYS;

    INSERT INTO dbo.MIG_20A_STG_KEYS (SRC_KEY, ENERGY_LREF)
    SELECT TOP (@Batch) m.SRC_KEY, m.ENERGY_LREF
    FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
    WHERE m.OV_KIND = 'TAH_INV'
      AND m.ENERGY_LREF IS NOT NULL
      AND m.SRC_KEY > @LastKey
    ORDER BY m.SRC_KEY
    OPTION (RECOMPILE, MAXDOP 8);

    SET @N = @@ROWCOUNT;
    IF @N = 0 BREAK;

    UPDATE mgr
    SET mgr.ENERGY_LREF = b.ENERGY_LREF
    FROM izgazMGR.dbo.LS_OV_ID_MAP mgr
    INNER JOIN dbo.MIG_20A_STG_KEYS b ON b.SRC_KEY = mgr.SRC_KEY
    WHERE mgr.ENERGY_LREF IS NULL
    OPTION (RECOMPILE, MAXDOP 8, FORCE ORDER);

    SET @Upd = @@ROWCOUNT;
    SELECT @LastKey = MAX(SRC_KEY) FROM dbo.MIG_20A_STG_KEYS;
    SET @Total = @Total + @Upd;
    SET @Msg = N'MGR TAH MAP +' + CAST(@Upd AS VARCHAR(20))
             + N'/' + CAST(@N AS VARCHAR(20))
             + N' total=' + CAST(@Total AS VARCHAR(20))
             + N' last=' + @LastKey
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
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK)
     WHERE OV_KIND = 'TAH_INV' AND ENERGY_LREF IS NULL) AS mgr_map_tah_null,
    (SELECT COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_TAH_INVOICE WITH (NOLOCK)) AS mgr_tah;

RAISERROR('========== 597 TAH MAP FAST FILL DONE ==========', 0, 1) WITH NOWAIT;
GO
