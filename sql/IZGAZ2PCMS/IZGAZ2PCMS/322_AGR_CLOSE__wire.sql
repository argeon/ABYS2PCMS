/* ============================================================
   SCRIPT_ID : AGR_CLOSE_WIRE
   SCRIPT_NO : 322
   FILE      : 322_AGR_CLOSE__wire.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- AGR migrate sonrası: ABYS_AGREEMENT_ID → AGRID (LS_005_01_AGR.LREF)
-- LS_005_01_AGR.ABYS_ID eklendiginde @AgrAbysColumn = N'ABYS_ID' kullanin
-- Orphan kontrol: 39_ls_agr_close_check_queries.sql
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_AGR_WIRE_AGRID
    @TargetSchema   SYSNAME = N'dbo',
    @TargetTable    SYSNAME,
    @AbysColumn     SYSNAME = N'ABYS_AGREEMENT_ID',
    @FkColumn       SYSNAME = N'AGRID',
    @AgrSchema      SYSNAME = N'dbo',
    @AgrTable       SYSNAME = N'LS_005_01_AGR',
    @AgrAbysColumn  SYSNAME = N'ABYS_ID',
    @AgrLrefColumn  SYSNAME = N'LREF',
    @Debug          BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Sql       NVARCHAR(MAX),
        @FullTable NVARCHAR(300),
        @FullAgr   NVARCHAR(300),
        @Updated   INT;

    SET @FullTable = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);
    SET @FullAgr   = QUOTENAME(@AgrSchema) + N'.' + QUOTENAME(@AgrTable);

    IF OBJECT_ID(N'energy.' + @FullTable, 'U') IS NULL
    BEGIN
        RAISERROR('Hedef tablo bulunamadi: energy.%s', 16, 1, @FullTable);
        RETURN 1;
    END

    IF OBJECT_ID(N'energy.' + @FullAgr, 'U') IS NULL
    BEGIN
        RAISERROR('AGR tablosu bulunamadi: energy.%s. Once AGR migrate calistirin.', 16, 1, @FullAgr);
        RETURN 1;
    END

    SET @Sql = N'
UPDATE t
SET t.' + QUOTENAME(@FkColumn) + N' = a.' + QUOTENAME(@AgrLrefColumn) + N'
FROM energy.' + @FullTable + N' t
INNER JOIN energy.' + @FullAgr + N' a
    ON a.' + QUOTENAME(@AgrAbysColumn) + N' = t.' + QUOTENAME(@AbysColumn) + N'
WHERE t.' + QUOTENAME(@AbysColumn) + N' IS NOT NULL
  AND (t.' + QUOTENAME(@FkColumn) + N' IS NULL
       OR t.' + QUOTENAME(@FkColumn) + N' <> a.' + QUOTENAME(@AgrLrefColumn) + N');';

    EXEC sp_executesql @Sql;
    SET @Updated = @@ROWCOUNT;

    IF @Debug = 1
        RAISERROR('Wiring %s.%s <- %s: %d satir', 0, 1,
            @TargetTable, @FkColumn, @AgrTable, @Updated) WITH NOWAIT;

    SELECT
        @TargetTable   AS TARGET_TABLE,
        @AbysColumn    AS ABYS_COLUMN,
        @FkColumn       AS FK_COLUMN,
        @AgrTable       AS AGR_TABLE,
        @Updated        AS UPDATED_ROWS;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_CLOSE_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- AGR.LREF = IDENTITY; wiring ABYS_AGREEMENT_ID -> AGR.LREF via ABYS_ID
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_CLOSE',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @AgrAbysColumn = N'ABYS_ID',
        @AgrLrefColumn = N'LREF',
        @Debug         = @Debug;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_DEV_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- AGR.LREF = IDENTITY; wiring ABYS_AGREEMENT_ID -> AGR.LREF via ABYS_ID
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_DEV_TR',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @AgrAbysColumn = N'ABYS_ID',
        @AgrLrefColumn = N'LREF',
        @Debug         = @Debug;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_SERVEQ_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- AGR.LREF = IDENTITY; wiring ABYS_AGREEMENT_ID -> AGR.LREF via ABYS_ID
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_SERVEQ_TR',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @AgrAbysColumn = N'ABYS_ID',
        @AgrLrefColumn = N'LREF',
        @Debug         = @Debug;
END
GO

