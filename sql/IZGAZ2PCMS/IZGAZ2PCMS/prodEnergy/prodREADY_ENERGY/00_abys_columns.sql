/* ============================================================
   prodREADY_ENERGY / 00_abys_columns
   energy hedef tablolarda 590/597 (+571/581/575) icin ABYS_* bridge
   kolonlarini idempotent olusturur. Cutover basinda calistir.

   Sira: 00_log_setup → 00_map_tables → 00_abys_columns → 01_linenr_smallint
   ============================================================ */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
RAISERROR('%s | E00A | INFO | ABYS bridge kolon kontrolu basladi', 0, 1, @Ts) WITH NOWAIT;

IF OBJECT_ID('dbo.LS_005_01_INVOICE', 'U') IS NULL
   OR OBJECT_ID('dbo.LS_005_01_INVLINES', 'U') IS NULL
   OR OBJECT_ID('dbo.LS_005_01_PAYTRANS', 'U') IS NULL
BEGIN
    RAISERROR('energy LS_005_01_INVOICE / INVLINES / PAYTRANS yok — once PCMS tablolari olmali.', 16, 1);
    RETURN;
END

/* ------------------------------------------------------------
   Helper: eksik kolon ekle + log (#Added)
   ------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Added') IS NOT NULL DROP TABLE #Added;
CREATE TABLE #Added (TBL SYSNAME NOT NULL, COL SYSNAME NOT NULL);

DECLARE @Sql NVARCHAR(MAX) = N'';
DECLARE @Tbl SYSNAME;
DECLARE @Cols TABLE (COL_NAME SYSNAME NOT NULL, COL_DEF NVARCHAR(300) NOT NULL);

/* ======================== INVOICE ======================== */
DELETE FROM @Cols;
INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 /* 590/597 zorunlu */
 (N'ABYS_ID',                  N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',          N'BIGINT NULL'),
 (N'ABYS_ACTION_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',        N'BIGINT NULL'),
 /* 571 bridge (guvenli genis set) */
 (N'ABYS_ACCRUE_TYPE_ID',      N'SMALLINT NULL'),
 (N'ABYS_REGISTER_ID',         N'BIGINT NULL'),
 (N'ABYS_INSTALLATION_ID',     N'BIGINT NULL'),
 (N'ABYS_METER_ID',            N'BIGINT NULL'),
 (N'ABYS_AREA_ID',             N'BIGINT NULL'),
 (N'ABYS_PROJECT_ID',          N'BIGINT NULL'),
 (N'ABYS_TARIFF_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_SKB_TARIFF_TYPE_ID',  N'BIGINT NULL'),
 (N'ABYS_SUBSCRIBER_TYPE_ID',  N'BIGINT NULL'),
 (N'ABYS_READING_DATE',        N'DATETIME2(0) NULL'),
 (N'ABYS_IS_E_BILL',           N'SMALLINT NULL'),
 (N'ABYS_IS_FPS',              N'SMALLINT NULL'),
 (N'ABYS_DO_DISCHARGE',        N'SMALLINT NULL'),
 (N'ABYS_INSTALLMENT_ID',      N'BIGINT NULL'),
 (N'ABYS_GROUP_ACCOUNT_ID',    N'BIGINT NULL'),
 (N'ABYS_BILL_TYPE_ID',        N'SMALLINT NULL'),
 (N'ABYS_BILL_SERIAL',         N'NVARCHAR(5) NULL'),
 (N'ABYS_BILL_ORDER_NUMBER',   N'DECIMAL(20,0) NULL'),
 (N'ABYS_BILL_NUMBER',         N'DECIMAL(20,0) NULL'),
 (N'ABYS_CONSUMPTION',         N'DECIMAL(16,6) NULL'),
 (N'ABYS_M3',                  N'DECIMAL(16,6) NULL'),
 (N'ABYS_KWH',                 N'DECIMAL(13,3) NULL'),
 (N'ABYS_CUSTOMER_BILL_TYPE',  N'SMALLINT NULL'),
 (N'ABYS_REF_DEPOSIT_ACCOUNT_ID', N'BIGINT NULL'),
 (N'ABYS_REF_DEP_ACC_ACTION_ID',  N'BIGINT NULL'),
 (N'ABYS_POOL_ID',             N'BIGINT NULL'),
 (N'ABYS_CREATED_USER_ID',     N'BIGINT NULL'),
 (N'ABYS_UPDATED_USER_ID',     N'BIGINT NULL'),
 (N'ABYS_VERSION',             N'BIGINT NULL'),
 (N'ABYS_TRANSACTION_TYPE_ID', N'SMALLINT NULL'),
 (N'ABYS_SOURCE_ACCRUE_TYPE_ID', N'SMALLINT NULL'),
 (N'ABYS_ADDUSER',             N'BIGINT NULL'),
 (N'ABYS_UPDUSER',             N'BIGINT NULL'),
 (N'ABYS_CANCEL_USER_ID',      N'BIGINT NULL');

SET @Tbl = N'LS_005_01_INVOICE';
SET @Sql = N'';
SELECT @Sql = @Sql + N'
IF COL_LENGTH(''dbo.' + @Tbl + N''', ''' + COL_NAME + N''') IS NULL
BEGIN
    ALTER TABLE dbo.' + @Tbl + N' ADD ' + QUOTENAME(COL_NAME) + N' ' + COL_DEF + N';
    INSERT INTO #Added(TBL, COL) VALUES (N''' + @Tbl + N''', N''' + COL_NAME + N''');
END;'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

/* ======================== INVLINES ======================== */
DELETE FROM @Cols;
INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 /* 590 zorunlu */
 (N'ABYS_ID',                  N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',        N'BIGINT NULL'),
 (N'ABYS_INCOME_ROW_ID',       N'BIGINT NULL'),
 (N'ABYS_INCOME_ID',           N'BIGINT NULL'),
 (N'ABYS_LINENR_SRC',          N'SMALLINT NULL'),
 /* 581 bridge */
 (N'ABYS_ACTION_ID',           N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',          N'BIGINT NULL'),
 (N'ABYS_REGISTER_ID',         N'BIGINT NULL'),
 (N'ABYS_ACTION_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_ACCRUE_TYPE_ID',      N'SMALLINT NULL'),
 (N'ABYS_IS_DISCOUNT',         N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_VAT_INCOME',       N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_DEPOSIT',          N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_OVERDUE_INCOME',   N'DECIMAL(22,0) NULL'),
 (N'ABYS_IS_LEGAL_FEE',        N'DECIMAL(22,0) NULL'),
 (N'ABYS_INCOME_CODE',         N'NVARCHAR(10) NULL'),
 (N'ABYS_AMOUNT_RAW',          N'DECIMAL(15,2) NULL'),
 (N'ABYS_STATUS',              N'SMALLINT NULL'),
 (N'ABYS_QUANTITY',            N'DECIMAL(15,3) NULL'),
 (N'ABYS_UNIT_PRICE',          N'DECIMAL(19,8) NULL'),
 (N'ABYS_AMOUNT1',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT2',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT3',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT4',             N'DECIMAL(15,2) NULL'),
 (N'ABYS_AMOUNT5',             N'DECIMAL(15,2) NULL');

SET @Tbl = N'LS_005_01_INVLINES';
SET @Sql = N'';
SELECT @Sql = @Sql + N'
IF COL_LENGTH(''dbo.' + @Tbl + N''', ''' + COL_NAME + N''') IS NULL
BEGIN
    ALTER TABLE dbo.' + @Tbl + N' ADD ' + QUOTENAME(COL_NAME) + N' ' + COL_DEF + N';
    INSERT INTO #Added(TBL, COL) VALUES (N''' + @Tbl + N''', N''' + COL_NAME + N''');
END;'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

/* ======================== PAYTRANS ======================== */
DELETE FROM @Cols;
INSERT INTO @Cols (COL_NAME, COL_DEF) VALUES
 /* 590/597 zorunlu */
 (N'ABYS_ID',                  N'BIGINT NULL'),
 (N'ABYS_ACCOUNT_ID',          N'BIGINT NULL'),
 (N'ABYS_AGREEMENT_ID',        N'BIGINT NULL'),
 (N'ABYS_INVOICE_LREF',        N'INT NULL'),
 /* 575 bridge */
 (N'ABYS_ACTION_TYPE_ID',      N'BIGINT NULL'),
 (N'ABYS_ACCRUE_TYPE_ID',      N'SMALLINT NULL'),
 (N'ABYS_REGISTER_ID',         N'BIGINT NULL'),
 (N'ABYS_ADDUSER',             N'BIGINT NULL'),
 (N'ABYS_UPDUSER',             N'BIGINT NULL');

SET @Tbl = N'LS_005_01_PAYTRANS';
SET @Sql = N'';
SELECT @Sql = @Sql + N'
IF COL_LENGTH(''dbo.' + @Tbl + N''', ''' + COL_NAME + N''') IS NULL
BEGIN
    ALTER TABLE dbo.' + @Tbl + N' ADD ' + QUOTENAME(COL_NAME) + N' ' + COL_DEF + N';
    INSERT INTO #Added(TBL, COL) VALUES (N''' + @Tbl + N''', N''' + COL_NAME + N''');
END;'
FROM @Cols;

IF LEN(@Sql) > 0
    EXEC sp_executesql @Sql;

/* ------------------------------------------------------------
   Log + zorunlu kolon dogrulama
   ------------------------------------------------------------ */
DECLARE @N INT = (SELECT COUNT(*) FROM #Added);
DECLARE @Msg NVARCHAR(400);

IF @N = 0
BEGIN
    SET @Msg = CONVERT(VARCHAR(30), SYSDATETIME(), 121)
             + N' | E00A | INFO | ABYS kolonlari zaten mevcut (ekleme yok)';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END
ELSE
BEGIN
    SET @Msg = CONVERT(VARCHAR(30), SYSDATETIME(), 121)
             + N' | E00A | INFO | ABYS kolon eklendi cnt=' + CAST(@N AS VARCHAR(20));
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

    SELECT TBL, COL
    FROM #Added
    ORDER BY TBL, COL;
END

/* 590/597 hard gereksinim */
DECLARE @Missing NVARCHAR(MAX) = N'';

IF COL_LENGTH('dbo.LS_005_01_INVOICE', 'ABYS_ID') IS NULL
    SET @Missing += N'INVOICE.ABYS_ID; ';
IF COL_LENGTH('dbo.LS_005_01_INVOICE', 'ABYS_AGREEMENT_ID') IS NULL
    SET @Missing += N'INVOICE.ABYS_AGREEMENT_ID; ';
IF COL_LENGTH('dbo.LS_005_01_INVOICE', 'ABYS_ACCOUNT_ID') IS NULL
    SET @Missing += N'INVOICE.ABYS_ACCOUNT_ID; ';
IF COL_LENGTH('dbo.LS_005_01_INVOICE', 'ABYS_ACTION_TYPE_ID') IS NULL
    SET @Missing += N'INVOICE.ABYS_ACTION_TYPE_ID; ';

IF COL_LENGTH('dbo.LS_005_01_INVLINES', 'ABYS_ID') IS NULL
    SET @Missing += N'INVLINES.ABYS_ID; ';
IF COL_LENGTH('dbo.LS_005_01_INVLINES', 'ABYS_AGREEMENT_ID') IS NULL
    SET @Missing += N'INVLINES.ABYS_AGREEMENT_ID; ';

IF COL_LENGTH('dbo.LS_005_01_PAYTRANS', 'ABYS_ID') IS NULL
    SET @Missing += N'PAYTRANS.ABYS_ID; ';
IF COL_LENGTH('dbo.LS_005_01_PAYTRANS', 'ABYS_AGREEMENT_ID') IS NULL
    SET @Missing += N'PAYTRANS.ABYS_AGREEMENT_ID; ';
IF COL_LENGTH('dbo.LS_005_01_PAYTRANS', 'ABYS_ACCOUNT_ID') IS NULL
    SET @Missing += N'PAYTRANS.ABYS_ACCOUNT_ID; ';
IF COL_LENGTH('dbo.LS_005_01_PAYTRANS', 'ABYS_INVOICE_LREF') IS NULL
    SET @Missing += N'PAYTRANS.ABYS_INVOICE_LREF; ';

IF LEN(@Missing) > 0
BEGIN
    SET @Msg = N'ABYS zorunlu kolon eksik kaldi: ' + @Missing;
    RAISERROR('%s', 16, 1, @Msg);
    RETURN;
END

SET @Msg = CONVERT(VARCHAR(30), SYSDATETIME(), 121)
         + N' | E00A | OK | INVOICE+INVLINES+PAYTRANS ABYS bridge hazir';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

IF OBJECT_ID('tempdb..#Added') IS NOT NULL DROP TABLE #Added;
GO
