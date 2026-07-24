/* ============================================================
   SCRIPT_ID : INVLINES_PILOT_AGR
   SCRIPT_NO : 588
   FILE      : 588_INVLINES__pilot_agr.sql
   VERSION   : 2
   ============================================================ */
-- v2: CLEAN = kaynak satir LREF ile PK delete (INVOICEREF full scan YOK)
-- Pilot AGR INVLINES aktarimi (Adim 2 dump → energy)
-- Full 581 KEYSET yerine: sozlesme bazli (~1K-10K satir) tek/az batch
-- Onkosul: 580 setup, 569 resolve, izgazMGR.LS_INVLINES, energy INVOICE (571)
-- ============================================================ */
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_CLEAN_BY_AGR
    @AGRID        BIGINT,
    @DELETE_BATCH INT = 20000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Deleted   INT,
        @TotalIl   BIGINT = 0,
        @KeyCnt    INT,
        @Msg       NVARCHAR(500),
        @BatchNo   INT = 0;

    IF @AGRID IS NULL
    BEGIN
        RAISERROR('SP_MIG_INVLINES_CLEAN_BY_AGR: @AGRID zorunlu.', 16, 1);
        RETURN;
    END

    -- Kaynak satir LREF listesi (kucuk) → energy PK seek ile sil
    -- INVOICEREF = @CurInv KULLANMA (index yoksa full scan x 259)
    IF OBJECT_ID('tempdb..#LINE_KEYS') IS NOT NULL DROP TABLE #LINE_KEYS;
    CREATE TABLE #LINE_KEYS (LREF INT NOT NULL PRIMARY KEY);

    INSERT INTO #LINE_KEYS (LREF)
    SELECT DISTINCT CAST(s.LREF AS INT)
    FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
    WHERE s.LREF BETWEEN 1 AND 2147483647
      AND (
            s.ABYS_AGREEMENT_ID = @AGRID
         OR s.INVOICEREF IN (
                SELECT CAST(i.ABYS_ACTION_ID AS INT)
                FROM izgazMGR.dbo.LS_INVOICE i WITH (NOLOCK)
                WHERE i.ABYS_AGREEMENT_ID = @AGRID
            )
          );

    SELECT @KeyCnt = COUNT(*) FROM #LINE_KEYS;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'INVLINES CLEAN v2 | AGR=' + CAST(@AGRID AS VARCHAR(20))
            + N' LineKeys=' + CAST(@KeyCnt AS VARCHAR(20))
            + N' (PK delete, INVOICEREF scan YOK)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @KeyCnt = 0
    BEGIN
        DROP TABLE #LINE_KEYS;
        RETURN;
    END

    -- Sadece energy'de gercekten var olan anahtarlari sil (PK)
    WHILE 1 = 1
    BEGIN
        SET @BatchNo += 1;

        DELETE TOP (@DELETE_BATCH) il
        FROM energy.dbo.LS_005_01_INVLINES il WITH (ROWLOCK)
        INNER JOIN #LINE_KEYS k ON k.LREF = il.LREF
        WHERE il.ABYS_ID IS NOT NULL
        OPTION (MAXDOP 1);

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        SET @TotalIl += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'INVLINES PK delete batch ' + CAST(@BatchNo AS VARCHAR(10))
                + N' +' + CAST(@Deleted AS VARCHAR(20))
                + N' toplam=' + CAST(@TotalIl AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    DECLARE @MaxLref INT;
    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVLINES;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVLINES', RESEED, @MaxLref) WITH NO_INFOMSGS;

    DROP TABLE #LINE_KEYS;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'INVLINES CLEAN v2 tamam silinen=' + CAST(@TotalIl AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_INVLINES_AGR
    @AGR_ID      BIGINT,
    @CLEAN       BIT = 1,
    @BATCH_SIZE  INT = 5000,
    @DEBUG       BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @AgrLref     INT,
        @AbysAgrId   BIGINT,
        @AgrNumber   VARCHAR(50),
        @SrcCnt      BIGINT,
        @Inserted    BIGINT = 0,
        @BatchFrom   BIGINT,
        @BatchTo     BIGINT,
        @LastKey     BIGINT = 0,
        @MaxKey      BIGINT,
        @RowCount    INT,
        @Msg         NVARCHAR(500),
        @BatchNo     INT = 0;

    IF @AGR_ID IS NULL
    BEGIN
        RAISERROR('@AGR_ID zorunlu (AGREEMENT_NUMBER).', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('izgazMGR.dbo.LS_INVLINES', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.dbo.LS_INVLINES yok.', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('energy.dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER', 'P') IS NULL
    BEGIN
        RAISERROR('569 deploy edin (SP_MIG_RESOLVE_AGR_BY_NUMBER).', 16, 1);
        RETURN;
    END

    EXEC dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER
        @AGRID     = @AGR_ID,
        @AgrLref   = @AgrLref   OUTPUT,
        @AbysAgrId = @AbysAgrId OUTPUT,
        @AgrNumber = @AgrNumber OUTPUT;

    IF @AgrLref IS NULL
    BEGIN
        SET @Msg = N'LS_005_01_AGR bulunamadi. AGREEMENT_NUMBER=' + CAST(@AGR_ID AS VARCHAR(20));
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    IF @CLEAN = 1
        EXEC dbo.SP_MIG_INVLINES_CLEAN_BY_AGR
            @AGRID = @AGR_ID, @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;

    IF OBJECT_ID('tempdb..#SRC_IL') IS NOT NULL DROP TABLE #SRC_IL;
    CREATE TABLE #SRC_IL (LREF BIGINT NOT NULL PRIMARY KEY);

    INSERT INTO #SRC_IL (LREF)
    SELECT DISTINCT CAST(s.LREF AS BIGINT)
    FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
    WHERE s.LREF BETWEEN 1 AND 2147483647
      AND (
            s.ABYS_AGREEMENT_ID = @AGR_ID
         OR s.INVOICEREF IN (
                SELECT CAST(i.ABYS_ACTION_ID AS INT)
                FROM izgazMGR.dbo.LS_INVOICE i WITH (NOLOCK)
                WHERE i.ABYS_AGREEMENT_ID = @AGR_ID
            )
          );

    SELECT @SrcCnt = COUNT(*), @MaxKey = MAX(LREF) FROM #SRC_IL;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'INVLINES AGR migrate | AGR=' + ISNULL(@AgrNumber, '?')
            + N' Kaynak=' + CAST(@SrcCnt AS VARCHAR(20))
            + N' MaxLREF=' + ISNULL(CAST(@MaxKey AS VARCHAR(20)), '0');
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @SrcCnt = 0
    BEGIN
        RAISERROR('Kaynak INVLINES bos (AGR).', 16, 1);
        DROP TABLE #SRC_IL;
        RETURN;
    END

    WHILE @LastKey < ISNULL(@MaxKey, 0)
    BEGIN
        SET @BatchNo += 1;

        SELECT @BatchFrom = MIN(LREF), @BatchTo = MAX(LREF)
        FROM (
            SELECT TOP (@BATCH_SIZE) LREF
            FROM #SRC_IL
            WHERE LREF > @LastKey
            ORDER BY LREF
        ) x;

        IF @BatchTo IS NULL BREAK;

        BEGIN TRY
            SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES ON;

            INSERT INTO energy.dbo.LS_005_01_INVLINES (
                LREF, INVOICEREF, CLIENTREF, DATE_, [TYPE], LINENR,
                TLTOTAL, CURID, CURRATE, CURTOTAL, FIRSTREAD, LASTREAD,
                TRANSTYPE, CANCELED, TAX, GRANDTOTAL, LINEEXP, LINETYPE,
                DV, FITNO, CNTREF, LOGO_FIRMNR, LOGO_FICHEREF, LOGO_FICHENO,
                XTYPE, UNITPRICE, SPEREF, AMOUNT,
                FIRST_DATE, LAST_DATE, [DAY],
                ABYS_ID, ABYS_INCOME_ROW_ID, ABYS_INCOME_ID, ABYS_ACTION_ID, ABYS_ACCOUNT_ID,
                ABYS_REGISTER_ID, ABYS_AGREEMENT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID,
                ABYS_IS_DISCOUNT, ABYS_IS_VAT_INCOME, ABYS_IS_DEPOSIT,
                ABYS_IS_OVERDUE_INCOME, ABYS_IS_LEGAL_FEE, ABYS_INCOME_CODE,
                ABYS_AMOUNT_RAW, ABYS_STATUS, ABYS_QUANTITY, ABYS_UNIT_PRICE,
                ABYS_AMOUNT1, ABYS_AMOUNT2, ABYS_AMOUNT3, ABYS_AMOUNT4, ABYS_AMOUNT5
            )
            SELECT
                CAST(s.LREF AS INT),
                CAST(s.INVOICEREF AS INT),
                CAST(s.CLIENTREF AS INT),
                CASE
                    WHEN s.DATE_ IS NULL THEN NULL
                    WHEN s.DATE_ < CAST('1900-01-01' AS DATETIME2(0)) THEN NULL
                    WHEN s.DATE_ > CAST('2079-06-06 23:59:00' AS DATETIME2(0)) THEN NULL
                    ELSE CAST(s.DATE_ AS SMALLDATETIME)
                END,
                CAST(s.[TYPE] AS TINYINT),
                CAST(s.LINENR AS TINYINT),
                CAST(s.TLTOTAL AS FLOAT),
                CAST(160 AS SMALLINT),
                CAST(1 AS FLOAT),
                CAST(s.TLTOTAL AS FLOAT),
                CAST(s.FIRSTREAD AS FLOAT),
                CAST(s.LASTREAD AS FLOAT),
                CAST(s.TRANSTYPE AS INT),
                CASE WHEN ISNULL(s.CANCELED, 0) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
                CAST(s.TAX AS FLOAT),
                CAST(s.GRANDTOTAL AS FLOAT),
                LEFT(s.LINEEXP, 300),
                CAST(s.LINETYPE AS INT),
                CAST(s.DV AS FLOAT),
                LEFT(s.FITNO, 100),
                CAST(s.CNTREF AS INT),
                CAST(s.LOGO_FIRMNR AS INT),
                CAST(s.LOGO_FICHEREF AS INT),
                LEFT(s.LOGO_FICHENO, 100),
                CAST(s.XTYPE AS INT),
                CAST(s.ABYS_UNIT_PRICE AS FLOAT),
                CAST(s.SPEREF AS INT),
                CAST(s.ABYS_QUANTITY AS FLOAT),
                s.FIRST_DATE,
                s.LAST_DATE,
                s.[DAY],
                s.ABYS_INCOME_ROW_ID,
                s.ABYS_INCOME_ROW_ID,
                s.ABYS_INCOME_ID,
                s.ABYS_ACTION_ID,
                s.ABYS_ACCOUNT_ID,
                s.ABYS_REGISTER_ID,
                s.ABYS_AGREEMENT_ID,
                s.ABYS_ACTION_TYPE_ID,
                s.ABYS_ACCRUE_TYPE_ID,
                s.ABYS_IS_DISCOUNT,
                s.ABYS_IS_VAT_INCOME,
                s.ABYS_IS_DEPOSIT,
                s.ABYS_IS_OVERDUE_INCOME,
                s.ABYS_IS_LEGAL_FEE,
                LEFT(s.ABYS_INCOME_CODE, 10),
                s.ABYS_AMOUNT_RAW,
                s.ABYS_STATUS,
                s.ABYS_QUANTITY,
                s.ABYS_UNIT_PRICE,
                s.ABYS_AMOUNT1,
                s.ABYS_AMOUNT2,
                s.ABYS_AMOUNT3,
                s.ABYS_AMOUNT4,
                s.ABYS_AMOUNT5
            FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
            INNER JOIN #SRC_IL k ON k.LREF = s.LREF
            WHERE s.LREF BETWEEN @BatchFrom AND @BatchTo
              AND NOT EXISTS (
                    SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
                    WHERE t.LREF = CAST(s.LREF AS INT)
                  );

            SET @RowCount = @@ROWCOUNT;
            SET @Inserted += @RowCount;
        END TRY
        BEGIN CATCH
            BEGIN TRY SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;
            THROW;
        END CATCH

        BEGIN TRY SET IDENTITY_INSERT energy.dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;

        SET @LastKey = @BatchTo;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + N' | ' + CAST(@BatchFrom AS VARCHAR(20)) + N'-' + CAST(@BatchTo AS VARCHAR(20))
                + N' +' + CAST(@RowCount AS VARCHAR(20))
                + N' toplam=' + CAST(@Inserted AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    DECLARE @MaxLref INT;
    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVLINES;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVLINES', RESEED, @MaxLref) WITH NO_INFOMSGS;

    -- Gate (PK join)
    SELECT
        (SELECT COUNT(*) FROM #SRC_IL) AS MGR_LINES,
        (SELECT COUNT(*)
           FROM #SRC_IL k
           INNER JOIN energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
               ON t.LREF = CAST(k.LREF AS INT)
        ) AS EN_LINES,
        (SELECT ROUND(SUM(CAST(s.GRANDTOTAL AS FLOAT)), 2)
           FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
           INNER JOIN #SRC_IL k ON k.LREF = s.LREF
        ) AS MGR_SUM,
        (SELECT ROUND(SUM(CAST(t.GRANDTOTAL AS FLOAT)), 2)
           FROM #SRC_IL k
           INNER JOIN energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
               ON t.LREF = CAST(k.LREF AS INT)
        ) AS EN_SUM,
        @Inserted AS INSERTED_THIS_RUN;

    DROP TABLE #SRC_IL;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'SP_MIGRATE_LS005_INVLINES_AGR bitti. Inserted=' + CAST(@Inserted AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

-- ------------------------------------------------------------
-- PILOT EXEC
-- ------------------------------------------------------------
-- Once: 580_INVLINES__setup.sql (+ 569)
--EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES_AGR
--     @AGR_ID     = 197168,
--     @CLEAN      = 1,
--     @BATCH_SIZE = 5000,
--     @DEBUG      = 1;
--GO

---- Hizli dogrulama
--DECLARE @AGR_ID BIGINT = 197168;

--IF OBJECT_ID('tempdb..#K') IS NOT NULL DROP TABLE #K;
--CREATE TABLE #K (LREF INT NOT NULL PRIMARY KEY);
--INSERT INTO #K (LREF)
--SELECT CAST(ABYS_ACTION_ID AS INT)
--FROM izgazMGR.dbo.LS_INVOICE WITH (NOLOCK)
--WHERE ABYS_AGREEMENT_ID = @AGR_ID;

--SELECT
--    (SELECT COUNT(*) FROM izgazMGR.dbo.LS_INVLINES l WITH (NOLOCK)
--      WHERE EXISTS (SELECT 1 FROM #K k WHERE k.LREF = l.INVOICEREF)) AS MGR_LINES,
--    (SELECT COUNT(*) FROM energy.dbo.LS_005_01_INVLINES l WITH (NOLOCK)
--      WHERE l.ABYS_ID IS NOT NULL
--        AND EXISTS (SELECT 1 FROM #K k WHERE k.LREF = l.INVOICEREF)) AS EN_LINES,
--    (SELECT ROUND(SUM(CAST(GRANDTOTAL AS FLOAT)), 2) FROM izgazMGR.dbo.LS_INVLINES l WITH (NOLOCK)
--      WHERE EXISTS (SELECT 1 FROM #K k WHERE k.LREF = l.INVOICEREF)) AS MGR_SUM,
--    (SELECT ROUND(SUM(CAST(GRANDTOTAL AS FLOAT)), 2) FROM energy.dbo.LS_005_01_INVLINES l WITH (NOLOCK)
--      WHERE l.ABYS_ID IS NOT NULL
--        AND EXISTS (SELECT 1 FROM #K k WHERE k.LREF = l.INVOICEREF)) AS EN_SUM;
---- beklenen: 1277 = 1277, 109843.94 = 109843.94
--DROP TABLE #K;
--GO
