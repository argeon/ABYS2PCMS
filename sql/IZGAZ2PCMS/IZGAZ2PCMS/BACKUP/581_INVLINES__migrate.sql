/* ============================================================
   SCRIPT_ID : INVLINES_MIGRATE
   SCRIPT_NO : 581
   FILE      : 581_INVLINES__migrate.sql
   VERSION   : 5
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_INVLINES
-- Kaynak  : izgazMGR.dbo.LS_INVLINES
-- Hedef   : energy.dbo.LS_005_01_INVLINES
-- LREF    : IDENTITY_INSERT = kaynak LREF
-- ABYS_ID : ABYS_INCOME_ROW_ID
--
-- Sabit / turetilmis:
--   CURID=160, CURRATE=1, CURTOTAL=TLTOTAL
--   UNITPRICE=ABYS_UNIT_PRICE, AMOUNT=ABYS_QUANTITY
--
-- v5 degisiklikler (performans):
--   - SP_MIG_INVLINES_CHECK_PERF: kaynak LREF index, hedef NC/FK/trigger
--     durumu, recovery model kontrolu. Run basinda otomatik calisir.
--     Kaynak LREF index YOKSA ve @RANGE_MODE='KEYSET' ise 16 ile durur
--     (her batch full scan = O(n^2), 350M satirda kabul edilemez).
--   - @RANGE_MODE:
--       'KEYSET'     (varsayilan): TOP(@BATCH_SIZE) ... ORDER BY LREF.
--                    Kaynak LREF index/PK GEREKTIRIR. Batch basina tam
--                    @BATCH_SIZE satir.
--       'ARITHMETIC': @BatchTo = @LastBridgeKey + @BATCH_SIZE.
--                    Kaynakta boundary sorgusu YOK. LREF seyrek ise
--                    batch'ler eksik dolar ama scan yapilmaz.
--   - INSERT_RANGE uzerinden WITH RECOMPILE kaldirildi (range seek
--     predicate parametre-duyarli degil; 3500+ batch'te derleme maliyeti
--     gereksiz). Ana SP'de RECOMPILE duruyor.
--   - Recovery model FULL ise uyari: minimal logging icin BULK_LOGGED
--     onerilir (migration sonrasi FULL'e don + FULL backup).
--
-- v3/v4'ten devam:
--   - DATE_ inline CASE (scalar UDF yok)
--   - NOT EXISTS yok; ORDER BY LREF
--   - RESUME: LastBridgeKey = MAX(log, hedef MAX ABYS LREF)
--   - PK duplicate: bisect YOK -> hedef MAX(LREF) ile atla
-- Pass 1 dump: FK/wire/JOIN yok.
-- NC index/FK: yukleme oncesi PREPARE_LOAD; sonra 582_INVLINES__post.
-- ~350M+ satir: @BATCH_SIZE varsayilan 100000; kaynak index + BULK_LOGGED
-- saglandiktan sonra 250000-500000 denenebilir.
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- PERF ON-KONTROL
-- Kaynak index, hedef NC/FK/trigger, recovery model.
-- @RaiseOnBlocking=1: keyset modda kaynak LREF index yoksa 16 ile durur.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_CHECK_PERF
    @RangeMode       VARCHAR(20) = 'KEYSET',
    @RaiseOnBlocking BIT         = 1,
    @DEBUG           BIT         = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @SrcHasLrefIndex BIT = 0,
        @SrcIsHeap       BIT = 0,
        @EnabledNcCount  INT = 0,
        @EnabledFkCount  INT = 0,
        @EnabledTrgCount INT = 0,
        @RecoveryModel   NVARCHAR(60),
        @Msg             NVARCHAR(500);

    -- 1) Kaynak: LREF onde anahtar kolon olan herhangi bir index var mi?
    SELECT @SrcHasLrefIndex = 1
    FROM izgazMGR.sys.indexes i
    INNER JOIN izgazMGR.sys.index_columns ic
        ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    INNER JOIN izgazMGR.sys.columns c
        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('izgazMGR.dbo.LS_INVLINES')
      AND i.type > 0
      AND ic.key_ordinal = 1
      AND ic.is_included_column = 0
      AND c.name = 'LREF';

    IF EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.LS_INVLINES')
          AND index_id = 0
    )
        SET @SrcIsHeap = 1;

    -- 2) Hedef: aktif NC index / FK / trigger sayisi (PREPARE_LOAD dogrulamasi)
    SELECT @EnabledNcCount = COUNT(*)
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_005_01_INVLINES')
      AND type = 2
      AND is_disabled = 0;

    SELECT @EnabledFkCount = COUNT(*)
    FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID('dbo.LS_005_01_INVLINES')
      AND is_disabled = 0;

    SELECT @EnabledTrgCount = COUNT(*)
    FROM sys.triggers
    WHERE parent_id = OBJECT_ID('dbo.LS_005_01_INVLINES')
      AND is_disabled = 0;

    -- 3) Recovery model
    SELECT @RecoveryModel = recovery_model_desc
    FROM sys.databases
    WHERE name = 'energy';

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'PERF CHECK | KaynakLrefIndex=' + CAST(@SrcHasLrefIndex AS VARCHAR(1))
            + ' Heap=' + CAST(@SrcIsHeap AS VARCHAR(1))
            + ' | HedefAktifNC=' + CAST(@EnabledNcCount AS VARCHAR(10))
            + ' FK=' + CAST(@EnabledFkCount AS VARCHAR(10))
            + ' TRG=' + CAST(@EnabledTrgCount AS VARCHAR(10))
            + ' | Recovery=' + @RecoveryModel
            + ' | Mode=' + @RangeMode;
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    -- Bloklayici: keyset modda kaynak LREF index sart
    IF @SrcHasLrefIndex = 0 AND @RangeMode = 'KEYSET' AND @RaiseOnBlocking = 1
        RAISERROR(N'izgazMGR.dbo.LS_INVLINES uzerinde LREF onde index YOK. KEYSET modda her batch full scan olur (350M satir x 3500 batch). Once index kur: CREATE NONCLUSTERED INDEX IX_MIG_LSINVLINES_LREF ON izgazMGR.dbo.LS_INVLINES(LREF) WITH (MAXDOP=24, ONLINE=OFF, SORT_IN_TEMPDB=ON); ya da @RANGE_MODE=''ARITHMETIC'' kullan (insert taramasi yine index ister, sadece boundary sorgusu kalkar).', 16, 1);

    -- Uyari seviyesi
    IF @SrcHasLrefIndex = 0 AND @RangeMode = 'ARITHMETIC'
        RAISERROR(N'UYARI: Kaynakta LREF index yok. ARITHMETIC boundary sorgusunu kaldirir ama INSERT_RANGE icindeki BETWEEN taramasi yine full scan olur. Index kurmadan hiz beklenmemeli.', 0, 1) WITH NOWAIT;

    IF @EnabledNcCount > 0
        RAISERROR(N'UYARI: Hedefte %d aktif NC index var. PREPARE_LOAD calismamis olabilir; her insert index bakim maliyeti oder.', 0, 1, @EnabledNcCount) WITH NOWAIT;

    IF @EnabledFkCount > 0
        RAISERROR(N'UYARI: Hedefte %d aktif FK var. Pass-1 dump yukunde FK dogrulamasi gereksiz maliyettir.', 0, 1, @EnabledFkCount) WITH NOWAIT;

    IF @EnabledTrgCount > 0
        RAISERROR(N'UYARI: Hedefte %d aktif trigger var.', 0, 1, @EnabledTrgCount) WITH NOWAIT;

    IF @RecoveryModel = N'FULL'
        RAISERROR(N'UYARI: energy recovery model = FULL. Minimal logging yok; WRITELOG/log growth darbogazi beklenir. Oneri: ALTER DATABASE energy SET RECOVERY BULK_LOGGED; (migration sonrasi FULL + tam yedek).', 0, 1) WITH NOWAIT;
END
GO

-- ============================================================
-- RANGE INSERT
-- v5: WITH RECOMPILE kaldirildi (sabit range-seek plani yeterli).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    BEGIN TRY
        SET IDENTITY_INSERT dbo.LS_005_01_INVLINES ON;

        INSERT INTO energy.dbo.LS_005_01_INVLINES WITH (TABLOCK) (
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
            /* tinyint 0..255; kaynak RN>255 ise 0 */
            CAST(CASE WHEN s.LINENR > 255 THEN 0 ELSE ISNULL(s.LINENR, 0) END AS TINYINT),
            CAST(s.TLTOTAL AS FLOAT),
            CAST(160 AS SMALLINT),                          -- CURID sabit
            CAST(1 AS FLOAT),                               -- CURRATE sabit
            CAST(s.TLTOTAL AS FLOAT),                       -- CURTOTAL = TLTOTAL
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
            CAST(s.ABYS_UNIT_PRICE AS FLOAT),               -- UNITPRICE = ABYS_UNIT_PRICE
            CAST(s.SPEREF AS INT),
            CAST(s.ABYS_QUANTITY AS FLOAT),                 -- AMOUNT = ABYS_QUANTITY
            s.FIRST_DATE,
            s.LAST_DATE,
            s.[DAY],
            s.ABYS_INCOME_ROW_ID,                           -- ABYS_ID
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
        WHERE s.LREF BETWEEN @BatchFrom AND @BatchTo
          AND s.LREF BETWEEN 1 AND 2147483647
        ORDER BY s.LREF
        OPTION (MAXDOP 24);  /* RECOMPILE yok: range-seek plani batch'ler arasi sabit kalsin */

        SET @RowCount = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;
        THROW;
    END CATCH

    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_INVLINES t
        WHERE t.LREF = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_INVLINES_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_INVLINES_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_INVLINES ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    EXEC dbo.SP_MIG_INVLINES_PREPARE_LOAD @DEBUG = @DEBUG;

    SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_INVLINES
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
    FROM energy.dbo.LS_005_01_INVLINES;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVLINES', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

