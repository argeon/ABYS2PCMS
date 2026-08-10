/* ============================================================
   SCRIPT_ID : READ_HHD_MSTR_APPLY
   SCRIPT_NO : 524
   FILE      : 524_READ_HHD_MSTR__apply.sql / 169_524_READ_HHD_MSTR__APPLY.SQL
   ============================================================
   SP_MIGRATE_LS005_HHD_MSTR
   Kaynak  : izgazMGR.dbo.LS_OV_HHD_MSTR (+ LS_OV_HHD_TRAN_MAP)
   Hedef   : energy.dbo.LS_005_01_hhd_to_hhd_mstr
             + LS_005_01_hhd_loc_inv_tran.read_no yama

   Kullanim:
     EXEC dbo.SP_MIGRATE_LS005_HHD_MSTR @MAXDOP = 64, @DEBUG = 1;
   ============================================================ */
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_HHD_MSTR
    @MAXDOP INT = 64,
    @DEBUG  BIT = 1
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    /* Filtered / ONLINE index CREATE icin session ayarlari */
    SET ANSI_NULLS ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET QUOTED_IDENTIFIER ON;
    SET NUMERIC_ROUNDABORT OFF;

    DECLARE @Msg NVARCHAR(400);
    DECLARE @N INT = 0;
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @PatchN INT = 0;

    IF @MAXDOP IS NULL OR @MAXDOP < 1 SET @MAXDOP = 1;
    IF @MAXDOP > 128 SET @MAXDOP = 128;

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_HHD_MSTR', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_OV_HHD_MSTR yok — once Oracle LS_HHD_MSTR.sql + dump.', 16, 1);
        RETURN;
    END;

    IF OBJECT_ID('energy.dbo.LS_005_01_hhd_to_hhd_mstr', 'U') IS NULL
    BEGIN
        RAISERROR('energy.dbo.LS_005_01_hhd_to_hhd_mstr yok.', 16, 1);
        RETURN;
    END;

    SET @Msg = N'========== 524 HHD MSTR APPLY START | MAXDOP=' + CAST(@MAXDOP AS VARCHAR(3)) + N' ==========';
    IF @DEBUG = 1 RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ------------------------------------------------------------------
       0) Index prep (ONLINE + MAXDOP)
       ------------------------------------------------------------------ */
    IF @DEBUG = 1 RAISERROR('---------- 524 INDEX PREP ----------', 0, 1) WITH NOWAIT;

    IF NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.indexes i
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = i.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = N'dbo' AND t.name = N'LS_OV_HHD_MSTR'
          AND i.name = N'UX_LS_OV_HHD_MSTR_READ_NO'
    )
    BEGIN
        IF @DEBUG = 1 RAISERROR('CREATE UX_LS_OV_HHD_MSTR_READ_NO (ONLINE)...', 0, 1) WITH NOWAIT;
        /* Filtered IX: BETWEEN yasak → >= / <= */
        SET @sql = N'
CREATE UNIQUE NONCLUSTERED INDEX UX_LS_OV_HHD_MSTR_READ_NO
    ON izgazMGR.dbo.LS_OV_HHD_MSTR (READ_NO)
    WHERE READ_NO >= 1 AND READ_NO <= 2147483647
    WITH (ONLINE = ON, MAXDOP = ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', SORT_IN_TEMPDB = ON);';
        EXEC sys.sp_executesql @sql;
    END
    ELSE IF @DEBUG = 1
        RAISERROR('UX_LS_OV_HHD_MSTR_READ_NO OK', 0, 1) WITH NOWAIT;

    IF NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.indexes i
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = i.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = N'dbo' AND t.name = N'LS_OV_HHD_MSTR'
          AND i.name = N'IX_LS_OV_HHD_MSTR_DATE_RN'
    )
    BEGIN
        IF @DEBUG = 1 RAISERROR('CREATE IX_LS_OV_HHD_MSTR_DATE_RN (ONLINE)...', 0, 1) WITH NOWAIT;
        SET @sql = N'
CREATE NONCLUSTERED INDEX IX_LS_OV_HHD_MSTR_DATE_RN
    ON izgazMGR.dbo.LS_OV_HHD_MSTR (READ_DATE, READ_NO)
    WITH (ONLINE = ON, MAXDOP = ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', SORT_IN_TEMPDB = ON);';
        EXEC sys.sp_executesql @sql;
    END
    ELSE IF @DEBUG = 1
        RAISERROR('IX_LS_OV_HHD_MSTR_DATE_RN OK', 0, 1) WITH NOWAIT;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic
            ON ic.object_id = i.object_id
           AND ic.index_id = i.index_id
           AND ic.index_column_id = 1
           AND ic.is_included_column = 0
        INNER JOIN sys.columns c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID(N'energy.dbo.LS_005_01_hhd_to_hhd_mstr')
          AND i.is_unique = 1
          AND c.name = N'read_no'
    )
    BEGIN
        IF @DEBUG = 1 RAISERROR('CREATE UX_LS005_HHD_MSTR_READ_NO (ONLINE)...', 0, 1) WITH NOWAIT;
        SET @sql = N'
