/* ============================================================
   SCRIPT_ID : MASTER_SUBSCR_MIGRATE
   SCRIPT_NO : 201
   FILE      : 201_MASTER_SUBSCR__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_CS_REGISTER
-- Kaynak  : izgazMGR.dbo.CS_REGISTER
-- Hedef   : energy.dbo.LS_005_SUBSCR (Kişi)
--           energy.dbo.LS_005_FIRM   (Firma)
-- Ortak MIG_* log + bisect batch hata daraltma
-- ============================================================
USE energy;
GO

-- ------------------------------------------------------------
-- Tek satır INSERT (bisect son adım)
-- Çağıran SP #RegPrimaryType, #RegTypeCount, #RegTypeMap temp tablolarını oluşturmuş olmalı.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_REG_INSERT_ONE
    @CurID         INT,
    @RegType       VARCHAR(6),    -- 'Kisi' veya 'Firma'
    @RowInserted   BIT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF @RegType = 'Kisi'
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM izgazMGR.dbo.CS_REGISTER r
            LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
            LEFT JOIN #RegTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
            WHERE r.ID = @CurID
              AND ISNULL(tm.REG_TYPE, 'Kisi') = 'Kisi'
        )
            RETURN;

        SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR ON;

        INSERT INTO energy.dbo.LS_005_SUBSCR (
            LREF, [TYPE], TCID, STATUS,
            FIRSTNAME, SURNAME, NAME_,
            BIRTHPLACE, BIRTHDATE,
            FATHER_NAME, MOTHER_NAME, GENDER,
            IDENTITY_ADDRESS, IDENTITY_CHANGE_DATE,
            IDENTITY_DISTRICT, IDENTITY_FAMILY_ROW_NUMBER,
            IDENTITY_ISSUE_DATE, IDENTITY_PROVINCE,
            IDENTITY_QUARTER, IDENTITY_QUARTER_ID,
            IDENTITY_REASON_FOR_ISSUE, IDENTITY_REGISTRATION_NUMBER,
            IDENTITY_ROW_NUMBER, IDENTITY_SERIAL, IDENTITY_SERIAL_NUMBER,
            IDENTITY_VOLUME_NUMBER, OTH_NO, OTH_DESC,
            CODE, DUALREG, IS_OLD, OLREF,
            EBILLING, CUSTOMER_BILL_TYPE, E_BILL_CUSTOMER_DATE,
            DEAD_DATE, DEADDATE,
            IS_COMMINICATION_PERMIT, POOL_ID,
            EXPRESS_CONSENT, MARKETING_APPROVE,
            IS_GSM, IS_PHONE, IS_MAIL, IS_ACTIVE,
            DELETED_TIMESTAMP, DELETED_USER_ID,
            ADDUSER, ADDDATE, UPDUSER, UPDDATE,
            RECORDID, IN_BLACKLIST
        )
        SELECT
            r.ID,
            0,  -- TYPE
            CAST(r.IDENTITY_NUMBER AS VARCHAR(20)),
            0,  -- STATUS
            LEFT(r.FIRST_NAME, 150), LEFT(r.LAST_NAME, 150),
  LEFT(ISNULL(r.FIRST_NAME, '') + ' ' + ISNULL(r.LAST_NAME, ''), 300),
            LEFT(r.BIRTH_PLACE, 50),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.BIRTH_DATE AS DATETIME2)),
            LEFT(r.FATHER_NAME, 100), LEFT(r.MOTHER_NAME, 100), r.GENDER,
            LEFT(r.IDENTITY_ADDRESS, 2000),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.IDENTITY_CHANGE_DATE AS DATETIME2)),
            LEFT(r.IDENTITY_DISTRICT, 50), r.IDENTITY_FAMILY_ROW_NUMBER,
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.IDENTITY_ISSUE_DATE AS DATETIME2)),
            LEFT(r.IDENTITY_PROVINCE, 50), LEFT(r.IDENTITY_QUARTER, 50),
            r.IDENTITY_QUARTER_ID, LEFT(r.IDENTITY_REASON_FOR_ISSUE, 50),
            r.IDENTITY_REGISTRATION_NUMBER, r.IDENTITY_ROW_NUMBER,
            LEFT(r.IDENTITY_SERIAL, 5), LEFT(r.IDENTITY_SERIAL_NUMBER, 15),
            r.IDENTITY_VOLUME_NUMBER,
            CAST(r.SOCIAL_SECURITY_NUMBER AS NVARCHAR(40)),
            LEFT(r.DESCRIPTION, 100), LEFT(r.CODE, 50),
            CASE WHEN cnt.TYPE_COUNT > 1 THEN 1 ELSE 0 END,
            0, r.ID, r.IS_E_BILL_CUSTOMER, r.CUSTOMER_BILL_TYPE,
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.E_BILL_CUSTOMER_DATE AS DATETIME2)),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.DEAD_DATE AS DATETIME2)),
            CAST(r.DEAD_DATE AS DATETIME2),
            r.IS_COMMINICATION_PERMIT, r.POOL_ID,
            ISNULL(r.HAS_EXPRESS_CONSENT, 0), ISNULL(r.IS_MARKETING_CONSENT_GIVEN, 0),
            ISNULL(r.IS_SMS_CONTACT_ALLOWED, 0), ISNULL(r.IS_CALL_CONTACT_ALLOWED, 0),
            ISNULL(r.IS_EMAIL_CONTACT_ALLOWED, 0),
            CASE WHEN r.DELETED_TIMESTAMP IS NOT NULL THEN 0
                 WHEN r.IS_LOST = 1 THEN 0 ELSE 1 END,
            CAST(r.DELETED_TIMESTAMP AS DATETIME2), energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.DELETED_USER_ID AS INT)),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.CREATED_USER_ID AS INT)),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.UPDATED_USER_ID AS INT)),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.UPDATED_TIMESTAMP AS DATETIME2)),
            r.ID,
            CASE WHEN ISNULL(r.IS_LOST, 0) = 1
                   OR ISNULL(r.BANKRUPTCY_RECORD, 0) = 1 THEN 1 ELSE 0 END
        FROM izgazMGR.dbo.CS_REGISTER r
        LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
        LEFT JOIN #RegTypeCount cnt ON cnt.REGISTER_ID = r.ID
        WHERE r.ID = @CurID;

        SET @RowInserted = 1;
        SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR OFF;
    END
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM izgazMGR.dbo.CS_REGISTER r
            LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
            LEFT JOIN #RegTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
            WHERE r.ID = @CurID
              AND ISNULL(tm.REG_TYPE, 'Kisi') = 'Firma'
        )
            RETURN;

        SET IDENTITY_INSERT energy.dbo.LS_005_FIRM ON;

        INSERT INTO energy.dbo.LS_005_FIRM (
            LREF, [TYPE], NAME_, STATUS,
            TAXNO, TAXOFFICE, CODE, DUALREG, OLREF,
            BANNED, IN_BLACKLIST, EBILLING, TAXNO2,
            ADDUSER, ADDDATE, UPDUSER, UPDDATE,
            RECORDID, IDENTITY_NUMBER, REGISTER_TYPE
        )
        SELECT
            r.ID, pt.PRIMARY_TYPE_ID,
            LEFT(ISNULL(r.FIRST_NAME, '') + ' ' + ISNULL(r.LAST_NAME, ''), 300),
            CASE WHEN r.DELETED_TIMESTAMP IS NOT NULL THEN 0
                 WHEN r.IS_LOST = 1 THEN 2 ELSE 1 END,
            LEFT(r.TAX_NUMBER, 15), LEFT(r.TAX_OFFICE, 20),
            LEFT(r.CODE, 50),
            CASE WHEN cnt.TYPE_COUNT > 1 THEN 1 ELSE 0 END,
            r.ID,
            ISNULL(r.BANKRUPTCY_RECORD, 0),
            CASE WHEN ISNULL(r.IS_LOST, 0) = 1
                   OR ISNULL(r.BANKRUPTCY_RECORD, 0) = 1 THEN 1 ELSE 0 END,
            r.IS_E_BILL_CUSTOMER, LEFT(r.CHAMBER_CODE, 100),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.CREATED_USER_ID AS INT)),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.UPDATED_USER_ID AS INT)),
            energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.UPDATED_TIMESTAMP AS DATETIME2)),
            r.ID, CAST(r.IDENTITY_NUMBER AS CHAR(11)),
            pt.PRIMARY_TYPE_ID
        FROM izgazMGR.dbo.CS_REGISTER r
        LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
        LEFT JOIN #RegTypeCount cnt ON cnt.REGISTER_ID = r.ID
        WHERE r.ID = @CurID;

        SET @RowInserted = 1;
        SET IDENTITY_INSERT energy.dbo.LS_005_FIRM OFF;
    END
END
GO


 
 -- ------------------------------------------------------------
-- Ana migrasyon SP
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_CS_REGISTER
    @BATCH_SIZE  INT = 5000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @DEBUG       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'CS_REGISTER',
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
        @RegType        VARCHAR(6),
        @RowInserted    BIT;

    EXEC dbo.SP_MIG_CS_REGISTER_VALIDATE_SOURCE @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        SET @ExecMode = 'HARD_RESET';
        IF @DEBUG = 1 RAISERROR('*** HARD RESET: LS_005_SUBSCR / LS_005_FIRM temizleniyor ***', 0, 1) WITH NOWAIT;

        SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR OFF;
        DELETE FROM energy.dbo.LS_005_SUBSCR;
        DBCC CHECKIDENT('energy.dbo.LS_005_SUBSCR', RESEED, 0) WITH NO_INFOMSGS;

        SET IDENTITY_INSERT energy.dbo.LS_005_FIRM OFF;
        DELETE FROM energy.dbo.LS_005_FIRM;
        DBCC CHECKIDENT('energy.dbo.LS_005_FIRM', RESEED, 0) WITH NO_INFOMSGS;

        SET @RESUME = 0;
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM izgazMGR.dbo.CS_REGISTER;
    SELECT @MaxBridgeKey = MAX(ID)       FROM izgazMGR.dbo.CS_REGISTER;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'CS_REGISTER',
        @TargetTable    = 'LS_005_SUBSCR+LS_005_FIRM',
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
            + ' | ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF OBJECT_ID('tempdb..#RegTypeMap') IS NOT NULL DROP TABLE #RegTypeMap;
    CREATE TABLE #RegTypeMap (
        REGISTER_TYPE_ID INT        NOT NULL PRIMARY KEY,
        REG_TYPE         VARCHAR(6) NOT NULL
    );
    INSERT INTO #RegTypeMap (REGISTER_TYPE_ID, REG_TYPE) VALUES
        (1,'Kisi'),(13,'Kisi'),(14,'Kisi'),(15,'Kisi'),(72,'Kisi'),
        (2,'Firma'),(3,'Firma'),(4,'Firma'),(5,'Firma'),(6,'Firma'),
        (7,'Firma'),(8,'Firma'),(9,'Firma'),(10,'Firma'),(11,'Firma'),
        (12,'Firma'),(32,'Firma'),(33,'Firma'),(53,'Firma'),(92,'Firma'),
        (93,'Firma'),(94,'Firma');

    IF OBJECT_ID('tempdb..#RegPrimaryType') IS NOT NULL DROP TABLE #RegPrimaryType;
    SELECT REGISTER_ID, MIN(REGISTER_TYPE_ID) AS PRIMARY_TYPE_ID
    INTO #RegPrimaryType
    FROM izgazMGR.dbo.CS_REGISTER_REGISTER_TYPE
    GROUP BY REGISTER_ID;
    CREATE CLUSTERED INDEX CX_RegPrimaryType ON #RegPrimaryType (REGISTER_ID);

    IF OBJECT_ID('tempdb..#RegTypeCount') IS NOT NULL DROP TABLE #RegTypeCount;
    SELECT REGISTER_ID, COUNT(*) AS TYPE_COUNT
    INTO #RegTypeCount
    FROM izgazMGR.dbo.CS_REGISTER_REGISTER_TYPE
    GROUP BY REGISTER_ID;
    CREATE CLUSTERED INDEX CX_RegTypeCount ON #RegTypeCount (REGISTER_ID);

    -- ==========================================================
    -- Ana batch döngüsü
    -- ==========================================================
    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;

        SELECT @BatchTo = MAX(ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) ID
            FROM izgazMGR.dbo.CS_REGISTER
            WHERE ID > @LastBridgeKey
            ORDER BY ID ASC
        ) t;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        -- ------------------------------------------------------
        -- SUBSCR toplu INSERT
        -- ------------------------------------------------------
        SET @RowCount = 0;
        BEGIN TRY
            BEGIN TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR ON;

            INSERT INTO energy.dbo.LS_005_SUBSCR (
                LREF, [TYPE], TCID, STATUS,
                FIRSTNAME, SURNAME, NAME_,
                BIRTHPLACE, BIRTHDATE,
                FATHER_NAME, MOTHER_NAME, GENDER,
                IDENTITY_ADDRESS, IDENTITY_CHANGE_DATE,
                IDENTITY_DISTRICT, IDENTITY_FAMILY_ROW_NUMBER,
                IDENTITY_ISSUE_DATE, IDENTITY_PROVINCE,
                IDENTITY_QUARTER, IDENTITY_QUARTER_ID,
                IDENTITY_REASON_FOR_ISSUE, IDENTITY_REGISTRATION_NUMBER,
                IDENTITY_ROW_NUMBER, IDENTITY_SERIAL, IDENTITY_SERIAL_NUMBER,
                IDENTITY_VOLUME_NUMBER, OTH_NO, OTH_DESC,
                CODE, DUALREG, IS_OLD, OLREF,
                EBILLING, CUSTOMER_BILL_TYPE, E_BILL_CUSTOMER_DATE,
                DEAD_DATE, DEADDATE,
                IS_COMMINICATION_PERMIT, POOL_ID,
                EXPRESS_CONSENT, MARKETING_APPROVE,
                IS_GSM, IS_PHONE, IS_MAIL, IS_ACTIVE,
                DELETED_TIMESTAMP, DELETED_USER_ID,
                ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                RECORDID, IN_BLACKLIST
            )
            SELECT
                r.ID, 0,  -- TYPE
                CAST(r.IDENTITY_NUMBER AS VARCHAR(20)),
                0,  -- STATUS
                LEFT(r.FIRST_NAME, 150), LEFT(r.LAST_NAME, 150),
                LEFT(ISNULL(r.FIRST_NAME, '') + ' ' + ISNULL(r.LAST_NAME, ''), 300),
                LEFT(r.BIRTH_PLACE, 50),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.BIRTH_DATE AS DATETIME2)),
                LEFT(r.FATHER_NAME, 100), LEFT(r.MOTHER_NAME, 100), r.GENDER,
                LEFT(r.IDENTITY_ADDRESS, 2000),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.IDENTITY_CHANGE_DATE AS DATETIME2)),
                LEFT(r.IDENTITY_DISTRICT, 50), r.IDENTITY_FAMILY_ROW_NUMBER,
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.IDENTITY_ISSUE_DATE AS DATETIME2)),
                LEFT(r.IDENTITY_PROVINCE, 50), LEFT(r.IDENTITY_QUARTER, 50),
                r.IDENTITY_QUARTER_ID, LEFT(r.IDENTITY_REASON_FOR_ISSUE, 50),
                r.IDENTITY_REGISTRATION_NUMBER, r.IDENTITY_ROW_NUMBER,
                LEFT(r.IDENTITY_SERIAL, 5), LEFT(r.IDENTITY_SERIAL_NUMBER, 15),
                r.IDENTITY_VOLUME_NUMBER,
                CAST(r.SOCIAL_SECURITY_NUMBER AS NVARCHAR(40)),
                LEFT(r.DESCRIPTION, 100), LEFT(r.CODE, 50),
                CASE WHEN cnt.TYPE_COUNT > 1 THEN 1 ELSE 0 END,
                0, r.ID, r.IS_E_BILL_CUSTOMER, r.CUSTOMER_BILL_TYPE,
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.E_BILL_CUSTOMER_DATE AS DATETIME2)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.DEAD_DATE AS DATETIME2)),
                CAST(r.DEAD_DATE AS DATETIME2),
                r.IS_COMMINICATION_PERMIT, r.POOL_ID,
                ISNULL(r.HAS_EXPRESS_CONSENT, 0), ISNULL(r.IS_MARKETING_CONSENT_GIVEN, 0),
                ISNULL(r.IS_SMS_CONTACT_ALLOWED, 0), ISNULL(r.IS_CALL_CONTACT_ALLOWED, 0),
                ISNULL(r.IS_EMAIL_CONTACT_ALLOWED, 0),
                CASE WHEN r.DELETED_TIMESTAMP IS NOT NULL THEN 0
                     WHEN r.IS_LOST = 1 THEN 0 ELSE 1 END,
                CAST(r.DELETED_TIMESTAMP AS DATETIME2), energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.DELETED_USER_ID AS INT)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.CREATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.UPDATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.UPDATED_TIMESTAMP AS DATETIME2)),
                r.ID,
                CASE WHEN ISNULL(r.IS_LOST, 0) = 1
                       OR ISNULL(r.BANKRUPTCY_RECORD, 0) = 1 THEN 1 ELSE 0 END
            FROM izgazMGR.dbo.CS_REGISTER r
            LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
            LEFT JOIN #RegTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
            LEFT JOIN #RegTypeCount cnt ON cnt.REGISTER_ID = r.ID
            WHERE r.ID BETWEEN @BatchFrom AND @BatchTo
              AND ISNULL(tm.REG_TYPE, 'Kisi') = 'Kisi';

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR OFF;
            COMMIT TRANSACTION;

            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());
            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'SUBSCR',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = NULL,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR OFF;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'SUBSCR',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('SUBSCR batch %d HATA → bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;
            SET @RegType    = 'Kisi';

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_REG_INSERT_ONE
                            @CurID = @BisectFrom, @RegType = @RegType,
                            @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'SUBSCR',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom, @BridgeTo = NULL,
                                @RowCount = 1;
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(N'ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'SUBSCR',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom, @BridgeTo = @BisectFrom,
                            @SourceID = @BisectFrom, @IsSingleRow = 1, @ErrorMsg = @SingleErrMsg;

                        SELECT @ErrorCount = tr.ERROR_COUNT
                        FROM energy.dbo.MIG_TABLE_RUN tr WHERE tr.TABLE_RUN_ID = @TableRunID;

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
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR ON;

                    INSERT INTO energy.dbo.LS_005_SUBSCR (
                        LREF, [TYPE], TCID, STATUS,
                        FIRSTNAME, SURNAME, NAME_,
                        BIRTHPLACE, BIRTHDATE,
                        FATHER_NAME, MOTHER_NAME, GENDER,
                        IDENTITY_ADDRESS, IDENTITY_CHANGE_DATE,
                        IDENTITY_DISTRICT, IDENTITY_FAMILY_ROW_NUMBER,
                        IDENTITY_ISSUE_DATE, IDENTITY_PROVINCE,
                        IDENTITY_QUARTER, IDENTITY_QUARTER_ID,
                        IDENTITY_REASON_FOR_ISSUE, IDENTITY_REGISTRATION_NUMBER,
                        IDENTITY_ROW_NUMBER, IDENTITY_SERIAL, IDENTITY_SERIAL_NUMBER,
                        IDENTITY_VOLUME_NUMBER, OTH_NO, OTH_DESC,
                        CODE, DUALREG, IS_OLD, OLREF,
                        EBILLING, CUSTOMER_BILL_TYPE, E_BILL_CUSTOMER_DATE,
                        DEAD_DATE, DEADDATE,
                        IS_COMMINICATION_PERMIT, POOL_ID,
                        EXPRESS_CONSENT, MARKETING_APPROVE,
                        IS_GSM, IS_PHONE, IS_MAIL, IS_ACTIVE,
                        DELETED_TIMESTAMP, DELETED_USER_ID,
                        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                        RECORDID, IN_BLACKLIST
                    )
                    SELECT
                        r.ID, 0,  -- TYPE
                        CAST(r.IDENTITY_NUMBER AS VARCHAR(20)),
                        0,  -- STATUS
                        LEFT(r.FIRST_NAME, 150), LEFT(r.LAST_NAME, 150),
                        LEFT(ISNULL(r.FIRST_NAME, '') + ' ' + ISNULL(r.LAST_NAME, ''), 300),
                        LEFT(r.BIRTH_PLACE, 50),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.BIRTH_DATE AS DATETIME2)),
                        LEFT(r.FATHER_NAME, 100), LEFT(r.MOTHER_NAME, 100), r.GENDER,
                        LEFT(r.IDENTITY_ADDRESS, 2000),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.IDENTITY_CHANGE_DATE AS DATETIME2)),
                        LEFT(r.IDENTITY_DISTRICT, 50), r.IDENTITY_FAMILY_ROW_NUMBER,
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.IDENTITY_ISSUE_DATE AS DATETIME2)),
                        LEFT(r.IDENTITY_PROVINCE, 50), LEFT(r.IDENTITY_QUARTER, 50),
                        r.IDENTITY_QUARTER_ID, LEFT(r.IDENTITY_REASON_FOR_ISSUE, 50),
                        r.IDENTITY_REGISTRATION_NUMBER, r.IDENTITY_ROW_NUMBER,
                        LEFT(r.IDENTITY_SERIAL, 5), LEFT(r.IDENTITY_SERIAL_NUMBER, 15),
                        r.IDENTITY_VOLUME_NUMBER,
                        CAST(r.SOCIAL_SECURITY_NUMBER AS NVARCHAR(40)),
                        LEFT(r.DESCRIPTION, 100), LEFT(r.CODE, 50),
                        CASE WHEN cnt.TYPE_COUNT > 1 THEN 1 ELSE 0 END,
                        0, r.ID, r.IS_E_BILL_CUSTOMER, r.CUSTOMER_BILL_TYPE,
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.E_BILL_CUSTOMER_DATE AS DATETIME2)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.DEAD_DATE AS DATETIME2)),
                        CAST(r.DEAD_DATE AS DATETIME2),
                        r.IS_COMMINICATION_PERMIT, r.POOL_ID,
                        ISNULL(r.HAS_EXPRESS_CONSENT, 0), ISNULL(r.IS_MARKETING_CONSENT_GIVEN, 0),
                        ISNULL(r.IS_SMS_CONTACT_ALLOWED, 0), ISNULL(r.IS_CALL_CONTACT_ALLOWED, 0),
                        ISNULL(r.IS_EMAIL_CONTACT_ALLOWED, 0),
                        CASE WHEN r.DELETED_TIMESTAMP IS NOT NULL THEN 0
                             WHEN r.IS_LOST = 1 THEN 0 ELSE 1 END,
                        CAST(r.DELETED_TIMESTAMP AS DATETIME2), energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.DELETED_USER_ID AS INT)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.CREATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.UPDATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.UPDATED_TIMESTAMP AS DATETIME2)),
                        r.ID,
                        CASE WHEN ISNULL(r.IS_LOST, 0) = 1
                               OR ISNULL(r.BANKRUPTCY_RECORD, 0) = 1 THEN 1 ELSE 0 END
                    FROM izgazMGR.dbo.CS_REGISTER r
                    LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
                    LEFT JOIN #RegTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
                    LEFT JOIN #RegTypeCount cnt ON cnt.REGISTER_ID = r.ID
                    WHERE r.ID BETWEEN @BisectFrom AND @BisectMid
                      AND ISNULL(tm.REG_TYPE, 'Kisi') = 'Kisi';

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR OFF;
                    COMMIT TRANSACTION;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'SUBSCR',
                        @BatchNo = @BatchNo, @BridgeFrom = @BisectLogFrom, @BridgeTo = NULL,
                        @RowCount = @BisectRows;

                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET IDENTITY_INSERT energy.dbo.LS_005_SUBSCR OFF;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @BisectTo = @BisectMid;
                END CATCH
            END -- bisect SUBSCR
        END CATCH

        IF @Stopped = 1 BREAK;

        -- ------------------------------------------------------
        -- FIRM toplu INSERT
        -- ------------------------------------------------------
        SET @RowCount = 0;
        BEGIN TRY
            BEGIN TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_005_FIRM ON;

            INSERT INTO energy.dbo.LS_005_FIRM (
                LREF, [TYPE], NAME_, STATUS,
                TAXNO, TAXOFFICE, CODE, DUALREG, OLREF,
                BANNED, IN_BLACKLIST, EBILLING, TAXNO2,
                ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                RECORDID, IDENTITY_NUMBER, REGISTER_TYPE
            )
            SELECT
                r.ID, pt.PRIMARY_TYPE_ID,
           LEFT(ISNULL(r.FIRST_NAME, '') + ' ' + ISNULL(r.LAST_NAME, ''), 300),
                CASE WHEN r.DELETED_TIMESTAMP IS NOT NULL THEN 0
                     WHEN r.IS_LOST = 1 THEN 2 ELSE 1 END,
                LEFT(r.TAX_NUMBER, 15), LEFT(r.TAX_OFFICE, 20),
                LEFT(r.CODE, 50),
                CASE WHEN cnt.TYPE_COUNT > 1 THEN 1 ELSE 0 END,
                r.ID, ISNULL(r.BANKRUPTCY_RECORD, 0),
                CASE WHEN ISNULL(r.IS_LOST, 0) = 1
                       OR ISNULL(r.BANKRUPTCY_RECORD, 0) = 1 THEN 1 ELSE 0 END,
                r.IS_E_BILL_CUSTOMER, LEFT(r.CHAMBER_CODE, 100),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.CREATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
                energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.UPDATED_USER_ID AS INT)),
                energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.UPDATED_TIMESTAMP AS DATETIME2)),
                r.ID, CAST(r.IDENTITY_NUMBER AS CHAR(11)),
                pt.PRIMARY_TYPE_ID
            FROM izgazMGR.dbo.CS_REGISTER r
            LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
            LEFT JOIN #RegTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
            LEFT JOIN #RegTypeCount cnt ON cnt.REGISTER_ID = r.ID
            WHERE r.ID BETWEEN @BatchFrom AND @BatchTo
              AND ISNULL(tm.REG_TYPE, 'Kisi') = 'Firma';

            SET @RowCount = @@ROWCOUNT;
            SET IDENTITY_INSERT energy.dbo.LS_005_FIRM OFF;
            COMMIT TRANSACTION;

            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());
            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'FIRM',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = NULL,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_005_FIRM OFF;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'FIRM',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('FIRM batch %d HATA → bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;
            SET @RegType    = 'Firma';

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_REG_INSERT_ONE
                            @CurID = @BisectFrom, @RegType = @RegType,
                            @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'FIRM',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom, @BridgeTo = NULL,
                                @RowCount = 1;
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(N'ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'FIRM',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom, @BridgeTo = @BisectFrom,
                            @SourceID = @BisectFrom, @IsSingleRow = 1, @ErrorMsg = @SingleErrMsg;

                        SELECT @ErrorCount = tr.ERROR_COUNT
                        FROM energy.dbo.MIG_TABLE_RUN tr WHERE tr.TABLE_RUN_ID = @TableRunID;

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
                    SET IDENTITY_INSERT energy.dbo.LS_005_FIRM ON;

                    INSERT INTO energy.dbo.LS_005_FIRM (
                        LREF, [TYPE], NAME_, STATUS,
                        TAXNO, TAXOFFICE, CODE, DUALREG, OLREF,
                        BANNED, IN_BLACKLIST, EBILLING, TAXNO2,
                        ADDUSER, ADDDATE, UPDUSER, UPDDATE,
                        RECORDID, IDENTITY_NUMBER, REGISTER_TYPE
                    )
                    SELECT
                        r.ID, pt.PRIMARY_TYPE_ID,
                 LEFT(ISNULL(r.FIRST_NAME, '') + ' ' + ISNULL(r.LAST_NAME, ''), 300),
                        CASE WHEN r.DELETED_TIMESTAMP IS NOT NULL THEN 0
                             WHEN r.IS_LOST = 1 THEN 2 ELSE 1 END,
                        LEFT(r.TAX_NUMBER, 15), LEFT(r.TAX_OFFICE, 20),
                        LEFT(r.CODE, 50),
                        CASE WHEN cnt.TYPE_COUNT > 1 THEN 1 ELSE 0 END,
                        r.ID, ISNULL(r.BANKRUPTCY_RECORD, 0),
                        CASE WHEN ISNULL(r.IS_LOST, 0) = 1
                               OR ISNULL(r.BANKRUPTCY_RECORD, 0) = 1 THEN 1 ELSE 0 END,
                        r.IS_E_BILL_CUSTOMER, LEFT(r.CHAMBER_CODE, 100),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.CREATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.CREATED_TIMESTAMP AS DATETIME2)),
                        energy.dbo.FN_MIG_MAP_USER_USERID(CAST(r.UPDATED_USER_ID AS INT)),
                        energy.dbo.FN_SAFE_SMALLDT_USR(CAST(r.UPDATED_TIMESTAMP AS DATETIME2)),
                        r.ID, CAST(r.IDENTITY_NUMBER AS CHAR(11)),
                        pt.PRIMARY_TYPE_ID
                    FROM izgazMGR.dbo.CS_REGISTER r
                    LEFT JOIN #RegPrimaryType pt ON pt.REGISTER_ID = r.ID
                    LEFT JOIN #RegTypeMap tm ON tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID
                    LEFT JOIN #RegTypeCount cnt ON cnt.REGISTER_ID = r.ID
                    WHERE r.ID BETWEEN @BisectFrom AND @BisectMid
                      AND ISNULL(tm.REG_TYPE, 'Kisi') = 'Firma';

                    SET @BisectRows = @@ROWCOUNT;
                    SET @BisectLogFrom = @BisectFrom;
                    SET IDENTITY_INSERT energy.dbo.LS_005_FIRM OFF;
                    COMMIT TRANSACTION;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'FIRM',
                        @BatchNo = @BatchNo, @BridgeFrom = @BisectLogFrom, @BridgeTo = NULL,
                        @RowCount = @BisectRows;

                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET IDENTITY_INSERT energy.dbo.LS_005_FIRM OFF;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @BisectTo = @BisectMid;
                END CATCH
            END -- bisect FIRM
        END CATCH

        IF @Stopped = 1 BREAK;

        -- Checkpoint ilerlet (SUBSCR + FIRM tamamlandı)
        SET @LastBridgeKey = @BatchTo;
        EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
            @RunID = @RunID, @TableRunID = @TableRunID,
            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
            @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
            @RowCount = 0;

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
                + ' LastID=' + CAST(@LastBridgeKey AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END -- WHILE

    SELECT @TargetCount = COUNT_BIG(*) FROM energy.dbo.LS_005_SUBSCR
    SELECT @TargetCount = @TargetCount + COUNT_BIG(*) FROM energy.dbo.LS_005_FIRM;

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

-- ============================================================
-- ÇALIŞTIRMA
-- ============================================================
-- Tam sıfırla:
 --EXEC energy.dbo.SP_MIGRATE_CS_REGISTER
 --     @HARD_RESET = 1, @BATCH_SIZE = 50000, @MAX_ERROR = 500, @DEBUG = 1;


 
-- Kaldığı yerden:
-- EXEC energy.dbo.SP_MIGRATE_CS_REGISTER
--      @RESUME = 1, @BATCH_SIZE = 5000, @DEBUG = 1;
-- ============================================================