-- ============================================================
-- ANA SP
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_INVLINES
    @BATCH_SIZE      INT         = 100000,
    @RESUME          BIT         = 1,
    @HARD_RESET      BIT         = 0,
    @MAX_ERROR       INT         = 500,
    @BISECT_MIN      INT         = 1,
    @RANGE_MODE      VARCHAR(20) = 'KEYSET',   -- 'KEYSET' | 'ARITHMETIC'
    @SKIP_PERF_CHECK BIT         = 0,
    @DEBUG           BIT         = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    IF @RANGE_MODE NOT IN ('KEYSET', 'ARITHMETIC')
    BEGIN
        RAISERROR(N'@RANGE_MODE ''KEYSET'' veya ''ARITHMETIC'' olmali.', 16, 1);
        RETURN;
    END

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_INVLINES',
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
        @BisectEnd      BIGINT,
        @BisectMid      BIGINT,
        @BisectSize     INT,
        @BisectRows     INT,
        @BisectLogFrom  BIGINT,
        @RowInserted    BIT,
        @MaxLref        INT,
        @TargetMaxLref  BIGINT;

    EXEC dbo.SP_MIG_INVLINES_VALIDATE_ALL @RaiseOnMissing = 1;

    -- Tahsilat: MGR LREF / INVOICEREF IX yoksa burada kurulur (355M+)
    IF OBJECT_ID('dbo.SP_MIG_INVLINES_ENSURE_MGR_INDEXES', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_INVLINES_ENSURE_MGR_INDEXES @DEBUG = @DEBUG;

    -- v5: performans on-kontrol (kaynak index yoksa KEYSET modda durur)
    IF @SKIP_PERF_CHECK = 0
        EXEC dbo.SP_MIG_INVLINES_CHECK_PERF
            @RangeMode       = @RANGE_MODE,
            @RaiseOnBlocking = 1,
            @DEBUG           = @DEBUG;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_INVLINES_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE
    BEGIN
        EXEC dbo.SP_MIG_INVLINES_PREPARE_LOAD @DEBUG = @DEBUG;
        IF @RESUME = 1
            SET @ExecMode = 'RESUME';
        ELSE
            SET @ExecMode = 'FULL';
    END

    SELECT @SourceCount = SUM(p.rows)
    FROM izgazMGR.sys.partitions p
    INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
    INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
    WHERE sch.name = 'dbo'
      AND t.name = 'LS_INVLINES'
      AND p.index_id IN (0, 1);

    SELECT @MaxBridgeKey = MAX(s.LREF)
    FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
    WHERE s.LREF BETWEEN 1 AND 2147483647;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_INVLINES',
        @TargetTable    = 'LS_005_01_INVLINES',
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

    -- Mig log LastBridgeKey=0 olsa bile hedefte ABYS satir varsa oradan devam et
    SELECT @TargetMaxLref = ISNULL(MAX(CAST(t.LREF AS BIGINT)), 0)
    FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
    WHERE t.ABYS_ID IS NOT NULL;

    IF @TargetMaxLref > ISNULL(@LastBridgeKey, 0)
    BEGIN
        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'RESUME sync: log LREF=' + CAST(ISNULL(@LastBridgeKey, 0) AS VARCHAR(20))
                + ' -> hedef MAX(LREF)=' + CAST(@TargetMaxLref AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
        SET @LastBridgeKey = @TargetMaxLref;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | Mode=' + @RANGE_MODE
            + ' | Kaynak~' + CAST(ISNULL(@SourceCount, 0) AS VARCHAR(20))
            + ' | LREF=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        IF @RANGE_MODE = 'KEYSET'
        BEGIN
            -- Kaynak LREF index'inde range seek; batch tam @BATCH_SIZE satir
            SELECT @BatchTo = MAX(LREF)
            FROM (
                SELECT TOP (@BATCH_SIZE) s.LREF
                FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
                WHERE s.LREF > @LastBridgeKey
                  AND s.LREF <= 2147483647
                ORDER BY s.LREF ASC
            ) x;

            IF @BatchTo IS NULL BREAK;
        END
        ELSE
        BEGIN
            -- Kaynakta boundary sorgusu yok; LREF araligi aritmetik ilerler.
            -- LREF seyrekse batch eksik dolar (zararsiz), yogunsa tam dolar.
            SET @BatchTo = @LastBridgeKey + @BATCH_SIZE;
            IF @BatchTo > @MaxBridgeKey SET @BatchTo = @MaxBridgeKey;
        END

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC dbo.SP_MIG_INVLINES_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
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
            BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;
            SET @ErrMsg = ERROR_MESSAGE();

            -- Onceki run'dan kalan satirlar: bisect etme, hedef MAX ile atla
            IF @ErrMsg LIKE N'%PRIMARY KEY%' OR @ErrMsg LIKE N'%duplicate key%'
            BEGIN
                SELECT @TargetMaxLref = ISNULL(MAX(CAST(t.LREF AS BIGINT)), @BatchTo)
                FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
                WHERE t.ABYS_ID IS NOT NULL
                  AND t.LREF >= @BatchFrom
                  AND t.LREF <= @BatchTo;

                IF @TargetMaxLref < @BatchFrom
                    SELECT @TargetMaxLref = ISNULL(MAX(CAST(t.LREF AS BIGINT)), @BatchTo)
                    FROM energy.dbo.LS_005_01_INVLINES t WITH (NOLOCK)
                    WHERE t.ABYS_ID IS NOT NULL;

                IF @DEBUG = 1
                BEGIN
                    SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                        + ' PK duplicate -> skip to LREF=' + CAST(@TargetMaxLref AS VARCHAR(20));
                    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                END

                EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                    @RunID = @RunID, @TableRunID = @TableRunID,
                    @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                    @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @TargetMaxLref,
                    @RowCount = 0, @ElapsedMs = 0;

                SET @LastBridgeKey = @TargetMaxLref;
                CONTINUE;
            END

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('Batch %d HATA -> bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            -- BisectTo daralinca tek-satir hata sonrasi kalan batch atlanmasin
            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;
            SET @BisectEnd  = @BatchTo;

            WHILE @BisectFrom <= @BisectEnd AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_INVLINES_INSERT_ONE
                            @CurID = @BisectFrom, @RowInserted = @RowInserted OUTPUT;

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
                            N'LREF=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

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

                    -- Izole edilen hatadan sonra batch sonuna kadar devam et
                    SET @BisectFrom += 1;
                    SET @BisectTo = @BisectEnd;
                    CONTINUE;
                END

                SET @BisectMid = @BisectFrom + (@BisectSize / 2) - 1;

                BEGIN TRY
                    BEGIN TRANSACTION;

                    EXEC dbo.SP_MIG_INVLINES_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
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
                    BEGIN TRY SET IDENTITY_INSERT dbo.LS_005_01_INVLINES OFF; END TRY BEGIN CATCH END CATCH;
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
    FROM energy.dbo.LS_005_01_INVLINES;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_INVLINES', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_INVLINES
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
        WHEN @Stopped = 1 THEN N'Max hata limitine ulasildi. RESUME ile devam edin. Index icin 582_INVLINES__post calistirin.'
        ELSE N'Aktarim bitti. Index icin: EXEC energy.dbo.SP_MIG_INVLINES_POST_INDEXES @DEBUG=1;'
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
        WHERE l.MIGRATION_CODE = 'LS_005_01_INVLINES'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

-- ============================================================
-- KULLANIM
-- ============================================================
-- 0) On-kontrol (tek basina):
--    EXEC dbo.SP_MIG_INVLINES_CHECK_PERF @RangeMode='KEYSET', @RaiseOnBlocking=0, @DEBUG=1;
--
-- 1) Kaynakta LREF index yoksa (bir kez, saatler surebilir ama 3500 batch'te geri doner):
--    CREATE NONCLUSTERED INDEX IX_MIG_LSINVLINES_LREF
--    ON izgazMGR.dbo.LS_INVLINES (LREF)
--    WITH (MAXDOP = 24, ONLINE = OFF, SORT_IN_TEMPDB = ON);
--
-- 2) Migration penceresi icin (sonrasinda FULL + tam yedek!):
--    ALTER DATABASE energy SET RECOVERY BULK_LOGGED;
--
-- 3) Calistir:
--    EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES
--         @HARD_RESET = 1, @RESUME = 1, @BATCH_SIZE = 100000,
--         @RANGE_MODE = 'KEYSET', @DEBUG = 1;
--
--    Kaynak index kurulamiyorsa (boundary sorgusunu kaldirir, insert
--    taramasini KALDIRMAZ):
--    EXEC energy.dbo.SP_MIGRATE_LS005_INVLINES
--         @RANGE_MODE = 'ARITHMETIC', @BATCH_SIZE = 100000, @DEBUG = 1;
--
-- 4) Bitince:
--    EXEC energy.dbo.SP_MIG_INVLINES_POST_INDEXES @DEBUG = 1;
--    ALTER DATABASE energy SET RECOVERY FULL;  -- + FULL backup