CREATE UNIQUE NONCLUSTERED INDEX UX_LS005_HHD_MSTR_READ_NO
    ON energy.dbo.LS_005_01_hhd_to_hhd_mstr (read_no)
    WITH (ONLINE = ON, MAXDOP = ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', SORT_IN_TEMPDB = ON);';
        EXEC sys.sp_executesql @sql;
    END
    ELSE IF @DEBUG = 1
        RAISERROR('hedef MSTR read_no UNIQUE OK', 0, 1) WITH NOWAIT;

    IF OBJECT_ID(N'izgazMGR.dbo.LS_OV_HHD_TRAN_MAP', N'U') IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM izgazMGR.sys.indexes i
            INNER JOIN izgazMGR.sys.tables t ON t.object_id = i.object_id
            INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = N'dbo' AND t.name = N'LS_OV_HHD_TRAN_MAP'
              AND i.name = N'IX_LS_OV_HHD_TRAN_MAP_SRC_LREF'
       )
    BEGIN
        IF @DEBUG = 1 RAISERROR('CREATE IX_LS_OV_HHD_TRAN_MAP_SRC_LREF (ONLINE)...', 0, 1) WITH NOWAIT;
        SET @sql = N'
CREATE NONCLUSTERED INDEX IX_LS_OV_HHD_TRAN_MAP_SRC_LREF
    ON izgazMGR.dbo.LS_OV_HHD_TRAN_MAP (SRC_LREF)
    INCLUDE (READ_NO)
    WITH (ONLINE = ON, MAXDOP = ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', SORT_IN_TEMPDB = ON);';
        EXEC sys.sp_executesql @sql;
    END
    ELSE IF OBJECT_ID(N'izgazMGR.dbo.LS_OV_HHD_TRAN_MAP', N'U') IS NOT NULL AND @DEBUG = 1
        RAISERROR('IX_LS_OV_HHD_TRAN_MAP_SRC_LREF OK', 0, 1) WITH NOWAIT;

    IF OBJECT_ID(N'energy.dbo.LS_005_01_hhd_loc_inv_tran', N'U') IS NOT NULL
       AND COL_LENGTH(N'energy.dbo.LS_005_01_hhd_loc_inv_tran', N'ABYS_ID') IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'energy.dbo.LS_005_01_hhd_loc_inv_tran')
              AND name = N'IX_HHD_TRAN_READNO_EMPTY'
       )
    BEGIN
        IF @DEBUG = 1 RAISERROR('CREATE IX_HHD_TRAN_READNO_EMPTY (ONLINE)...', 0, 1) WITH NOWAIT;
        SET @sql = N'
