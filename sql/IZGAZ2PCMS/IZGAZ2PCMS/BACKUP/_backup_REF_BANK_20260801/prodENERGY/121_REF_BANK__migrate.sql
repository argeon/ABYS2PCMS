/* ============================================================
   SCRIPT_ID : REF_BANK_MIGRATE
   SCRIPT_NO : 121
   FILE      : 121_REF_BANK__migrate.sql
   VERSION   : 1
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================
-- SP_MIGRATE_LS_BANK
-- Faz 1: MAP  — mevcut LS_BANK satirlarina ABYS_ID yaz (UPDATE)
-- Faz 2: INSERT — yeni ABYS banka/hesap kayitlari
--
-- Orphan FK kontrolu proje sonunda (35_ls_bank_check_queries.sql)
-- ============================================================
USE energy;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_LS_BANK_HARD_RESET
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_BANK ABYS koprusu ***', 0, 1) WITH NOWAIT;

    DECLARE @DelStr VARCHAR(20);

    -- INSERT ile eklenen satirlari sil (sadece map listesindeki ABYS_ID)
    DELETE b
    FROM energy.dbo.LS_BANK b
    INNER JOIN energy.dbo.MIG_LS_BANK_MAP m
        ON m.ABYS_BANK_ID = b.ABYS_ID
       AND m.ACTION_TYPE = 'INSERT';

    IF @DEBUG = 1
    BEGIN
        SET @DelStr = CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('  silindi INSERT LS_BANK: %s', 0, 1, @DelStr) WITH NOWAIT;
    END

    -- MAP satirlarinda sadece kopru temizle (LREF korunur)
    UPDATE b
    SET b.ABYS_ID = NULL,
        b.ABYS_CODE = NULL
    FROM energy.dbo.LS_BANK b
    INNER JOIN energy.dbo.MIG_LS_BANK_MAP m
        ON m.ABYS_BANK_ID = b.ABYS_ID
       AND m.ACTION_TYPE = 'MAP';

    IF @DEBUG = 1
    BEGIN
        SET @DelStr = CAST(@@ROWCOUNT AS VARCHAR(20));
        RAISERROR('  temizlendi MAP ABYS_ID: %s', 0, 1, @DelStr) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS_BANK
    @HARD_RESET BIT = 0,
    @DEBUG      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_BANK',
        @RunID          UNIQUEIDENTIFIER,
        @TableRunID     BIGINT,
        @LastBridgeKey  BIGINT           = 0,
        @BatchNo        INT              = 0,
        @InsertedLog    BIGINT           = 0,
        @SkippedLog     BIGINT           = 0,
        @ErrorLog       BIGINT           = 0,
        @SourceCount    BIGINT,
        @TargetCount    BIGINT,
        @MapUpdated     INT              = 0,
        @InsertCount    INT              = 0,
        @SkippedMap     INT              = 0,
        @SkippedInsert  INT              = 0,
        @Msg            NVARCHAR(500),
        @RunStatus      VARCHAR(25)      = 'COMPLETED',
        @PhaseStatus    VARCHAR(20)      = 'COMPLETED',
        @FinishErrorMsg NVARCHAR(4000),
        @ValidResult    INT,
        @ExecMode       VARCHAR(20),
        @SkippedTotal   INT;

    IF @HARD_RESET = 1
        EXEC dbo.SP_MIG_LS_BANK_HARD_RESET @DEBUG = @DEBUG;

    EXEC @ValidResult = dbo.SP_MIG_LS_BANK_VALIDATE_MAP @RaiseOnError = 1;
    IF @ValidResult <> 0
        RETURN 1;

    SELECT @SourceCount = COUNT(*) FROM energy.dbo.MIG_LS_BANK_MAP;

    SET @ExecMode = CASE WHEN @HARD_RESET = 1 THEN 'HARD_RESET' ELSE 'FULL' END;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'energy',
        @SourceTable    = 'MIG_LS_BANK_MAP',
        @TargetTable    = 'LS_BANK',
        @RunPhase       = 'BRIDGE',
        @ExecMode       = @ExecMode,
        @BatchSize      = 0,
        @Phase          = 'BRIDGE',
        @SourceRowCount = @SourceCount,
        @MaxBridgeKey   = NULL,
        @Resume         = 0,
        @RunID          = @RunID          OUTPUT,
        @TableRunID     = @TableRunID     OUTPUT,
        @LastBridgeKey  = @LastBridgeKey  OUTPUT,
        @BatchNo        = @BatchNo        OUTPUT,
        @InsertedCount  = @InsertedLog     OUTPUT,
        @SkippedCount   = @SkippedLog      OUTPUT,
        @ErrorCount     = @ErrorLog        OUTPUT;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | Map+Insert kaynak=' + CAST(@SourceCount AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    BEGIN TRY
        -- ----------------------------------------------------------
        -- Faz 1: MAP — mevcut PCMS bankalarina ABYS koprusu
        -- ----------------------------------------------------------
        UPDATE b
        SET
            b.ABYS_ID   = m.ABYS_BANK_ID,
            b.ABYS_CODE = m.ABYS_BANK_CODE,
            b.ISACTIVE  = m.IS_ACTIVE
        FROM energy.dbo.LS_BANK b
        INNER JOIN energy.dbo.MIG_LS_BANK_MAP m
            ON m.PCMS_LREF = b.LREF
           AND m.ACTION_TYPE = 'MAP'
        WHERE b.ABYS_ID IS NULL
           OR b.ABYS_ID = m.ABYS_BANK_ID;

        SET @MapUpdated = @@ROWCOUNT;

        SELECT @SkippedMap = COUNT(*)
        FROM energy.dbo.MIG_LS_BANK_MAP m
        INNER JOIN energy.dbo.LS_BANK b ON b.LREF = m.PCMS_LREF
        WHERE m.ACTION_TYPE = 'MAP'
          AND b.ABYS_ID IS NOT NULL
          AND b.ABYS_ID <> m.ABYS_BANK_ID;

        IF @SkippedMap > 0 AND @DEBUG = 1
            RAISERROR('  MAP atlandi (farkli ABYS koprusu): %d', 0, 1, @SkippedMap) WITH NOWAIT;

        SELECT @SkippedInsert = COUNT(*)
        FROM energy.dbo.MIG_LS_BANK_MAP m
        WHERE m.ACTION_TYPE = 'INSERT'
          AND EXISTS (
              SELECT 1 FROM energy.dbo.LS_BANK t WHERE t.ABYS_ID = m.ABYS_BANK_ID
          );

        -- ----------------------------------------------------------
        -- Faz 2: INSERT — yeni banka/hesap kayitlari
        -- ----------------------------------------------------------
        INSERT INTO energy.dbo.LS_BANK
        (
            DEFN,
            ISACTIVE,
            UBANKCODE,
            ABYS_ID,
            ABYS_CODE,
            ISONLINE,
            FILETYPE
        )
        SELECT
            m.DEFN,
            m.IS_ACTIVE,
            m.ABYS_BANK_CODE,
            m.ABYS_BANK_ID,
            m.ABYS_BANK_CODE,
            CASE
                WHEN m.DEFN LIKE N'%SANAL POS%'
                  OR m.DEFN LIKE N'%ONLINE%' THEN CAST(1 AS BIT)
                ELSE CAST(0 AS BIT)
            END,
            0
        FROM energy.dbo.MIG_LS_BANK_MAP m
        WHERE m.ACTION_TYPE = 'INSERT'
          AND NOT EXISTS (
              SELECT 1
              FROM energy.dbo.LS_BANK t
              WHERE t.ABYS_ID = m.ABYS_BANK_ID
          );

        SET @InsertCount = @@ROWCOUNT;

        IF @SkippedInsert > 0 AND @DEBUG = 1
            RAISERROR('  INSERT atlandi (zaten var): %d', 0, 1, @SkippedInsert) WITH NOWAIT;

        IF @DEBUG = 1
        BEGIN
            RAISERROR('  MAP guncellendi: %d', 0, 1, @MapUpdated) WITH NOWAIT;
            RAISERROR('  INSERT eklendi: %d', 0, 1, @InsertCount) WITH NOWAIT;
        END
    END TRY
    BEGIN CATCH
        SET @RunStatus = 'FAILED';
        SET @PhaseStatus = 'FAILED';
        SET @FinishErrorMsg = ERROR_MESSAGE();

        EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE
            @TableRunID = @TableRunID, @Status = @PhaseStatus;

        EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
            @RunID = @RunID, @Status = @RunStatus,
            @TargetRowCount = NULL,
            @ErrorMsg = @FinishErrorMsg;

        THROW;
    END CATCH

    SELECT @TargetCount = COUNT(*)
    FROM energy.dbo.LS_BANK
    WHERE ABYS_ID IS NOT NULL;

    SET @SkippedTotal = @SkippedMap + @SkippedInsert;

    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
        @RunID         = @RunID,
        @TableRunID    = @TableRunID,
        @MigrationCode = @MigrationCode,
        @Phase         = 'BRIDGE',
        @BatchNo       = 1,
        @RowCount      = @InsertCount,
        @SkippedCount  = @SkippedTotal;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE
        @TableRunID = @TableRunID, @Status = @PhaseStatus;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID, @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = NULL;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'Tamamlandi | MAP=' + CAST(@MapUpdated AS VARCHAR(20))
            + ' | INSERT=' + CAST(@InsertCount AS VARCHAR(20))
            + ' | LS_BANK ABYS kopru toplam=' + CAST(@TargetCount AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

-- ------------------------------------------------------------
-- Bagimli tablolarda ABYS banka ID → LS_BANK.LREF wiring (UPDATE)
-- Orphan FK proje sonunda kontrol edilir; bu SP sadece eslestirir.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_LS_BANK_WIRE_FK
    @TargetSchema SYSNAME = N'dbo',
    @TargetTable  SYSNAME,
    @AbysColumn   SYSNAME,
    @FkColumn     SYSNAME,
    @Debug        BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Sql       NVARCHAR(MAX),
        @FullTable NVARCHAR(300),
        @Updated   INT;

    IF NOT EXISTS (
        SELECT 1 FROM energy.dbo.MIG_LS_BANK_MAP
    )
    BEGIN
        RAISERROR('MIG_LS_BANK_MAP bos. Once SP_MIGRATE_LS_BANK calistirin.', 16, 1);
        RETURN 1;
    END

    SET @FullTable = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

    IF OBJECT_ID(N'energy.' + @FullTable, 'U') IS NULL
    BEGIN
        RAISERROR('Hedef tablo bulunamadi: energy.%s', 16, 1, @FullTable);
        RETURN 1;
    END

    SET @Sql = N'
UPDATE t
SET t.' + QUOTENAME(@FkColumn) + N' = b.LREF
FROM energy.' + @FullTable + N' t
INNER JOIN energy.dbo.LS_BANK b ON b.ABYS_ID = t.' + QUOTENAME(@AbysColumn) + N'
WHERE t.' + QUOTENAME(@AbysColumn) + N' IS NOT NULL
  AND (t.' + QUOTENAME(@FkColumn) + N' IS NULL OR t.' + QUOTENAME(@FkColumn) + N' <> b.LREF);';

    EXEC sp_executesql @Sql;
    SET @Updated = @@ROWCOUNT;

    IF @Debug = 1
        RAISERROR('Wiring %s.%s -> %s: %d satir', 0, 1, @TargetTable, @FkColumn, @Updated) WITH NOWAIT;

    SELECT
        @TargetTable AS TARGET_TABLE,
        @AbysColumn  AS ABYS_COLUMN,
        @FkColumn    AS FK_COLUMN,
        @Updated     AS UPDATED_ROWS;
END
GO

