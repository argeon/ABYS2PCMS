/* ============================================================
   SCRIPT_ID : INVOICE_CLEAN_BY_AGR
   SCRIPT_NO : 569
   FILE      : 569_INVOICE_CLEAN_BY_AGR.sql
   VERSION   : 4
   ============================================================ */
-- v4: mukerrer temizligi — energy LREF=ACTION + ABYS_ID=ACTION (eski IDENTITY LREF)
--     INVLINES: mgr satir PK + INVOICEREF IN (#inv genisletilmis)
-- v4b: PREPARE_LOAD yalniz @ForcePrepareLoad=1 (pilot asla otomatik DISABLE etmez)
-- v3: energy AGR/OWNERREF taramasi YOK
--     anahtarlar izgazMGR'den (kucuk) → energy PK / INVOICEREF seek
-- Silme: PAYTRANS → INVLINES → INVOICE
-- ============================================================ */
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER
    @AGRID       BIGINT,
    @AgrLref     INT            = NULL OUTPUT,
    @AbysAgrId   BIGINT         = NULL OUTPUT,
    @AgrNumber   VARCHAR(50)    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @AgrLref   = NULL;
    SET @AbysAgrId = NULL;
    SET @AgrNumber = LTRIM(RTRIM(CAST(@AGRID AS VARCHAR(50))));

    IF OBJECT_ID('energy.dbo.LS_005_01_AGR', 'U') IS NULL
        RETURN;

    SELECT TOP (1)
        @AgrLref   = a.LREF,
        @AbysAgrId = COALESCE(
                        TRY_CAST(a.ABYS_ID AS BIGINT),
                        TRY_CAST(a.AGREEMENT_NUMBER AS BIGINT),
                        @AGRID)
    FROM energy.dbo.LS_005_01_AGR a WITH (NOLOCK)
    WHERE a.AGREEMENT_NUMBER = @AgrNumber
       OR TRY_CAST(a.AGREEMENT_NUMBER AS BIGINT) = @AGRID
       OR TRY_CAST(a.ABYS_ID AS BIGINT) = @AGRID
    ORDER BY a.LREF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR
    @AGRID              BIGINT,
    @DELETE_BATCH       INT = 20000,
    @DEBUG              BIT = 0,
    @RaiseIfAgrMissing  BIT = 1,
    @ForcePrepareLoad   BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @AgrLref     INT,
        @AbysAgrId   BIGINT,
        @AgrNumber   VARCHAR(50),
        @Deleted     INT,
        @TotalPt     BIGINT = 0,
        @TotalIl     BIGINT = 0,
        @TotalInv    BIGINT = 0,
        @InvCnt      INT,
        @LineCnt     INT,
        @Msg         NVARCHAR(500),
        @BatchNo     INT = 0;

    IF @AGRID IS NULL
    BEGIN
        RAISERROR('SP_MIG_CLEAN_INVOICE_CHAIN_BY_AGR: @AGRID zorunlu.', 16, 1);
        RETURN;
    END

    IF @DELETE_BATCH IS NULL OR @DELETE_BATCH < 1
        SET @DELETE_BATCH = 20000;

    EXEC dbo.SP_MIG_RESOLVE_AGR_BY_NUMBER
        @AGRID     = @AGRID,
        @AgrLref   = @AgrLref   OUTPUT,
        @AbysAgrId = @AbysAgrId OUTPUT,
        @AgrNumber = @AgrNumber OUTPUT;

    IF @AgrLref IS NULL
    BEGIN
        IF @RaiseIfAgrMissing = 1
        BEGIN
            SET @Msg = N'LS_005_01_AGR bulunamadi. AGREEMENT_NUMBER=' + ISNULL(@AgrNumber, '?');
            RAISERROR('%s', 16, 1, @Msg);
            RETURN;
        END
    END

    /* ---- Anahtarlar: izgazMGR ACTION_ID → energy LREF (PK + ABYS_ID) ---- */
    IF OBJECT_ID('tempdb..#MIG_KEYS') IS NOT NULL DROP TABLE #MIG_KEYS;
    CREATE TABLE #MIG_KEYS (ACTION_ID BIGINT NOT NULL PRIMARY KEY);

    IF OBJECT_ID('tempdb..#MIG_CLEAN_INV') IS NOT NULL DROP TABLE #MIG_CLEAN_INV;
    CREATE TABLE #MIG_CLEAN_INV (LREF INT NOT NULL PRIMARY KEY);

    IF OBJECT_ID('izgazMGR.dbo.LS_INVOICE', 'U') IS NOT NULL
        INSERT INTO #MIG_KEYS (ACTION_ID)
        SELECT DISTINCT s.ABYS_ACTION_ID
        FROM izgazMGR.dbo.LS_INVOICE s WITH (NOLOCK)
        WHERE s.ABYS_AGREEMENT_ID = @AGRID
          AND s.ABYS_ACTION_ID BETWEEN 1 AND 2147483647;

    -- 1) hedef LREF = ACTION_ID (dogru migrate)
    INSERT INTO #MIG_CLEAN_INV (LREF)
    SELECT CAST(k.ACTION_ID AS INT)
    FROM #MIG_KEYS k;

    -- 2) mukerrer / eski: ABYS_ID=ACTION ama LREF farkli (IX_MIG_INV_ABYS_ID)
    IF EXISTS (SELECT 1 FROM #MIG_KEYS)
        INSERT INTO #MIG_CLEAN_INV (LREF)
        SELECT inv.LREF
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        INNER JOIN #MIG_KEYS k ON inv.ABYS_ID = k.ACTION_ID
        WHERE NOT EXISTS (SELECT 1 FROM #MIG_CLEAN_INV x WHERE x.LREF = inv.LREF)
        OPTION (RECOMPILE, MAXDOP 1);

    -- fallback: mgr yoksa AGR index
    IF NOT EXISTS (SELECT 1 FROM #MIG_CLEAN_INV)
        INSERT INTO #MIG_CLEAN_INV (LREF)
        SELECT inv.LREF
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.ABYS_ID IS NOT NULL
          AND inv.ABYS_AGREEMENT_ID = @AGRID
        OPTION (RECOMPILE, MAXDOP 1);

    SELECT @InvCnt = COUNT(*) FROM #MIG_CLEAN_INV;

    IF OBJECT_ID('tempdb..#MIG_CLEAN_IL') IS NOT NULL DROP TABLE #MIG_CLEAN_IL;
    CREATE TABLE #MIG_CLEAN_IL (LREF INT NOT NULL PRIMARY KEY);

    IF OBJECT_ID('izgazMGR.dbo.LS_INVLINES', 'U') IS NOT NULL
        INSERT INTO #MIG_CLEAN_IL (LREF)
        SELECT DISTINCT CAST(s.LREF AS INT)
        FROM izgazMGR.dbo.LS_INVLINES s WITH (NOLOCK)
        WHERE s.LREF BETWEEN 1 AND 2147483647
          AND (
                s.ABYS_AGREEMENT_ID = @AGRID
             OR EXISTS (SELECT 1 FROM #MIG_KEYS k WHERE k.ACTION_ID = s.INVOICEREF)
              );

    -- energy: eski INVOICEREF = yanlis invoice LREF (genisletilmis #inv)
    IF @InvCnt > 0 AND OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
        INSERT INTO #MIG_CLEAN_IL (LREF)
        SELECT il.LREF
        FROM energy.dbo.LS_005_01_INVLINES il WITH (NOLOCK)
        INNER JOIN #MIG_CLEAN_INV i ON i.LREF = il.INVOICEREF
        WHERE il.ABYS_ID IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #MIG_CLEAN_IL x WHERE x.LREF = il.LREF)
        OPTION (RECOMPILE, MAXDOP 1);

    SELECT @LineCnt = COUNT(*) FROM #MIG_CLEAN_IL;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'CLEAN BY AGR v4 | AGR=' + ISNULL(@AgrNumber, '?')
            + N' MgrActions=' + CAST((SELECT COUNT(*) FROM #MIG_KEYS) AS VARCHAR(20))
            + N' InvLrefs=' + CAST(@InvCnt AS VARCHAR(20))
            + N' LineKeys=' + CAST(@LineCnt AS VARCHAR(20))
            + N' (ACTION+ABYS_ID → PK)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    IF @InvCnt = 0 AND @LineCnt = 0
    BEGIN
        IF @DEBUG = 1
            RAISERROR('CLEAN BY AGR: silinecek anahtar yok.', 0, 1) WITH NOWAIT;
        DROP TABLE #MIG_CLEAN_INV;
        DROP TABLE #MIG_CLEAN_IL;
        IF OBJECT_ID('tempdb..#MIG_KEYS') IS NOT NULL DROP TABLE #MIG_KEYS;
        RETURN;
    END

    -- Pilot: index DISABLE etme. Yalniz acikca ForcePrepareLoad=1 (buyuk/full)
    IF @ForcePrepareLoad = 1
    BEGIN
        IF OBJECT_ID('energy.dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_DEBT_PAYTRANS_PREPARE_LOAD @DEBUG = 0;
        IF OBJECT_ID('energy.dbo.SP_MIG_INVLINES_PREPARE_LOAD', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_INVLINES_PREPARE_LOAD @DEBUG = 0;
        IF OBJECT_ID('energy.dbo.SP_MIG_INVOICE_PREPARE_LOAD', 'P') IS NOT NULL
            EXEC dbo.SP_MIG_INVOICE_PREPARE_LOAD @DEBUG = 0;
    END
    ELSE IF @DEBUG = 1
        RAISERROR('CLEAN BY AGR: PREPARE_LOAD atlandi (index DISABLE yok).', 0, 1) WITH NOWAIT;

    /* ---- 1) PAYTRANS: INVOICEREF JOIN #inv (IX_MIG_PT_INVREF_IO) ---- */
    SET @BatchNo = 0;
    WHILE @InvCnt > 0
    BEGIN
        SET @BatchNo += 1;

        DELETE TOP (@DELETE_BATCH) pt
        FROM energy.dbo.LS_005_01_PAYTRANS pt WITH (ROWLOCK)
        INNER JOIN #MIG_CLEAN_INV i ON i.LREF = pt.INVOICEREF
        WHERE pt.ABYS_ID IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 1);

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        SET @TotalPt += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'PAYTRANS PK/INVREF batch ' + CAST(@BatchNo AS VARCHAR(10))
                + N' +' + CAST(@Deleted AS VARCHAR(20))
                + N' toplam=' + CAST(@TotalPt AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    /* ---- 2) INVLINES: satir LREF PK ---- */
    IF OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL AND @LineCnt > 0
    BEGIN
        SET @BatchNo = 0;
        WHILE 1 = 1
        BEGIN
            SET @BatchNo += 1;

            DELETE TOP (@DELETE_BATCH) il
            FROM energy.dbo.LS_005_01_INVLINES il WITH (ROWLOCK)
            INNER JOIN #MIG_CLEAN_IL k ON k.LREF = il.LREF
            WHERE il.ABYS_ID IS NOT NULL
            OPTION (RECOMPILE, MAXDOP 1);

            SET @Deleted = @@ROWCOUNT;
            IF @Deleted = 0 BREAK;
            SET @TotalIl += @Deleted;

            IF @DEBUG = 1
            BEGIN
                SET @Msg = N'INVLINES PK batch ' + CAST(@BatchNo AS VARCHAR(10))
                    + N' +' + CAST(@Deleted AS VARCHAR(20))
                    + N' toplam=' + CAST(@TotalIl AS VARCHAR(20));
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
            END
        END
    END

    /* ---- 3) INVOICE: LREF PK ---- */
    SET IDENTITY_INSERT energy.dbo.LS_005_01_INVOICE OFF;
    SET @BatchNo = 0;

    WHILE @InvCnt > 0
    BEGIN
        SET @BatchNo += 1;

        DELETE TOP (@DELETE_BATCH) inv
        FROM energy.dbo.LS_005_01_INVOICE inv WITH (ROWLOCK)
        INNER JOIN #MIG_CLEAN_INV i ON i.LREF = inv.LREF
        WHERE inv.ABYS_ID IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 1);

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;
        SET @TotalInv += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'INVOICE PK batch ' + CAST(@BatchNo AS VARCHAR(10))
                + N' +' + CAST(@Deleted AS VARCHAR(20))
                + N' toplam=' + CAST(@TotalInv AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
    END

    DECLARE @MaxLref INT;
    SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVOICE;
    DBCC CHECKIDENT('energy.dbo.LS_005_01_INVOICE', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS', 'U') IS NOT NULL
    BEGIN
        SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_PAYTRANS;
        DBCC CHECKIDENT('energy.dbo.LS_005_01_PAYTRANS', RESEED, @MaxLref) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID('energy.dbo.LS_005_01_INVLINES', 'U') IS NOT NULL
    BEGIN
        SELECT @MaxLref = ISNULL(MAX(LREF), 0) FROM energy.dbo.LS_005_01_INVLINES;
        DBCC CHECKIDENT('energy.dbo.LS_005_01_INVLINES', RESEED, @MaxLref) WITH NO_INFOMSGS;
    END

    DROP TABLE #MIG_CLEAN_INV;
    DROP TABLE #MIG_CLEAN_IL;
    IF OBJECT_ID('tempdb..#MIG_KEYS') IS NOT NULL DROP TABLE #MIG_KEYS;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'CLEAN BY AGR v4 OK | PT=' + CAST(@TotalPt AS VARCHAR(20))
            + N' IL=' + CAST(@TotalIl AS VARCHAR(20))
            + N' INV=' + CAST(@TotalInv AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO

PRINT '569_INVOICE_CLEAN_BY_AGR v4 OK (ACTION+ABYS_ID → PK delete)';
GO