CREATE NONCLUSTERED INDEX IX_HHD_TRAN_READNO_EMPTY
    ON energy.dbo.LS_005_01_hhd_loc_inv_tran (ABYS_ID)
    INCLUDE (read_no)
    WHERE read_no IS NULL OR read_no = 0
    WITH (ONLINE = ON, MAXDOP = ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', SORT_IN_TEMPDB = ON);';
        EXEC sys.sp_executesql @sql;
    END
    ELSE IF OBJECT_ID(N'energy.dbo.LS_005_01_hhd_loc_inv_tran', N'U') IS NOT NULL AND @DEBUG = 1
        RAISERROR('IX_HHD_TRAN_READNO_EMPTY OK', 0, 1) WITH NOWAIT;

    IF @DEBUG = 1 RAISERROR('---------- 524 INDEX PREP DONE ----------', 0, 1) WITH NOWAIT;

    /* ------------------------------------------------------------------
       1) MSTR INSERT (IDENTITY_INSERT + TABLOCK + parallel)
       ------------------------------------------------------------------ */
    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_hhd_to_hhd_mstr ON;

        SET @sql = N'
INSERT INTO energy.dbo.LS_005_01_hhd_to_hhd_mstr WITH (TABLOCK) (
    read_no, reader_region, reader_cmp, read_date, reader_prsnl, reader_prsnl_id,
    TOTAL_COUNT, NOTREAD_COUNT, ENDOFDAY_ID, rec_status, READING_TYPE,
    route_grp, ADDDATE, ADDUSER
)
SELECT
    CAST(s.READ_NO AS INT),
    CAST(s.READER_REGION AS INT),
    CAST(ISNULL(s.READER_CMP, 0) AS INT),
    CASE
        WHEN s.READ_DATE IS NULL THEN CAST(''19000101'' AS SMALLDATETIME)
        WHEN CAST(s.READ_DATE AS DATETIME2) < ''1900-01-01'' THEN CAST(''19000101'' AS SMALLDATETIME)
        WHEN CAST(s.READ_DATE AS DATETIME2) > ''2079-06-06 23:59:00'' THEN CAST(''2079-06-06 23:59:00'' AS SMALLDATETIME)
        ELSE CAST(s.READ_DATE AS SMALLDATETIME)
    END,
    LEFT(s.READER_PRSNL, 50),
    CAST(s.READER_PRSNL_ID AS INT),
    CAST(s.TOTAL_COUNT AS INT),
    CAST(s.NOTREAD_COUNT AS INT),
    CAST(s.ENDOFDAY_ID AS INT),
    CAST(ISNULL(s.REC_STATUS, 3) AS SMALLINT),
    CAST(ISNULL(s.READING_TYPE, 0) AS INT),
    CAST(LEFT(ISNULL(s.ROUTE_GRP, N''''), 50) AS VARCHAR(50)),
    GETDATE(),
    0
FROM izgazMGR.dbo.LS_OV_HHD_MSTR s WITH (NOLOCK)
WHERE s.READ_NO BETWEEN 1 AND 2147483647
  AND NOT EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_hhd_to_hhd_mstr t WITH (NOLOCK)
        WHERE t.read_no = CAST(s.READ_NO AS INT)
      )
ORDER BY s.READ_DATE, s.READ_NO
OPTION (RECOMPILE, MAXDOP ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', USE HINT(''ENABLE_PARALLEL_PLAN_PREFERENCE''));';

        EXEC sys.sp_executesql @sql;
        SET @N = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_hhd_to_hhd_mstr OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH;

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_hhd_to_hhd_mstr OFF; END TRY BEGIN CATCH END CATCH;

    SET @Msg = N'524 MSTR INSERT=' + CAST(@N AS VARCHAR(20)) + N' | MAXDOP=' + CAST(@MAXDOP AS VARCHAR(3));
    IF @DEBUG = 1 RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    /* ------------------------------------------------------------------
       2) TRAN read_no PATCH (MAP)
       ------------------------------------------------------------------ */
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_HHD_TRAN_MAP', 'U') IS NOT NULL
    BEGIN
        SET @sql = N'
UPDATE t
SET t.read_no = CAST(m.READ_NO AS INT)
FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t WITH (TABLOCK)
INNER JOIN izgazMGR.dbo.LS_OV_HHD_TRAN_MAP m WITH (NOLOCK)
    ON m.SRC_LREF = t.ABYS_ID
WHERE ISNULL(t.read_no, 0) = 0
  AND m.READ_NO BETWEEN 1 AND 2147483647
OPTION (RECOMPILE, MAXDOP ' + CAST(@MAXDOP AS NVARCHAR(3)) + N', USE HINT(''ENABLE_PARALLEL_PLAN_PREFERENCE''));';

        EXEC sys.sp_executesql @sql;
        SET @PatchN = @@ROWCOUNT;

        SET @Msg = N'524 TRAN read_no PATCH=' + CAST(@PatchN AS VARCHAR(20)) + N' | MAXDOP=' + CAST(@MAXDOP AS VARCHAR(3));
        IF @DEBUG = 1 RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
    ELSE IF @DEBUG = 1
        RAISERROR('524 TRAN MAP yok — sadece MSTR basildi.', 0, 1) WITH NOWAIT;

    /* ------------------------------------------------------------------
       3) Kontrol
       ------------------------------------------------------------------ */
    SELECT 'MSTR' AS K, COUNT(*) AS N FROM dbo.LS_005_01_hhd_to_hhd_mstr WITH (NOLOCK)
    UNION ALL
    SELECT 'MSTR_ORPHAN_TYPE9', COUNT(*) FROM dbo.LS_005_01_hhd_to_hhd_mstr WITH (NOLOCK) WHERE READING_TYPE = 9
    UNION ALL
    SELECT 'MSTR_INSERTED_THIS_RUN', @N
    UNION ALL
    SELECT 'TRAN_READNO_PATCH', @PatchN
    UNION ALL
    SELECT 'TRAN_READNO0', COUNT(*) FROM dbo.LS_005_01_hhd_loc_inv_tran WITH (NOLOCK) WHERE ISNULL(read_no,0) = 0;

    IF @DEBUG = 1 RAISERROR('========== 524 HHD MSTR APPLY DONE ==========', 0, 1) WITH NOWAIT;
END
GO

/* Deploy sonrasi exec ornegi:
EXEC dbo.SP_MIGRATE_LS005_HHD_MSTR @MAXDOP = 64, @DEBUG = 1;
*/
GO
