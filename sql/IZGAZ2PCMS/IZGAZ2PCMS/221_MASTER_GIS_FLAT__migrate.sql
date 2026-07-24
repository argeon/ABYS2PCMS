/* ============================================================
   SCRIPT_ID : MASTER_GIS_FLAT_MIGRATE
   SCRIPT_NO : 221
   FILE      : 221_MASTER_GIS_FLAT__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_GIS_BUILDING_FLAT  (LS_FLAT doldurma)
-- Kaynak  : izgazMGR.dbo.LS_FLAT → VW_MIG_LS_FLAT_SOURCE
-- Hedef   : energy.dbo.LS_FLAT  (ENT_ID = 4102)
-- Köprü   : MIG_ROW_ID (FLAT_CREATED_TIMESTAMP sırası)
-- Not     : Once 220_MASTER_GIS_FLAT__setup.sql deploy edilmeli
-- HARD_RESET: LS_FLAT'a bakan FK'leri drop → delete → WITH NOCHECK recreate
-- ============================================================
USE energy;
GO

 
 


CREATE OR ALTER PROCEDURE dbo.SP_MIG_FLAT_INSERT_ONE
    @MigRowID    BIGINT,
    @ENT_ID      INT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1
        FROM energy.dbo.LS_FLAT t
        INNER JOIN energy.dbo.VW_MIG_LS_FLAT_SOURCE s
            ON s.ABYS_INSTALLATION_ID = t.ABYS_INSTALLATION_ID
        WHERE s.MIG_ROW_ID = @MigRowID
          AND t.ENT_ID = @ENT_ID
    )
        RETURN;

    INSERT INTO energy.dbo.LS_FLAT (
        ABYS_FLAT_ID, ABYS_SUBSCRIBER_TYPE_ID, ABYS_INSTALLATION_ID,
        ABYS_INSTALLATION_GSTATUS, ABYS_STARTUP_DATE,
        ABYS_INSTALLATION_STATUS_ID, ABYS_INSTALLATION_CANCEL_DATE,
        FLATNR, FLATDEFN, FLOOR_NUMBER, BNA_ID, ENT_ID,
        TYPE, ADDRESS_NUMBER, NATIONAL_CODE, BUILDING_DOOR_ID,
        CREATED_TIMESTAMP, CREATED_USER_ID, UPDATED_TIMESTAMP, UPDATED_USER_ID
    )
    SELECT
        s.ABYS_FLAT_ID,
        s.ABYS_SUBSCRIBER_TYPE_ID,
        s.ABYS_INSTALLATION_ID,
        s.ABYS_INSTALLATION_GSTATUS,
        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_STARTUP_DATE_RAW AS DATETIME2)),
        s.ABYS_INSTALLATION_STATUS_ID,
        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_INSTALLATION_CANCEL_DATE_RAW AS DATETIME2)),
        energy.dbo.FN_SAFE_FLATNR(s.FLAT_NUMBER_RAW),
        s.FLATDEFN,
        s.FLOOR_NUMBER,
        s.BNA_ID,
        @ENT_ID,
        s.TYPE,
        LEFT(CAST(s.ADDRESS_NUMBER AS NVARCHAR(50)), 50),
        s.NATIONAL_CODE,
        s.BUILDING_DOOR_ID,
        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.FLAT_CREATED_USER_ID AS INT)),
        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_UPDATED_TIMESTAMP AS DATETIME2)),
        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.FLAT_UPDATED_USER_ID AS INT))
    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
    WHERE s.MIG_ROW_ID = @MigRowID;

    SET @RowInserted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_FLAT_HARD_RESET
    @ENT_ID       INT = 4102,
    @DELETE_BATCH INT = 5000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Deleted          INT,
        @TotalDeleted     BIGINT = 0,
        @TotalDeletedStr  VARCHAR(20),
        @FkName           SYSNAME,
        @DropSql          NVARCHAR(MAX),
        @CreateSql        NVARCHAR(MAX),
        @FkCount          INT = 0,
        @FkMsg            NVARCHAR(500);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_FLAT ENT_ID=%d ABYS tesisat kayitlari (batch=%d) ***',
            0, 1, @ENT_ID, @DELETE_BATCH) WITH NOWAIT;

    -- ------------------------------------------------------------
    -- LS_FLAT'a bakan FK'leri snapshot al, sonra drop
    -- ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#LS_FLAT_FK_SNAPSHOT') IS NOT NULL
        DROP TABLE #LS_FLAT_FK_SNAPSHOT;

    CREATE TABLE #LS_FLAT_FK_SNAPSHOT (
        FK_OBJECT_ID     INT            NOT NULL PRIMARY KEY,
        FK_NAME          SYSNAME        NOT NULL,
        PARENT_SCHEMA    SYSNAME        NOT NULL,
        PARENT_TABLE     SYSNAME        NOT NULL,
        REF_SCHEMA       SYSNAME        NOT NULL,
        REF_TABLE        SYSNAME        NOT NULL,
        PARENT_COLS      NVARCHAR(MAX)  NOT NULL,
        REF_COLS         NVARCHAR(MAX)  NOT NULL,
        DELETE_ACTION    TINYINT        NOT NULL,
        UPDATE_ACTION    TINYINT        NOT NULL,
        IS_DISABLED      BIT            NOT NULL,
        IS_NOT_TRUSTED   BIT            NOT NULL
    );

    INSERT INTO #LS_FLAT_FK_SNAPSHOT (
        FK_OBJECT_ID, FK_NAME,
        PARENT_SCHEMA, PARENT_TABLE,
        REF_SCHEMA, REF_TABLE,
        PARENT_COLS, REF_COLS,
        DELETE_ACTION, UPDATE_ACTION,
        IS_DISABLED, IS_NOT_TRUSTED
    )
    SELECT
        fk.object_id,
        fk.name,
        OBJECT_SCHEMA_NAME(fk.parent_object_id),
        OBJECT_NAME(fk.parent_object_id),
        OBJECT_SCHEMA_NAME(fk.referenced_object_id),
        OBJECT_NAME(fk.referenced_object_id),
        STUFF((
            SELECT N', ' + QUOTENAME(COL_NAME(fc.parent_object_id, fc.parent_column_id))
            FROM sys.foreign_key_columns fc
            WHERE fc.constraint_object_id = fk.object_id
            ORDER BY fc.constraint_column_id
            FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 2, N''),
        STUFF((
            SELECT N', ' + QUOTENAME(COL_NAME(fc.referenced_object_id, fc.referenced_column_id))
            FROM sys.foreign_key_columns fc
            WHERE fc.constraint_object_id = fk.object_id
            ORDER BY fc.constraint_column_id
            FOR XML PATH(N''), TYPE
        ).value(N'.', N'nvarchar(max)'), 1, 2, N''),
        fk.delete_referential_action,
        fk.update_referential_action,
        fk.is_disabled,
        fk.is_not_trusted
    FROM sys.foreign_keys fk
    WHERE fk.referenced_object_id = OBJECT_ID('dbo.LS_FLAT');

    SET @FkCount = @@ROWCOUNT;

    IF @DEBUG = 1
    BEGIN
        SET @FkMsg = N'LS_FLAT FK snapshot: ' + CAST(@FkCount AS NVARCHAR(10)) + N' constraint';
        RAISERROR('%s', 0, 1, @FkMsg) WITH NOWAIT;
    END

    DECLARE
        @ParentSchema SYSNAME,
        @ParentTable  SYSNAME;

    DECLARE fk_drop_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT FK_NAME, PARENT_SCHEMA, PARENT_TABLE
        FROM #LS_FLAT_FK_SNAPSHOT
        ORDER BY FK_NAME;

    OPEN fk_drop_cur;
    FETCH NEXT FROM fk_drop_cur INTO @FkName, @ParentSchema, @ParentTable;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @DropSql = N'ALTER TABLE '
            + QUOTENAME(@ParentSchema) + N'.' + QUOTENAME(@ParentTable)
            + N' DROP CONSTRAINT ' + QUOTENAME(@FkName) + N';';

        IF @DEBUG = 1
        BEGIN
            SET @FkMsg = N'  FK DROP: ' + @FkName;
            RAISERROR('%s', 0, 1, @FkMsg) WITH NOWAIT;
        END

        EXEC sys.sp_executesql @DropSql;

        FETCH NEXT FROM fk_drop_cur INTO @FkName, @ParentSchema, @ParentTable;
    END

    CLOSE fk_drop_cur;
    DEALLOCATE fk_drop_cur;

    -- ------------------------------------------------------------
    -- Batch delete
    -- ------------------------------------------------------------
    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_FLAT
        WHERE ENT_ID = @ENT_ID
          AND ABYS_INSTALLATION_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;
        SET @TotalDeletedStr = CAST(@TotalDeleted AS VARCHAR(20));

        RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalDeletedStr) WITH NOWAIT;
    END

    -- ------------------------------------------------------------
    -- FK recreate (snapshot)
    -- ------------------------------------------------------------
    DECLARE
        @RefSchema     SYSNAME,
        @RefTable      SYSNAME,
        @ParentCols    NVARCHAR(MAX),
        @RefCols       NVARCHAR(MAX),
        @DeleteAction  TINYINT,
        @UpdateAction  TINYINT,
        @IsDisabled    BIT,
        @IsNotTrusted  BIT,
        @DeleteClause  NVARCHAR(40),
        @UpdateClause  NVARCHAR(40),
        @CheckClause   NVARCHAR(20);

    DECLARE fk_create_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            FK_NAME, PARENT_SCHEMA, PARENT_TABLE,
            REF_SCHEMA, REF_TABLE, PARENT_COLS, REF_COLS,
            DELETE_ACTION, UPDATE_ACTION, IS_DISABLED, IS_NOT_TRUSTED
        FROM #LS_FLAT_FK_SNAPSHOT
        ORDER BY FK_NAME;

    OPEN fk_create_cur;
    FETCH NEXT FROM fk_create_cur INTO
        @FkName, @ParentSchema, @ParentTable,
        @RefSchema, @RefTable, @ParentCols, @RefCols,
        @DeleteAction, @UpdateAction, @IsDisabled, @IsNotTrusted;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM sys.foreign_keys
            WHERE name = @FkName
              AND parent_object_id = OBJECT_ID(QUOTENAME(@ParentSchema) + N'.' + QUOTENAME(@ParentTable))
        )
        BEGIN
            FETCH NEXT FROM fk_create_cur INTO
                @FkName, @ParentSchema, @ParentTable,
                @RefSchema, @RefTable, @ParentCols, @RefCols,
                @DeleteAction, @UpdateAction, @IsDisabled, @IsNotTrusted;
            CONTINUE;
        END

        SET @DeleteClause = CASE @DeleteAction
            WHEN 1 THEN N' ON DELETE CASCADE'
            WHEN 2 THEN N' ON DELETE SET NULL'
            WHEN 3 THEN N' ON DELETE SET DEFAULT'
            ELSE N''
        END;
        SET @UpdateClause = CASE @UpdateAction
            WHEN 1 THEN N' ON UPDATE CASCADE'
            WHEN 2 THEN N' ON UPDATE SET NULL'
            WHEN 3 THEN N' ON UPDATE SET DEFAULT'
            ELSE N''
        END;
        -- Child FLATID'ler hard reset sonrasi orphan kalabilir (LREF yeniden uretilir).
        -- Bu yuzden recreate her zaman WITH NOCHECK; CHECK sonra wire/cleanup ile yapilir.
        SET @CheckClause = N'WITH NOCHECK';

        SET @CreateSql = N'ALTER TABLE '
            + QUOTENAME(@ParentSchema) + N'.' + QUOTENAME(@ParentTable)
            + N' ' + @CheckClause
            + N' ADD CONSTRAINT ' + QUOTENAME(@FkName)
            + N' FOREIGN KEY (' + @ParentCols + N')'
            + N' REFERENCES ' + QUOTENAME(@RefSchema) + N'.' + QUOTENAME(@RefTable)
            + N' (' + @RefCols + N')'
            + @DeleteClause + @UpdateClause + N';';

        IF @DEBUG = 1
        BEGIN
            SET @FkMsg = N'  FK CREATE (NOCHECK): ' + @FkName;
            RAISERROR('%s', 0, 1, @FkMsg) WITH NOWAIT;
        END

        BEGIN TRY
            EXEC sys.sp_executesql @CreateSql;

            IF @IsDisabled = 1
            BEGIN
                SET @CreateSql = N'ALTER TABLE '
                    + QUOTENAME(@ParentSchema) + N'.' + QUOTENAME(@ParentTable)
                    + N' NOCHECK CONSTRAINT ' + QUOTENAME(@FkName) + N';';
                EXEC sys.sp_executesql @CreateSql;
            END
        END TRY
        BEGIN CATCH
            SET @FkMsg = N'  FK CREATE HATA (' + @FkName + N'): ' + ERROR_MESSAGE();
            RAISERROR('%s', 0, 1, @FkMsg) WITH NOWAIT;
        END CATCH

        FETCH NEXT FROM fk_create_cur INTO
            @FkName, @ParentSchema, @ParentTable,
            @RefSchema, @RefTable, @ParentCols, @RefCols,
            @DeleteAction, @UpdateAction, @IsDisabled, @IsNotTrusted;
    END

    CLOSE fk_create_cur;
    DEALLOCATE fk_create_cur;

    IF OBJECT_ID('tempdb..#LS_FLAT_FK_SNAPSHOT') IS NOT NULL
        DROP TABLE #LS_FLAT_FK_SNAPSHOT;

    IF @DEBUG = 1
    BEGIN
        SET @TotalDeletedStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s | FK snapshot: %d',
            0, 1, @TotalDeletedStr, @FkCount) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_GIS_BUILDING_FLAT
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @ENT_ID      INT = 4102,
    @DEBUG       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_FLAT',
        @RunID          UNIQUEIDENTIFIER,
        @TableRunID     BIGINT,
        @LastBridgeKey  BIGINT           = 0,
        @MaxBridgeKey   BIGINT,
        @SourceCount    BIGINT,
        @TargetCount    BIGINT,
        @BatchNo        INT              = 0,
        @InsertedCount  BIGINT           = 0,
        @SkippedCount   BIGINT           = 0,
        @ErrorCount     BIGINT           = 0,
        @BatchFrom      BIGINT,
        @BatchTo        BIGINT,
        @RowCount       INT,
        @ErrMsg         NVARCHAR(4000),
        @SingleErrMsg   NVARCHAR(4000),
        @Msg            NVARCHAR(500),
        @BatchStart     DATETIME2(3),
        @ElapsedMs      INT,
        @ExecMode       VARCHAR(20),
        @RunStatus      VARCHAR(25),
        @PhaseStatus    VARCHAR(20),
        @Stopped        BIT              = 0,
        @FinishErrorMsg NVARCHAR(4000),
        @BisectFrom     BIGINT,
        @BisectTo       BIGINT,
        @BisectMid      BIGINT,
        @BisectSize     INT,
        @BisectRows     INT,
        @BisectLogFrom  BIGINT,
        @RowInserted    BIT;

    EXEC dbo.SP_MIG_FLAT_VALIDATE_SOURCE @RaiseOnMissing = 1;
    EXEC dbo.SP_MIG_FLAT_PREP_SOURCE;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';

        EXEC dbo.SP_MIG_FLAT_HARD_RESET
            @ENT_ID = @ENT_ID, @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*)
    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE;

    SELECT @MaxBridgeKey = MAX(s.MIG_ROW_ID)
    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_FLAT',
        @TargetTable    = 'LS_FLAT',
        @RunPhase       = 'INSERT',
        @ExecMode       = @ExecMode,
        @BatchSize      = @BATCH_SIZE,
        @Phase          = 'INSERT',
        @SourceRowCount = @SourceCount,
        @MaxBridgeKey   = @MaxBridgeKey,
        @Resume         = @RESUME,
        @RunID          = @RunID          OUTPUT,
        @TableRunID     = @TableRunID     OUTPUT,
        @LastBridgeKey  = @LastBridgeKey  OUTPUT,
        @BatchNo        = @BatchNo        OUTPUT,
        @InsertedCount  = @InsertedCount  OUTPUT,
        @SkippedCount   = @SkippedCount   OUTPUT,
        @ErrorCount     = @ErrorCount     OUTPUT;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | ENT_ID=' + CAST(@ENT_ID AS VARCHAR(10))
            + ' | Kaynak=' + CAST(@SourceCount AS VARCHAR(20))
            + ' | MIG_ROW_ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(MIG_ROW_ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.MIG_ROW_ID
            FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
            WHERE s.MIG_ROW_ID > @LastBridgeKey
            ORDER BY s.MIG_ROW_ID ASC
        ) t;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | MIG_ROW_ID ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            INSERT INTO energy.dbo.LS_FLAT (
                ABYS_FLAT_ID, ABYS_SUBSCRIBER_TYPE_ID, ABYS_INSTALLATION_ID,
                ABYS_INSTALLATION_GSTATUS, ABYS_STARTUP_DATE,
                ABYS_INSTALLATION_STATUS_ID, ABYS_INSTALLATION_CANCEL_DATE,
                FLATNR, FLATDEFN, FLOOR_NUMBER, BNA_ID, ENT_ID,
                TYPE, ADDRESS_NUMBER, NATIONAL_CODE, BUILDING_DOOR_ID,
                CREATED_TIMESTAMP, CREATED_USER_ID, UPDATED_TIMESTAMP, UPDATED_USER_ID
            )
            SELECT
                s.ABYS_FLAT_ID,
                s.ABYS_SUBSCRIBER_TYPE_ID,
                s.ABYS_INSTALLATION_ID,
                s.ABYS_INSTALLATION_GSTATUS,
                energy.dbo.FN_SAFE_DT(CAST(s.ABYS_STARTUP_DATE_RAW AS DATETIME2)),
                s.ABYS_INSTALLATION_STATUS_ID,
                energy.dbo.FN_SAFE_DT(CAST(s.ABYS_INSTALLATION_CANCEL_DATE_RAW AS DATETIME2)),
                energy.dbo.FN_SAFE_FLATNR(s.FLAT_NUMBER_RAW),
                s.FLATDEFN,
                s.FLOOR_NUMBER,
                s.BNA_ID,
                @ENT_ID,
                s.TYPE,
                LEFT(CAST(s.ADDRESS_NUMBER AS NVARCHAR(50)), 50),
                s.NATIONAL_CODE,
                s.BUILDING_DOOR_ID,
                energy.dbo.FN_SAFE_DT(CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.FLAT_CREATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_DT(CAST(s.FLAT_UPDATED_TIMESTAMP AS DATETIME2)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.FLAT_UPDATED_USER_ID AS INT))
            FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
            WHERE s.MIG_ROW_ID BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_FLAT t
                  WHERE t.ABYS_INSTALLATION_ID = s.ABYS_INSTALLATION_ID
                    AND t.ENT_ID = @ENT_ID
              );

            SET @RowCount = @@ROWCOUNT;
            COMMIT TRANSACTION;

            SET @LastBridgeKey = @BatchTo;
            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('Batch %d HATA → bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_FLAT_INSERT_ONE
                            @MigRowID = @BisectFrom, @ENT_ID = @ENT_ID,
                            @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(
                            N'MIG_ROW_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                            @BridgeTo = @BisectFrom, @SourceID = @BisectFrom,
                            @IsSingleRow = 1, @ErrorMsg = @SingleErrMsg;

                        SELECT @ErrorCount = tr.ERROR_COUNT
                        FROM energy.dbo.MIG_TABLE_RUN tr
                        WHERE tr.TABLE_RUN_ID = @TableRunID;

                        IF @ErrorCount >= @MAX_ERROR
                        BEGIN
                            SET @Stopped = 1;
                            RAISERROR('Max hata limiti (%d) asildi. Durduruldu.', 16, 1, @MAX_ERROR);
                        END
                    END CATCH

                    SET @BisectFrom += 1;
                    CONTINUE;
                END

                SET @BisectMid = @BisectFrom + (@BisectSize / 2) - 1;

                BEGIN TRY
                    BEGIN TRANSACTION;

                    INSERT INTO energy.dbo.LS_FLAT (
                        ABYS_FLAT_ID, ABYS_SUBSCRIBER_TYPE_ID, ABYS_INSTALLATION_ID,
                        ABYS_INSTALLATION_GSTATUS, ABYS_STARTUP_DATE,
                        ABYS_INSTALLATION_STATUS_ID, ABYS_INSTALLATION_CANCEL_DATE,
                        FLATNR, FLATDEFN, FLOOR_NUMBER, BNA_ID, ENT_ID,
                        TYPE, ADDRESS_NUMBER, NATIONAL_CODE, BUILDING_DOOR_ID,
                        CREATED_TIMESTAMP, CREATED_USER_ID, UPDATED_TIMESTAMP, UPDATED_USER_ID
                    )
                    SELECT
                        s.ABYS_FLAT_ID,
                        s.ABYS_SUBSCRIBER_TYPE_ID,
                        s.ABYS_INSTALLATION_ID,
                        s.ABYS_INSTALLATION_GSTATUS,
                        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_STARTUP_DATE_RAW AS DATETIME2)),
                        s.ABYS_INSTALLATION_STATUS_ID,
                        energy.dbo.FN_SAFE_DT(CAST(s.ABYS_INSTALLATION_CANCEL_DATE_RAW AS DATETIME2)),
                        energy.dbo.FN_SAFE_FLATNR(s.FLAT_NUMBER_RAW),
                        s.FLATDEFN,
                        s.FLOOR_NUMBER,
                        s.BNA_ID,
                        @ENT_ID,
                        s.TYPE,
                        LEFT(CAST(s.ADDRESS_NUMBER AS NVARCHAR(50)), 50),
                        s.NATIONAL_CODE,
                        s.BUILDING_DOOR_ID,
                        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_CREATED_TIMESTAMP AS DATETIME2)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.FLAT_CREATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_DT(CAST(s.FLAT_UPDATED_TIMESTAMP AS DATETIME2)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.FLAT_UPDATED_USER_ID AS INT))
                    FROM energy.dbo.VW_MIG_LS_FLAT_SOURCE s
                    WHERE s.MIG_ROW_ID BETWEEN @BisectFrom AND @BisectMid
                      AND NOT EXISTS (
                          SELECT 1
                          FROM energy.dbo.LS_FLAT t
                          WHERE t.ABYS_INSTALLATION_ID = s.ABYS_INSTALLATION_ID
                            AND t.ENT_ID = @ENT_ID
                      );

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    COMMIT TRANSACTION;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                        @BatchNo = @BatchNo, @BridgeFrom = @BisectLogFrom,
                        @BridgeTo = @BisectMid, @RowCount = @BisectRows;

                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @BisectTo = @BisectMid;
                END CATCH
            END

            IF @Stopped = 0
                SET @LastBridgeKey = @BatchTo;
        END CATCH

        SELECT
            @InsertedCount = tr.INSERTED_COUNT,
            @SkippedCount  = tr.SKIPPED_COUNT,
            @ErrorCount    = tr.ERROR_COUNT
        FROM energy.dbo.MIG_TABLE_RUN tr
        WHERE tr.TABLE_RUN_ID = @TableRunID;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = '  → OK=' + CAST(@InsertedCount AS VARCHAR(20))
                + ' ERR=' + CAST(@ErrorCount AS VARCHAR(20))
                + ' LastMigRow=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_FLAT
    WHERE ENT_ID = @ENT_ID AND ABYS_INSTALLATION_ID IS NOT NULL;

    IF @Stopped = 1
    BEGIN
        SET @RunStatus   = 'STOPPED';
        SET @PhaseStatus = 'PAUSED';
    END
    ELSE IF @ErrorCount > 0
    BEGIN
        SET @RunStatus   = 'COMPLETED_WITH_ERRORS';
        SET @PhaseStatus = 'COMPLETED';
    END
    ELSE
    BEGIN
        SET @RunStatus   = 'COMPLETED';
        SET @PhaseStatus = 'COMPLETED';
    END

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE
        @TableRunID = @TableRunID, @Status = @PhaseStatus;

    SET @FinishErrorMsg = CASE
        WHEN @Stopped = 1 THEN N'Max hata limitine ulasildi. RESUME ile devam edin.'
        ELSE NULL
    END;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID, @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = @FinishErrorMsg;

    EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY
        @MigrationCode = @MigrationCode, @RunID = @RunID;
END
GO




--EXEC dbo.SP_MIGRATE_GIS_BUILDING_FLAT
--     @HARD_RESET = 1,
--     @ENT_ID = 4102,
--     @BATCH_SIZE = 5000,
--     @DEBUG = 1;


--select COUNT(1)  from izgazMgr.dbo.LS_FLAT