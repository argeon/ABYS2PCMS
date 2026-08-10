/* ============================================================
   SCRIPT_ID : INVOICE_SETUP
   SCRIPT_NO : 570
   FILE      : 570_INVOICE__setup.sql
   VERSION   : 3
   ============================================================ */
-- v3: LREF = ABYS_ACTION_ID (kaynak LREF kullanilmaz)
-- v2: kaynak LREF eklendi; EXPLAIN kalkti; tip/uzunluk guncellemeleri
-- ============================================================
-- izgazMGR.dbo.LS_INVOICE
--   → energy.dbo.LS_005_01_INVOICE
--
-- Pass 1 dump-style:
--   - ABYS_* bridge kolonlari TABLO SONUNA eklenir
--   - FK / wire YOK
--   - Unique / NC index YOK (572_INVOICE__post sonrasi)
--   - LREF = ABYS_ACTION_ID (IDENTITY_INSERT), ABYS_ID = ABYS_ACTION_ID
--   - USERID: FN_MIG_MAP_USER_USERID (+10000) — migrate'de
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('energy.dbo.LS_005_01_INVOICE', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_005_01_INVOICE bulunamadi. Once hedef tabloyu olusturun.', 16, 1);
    RETURN;
END
GO

-- ------------------------------------------------------------
-- Kaynak uzunluklari > hedef: truncation onleme (idempotent)
-- nvarchar(4000) kaynak alanlari hedef sinirinda LEFT ile kesilir.
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'FICHENO'
      AND (
            TYPE_NAME(c.user_type_id) NOT IN ('varchar', 'nvarchar')
         OR (c.max_length > 0 AND c.max_length < 45)
      )
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN FICHENO VARCHAR(45) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'CUSTBNK_ACC'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 40))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN CUSTBNK_ACC NVARCHAR(20) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'BANK_RECORD_REF'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 100))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN BANK_RECORD_REF NVARCHAR(50) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'LOGO_FICHENO'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 200))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN LOGO_FICHENO NVARCHAR(100) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'CCCONFIRMCODE'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 100))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN CCCONFIRMCODE NVARCHAR(50) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'SuccessCode'
      AND (TYPE_NAME(c.user_type_id) NOT IN ('varchar', 'nvarchar') OR (c.max_length > 0 AND c.max_length < 100))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN SuccessCode VARCHAR(100) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'InvoiceReturnMessage'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 800))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN InvoiceReturnMessage NVARCHAR(400) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND c.name = 'DESCRIPTION'
      AND (TYPE_NAME(c.user_type_id) <> 'nvarchar' OR (c.max_length > 0 AND c.max_length < 800))
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ALTER COLUMN DESCRIPTION NVARCHAR(400) NULL;
GO

-- ------------------------------------------------------------
-- ABYS bridge kolonlari — TABLO SONUNA (idempotent)
-- Index / FK burada OLUSTURULMAZ.
-- ------------------------------------------------------------
DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(300) NOT NULL);

INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 (N'ABYS_ID',                      N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',              N'BIGINT NULL'),
 (N'ABYS_ACTION_TYPE_ID',          N'BIGINT NULL'),
 (N'ABYS_ACCRUE_TYPE_ID',          N'SMALLINT NULL'),
 (N'ABYS_REGISTER_ID',             N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',            N'BIGINT NULL'),
 (N'ABYS_INSTALLATION_ID',         N'BIGINT NULL'),
 (N'ABYS_METER_ID',                N'BIGINT NULL'),
 (N'ABYS_AREA_ID',                 N'BIGINT NULL'),
 (N'ABYS_PROJECT_ID',              N'BIGINT NULL'),
 (N'ABYS_TARIFF_TYPE_ID',          N'BIGINT NULL'),
 (N'ABYS_SKB_TARIFF_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_SUBSCRIBER_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_READING_DATE',            N'DATETIME2(0) NULL'),
 (N'ABYS_IS_E_BILL',               N'SMALLINT NULL'),
 (N'ABYS_IS_FPS',                  N'SMALLINT NULL'),
 (N'ABYS_DO_DISCHARGE',            N'SMALLINT NULL'),
 (N'ABYS_INSTALLMENT_ID',          N'BIGINT NULL'),
 (N'ABYS_GROUP_ACCOUNT_ID',        N'BIGINT NULL'),
 (N'ABYS_BILL_TYPE_ID',            N'SMALLINT NULL'),
 (N'ABYS_BILL_SERIAL',             N'NVARCHAR(5) NULL'),
 (N'ABYS_BILL_ORDER_NUMBER',       N'DECIMAL(20,0) NULL'),
 (N'ABYS_BILL_NUMBER',             N'DECIMAL(20,0) NULL'),
 (N'ABYS_CONSUMPTION',             N'DECIMAL(16,6) NULL'),
 (N'ABYS_M3',                      N'DECIMAL(16,6) NULL'),
 (N'ABYS_KWH',                     N'DECIMAL(13,3) NULL'),
 (N'ABYS_CUSTOMER_BILL_TYPE',      N'SMALLINT NULL'),
 (N'ABYS_REF_DEPOSIT_ACCOUNT_ID',  N'BIGINT NULL'),
 (N'ABYS_REF_DEP_ACC_ACTION_ID',   N'BIGINT NULL'),
 (N'ABYS_POOL_ID',                 N'BIGINT NULL'),
 (N'ABYS_CREATED_USER_ID',         N'BIGINT NULL'),
 (N'ABYS_UPDATED_USER_ID',         N'BIGINT NULL'),
 (N'ABYS_VERSION',                 N'BIGINT NULL'),
 (N'ABYS_TRANSACTION_TYPE_ID',     N'SMALLINT NULL'),
 (N'ABYS_SOURCE_ACCRUE_TYPE_ID',   N'SMALLINT NULL'),
 (N'ABYS_ADDUSER',                 N'BIGINT NULL'),
 (N'ABYS_UPDUSER',                 N'BIGINT NULL'),
 (N'ABYS_CANCEL_USER_ID',          N'BIGINT NULL');

SELECT @Sql = @Sql + N'
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(''energy.dbo.LS_005_01_INVOICE'')
      AND name = ''' + COL_NAME + N'''
)
    ALTER TABLE energy.dbo.LS_005_01_INVOICE ADD ' + COL_NAME + N' ' + COL_DEF + N';'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;
GO

-- ------------------------------------------------------------
-- Yukleme oncesi: outbound FK + NC index kaldir/disable
-- (PK clustered kalir. Index/FK 572 post'ta kurulur.)
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_PREPARE_LOAD
    @DEBUG BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Sql NVARCHAR(MAX) = N'';
    DECLARE @Msg NVARCHAR(500);

    -- 1) Bu tablodan cikan FK'leri dus
    SELECT @Sql = @Sql + N'
ALTER TABLE energy.dbo.LS_005_01_INVOICE DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE');

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('INVOICE outbound FK drop...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    -- 2) Bu tabloya gelen FK'leri dus (child → INVOICE)
    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id))
        + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
        + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';'
    FROM sys.foreign_keys fk
    WHERE fk.referenced_object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE');

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('INVOICE inbound FK drop...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    -- 3) NC index disable (clustered PK haric)
    SET @Sql = N'';
    SELECT @Sql = @Sql + N'
ALTER INDEX ' + QUOTENAME(i.name) + N' ON energy.dbo.LS_005_01_INVOICE DISABLE;'
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
      AND i.type_desc = 'NONCLUSTERED'
      AND i.is_disabled = 0
      AND i.name IS NOT NULL;

    IF LEN(@Sql) > 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('INVOICE NC index DISABLE...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @Sql;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'SP_MIG_INVOICE_PREPARE_LOAD OK (FK yok, NC index disabled)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

-- ------------------------------------------------------------
-- Validate
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.LS_INVOICE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.LS_INVOICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),
            ('ABYS_ACTION_ID'),('ABYS_ACCOUNT_ID'),('ABYS_ACTION_TYPE_ID'),('ABYS_ACCRUE_TYPE_ID'),
            ('ABYS_REGISTER_ID'),('ABYS_AGREEMENT_ID'),('ABYS_INSTALLATION_ID'),('ABYS_METER_ID'),
            ('ABYS_AREA_ID'),('ABYS_PROJECT_ID'),('ABYS_TARIFF_TYPE_ID'),('ABYS_SKB_TARIFF_TYPE_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'),('ABYS_READING_DATE'),('ABYS_IS_E_BILL'),('ABYS_IS_FPS'),
            ('ABYS_DO_DISCHARGE'),('ABYS_INSTALLMENT_ID'),('ABYS_GROUP_ACCOUNT_ID'),
            ('ABYS_BILL_TYPE_ID'),('ABYS_BILL_SERIAL'),('ABYS_BILL_ORDER_NUMBER'),('ABYS_BILL_NUMBER'),
            ('ABYS_CONSUMPTION'),('ABYS_M3'),('ABYS_KWH'),('ABYS_CUSTOMER_BILL_TYPE'),
            ('ABYS_REF_DEPOSIT_ACCOUNT_ID'),('ABYS_REF_DEP_ACC_ACTION_ID'),('ABYS_POOL_ID'),
            ('ABYS_CREATED_USER_ID'),('ABYS_UPDATED_USER_ID'),('ABYS_VERSION'),
            ('TRNSACTION_TYPE_ID'),('IOCODE'),('FICHENO'),('DATE_'),('DUEDATE'),('TYPE'),
            ('CLIENTREF'),('TLTOTAL'),('CURID'),('CURTOTAL'),('ACCRUE_TYPE_ID'),
            ('CANCELED'),('OWNERREF'),('OWNERTYPE'),('LOGOREF'),('TAX'),('DV'),('GRANDTOTAL'),
            ('PRINTCOUNT'),('PAYABLETOTAL'),('READ_TRANSREF'),('INTERESTRATE'),
            ('GAS_OPEN_FEE'),('DETACH_ATTACH_FEE'),('TEST_FEE'),('SPEC_SERV_FEE'),
            ('FIXED_FEE'),('EXPEND_FEE'),('DEFAULT_FINE'),('DEFAULT_FINETAX'),
            ('FITNO'),('CHEQUEREF'),('ADDDATE'),('ADDUSER'),('UPDDATE'),('UPDUSER'),
            ('LAWDETAILREF'),('BANKREF'),('CUSTBNK_ACC'),('BANK_STAT'),('BANK_CANCELLED'),
            ('BANK_RECORD_REF'),('ILLEGAL_USE_FEE'),('LOGO_FIRMNR'),('LOGO_FICHEREF'),
            ('LOGO_FICHENO'),('DISCOUNT_ADDITION'),('RETURN_SOURCE_INVREF'),('RETURN_TARGET_INVREF'),
            ('CLOSED'),('CCCONFIRMCODE'),('BANKACCREF'),('XTYPE'),('BN_TYPE'),('OLOC_ID'),
            ('OLREF'),('LASTPAIDDATE'),('IS_DUPLICATE_PAYMENT'),('PRJ_INV_REF'),('IS_LAW'),
            ('ISSENDINVOICE'),('ISAPPROVEINVOICE'),('SUCCESSCODE'),('ETTN'),('ARCHIVENO'),
            ('INVPRENAME'),('ISBUYUKSANAYIFATURA'),('INVOICERETURNMESSAGE'),
            ('CANCELEARCHIVEINVOICEISSEND'),('AMOUNT'),
            ('ARCHIVE_SEND_STATUS'),('ARCHIVE_MAIL_SEND_STATUS'),
            ('ARCHIVE_SEND_DATE'),('ARCHIVE_MAIL_SEND_DATE'),('PERIOD'),
            ('HAS_DISCOUNT'),('DISCOUNT_AMOUNT'),('DISCOUNT_REMAIN_AMOUNT'),('DISCOUNT_USED_AMOUNT'),
            ('CANCEL_DATE'),('CANCEL_REASON_ID'),('CANCEL_USER_ID'),('DESCRIPTION'),
            ('INSTALLMENT_PLAN_REF'),('TAX_TEVKIFAT'),('QMIN'),('QMAX'),
            ('ARCHIVE_CANCEL_DATE'),('ARCHIVE_LAST_PROCESS_DATE')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'LS_INVOICE' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_INVOICE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_INVOICE kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_VALIDATE_TARGET
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.LS_005_01_INVOICE', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('energy.dbo.LS_005_01_INVOICE bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('LREF'),('IOCODE'),('FICHENO'),('DATE_'),('DUEDATE'),('TYPE'),('CLIENTREF'),
            ('TLTOTAL'),('CURID'),('CURTOTAL'),('EXPLAIN'),('CANCELED'),('OWNERREF'),('OWNERTYPE'),
            ('LOGOREF'),('TAX'),('DV'),('GRANDTOTAL'),('PRINTCOUNT'),('PAYABLETOTAL'),
            ('READ_TRANSREF'),('INTERESTRATE'),
            ('gas_open_fee'),('detach_attach_fee'),('test_fee'),('spec_serv_fee'),
            ('fixed_fee'),('expend_fee'),('DEFAULT_FINE'),('DEFAULT_FINETAX'),
            ('FITNO'),('CHEQUEREF'),('ADDDATE'),('ADDUSER'),('UPDDATE'),('UPDUSER'),
            ('LAWDETAILREF'),('BANKREF'),('CUSTBNK_ACC'),('BANK_STAT'),('BANK_CANCELLED'),
            ('BANK_RECORD_REF'),('illegal_use_fee'),('LOGO_FIRMNR'),('LOGO_FICHEREF'),
            ('LOGO_FICHENO'),('discount_addition'),('RETURN_SOURCE_INVREF'),('RETURN_TARGET_INVREF'),
            ('CLOSED'),('CCCONFIRMCODE'),('BANKACCREF'),('XTYPE'),('BN_TYPE'),('OLOC_ID'),
            ('OLREF'),('LASTPAIDDATE'),('IS_DUPLICATE_PAYMENT'),('PRJ_INV_REF'),('IS_LAW'),
            ('IsSendInvoice'),('IsApproveInvoice'),('SuccessCode'),('ETTN'),('ArchiveNo'),
            ('InvPreName'),('IsBuyukSanayiFatura'),('InvoiceReturnMessage'),
            ('CancelEArchiveInvoiceIsSend'),('AMOUNT'),
            ('ARCHIVE_SEND_STATUS'),('ARCHIVE_MAIL_SEND_STATUS'),
            ('ARCHIVE_SEND_DATE'),('ARCHIVE_MAIL_SEND_DATE'),('PERIOD'),
            ('HAS_DISCOUNT'),('DISCOUNT_AMOUNT'),('DISCOUNT_REMAIN_AMOUNT'),('DISCOUNT_USED_AMOUNT'),
            ('CANCEL_DATE'),('CANCEL_REASON_ID'),('CANCEL_DESCRIPTION'),('CANCEL_USER_ID'),
            ('DESCRIPTION'),('INSTALLMENT_PLAN_REF'),('TAX_TEVKIFAT'),('Qmin'),('Qmax'),
            ('ARCHIVE_CANCEL_DATE'),('ARCHIVE_LAST_PROCESS_DATE'),
            ('ABYS_ID'),('ABYS_ACCOUNT_ID'),('ABYS_ACTION_TYPE_ID'),('ABYS_ACCRUE_TYPE_ID'),
            ('ABYS_REGISTER_ID'),('ABYS_AGREEMENT_ID'),('ABYS_INSTALLATION_ID'),('ABYS_METER_ID'),
            ('ABYS_AREA_ID'),('ABYS_PROJECT_ID'),('ABYS_TARIFF_TYPE_ID'),('ABYS_SKB_TARIFF_TYPE_ID'),
            ('ABYS_SUBSCRIBER_TYPE_ID'),('ABYS_READING_DATE'),('ABYS_IS_E_BILL'),('ABYS_IS_FPS'),
            ('ABYS_DO_DISCHARGE'),('ABYS_INSTALLMENT_ID'),('ABYS_GROUP_ACCOUNT_ID'),
            ('ABYS_BILL_TYPE_ID'),('ABYS_BILL_SERIAL'),('ABYS_BILL_ORDER_NUMBER'),('ABYS_BILL_NUMBER'),
            ('ABYS_CONSUMPTION'),('ABYS_M3'),('ABYS_KWH'),('ABYS_CUSTOMER_BILL_TYPE'),
            ('ABYS_REF_DEPOSIT_ACCOUNT_ID'),('ABYS_REF_DEP_ACC_ACTION_ID'),('ABYS_POOL_ID'),
            ('ABYS_CREATED_USER_ID'),('ABYS_UPDATED_USER_ID'),('ABYS_VERSION'),
            ('ABYS_TRANSACTION_TYPE_ID'),('ABYS_SOURCE_ACCRUE_TYPE_ID'),
            ('ABYS_ADDUSER'),('ABYS_UPDUSER'),('ABYS_CANCEL_USER_ID')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM energy.sys.columns c
        WHERE c.object_id = OBJECT_ID('energy.dbo.LS_005_01_INVOICE')
          AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'LS_005_01_INVOICE eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'LS_005_01_INVOICE hedef dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVOICE_VALIDATE_ALL
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rc INT = 0;

    EXEC @Rc = dbo.SP_MIG_INVOICE_VALIDATE_SOURCE @RaiseOnMissing = @RaiseOnMissing;
    IF @Rc <> 0 RETURN @Rc;

    EXEC @Rc = dbo.SP_MIG_INVOICE_VALIDATE_TARGET @RaiseOnMissing = @RaiseOnMissing;
    RETURN @Rc;
END
GO

EXEC dbo.SP_MIG_INVOICE_VALIDATE_ALL @RaiseOnMissing = 0;
GO

PRINT '570_INVOICE__setup OK (FK/index yok — post: 572)';
GO
