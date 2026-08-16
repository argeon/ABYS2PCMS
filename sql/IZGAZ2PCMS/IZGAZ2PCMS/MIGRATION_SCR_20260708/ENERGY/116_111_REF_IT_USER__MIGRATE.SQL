/* ============================================================
   SCRIPT_ID : REF_IT_USER_MIGRATE
   SCRIPT_NO : 111
   FILE      : 111_REF_IT_USER__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_IT_USER
-- Kaynak: izgazMGR.dbo.IT_USER → Hedef: energy.dbo.LS_USER
-- Sadece INSERT fazı (LS_USER). Ortak MIG_* log şemasını kullanır.
-- ============================================================
USE energy;
GO
 


  --EXEC energy.dbo.SP_MIGRATE_IT_USER
  --     @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;



CREATE OR ALTER PROCEDURE SP_MIGRATE_IT_USER
    @BATCH_SIZE  INT         = 5000,
    @RESUME      BIT         = 1,
    @HARD_RESET  BIT         = 0,
    @MAX_ERROR   INT         = 200,
    @DEBUG       BIT         = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode VARCHAR(50)      = 'IT_USER',
        @RunID         UNIQUEIDENTIFIER,
        @TableRunID    BIGINT,
        @LastBridgeKey BIGINT          = 0,
        @MaxBridgeKey  BIGINT,
        @SourceCount   BIGINT,
        @TargetCount   BIGINT,
        @BatchNo       INT             = 0,
        @InsertedCount BIGINT          = 0,
        @SkippedCount  BIGINT          = 0,
        @ErrorCount    BIGINT          = 0,
        @BatchFrom     BIGINT,
        @BatchTo       BIGINT,
        @RowCount      INT,
        @SkippedBatch  INT,
        @SingleID      INT,
        @ErrMsg        NVARCHAR(4000),
        @Msg           NVARCHAR(500),
        @BatchStart    DATETIME2(3),
        @ElapsedMs     INT,
        @ExecMode      VARCHAR(20),
        @RunStatus     VARCHAR(25),
        @PhaseStatus    VARCHAR(20),
        @Stopped        BIT             = 0,
        @LogBridgeFrom  BIGINT,
        @SingleErrMsg   NVARCHAR(4000),
        @FinishErrorMsg NVARCHAR(4000),
        @ReseedTo       BIGINT;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        IF @DEBUG = 1 RAISERROR('*** HARD RESET: LS_USER temizleniyor ***', 0, 1) WITH NOWAIT;

        DELETE FROM energy.dbo.LS_USER WHERE ABYS_ID IS NOT NULL;
        -- IDENTITY seed: native band (1..10000) korunur; sonraki auto-id icin guvenli taban
        SET @ReseedTo =
            ISNULL((SELECT MAX(USERID) FROM energy.dbo.LS_USER), 10000);
        DBCC CHECKIDENT('energy.dbo.LS_USER', RESEED, @ReseedTo) WITH NO_INFOMSGS;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM izgazMGR.dbo.IT_USER;
    SELECT @MaxBridgeKey = MAX(ID)       FROM izgazMGR.dbo.IT_USER;

    -- Cakisma: native USERID (ABYS_ID IS NULL) migrasyon bandina girmemeli
    IF EXISTS (
        SELECT 1
        FROM energy.dbo.LS_USER
        WHERE ABYS_ID IS NULL
          AND USERID > 10000
          AND USERID <= ISNULL(@MaxBridgeKey, 0) + 10000
    )
    BEGIN
        RAISERROR('IT_USER offset cakismasi: native LS_USER.USERID 10000+ bantinda. USERID=ABYS_ID+10000 guvensiz.', 16, 1);
        RETURN;
    END

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'IT_USER',
        @TargetTable    = 'LS_USER',
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
            + ' | Kaynak=' + CAST(@SourceCount AS VARCHAR(20))
            + ' | BridgeKey=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    -- Tip haritası (statik)
    IF OBJECT_ID('tempdb..#RTypeMap') IS NOT NULL DROP TABLE #RTypeMap;
    CREATE TABLE #RTypeMap (
        REGISTER_TYPE_ID INT         NOT NULL PRIMARY KEY,
        REG_TYPE         VARCHAR(6)  NOT NULL
    );
    INSERT INTO #RTypeMap (REGISTER_TYPE_ID, REG_TYPE) VALUES
        (1,'Kisi'),(13,'Kisi'),(14,'Kisi'),(15,'Kisi'),(72,'Kisi'),
        (2,'Firma'),(3,'Firma'),(4,'Firma'),(5,'Firma'),(6,'Firma'),
        (7,'Firma'),(8,'Firma'),(9,'Firma'),(10,'Firma'),(11,'Firma'),
        (12,'Firma'),(32,'Firma'),(33,'Firma'),(53,'Firma'),(92,'Firma'),
        (93,'Firma'),(94,'Firma');

    -- Register primary type (bir kez)
    IF OBJECT_ID('tempdb..#RegPrimaryType') IS NOT NULL DROP TABLE #RegPrimaryType;
    SELECT
        REGISTER_ID,
        MIN(REGISTER_TYPE_ID) AS PRIMARY_TYPE_ID
    INTO #RegPrimaryType
    FROM izgazMGR.dbo.CS_REGISTER_REGISTER_TYPE
    GROUP BY REGISTER_ID;

    CREATE CLUSTERED INDEX CX_RegPrimaryType ON #RegPrimaryType (REGISTER_ID);

    -- ----------------------------------------------------------
    -- Batch döngüsü
    -- ----------------------------------------------------------
    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = NULL;
        SET @BatchTo    = NULL;
        SET @RowCount   = 0;
        SET @SkippedBatch = 0;

        BEGIN TRY
            BEGIN TRANSACTION;

            DECLARE @InsertedIds TABLE (ABYS_ID INT NOT NULL PRIMARY KEY);

            SET IDENTITY_INSERT energy.dbo.LS_USER ON;

            INSERT INTO energy.dbo.LS_USER (
                USERID, ABYS_ID, USERCODE, USERPASS,
                USERNAME, USERSNAME, USEREMAIL,
                ISACTIVE, ACCOUNT_LOCKED, FAILED_LOGIN_ATTEMPTS,
                LASTPASSWORDCHANGEDATE, LAST_LOGIN_DATE, LAST_ACTIVITY_DATE,
                R_CREATOR, R_CREDATE,
                R_MODIFIER, R_MODATE,
                USERCOMPANY, ALIAS,
                REGISTER_ID, REGISTER_TABLE, USER_TYPE, WORK_PLACE_ID
            )
            OUTPUT inserted.ABYS_ID INTO @InsertedIds (ABYS_ID)
            SELECT TOP (@BATCH_SIZE)
                u.ID + 10000,
                u.ID,
                LEFT(u.USER_NAME, 20),
                LEFT(u.PASSWORD, 100),
                LEFT(ISNULL(r.FIRST_NAME, ''), 20),
                LEFT(ISNULL(r.LAST_NAME, ''), 20),
                LEFT(u.EMAIL, 100),
                u.IS_ACTIVE,
                u.IS_LOCK,
                ISNULL(u.PASSWORD_TRY_NUMBER, 0),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.PASSWORD_CHANGE_DATE AS DATETIME2)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.LAST_ENTRY_DATE AS DATETIME2)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.LAST_ENTRY_DATE AS DATETIME2)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(u.CREATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.CREATED_TIMESTAMP AS DATETIME2)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(u.UPDATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.UPDATED_TIMESTAMP AS DATETIME2)),
                u.DEFAULT_CORPORATION_ID,
                LEFT(u.SSO_USER_NAME, 100),
                u.REGISTER_ID,
                CASE
                    WHEN tm.REG_TYPE = 'Kisi'  THEN 'SUBSCR'
                    WHEN tm.REG_TYPE = 'Firma' THEN 'FIRM'
                    ELSE NULL
                END,
                CASE
                    WHEN tm.REG_TYPE = 'Kisi'  THEN 1
                    WHEN tm.REG_TYPE = 'Firma' THEN 2
                    ELSE NULL
                END,
                u.WORK_PLACE_ID
            FROM izgazMGR.dbo.IT_USER u
            LEFT JOIN izgazMGR.dbo.CS_REGISTER r
                ON r.ID = u.REGISTER_ID
            LEFT JOIN #RegPrimaryType pt
                ON pt.REGISTER_ID = u.REGISTER_ID
            LEFT JOIN #RTypeMap tm
                ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
            WHERE u.ID > @LastBridgeKey
              AND NOT EXISTS (
                  SELECT 1
                  FROM energy.dbo.LS_USER t
                  WHERE t.ABYS_ID = u.ID
              )
            ORDER BY u.ID;

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_USER OFF;

            SELECT
                @BatchFrom = MIN(ABYS_ID),
                @BatchTo   = MAX(ABYS_ID)
            FROM @InsertedIds;

            COMMIT TRANSACTION;

            -- Hiç insert yoksa: atlanan kayıtları geç, sonsuz döngüyü önle
            IF @RowCount = 0
            BEGIN
                SELECT @BatchTo = MAX(ID)
                FROM (
                    SELECT TOP (@BATCH_SIZE) u.ID
                    FROM izgazMGR.dbo.IT_USER u
                    WHERE u.ID > @LastBridgeKey
                      AND NOT EXISTS (
                          SELECT 1 FROM energy.dbo.LS_USER t WHERE t.ABYS_ID = u.ID
                      )
                    ORDER BY u.ID
                ) s;

                IF @BatchTo IS NULL
                BEGIN
                    SELECT @BatchTo = MAX(ID)
                    FROM (
                        SELECT TOP (@BATCH_SIZE) ID
                        FROM izgazMGR.dbo.IT_USER
                        WHERE ID > @LastBridgeKey
                        ORDER BY ID ASC
                    ) z;

                    IF @BatchTo IS NOT NULL
                    BEGIN
                        SET @SkippedBatch  = @BATCH_SIZE;
                        SET @LogBridgeFrom = @BatchTo - @BATCH_SIZE + 1;
                        SET @LastBridgeKey = @BatchTo;
                        SET @ElapsedMs     = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                            @BatchNo = @BatchNo, @BridgeFrom = @LogBridgeFrom,
                            @BridgeTo = @BatchTo, @RowCount = 0,
                            @SkippedCount = @SkippedBatch,
                            @ElapsedMs = @ElapsedMs;
                    END
                    ELSE
                        BREAK;
                END
                ELSE
                BEGIN
                    SET @LastBridgeKey = @BatchTo;
                END
            END
            ELSE
            BEGIN
                SET @LastBridgeKey = @BatchTo;
                SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

                EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                    @RunID = @RunID, @TableRunID = @TableRunID,
                    @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                    @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                    @RowCount = @RowCount, @SkippedCount = 0, @ElapsedMs = @ElapsedMs;

                SET @InsertedCount += @RowCount;

                IF @DEBUG = 1
                BEGIN
                    SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR) + ' OK '
                        + CAST(@RowCount AS VARCHAR) + ' satir [' + CAST(@BatchFrom AS VARCHAR)
                        + '-' + CAST(@BatchTo AS VARCHAR) + ']';
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END
            END

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_USER OFF;

            SET @ErrMsg = ERROR_MESSAGE();
            SET @LogBridgeFrom = @LastBridgeKey + 1;

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @LogBridgeFrom,
                @BridgeTo = NULL, @ErrorMsg = @ErrMsg;

            SET @ErrorCount += 1;

            IF @DEBUG = 1
                RAISERROR('Batch HATA: %s', 0, 1, @ErrMsg) WITH NOWAIT;

            -- Satır satır fallback
            SELECT @BatchTo = MAX(ID)
            FROM (
                SELECT TOP (@BATCH_SIZE) u.ID
                FROM izgazMGR.dbo.IT_USER u
                WHERE u.ID > @LastBridgeKey
                  AND NOT EXISTS (
                      SELECT 1 FROM energy.dbo.LS_USER t WHERE t.ABYS_ID = u.ID
                  )
                ORDER BY u.ID
            ) fb;

            IF @BatchTo IS NULL BREAK;

            SET @SingleID = (
                SELECT MIN(u.ID)
                FROM izgazMGR.dbo.IT_USER u
                WHERE u.ID > @LastBridgeKey
                  AND u.ID <= @BatchTo
                  AND NOT EXISTS (
                      SELECT 1 FROM energy.dbo.LS_USER t WHERE t.ABYS_ID = u.ID
                  )
            );

            WHILE @SingleID IS NOT NULL AND @SingleID <= @BatchTo AND @Stopped = 0
            BEGIN
                BEGIN TRY
                    BEGIN TRANSACTION;

                    SET IDENTITY_INSERT energy.dbo.LS_USER ON;

                    INSERT INTO energy.dbo.LS_USER (
                        USERID, ABYS_ID, USERCODE, USERPASS,
                        USERNAME, USERSNAME, USEREMAIL,
                        ISACTIVE, ACCOUNT_LOCKED, FAILED_LOGIN_ATTEMPTS,
                        LASTPASSWORDCHANGEDATE, LAST_LOGIN_DATE, LAST_ACTIVITY_DATE,
                        R_CREATOR, R_CREDATE,
                        R_MODIFIER, R_MODATE,
                        USERCOMPANY, ALIAS,
                        REGISTER_ID, REGISTER_TABLE, USER_TYPE, WORK_PLACE_ID
                    )
                    SELECT
                        u.ID + 10000,
                        u.ID,
                        LEFT(u.USER_NAME, 20),
                        LEFT(u.PASSWORD, 100),
                        LEFT(ISNULL(r.FIRST_NAME, ''), 20),
                        LEFT(ISNULL(r.LAST_NAME, ''), 20),
                        LEFT(u.EMAIL, 100),
                        u.IS_ACTIVE,
                        u.IS_LOCK,
                        ISNULL(u.PASSWORD_TRY_NUMBER, 0),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.PASSWORD_CHANGE_DATE AS DATETIME2)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.LAST_ENTRY_DATE AS DATETIME2)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.LAST_ENTRY_DATE AS DATETIME2)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(u.CREATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.CREATED_TIMESTAMP AS DATETIME2)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(u.UPDATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(u.UPDATED_TIMESTAMP AS DATETIME2)),
                        u.DEFAULT_CORPORATION_ID,
                        LEFT(u.SSO_USER_NAME, 100),
                        u.REGISTER_ID,
                        CASE WHEN tm.REG_TYPE = 'Kisi'  THEN 'SUBSCR'
                             WHEN tm.REG_TYPE = 'Firma' THEN 'FIRM'
                             ELSE NULL END,
                        CASE WHEN tm.REG_TYPE = 'Kisi'  THEN 1
                             WHEN tm.REG_TYPE = 'Firma' THEN 2
                             ELSE NULL END,
                        u.WORK_PLACE_ID
                    FROM izgazMGR.dbo.IT_USER u
                    LEFT JOIN izgazMGR.dbo.CS_REGISTER r ON r.ID = u.REGISTER_ID
                    LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = u.REGISTER_ID
                    LEFT JOIN #RTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
                    WHERE u.ID = @SingleID;

                    SET IDENTITY_INSERT energy.dbo.LS_USER OFF;

                    COMMIT TRANSACTION;

                    SET @InsertedCount += 1;
                    SET @LastBridgeKey  = @SingleID;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                        @BatchNo = @BatchNo, @BridgeFrom = @SingleID, @BridgeTo = @SingleID,
                        @RowCount = 1, @ElapsedMs = NULL;

                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET IDENTITY_INSERT energy.dbo.LS_USER OFF;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @ErrorCount += 1;
                    SET @SingleErrMsg = LEFT(
                        N'ABYS_ID=' + CAST(@SingleID AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                        @BatchNo = @BatchNo, @BridgeFrom = @SingleID, @BridgeTo = @SingleID,
                        @SourceID = @SingleID, @IsSingleRow = 1,
                        @ErrorMsg = @SingleErrMsg;

                    IF @ErrorCount >= @MAX_ERROR
                    BEGIN
                        SET @Stopped = 1;
                        RAISERROR('Max hata limiti (%d) asildi. Durduruldu.', 16, 1, @MAX_ERROR);
                    END
                END CATCH

                SET @SingleID = (
                    SELECT MIN(u.ID)
                    FROM izgazMGR.dbo.IT_USER u
                    WHERE u.ID > @LastBridgeKey
                      AND u.ID <= @BatchTo
                      AND NOT EXISTS (
                          SELECT 1 FROM energy.dbo.LS_USER t WHERE t.ABYS_ID = u.ID
                      )
                );
            END -- single loop

            IF @Stopped = 0 AND @LastBridgeKey < @BatchTo
                SET @LastBridgeKey = @BatchTo;

        END CATCH -- batch

        SELECT
            @InsertedCount = tr.INSERTED_COUNT,
            @SkippedCount  = tr.SKIPPED_COUNT,
            @ErrorCount    = tr.ERROR_COUNT
        FROM energy.dbo.MIG_TABLE_RUN tr
        WHERE tr.TABLE_RUN_ID = @TableRunID;

    END -- WHILE

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_USER
    WHERE ABYS_ID IS NOT NULL;

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
        WHEN @Stopped = 1
        THEN N'Max hata limitine ulasildi. RESUME ile devam edin.'
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




