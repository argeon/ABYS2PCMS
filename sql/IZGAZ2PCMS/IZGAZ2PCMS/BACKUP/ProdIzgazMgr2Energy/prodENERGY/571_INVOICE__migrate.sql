/* ============================================================
   SCRIPT_ID : INVOICE_MIGRATE
   SCRIPT_NO : 571
   FILE      : 571_INVOICE__migrate.sql
   VERSION   : 10
   ============================================================ */
-- v10: #temp YOK — fiziki MIG_571_STG_BATCH_KEYS / KEYS / SKIP (+ IX)
--      Onkosul: 00e_invoice_staging.sql
-- v9: key-list batch — #MIG_INV_BATCH_KEYS (GERI — kural ihlali)
-- v8: mukerrer — DISTINCT ABYS_ACTION_ID (#KEYS + ROW_NUMBER); skip LREF|ABYS_ID per key
-- v7b: @AGR_ID doluysa PREPARE_LOAD cagirilmaz (index DISABLE yok)
-- v7: ABYS_ID correlated NOT EXISTS KALDIRILDI (index yokken 35M+ read)
--     #MIG_INV_SKIP: LREF PK seek + AGR'de ABYS_ID (IX_MIG_INV_ABYS_AGR)
-- v6: mukerrer — NOT EXISTS LREF + ABYS_ID (AGR disinda full scan riski)
-- v5: @AGR_ID — LS_005_01_AGR.AGREEMENT_NUMBER ile cozum; once fatura zinciri temizlenir
-- v4: NOT EXISTS sadece LREF (ABYS_ID OR kosulu kaldirildi — index yokken tarama yapiyordu)
-- v3: LREF = ABYS_ACTION_ID (IDENTITY_INSERT); batch = ABYS_ACTION_ID; kaynak LREF kullanilmaz
-- v2: batch/LREF = kaynak LREF; tip/uzunluk guncellemeleri
-- v12: @AGR_ID=-1 → NO_AGR (ABYS_AGREEMENT_ID IS NULL only)
-- v11: EXPLAIN ← izgazMGR.LS_INVOICE.EXPLAIN (LEFT 250)
-- ============================================================
-- SP_MIGRATE_LS005_INVOICE
-- Kaynak  : izgazMGR.dbo.LS_INVOICE
-- Hedef   : energy.dbo.LS_005_01_INVOICE
-- @AGR_ID : NULL=ALL | >0=AGR | -1=NO_AGR (sozlesmesiz)
-- LREF    : IDENTITY_INSERT = ABYS_ACTION_ID
-- ABYS_ID : ABYS_ACTION_ID
-- OLREF   : kaynak OLREF (ayri kolon)
-- Kaynak LREF kullanilmaz (duplicate riski).
--
-- @AGR_ID : AGREEMENT_NUMBER (ABYS sozlesme no). Doluysa:
--   1) SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR (PAYTRANS→INVLINES→INVOICE)
--   2) yalniz o sozlesmenin kaynak satirlari insert
-- Onkosul AGR: 569_INVOICE_CLEAN_BY_AGR.sql + LS_005_01_AGR yuklu
-- Onkosul index: adim3_verify_indexes (IX_MIG_INV_ABYS_AGR, IX_MIG_INV_ABYS_ID)
--
-- Pass 1 dump: FK/wire/JOIN yok.
-- User: FN_MIG_MAP_USER_USERID (+10000).
-- @AGR_ID dolu (pilot): PREPARE_LOAD / index DISABLE YOK — NC indexler acik kalir.
-- Full load (@AGR_ID NULL): PREPARE_LOAD; sonra 572_INVOICE__post.
-- Batch: caller MIG_571_STG_BATCH_KEYS doldurur; INSERT_RANGE equality join (BETWEEN yok).
-- ~80M satir: @BATCH_SIZE varsayilan 50000.
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @AGR_ID    BIGINT = NULL,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    /* v10: fiziki STG — #temp YOK
       - Full (@AGR_ID NULL): BETWEEN → MIG_571_STG_KEYS
       - AGR: MIG_571_STG_BATCH_KEYS equality (seyrek ID)
       Correlated ABYS_ID NOT EXISTS YASAK. */
    IF OBJECT_ID('energy.dbo.MIG_571_STG_BATCH_KEYS', 'U') IS NULL
       OR OBJECT_ID('energy.dbo.MIG_571_STG_KEYS', 'U') IS NULL
       OR OBJECT_ID('energy.dbo.MIG_571_STG_SKIP', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_571_STG_* yok — once 00e_invoice_staging.sql', 16, 1);
        RETURN;
    END

    DECLARE @UseKeyList BIT = 0;
    IF @AGR_ID IS NOT NULL
       AND EXISTS (SELECT 1 FROM energy.dbo.MIG_571_STG_BATCH_KEYS)
        SET @UseKeyList = 1;

    TRUNCATE TABLE energy.dbo.MIG_571_STG_KEYS;

    IF @UseKeyList = 1
        INSERT INTO energy.dbo.MIG_571_STG_KEYS (ACTION_ID)
        SELECT DISTINCT CAST(k.ACTION_ID AS BIGINT)
        FROM energy.dbo.MIG_571_STG_BATCH_KEYS k
        WHERE k.ACTION_ID BETWEEN 1 AND 2147483647;
    ELSE
        /* Full: ACTION index seek → key list (heap full scan / OR plan YOK) */
        INSERT INTO energy.dbo.MIG_571_STG_KEYS (ACTION_ID)
        SELECT DISTINCT CAST(s.ABYS_ACTION_ID AS BIGINT)
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK, INDEX(IX_MIG_LSINV_ACTION))
        WHERE s.ABYS_ACTION_ID BETWEEN @BatchFrom AND @BatchTo
          AND s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647;

    TRUNCATE TABLE energy.dbo.MIG_571_STG_SKIP;

    IF @UseKeyList = 1
    BEGIN
        INSERT INTO energy.dbo.MIG_571_STG_SKIP (ID)
        SELECT k.ACTION_ID
        FROM energy.dbo.MIG_571_STG_KEYS k
        WHERE EXISTS (
              SELECT 1
              FROM energy.dbo.LS_005_01_INVOICE t
              WHERE t.LREF = CAST(k.ACTION_ID AS INT)
            );

        INSERT INTO energy.dbo.MIG_571_STG_SKIP (ID)
        SELECT k.ACTION_ID
        FROM energy.dbo.MIG_571_STG_KEYS k
        WHERE EXISTS (
              SELECT 1
              FROM energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
              WHERE t.ABYS_ID = k.ACTION_ID
                AND (
                      (@AGR_ID = -1 AND t.ABYS_AGREEMENT_ID IS NULL)
                   OR (@AGR_ID > 0 AND t.ABYS_AGREEMENT_ID = @AGR_ID)
                    )
            )
          AND NOT EXISTS (SELECT 1 FROM energy.dbo.MIG_571_STG_SKIP x WHERE x.ID = k.ACTION_ID)
        OPTION (RECOMPILE, MAXDOP 24);
    END
    ELSE
    BEGIN
        /* Full: PK LREF araligi — kaynak cift tarama yok */
        INSERT INTO energy.dbo.MIG_571_STG_SKIP (ID)
        SELECT CAST(t.LREF AS BIGINT)
        FROM energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
        WHERE t.LREF BETWEEN @BatchFrom AND @BatchTo
          AND t.LREF BETWEEN 1 AND 2147483647
        OPTION (RECOMPILE, MAXDOP 24);
    END

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_INVOICE ON;

        /* v10: full = BETWEEN tek pass; AGR = key-list */

        INSERT INTO energy.dbo.LS_005_01_INVOICE WITH (TABLOCK) (
            LREF, IOCODE, FICHENO, DATE_, DUEDATE, [TYPE], CLIENTREF,
            TLTOTAL, CURID, CURTOTAL, EXPLAIN, CANCELED, OWNERREF, OWNERTYPE, LOGOREF,
            TAX, DV, GRANDTOTAL, PRINTCOUNT, PAYABLETOTAL, READ_TRANSREF, INTERESTRATE,
            gas_open_fee, detach_attach_fee, test_fee, spec_serv_fee, fixed_fee, expend_fee,
            DEFAULT_FINE, DEFAULT_FINETAX, FITNO, CHEQUEREF,
            ADDDATE, ADDUSER, UPDDATE, UPDUSER,
            LAWDETAILREF, BANKREF, CUSTBNK_ACC, BANK_STAT, BANK_CANCELLED, BANK_RECORD_REF,
            illegal_use_fee, LOGO_FIRMNR, LOGO_FICHEREF, LOGO_FICHENO, discount_addition,
            RETURN_SOURCE_INVREF, RETURN_TARGET_INVREF, CLOSED,
            CCCONFIRMCODE, BANKACCREF, XTYPE, BN_TYPE, OLOC_ID, OLREF,
            LASTPAIDDATE, IS_DUPLICATE_PAYMENT, PRJ_INV_REF, IS_LAW,
            IsSendInvoice, IsApproveInvoice, SuccessCode, ETTN, ArchiveNo, InvPreName,
            IsBuyukSanayiFatura, InvoiceReturnMessage, CancelEArchiveInvoiceIsSend, AMOUNT,
            ARCHIVE_SEND_STATUS, ARCHIVE_MAIL_SEND_STATUS, ARCHIVE_SEND_DATE, ARCHIVE_MAIL_SEND_DATE,
            PERIOD, HAS_DISCOUNT, DISCOUNT_AMOUNT, DISCOUNT_REMAIN_AMOUNT, DISCOUNT_USED_AMOUNT,
            CANCEL_DATE, CANCEL_REASON_ID, CANCEL_DESCRIPTION, CANCEL_USER_ID, DESCRIPTION,
            INSTALLMENT_PLAN_REF, TAX_TEVKIFAT, Qmin, Qmax,
            ARCHIVE_CANCEL_DATE, ARCHIVE_LAST_PROCESS_DATE,
            ABYS_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
            ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, ABYS_INSTALLATION_ID, ABYS_METER_ID,
            ABYS_AREA_ID, ABYS_PROJECT_ID, ABYS_TARIFF_TYPE_ID, ABYS_SKB_TARIFF_TYPE_ID,
            ABYS_SUBSCRIBER_TYPE_ID, ABYS_READING_DATE, ABYS_IS_E_BILL, ABYS_IS_FPS,
            ABYS_DO_DISCHARGE, ABYS_INSTALLMENT_ID, ABYS_GROUP_ACCOUNT_ID,
            ABYS_BILL_TYPE_ID, ABYS_BILL_SERIAL, ABYS_BILL_ORDER_NUMBER, ABYS_BILL_NUMBER,
            ABYS_CONSUMPTION, ABYS_M3, ABYS_KWH, ABYS_CUSTOMER_BILL_TYPE,
            ABYS_REF_DEPOSIT_ACCOUNT_ID, ABYS_REF_DEP_ACC_ACTION_ID, ABYS_POOL_ID,
            ABYS_CREATED_USER_ID, ABYS_UPDATED_USER_ID, ABYS_VERSION,
            ABYS_TRANSACTION_TYPE_ID, ABYS_SOURCE_ACCRUE_TYPE_ID,
            ABYS_ADDUSER, ABYS_UPDUSER, ABYS_CANCEL_USER_ID
        )
        SELECT
            CAST(s.ABYS_ACTION_ID AS INT),
            CAST(s.IOCODE AS TINYINT),
            LEFT(s.FICHENO, 45),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DATE_ AS DATETIME2)),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.DUEDATE AS DATETIME2)),
            CAST(s.[TYPE] AS TINYINT),
            CAST(s.CLIENTREF AS INT),
            CAST(s.TLTOTAL AS FLOAT),
            /* compat <110: TRY_CAST yok → guvenli CAST */
            CASE
                WHEN s.CURID IS NULL THEN CAST(NULL AS SMALLINT)
                WHEN CAST(s.CURID AS BIGINT) BETWEEN -32768 AND 32767
                    THEN CAST(s.CURID AS SMALLINT)
                ELSE CAST(NULL AS SMALLINT)
            END,
            CAST(s.CURTOTAL AS FLOAT),
            LEFT(s.EXPLAIN, 250),
            CASE WHEN ISNULL(s.CANCELED, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            CAST(s.OWNERREF AS INT),
            CAST(s.OWNERTYPE AS TINYINT),
            CAST(s.LOGOREF AS INT),
            CAST(s.TAX AS FLOAT),
            CAST(s.DV AS FLOAT),
            CAST(s.GRANDTOTAL AS FLOAT),
            CAST(s.PRINTCOUNT AS INT),
            CAST(s.PAYABLETOTAL AS FLOAT),
            CASE
                WHEN s.READ_TRANSREF IS NULL THEN CAST(NULL AS INT)
                WHEN CAST(s.READ_TRANSREF AS BIGINT) BETWEEN -2147483648 AND 2147483647
                    THEN CAST(s.READ_TRANSREF AS INT)
                ELSE CAST(NULL AS INT)
            END,
            CAST(s.INTERESTRATE AS FLOAT),
            CAST(s.GAS_OPEN_FEE AS FLOAT),
            CAST(s.DETACH_ATTACH_FEE AS FLOAT),
            CAST(s.TEST_FEE AS FLOAT),
            CAST(s.SPEC_SERV_FEE AS FLOAT),
            CAST(s.FIXED_FEE AS FLOAT),
            CAST(s.EXPEND_FEE AS FLOAT),
            CAST(s.DEFAULT_FINE AS FLOAT),
            CAST(s.DEFAULT_FINETAX AS FLOAT),
            CAST(s.FITNO AS BIGINT),
            CAST(s.CHEQUEREF AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.ADDDATE AS DATETIME2)),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.ADDUSER AS INT)),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.UPDDATE AS DATETIME2)),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.UPDUSER AS INT)),
            CAST(s.LAWDETAILREF AS INT),
            s.BANKREF,
            LEFT(s.CUSTBNK_ACC, 20),
            CAST(s.BANK_STAT AS INT),
            CASE WHEN ISNULL(s.BANK_CANCELLED, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            LEFT(s.BANK_RECORD_REF, 50),
            CAST(s.ILLEGAL_USE_FEE AS FLOAT),
            CAST(s.LOGO_FIRMNR AS INT),
            CAST(s.LOGO_FICHEREF AS INT),
            LEFT(s.LOGO_FICHENO, 100),
            CAST(s.DISCOUNT_ADDITION AS FLOAT),
            CAST(s.RETURN_SOURCE_INVREF AS INT),
            CAST(s.RETURN_TARGET_INVREF AS INT),
            CASE WHEN ISNULL(s.CLOSED, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            LEFT(s.CCCONFIRMCODE, 50),
            CAST(s.BANKACCREF AS INT),
            CAST(s.XTYPE AS INT),
            CAST(s.BN_TYPE AS INT),
            s.OLOC_ID,
            CAST(s.OLREF AS INT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.LASTPAIDDATE AS DATETIME2)),
            CASE WHEN ISNULL(s.IS_DUPLICATE_PAYMENT, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            CAST(s.PRJ_INV_REF AS INT),
            CASE WHEN ISNULL(s.IS_LAW, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            CASE WHEN ISNULL(s.ISSENDINVOICE, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            CASE WHEN ISNULL(s.ISAPPROVEINVOICE, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            LEFT(s.SUCCESSCODE, 100),
            /* compat <110: TRY_CONVERT yok — GUID pattern + CONVERT */
            CASE
                WHEN NULLIF(LTRIM(RTRIM(s.ETTN)), N'') IS NULL THEN CAST(NULL AS UNIQUEIDENTIFIER)
                WHEN LTRIM(RTRIM(s.ETTN)) LIKE
                     '[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]'
                    THEN CONVERT(UNIQUEIDENTIFIER, LTRIM(RTRIM(s.ETTN)))
                ELSE CAST(NULL AS UNIQUEIDENTIFIER)
            END,
            CAST(s.ARCHIVENO AS INT),
            LEFT(s.INVPRENAME, 5),
            CASE WHEN ISNULL(s.ISBUYUKSANAYIFATURA, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            LEFT(s.INVOICERETURNMESSAGE, 400),
            CASE WHEN ISNULL(s.CANCELEARCHIVEINVOICEISSEND, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            CAST(s.AMOUNT AS FLOAT),
            CAST(s.ARCHIVE_SEND_STATUS AS INT),
            CAST(s.ARCHIVE_MAIL_SEND_STATUS AS INT),
            CAST(s.ARCHIVE_SEND_DATE AS DATETIME),
            CAST(s.ARCHIVE_MAIL_SEND_DATE AS DATETIME),
            s.PERIOD,
            CASE WHEN ISNULL(s.HAS_DISCOUNT, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
            CAST(s.DISCOUNT_AMOUNT AS FLOAT),
            CAST(s.DISCOUNT_REMAIN_AMOUNT AS FLOAT),
            CAST(s.DISCOUNT_USED_AMOUNT AS FLOAT),
            energy.dbo.FN_SAFE_SMALLDT_DEP(CAST(s.CANCEL_DATE AS DATETIME2)),
            CAST(s.CANCEL_REASON_ID AS INT),
            CAST(NULL AS NVARCHAR(MAX)),
            energy.dbo.FN_MIG_MAP_USER_USERID(CAST(s.CANCEL_USER_ID AS INT)),
            LEFT(s.DESCRIPTION, 400),
            CAST(s.INSTALLMENT_PLAN_REF AS INT),
            CAST(s.TAX_TEVKIFAT AS FLOAT),
            CAST(s.QMIN AS FLOAT),
            CAST(s.QMAX AS FLOAT),
            CAST(s.ARCHIVE_CANCEL_DATE AS DATETIME),
            CAST(s.ARCHIVE_LAST_PROCESS_DATE AS DATETIME),
            s.ABYS_ACTION_ID,
            s.ABYS_ACCOUNT_ID,
            s.ABYS_ACTION_TYPE_ID,
            s.ABYS_ACCRUE_TYPE_ID,
            s.ABYS_REGISTER_ID,
            s.ABYS_AGREEMENT_ID,
            s.ABYS_INSTALLATION_ID,
            s.ABYS_METER_ID,
            s.ABYS_AREA_ID,
            s.ABYS_PROJECT_ID,
            s.ABYS_TARIFF_TYPE_ID,
            s.ABYS_SKB_TARIFF_TYPE_ID,
            s.ABYS_SUBSCRIBER_TYPE_ID,
            s.ABYS_READING_DATE,
            s.ABYS_IS_E_BILL,
            s.ABYS_IS_FPS,
            s.ABYS_DO_DISCHARGE,
            s.ABYS_INSTALLMENT_ID,
            s.ABYS_GROUP_ACCOUNT_ID,
            s.ABYS_BILL_TYPE_ID,
            s.ABYS_BILL_SERIAL,
            s.ABYS_BILL_ORDER_NUMBER,
            s.ABYS_BILL_NUMBER,
            s.ABYS_CONSUMPTION,
            s.ABYS_M3,
            s.ABYS_KWH,
            s.ABYS_CUSTOMER_BILL_TYPE,
            s.ABYS_REF_DEPOSIT_ACCOUNT_ID,
            s.ABYS_REF_DEP_ACC_ACTION_ID,
            s.ABYS_POOL_ID,
            s.ABYS_CREATED_USER_ID,
            s.ABYS_UPDATED_USER_ID,
            s.ABYS_VERSION,
            s.TRNSACTION_TYPE_ID,
            s.ACCRUE_TYPE_ID,
            s.ADDUSER,
            s.UPDUSER,
            s.CANCEL_USER_ID
        FROM (
            SELECT
                s0.*,
                ROW_NUMBER() OVER (
                    PARTITION BY s0.ABYS_ACTION_ID
                    ORDER BY s0.ABYS_ACTION_ID
                ) AS rn
            FROM izgazMGR.dbo.LS_INVOICE s0 WITH (NOLOCK)
            INNER JOIN energy.dbo.MIG_571_STG_KEYS kx ON kx.ACTION_ID = s0.ABYS_ACTION_ID
            WHERE (
                    @AGR_ID IS NULL
                 OR (@AGR_ID = -1 AND s0.ABYS_AGREEMENT_ID IS NULL AND s0.ABYS_ACCOUNT_ID IS NOT NULL)
                 OR (@AGR_ID > 0 AND s0.ABYS_AGREEMENT_ID = @AGR_ID)
                  )
        ) s
        WHERE s.rn = 1
          AND NOT EXISTS (
              SELECT 1 FROM energy.dbo.MIG_571_STG_SKIP x WHERE x.ID = s.ABYS_ACTION_ID
          )
        OPTION (RECOMPILE, MAXDOP 24);

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_INSERT_ONE
    @CurID       BIGINT,
    @AGR_ID      BIGINT = NULL,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INVOICE t
        WHERE t.LREF = @CurID
    )
        RETURN;

    IF @AGR_ID IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM energy.dbo.LS_005_01_INVOICE t WITH (NOLOCK)
            WHERE t.ABYS_ID = @CurID
              AND (
                    (@AGR_ID = -1 AND t.ABYS_AGREEMENT_ID IS NULL)
                 OR (@AGR_ID > 0 AND t.ABYS_AGREEMENT_ID = @AGR_ID)
                  )
        )
            RETURN;
    END
    ELSE IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND name = 'IX_MIG_INV_ABYS_ID'
    )
    AND EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INVOICE t
        WHERE t.ABYS_ID = @CurID
    )
        RETURN;

    IF @AGR_ID IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
            WHERE s.ABYS_ACTION_ID = @CurID
              AND (
                    (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
                 OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                  )
       )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_INVOICE_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @AGR_ID    = @AGR_ID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_INVOICE ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG = @DEBUG;

    SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_INVOICE
        WHERE ABYS_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
            RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalStr) WITH NOWAIT;
        END
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_INVOICE;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVOICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_INVOICE
    @BATCH_SIZE  INT = 50000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @AGR_ID      BIGINT = NULL,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_INVOICE',
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
        @RowInserted    BIT,
        @MaxLref        INT;

    EXEC dbo.SP_MIG_INVOICE_VALIDATE_ALL @RaiseOnMissing = 1;

    -- @AGR_ID > 0: AGREEMENT_NUMBER ile cozum + fatura zinciri temizligi
    -- @AGR_ID = -1 (NO_AGR): clean yok — dogrudan insert
    IF @AGR_ID > 0 AND (@RESUME = 0 OR @HARD_RESET = 1)
    BEGIN
        IF OBJECT_ID('energy.dbo.SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR', 'P') IS NULL
        BEGIN
            RAISERROR('SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR yok. Once 569_INVOICE_CLEAN_BY_AGR.sql deploy edin.', 16, 1);
            RETURN;
        END

        EXEC dbo.SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR
            @AGRID        = @AGR_ID,
            @DELETE_BATCH = @BATCH_SIZE,
            @DEBUG        = @DEBUG,
            @RaiseIfAgrMissing = 1;

        SET @RESUME = 0;
        SET @ExecMode = 'AGR_CLEAN';
        IF @DEBUG = 1
            RAISERROR('AGR pilot: PREPARE_LOAD atlandi (index DISABLE yok).', 0, 1) WITH NOWAIT;
    END
    ELSE IF @AGR_ID = -1
    BEGIN
        SET @ExecMode = CASE WHEN @RESUME = 1 THEN 'NO_AGR_RESUME' ELSE 'NO_AGR' END;
        IF @DEBUG = 1
            RAISERROR('NO_AGR: PREPARE_LOAD atlandi (index DISABLE yok).', 0, 1) WITH NOWAIT;
    END
    ELSE IF @AGR_ID IS NOT NULL
    BEGIN
        SET @ExecMode = 'AGR_RESUME';
        IF @DEBUG = 1
            RAISERROR('AGR pilot: PREPARE_LOAD atlandi (index DISABLE yok).', 0, 1) WITH NOWAIT;
    END
    ELSE IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_INVOICE_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE
    BEGIN
        -- Full / resume (AGR degil): index disable
        EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG = @DEBUG;
        IF @RESUME = 1
            SET @ExecMode = 'RESUME';
        ELSE
            SET @ExecMode = 'FULL';
    END

    IF @AGR_ID = -1
    BEGIN
        /* NO_AGR: sozlesmesiz tahakkuk — ACCOUNT koprulu */
        SELECT @SourceCount = COUNT_BIG(*)
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
          AND s.ABYS_AGREEMENT_ID IS NULL
          AND s.ABYS_ACCOUNT_ID IS NOT NULL;

        SELECT @MaxBridgeKey = MAX(s.ABYS_ACTION_ID)
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
          AND s.ABYS_AGREEMENT_ID IS NULL
          AND s.ABYS_ACCOUNT_ID IS NOT NULL;
    END
    ELSE IF @AGR_ID IS NOT NULL
    BEGIN
        SELECT @SourceCount = COUNT_BIG(*)
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
          AND s.ABYS_AGREEMENT_ID = @AGR_ID;

        SELECT @MaxBridgeKey = MAX(s.ABYS_ACTION_ID)
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647
          AND s.ABYS_AGREEMENT_ID = @AGR_ID;
    END
    ELSE
    BEGIN
        SELECT @SourceCount = SUM(p.rows)
        FROM izgazMGR.sys.partitions p
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
        INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
        WHERE sch.name = 'dbo'
          AND t.name = 'LS_INVOICE'
          AND p.index_id IN (0, 1);

        SELECT @MaxBridgeKey = MAX(s.ABYS_ACTION_ID)
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647;
    END

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_INVOICE',
        @TargetTable    = 'LS_005_01_INVOICE',
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
            + ' | AGR=' + ISNULL(CAST(@AGR_ID AS VARCHAR(20)), 'ALL')
            + ' | Kaynak~' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
            + ' | ABYS_ACTION_ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20))
            + ' | key-list';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF OBJECT_ID('energy.dbo.MIG_571_STG_BATCH_KEYS', 'U') IS NULL
       OR OBJECT_ID('energy.dbo.MIG_571_STG_KEYS', 'U') IS NULL
       OR OBJECT_ID('energy.dbo.MIG_571_STG_SKIP', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_571_STG_* yok — once 00e_invoice_staging.sql', 16, 1);
        RETURN;
    END

    TRUNCATE TABLE energy.dbo.MIG_571_STG_BATCH_KEYS;
    TRUNCATE TABLE energy.dbo.MIG_571_STG_KEYS;
    TRUNCATE TABLE energy.dbo.MIG_571_STG_SKIP;

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @RowCount   = 0;

        TRUNCATE TABLE energy.dbo.MIG_571_STG_BATCH_KEYS;

        IF @AGR_ID IS NULL
        BEGIN
            /* Full: tarihi hizli yol — arithmetic BETWEEN (TOP/ORDER BY heap scan YOK) */
            SET @BatchFrom = @LastBridgeKey + 1;
            SET @BatchTo   = @LastBridgeKey + @BATCH_SIZE;
            IF @BatchTo > @MaxBridgeKey
                SET @BatchTo = @MaxBridgeKey;
            IF @BatchFrom > @BatchTo BREAK;
        END
        ELSE
        BEGIN
            /* AGR veya NO_AGR(-1): key-list (seyrek ID; Last+1 BETWEEN yasak) */
            INSERT INTO energy.dbo.MIG_571_STG_BATCH_KEYS (ACTION_ID)
            SELECT TOP (@BATCH_SIZE) s.ABYS_ACTION_ID
            FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
            WHERE s.ABYS_ACTION_ID > @LastBridgeKey
              AND s.ABYS_ACTION_ID <= 2147483647
              AND (
                    (@AGR_ID = -1 AND s.ABYS_AGREEMENT_ID IS NULL AND s.ABYS_ACCOUNT_ID IS NOT NULL)
                 OR (@AGR_ID > 0 AND s.ABYS_AGREEMENT_ID = @AGR_ID)
                  )
            ORDER BY s.ABYS_ACTION_ID ASC;

            SELECT @BatchFrom = MIN(ACTION_ID),
                   @BatchTo   = MAX(ACTION_ID)
            FROM energy.dbo.MIG_571_STG_BATCH_KEYS;

            IF @BatchTo IS NULL BREAK;
        END

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + CASE WHEN @AGR_ID IS NULL THEN ' | ARITH '
                       WHEN @AGR_ID = -1 THEN ' | NO_AGR keys=' + CAST((SELECT COUNT(*) FROM energy.dbo.MIG_571_STG_BATCH_KEYS) AS VARCHAR(20)) + ' | STG | '
                       ELSE ' | keys=' + CAST((SELECT COUNT(*) FROM energy.dbo.MIG_571_STG_BATCH_KEYS) AS VARCHAR(20)) + ' | STG | '
                  END
                + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC dbo.SP_MIG_INVOICE_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @AGR_ID    = @AGR_ID,
                @RowCount  = @RowCount OUTPUT;

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
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('Batch %d HATA → bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            /* Bisect BETWEEN kullanir — key-list temizle */
            TRUNCATE TABLE energy.dbo.MIG_571_STG_BATCH_KEYS;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_INVOICE_INSERT_ONE
                            @CurID = @BisectFrom,
                            @AGR_ID = @AGR_ID,
                            @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                        BEGIN
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
                        END
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(
                            N'ABYS_ACTION_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    EXEC dbo.SP_MIG_INVOICE_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @AGR_ID    = @AGR_ID,
                        @RowCount  = @BisectRows OUTPUT;

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
                    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVOICE OFF; END TRY BEGIN CATCH END CATCH;
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
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_INVOICE;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_INVOICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_INVOICE
    WHERE ABYS_ID IS NOT NULL
      AND (
            @AGR_ID IS NULL
         OR (@AGR_ID = -1 AND ABYS_AGREEMENT_ID IS NULL)
         OR (@AGR_ID > 0 AND ABYS_AGREEMENT_ID = @AGR_ID)
          );

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
        WHEN @Stopped = 1 AND @AGR_ID IS NOT NULL
            THEN N'Max hata limitine ulasildi. RESUME ile devam edin (AGR: index DISABLE edilmedi).'
        WHEN @Stopped = 1
            THEN N'Max hata limitine ulasildi. RESUME ile devam edin. Index icin 572_INVOICE__post calistirin.'
        WHEN @AGR_ID IS NOT NULL
            THEN N'AGR pilot aktarim bitti (index DISABLE edilmedi).'
        ELSE N'Aktarim bitti. Index icin: EXEC energy.dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG=1;'
    END;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID, @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = @FinishErrorMsg;

    EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY
        @MigrationCode = @MigrationCode, @RunID = @RunID;

    IF @ErrorCount > 0
    BEGIN
        SELECT TOP 10
            l.MIGRATION_CODE,
            l.BATCH_NO,
            l.BRIDGE_FROM,
            l.BRIDGE_TO,
            l.SOURCE_ID,
            l.ERROR_MSG,
            l.LOGGED_AT
        FROM energy.dbo.MIG_BATCH_LOG l
        WHERE l.MIGRATION_CODE = 'LS_005_01_INVOICE'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

 -- Pilot (AGREEMENT_NUMBER = ABYS sozlesme):
 -- EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
 --      @AGR_ID = 197168, @RESUME = 0, @BATCH_SIZE = 1000, @DEBUG = 1;
 -- Full:
 -- EXEC energy.dbo.SP_MIGRATE_LS005_INVOICE
 --      @HARD_RESET = 1, @RESUME = 1, @BATCH_SIZE = 50000, @DEBUG = 1;
 -- EXEC energy.dbo.SP_MIG_INVOICE_POST_INDEXES @DEBUG = 1;


 
--UPDATE inv SET   
--inv.CLIENTREF =ISNULL(agr.CON,agr.FRMID),
--inv.OWNERTYPE= CASE WHEN ISNULL(agr.CON,0) >0 THEN 91 ELSE 90 END ,
--inv.OWNERREF = agr.LREF
--  from LS_005_01_INVOICE  inv 
--  JOIN LS_005_01_AGR agr on inv.ABYS_AGREEMENT_ID = agr.ABYS_ID
-- where   inv.ABYS_AGREEMENT_ID = 197168  and agr.TP2 ='KUL'



--  select *  from LS_005_01_INVOICE  inv  
--  JOIN LS_005_01_PAYTRANS pyt on pyt.INVOICEREF = inv.LREF
--  LEFT JOIN LS_005_01_PAYTRANS pyt2 on pyt2.LREF = pyt.CROSSREF
-- LEFT JOIN LS_005_01_INVOICE  inv2   on pyt2.INVOICEREF = inv2.LREF
--  where   inv.LREF= 17424368



--     select agr.ABYS_ID,inv.ABYS_AGREEMENT_ID  ,inv.CLIENTREF,agr.con,agr.FRMID   from LS_005_01_INVOICE  inv 
--  JOIN LS_005_01_AGR agr on inv.ABYS_AGREEMENT_ID = agr.ABYS_ID
-- where   inv.ABYS_AGREEMENT_ID = 197168  and agr.TP2 ='KUL'



----UPDATE invl SET   
----invl.INVOICEREF = inv.LREF 
----  from LS_005_01_INVLINES invl  
----  JOIN  LS_005_01_INVOICE  inv   on inv.ABYS_ACCOUNT_ID = invl.ABYS_ACCOUNT_ID


--SET NOCOUNT ON;
--SELECT COUNT_BIG(*) AS TGT_NOW FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN WITH (NOLOCK) WHERE ABYS_ID IS NOT NULL;
--SELECT TOP 3 * FROM energy.dbo.MIG_RUN WITH (NOLOCK) WHERE MIGRATION_CODE = 'LS_005_01_INSTALLMENT_PLAN' ORDER BY STARTED_AT DESC;
--SELECT TOP 5 BATCH_NO, BRIDGE_FROM, BRIDGE_TO, STATUS, ROW_COUNT, ELAPSED_MS, LOGGED_AT
--FROM energy.dbo.MIG_BATCH_LOG WITH (NOLOCK)
--WHERE MIGRATION_CODE = 'LS_005_01_INSTALLMENT_PLAN'
--ORDER BY LOGGED_AT DESC;


--select * from LS_005_01_INSTALLMENT_PLAN

--UPDATE invl SET   
--invl.INVOICEREF = inv.LREF 
--  from LS_005_01_INVLINES invl  
--  JOIN  LS_005_01_INVOICE  inv   on inv.ABYS_ACCOUNT_ID = invl.ABYS_ACCOUNT_ID


--  UPDATE inv SET    
--inv.OWNERREF = agr.LREF
--  from LS_005_01_INSTALLMENT_PLAN  inv 
--  JOIN LS_005_01_AGR agr on inv.ABYS_AGREEMENT_ID = agr.ABYS_ID
-- where  agr.TP2 ='KUL'



