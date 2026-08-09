/* ============================================================
   SCRIPT_ID : AGR_CLOSE_WIRE
   SCRIPT_NO : 322
   FILE      : 322_AGR_CLOSE__wire.sql
   VERSION   : 2
   ============================================================
   REV 2026-08-08: Wire KALDIRILDI.
   AGRID artık energy.LS_005_01_AGR.LREF'e map edilmez.
   AGRID = ABYS_AGREEMENT_ID (Oracle/ABYS kaynak hali) kalır.

   Bu script SP'leri NO-OP / ABYS passthrough yapar:
     UPDATE ... SET AGRID = ABYS_AGREEMENT_ID
   Eski LREF-wire çağrıları güvenle aynı isimle çalışır, zarar vermez.
   ============================================================ */
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
        @Updated   INT;

    SET @FullTable = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

    IF OBJECT_ID(N'energy.' + @FullTable, 'U') IS NULL
    BEGIN
        RAISERROR('Hedef tablo bulunamadi: energy.%s', 16, 1, @FullTable);
        RETURN 1;
    END

    /* Wire yok: AGRID ← ABYS_AGREEMENT_ID (kaynak hali) */
    SET @Sql = N'
UPDATE t
SET t.' + QUOTENAME(@FkColumn) + N' = t.' + QUOTENAME(@AbysColumn) + N'
FROM energy.' + @FullTable + N' t
WHERE t.' + QUOTENAME(@AbysColumn) + N' IS NOT NULL
  AND (t.' + QUOTENAME(@FkColumn) + N' IS NULL
       OR t.' + QUOTENAME(@FkColumn) + N' <> t.' + QUOTENAME(@AbysColumn) + N');';

    EXEC sp_executesql @Sql;
    SET @Updated = @@ROWCOUNT;

    IF @Debug = 1
        RAISERROR('ABYS-passthrough %s.%s <- %s: %d satir (LREF wire YOK)', 0, 1,
            @TargetTable, @FkColumn, @AbysColumn, @Updated) WITH NOWAIT;

    SELECT
        @TargetTable   AS TARGET_TABLE,
        @AbysColumn    AS ABYS_COLUMN,
        @FkColumn       AS FK_COLUMN,
        N'ABYS_PASSTHROUGH' AS MODE,
        @Updated        AS UPDATED_ROWS;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_CLOSE_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_CLOSE',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @Debug         = @Debug;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_DEV_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_DEV_TR',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @Debug         = @Debug;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_SERVEQ_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_SERVEQ_TR',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @Debug         = @Debug;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_WIRE_AGR_FITMENTFEE_AGRID
    @AgrTable SYSNAME = N'LS_005_01_AGR',
    @Debug    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.SP_MIG_AGR_WIRE_AGRID
        @TargetTable   = N'LS_005_01_AGR_FITMENTFEE_TR',
        @AbysColumn    = N'ABYS_AGREEMENT_ID',
        @FkColumn      = N'AGRID',
        @AgrTable      = @AgrTable,
        @Debug         = @Debug;
END
GO

PRINT '322_AGR_CLOSE__wire: ABYS passthrough (LREF wire disabled).';
GO
