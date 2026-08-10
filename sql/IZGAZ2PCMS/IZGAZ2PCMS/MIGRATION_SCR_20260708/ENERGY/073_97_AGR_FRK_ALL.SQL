/* ============================================================
   FILE : prodEnergy/90_afl_frk/97_agr_frk_all.sql
   SP   : energy.dbo.SP_AGR_FRK_ALL
   Sozlesme FRK ozeti (1 satir = 1 AGREEMENT_ID)

   Parametre:
     @Agr         NULL = tum sozlesmeler | deger = tek sozlesme
     @OnlyDiff    1 = sadece farkli satirlar
     @Eps         tolerans (varsayilan 0.02)
     @WriteTable  1 = energy.dbo.MIG_AGR_FRK_ALL yaz (varsayilan)
     @ReturnResult 1 = sonuc seti de dondur (varsayilan 0)

   Tablo:
     MIG_AGR_FRK_ALL — @Agr NULL → TRUNCATE+INSERT | tek AGR → DELETE+INSERT
     Incele: SELECT KIND_FRK, COUNT(*) FROM MIG_AGR_FRK_ALL GROUP BY KIND_FRK;

   Sozlesme evreni (seed):
     INV.TYPE IN (119,121,86) GROUP BY OWNERREF  (~977k)

   Ornek:
     EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 0;           -- ~977k tablo
     EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 1;           -- sadece FRK
     EXEC dbo.SP_AGR_FRK_ALL @Agr = 197168, @ReturnResult = 1;

   Ek alanlar (fark okuma):
     EN_IADE_SM3/KWH/CONSUMPTION — IADE/eksilten fis tuketimi (IOCODE=1/TYPE92)
     DELTA_CONSUMPTION + _EKS/_NET — SM3/KWH ile ayni ayirim
     DELTA_KALAN_EKS/_NET — acik PT farki eksiltenli vs diger hesap
     ASIM_CNT, OV_ASIM_TUTAR — OV KIND=ASIM (EKS>TAH; TAM/KISMI disi)

   Indeks (DDL + SP @WriteTable=1 yoksa olustur; ONLINE edition uygunsa):
     IX_MIG_AGR_FRK_KIND | IX_AGR_FRK_KALAN | IX_AGR_FRK_TAH_NET | IX_AGR_FRK_ASIM
   ============================================================ */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_AGR_FRK_ALL (
        RUN_ID            UNIQUEIDENTIFIER NOT NULL,
        SNAPSHOT_TS       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_MIG_AGR_FRK_TS DEFAULT (SYSDATETIME()),
        AGREEMENT_ID      BIGINT           NOT NULL,
        KIND_FRK          VARCHAR(20)      NOT NULL,
        ACIKLAMA          NVARCHAR(1000)   NULL,
        TTK_SOURCE        VARCHAR(20)      NULL,
        EN_ACC_CNT        INT              NULL,
        ABYS_ACC_CNT      INT              NULL,
        ACC_UNION         INT              NULL,
        INV_CNT           INT              NULL,
        EN_TAH_TUTAR      DECIMAL(18,2)    NULL,
        ABYS_TAH_TUTAR    DECIMAL(18,2)    NULL,
        DELTA_TAH         DECIMAL(18,2)    NULL,
        EN_SM3            DECIMAL(18,6)    NULL,
        ABYS_SM3          DECIMAL(18,6)    NULL,
        DELTA_SM3         DECIMAL(18,6)    NULL,
        DELTA_SM3_EKS     DECIMAL(18,6)    NULL,
        DELTA_SM3_NET     DECIMAL(18,6)    NULL,
        EN_KWH            DECIMAL(18,6)    NULL,
        ABYS_KWH          DECIMAL(18,6)    NULL,
        DELTA_KWH         DECIMAL(18,6)    NULL,
        DELTA_KWH_EKS     DECIMAL(18,6)    NULL,
        DELTA_KWH_NET     DECIMAL(18,6)    NULL,
        EN_CONSUMPTION    DECIMAL(18,6)    NULL,
        ABYS_CONSUMPTION  DECIMAL(18,6)    NULL,
        DELTA_CONSUMPTION DECIMAL(18,6)    NULL,
        DELTA_CONSUMPTION_EKS DECIMAL(18,6) NULL,
        DELTA_CONSUMPTION_NET DECIMAL(18,6) NULL,
        EN_IADE_TUTAR     DECIMAL(18,2)    NULL,
        EN_IADE_SM3       DECIMAL(18,6)    NULL,
        EN_IADE_KWH       DECIMAL(18,6)    NULL,
        EN_IADE_CONSUMPTION DECIMAL(18,6)  NULL,
        OV_EKS_TUTAR      DECIMAL(18,2)    NULL,
        OV_ASIM_TUTAR     DECIMAL(18,2)    NULL,
        DELTA_TAH_EKS     DECIMAL(18,2)    NULL,
        DELTA_TAH_NET     DECIMAL(18,2)    NULL,
        EKSILTEN_CNT      INT              NULL,
        TAM_CNT           INT              NULL,
        KISMI_CNT         INT              NULL,
        ASIM_CNT          INT              NULL,
        ONLY_EN_CNT       INT              NULL,
        ONLY_ABYS_CNT     INT              NULL,
        TAH_MATCH_CNT     INT              NULL,
        TAH_DIFF_CNT      INT              NULL,
        EN_KALAN          DECIMAL(18,2)    NULL,
        AFL_KALAN         DECIMAL(18,2)    NULL,
        DELTA_KALAN       DECIMAL(18,2)    NULL,
        DELTA_KALAN_EKS   DECIMAL(18,2)    NULL,
        DELTA_KALAN_NET   DECIMAL(18,2)    NULL,
        CONSTRAINT PK_MIG_AGR_FRK_ALL PRIMARY KEY CLUSTERED (AGREEMENT_ID)
    );
END
GO

/* Mevcut tabloya yeni kolonlar (idempotent) */
IF OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'EN_IADE_SM3') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD EN_IADE_SM3 DECIMAL(18,6) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'EN_IADE_KWH') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD EN_IADE_KWH DECIMAL(18,6) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'EN_IADE_CONSUMPTION') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD EN_IADE_CONSUMPTION DECIMAL(18,6) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'DELTA_CONSUMPTION') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD DELTA_CONSUMPTION DECIMAL(18,6) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'DELTA_CONSUMPTION_EKS') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD DELTA_CONSUMPTION_EKS DECIMAL(18,6) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'DELTA_CONSUMPTION_NET') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD DELTA_CONSUMPTION_NET DECIMAL(18,6) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'OV_ASIM_TUTAR') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD OV_ASIM_TUTAR DECIMAL(18,2) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'ASIM_CNT') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD ASIM_CNT INT NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'DELTA_KALAN_EKS') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD DELTA_KALAN_EKS DECIMAL(18,2) NULL;
    IF COL_LENGTH('energy.dbo.MIG_AGR_FRK_ALL', 'DELTA_KALAN_NET') IS NULL
        ALTER TABLE energy.dbo.MIG_AGR_FRK_ALL ADD DELTA_KALAN_NET DECIMAL(18,2) NULL;
END
GO

/* Inceleme indeksleri — ONLINE dene, destek yoksa offline (Standard) */
IF OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL', 'U') IS NOT NULL
BEGIN
    /* KIND covering (eski dar INCLUDE varsa yenile) */
    IF EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL')
          AND name = N'IX_MIG_AGR_FRK_KIND'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic
            ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
        INNER JOIN sys.columns c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL')
          AND i.name = N'IX_MIG_AGR_FRK_KIND'
          AND c.name = N'ASIM_CNT'
    )
        DROP INDEX IX_MIG_AGR_FRK_KIND ON energy.dbo.MIG_AGR_FRK_ALL;

    DECLARE @IxSql NVARCHAR(MAX);
    DECLARE @IxOnline BIT = CASE WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) IN (3, 5, 8) THEN 1 ELSE 0 END;
    /* 3=Eval/Enterprise, 5=Azure SQL DB, 8=Azure Managed Instance — ONLINE destek */

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_MIG_AGR_FRK_KIND'
    )
    BEGIN
        SET @IxSql = N'
CREATE NONCLUSTERED INDEX IX_MIG_AGR_FRK_KIND
ON energy.dbo.MIG_AGR_FRK_ALL (KIND_FRK)
INCLUDE (
    DELTA_TAH, DELTA_TAH_EKS, DELTA_TAH_NET,
    DELTA_KALAN, DELTA_KALAN_EKS, DELTA_KALAN_NET,
    EN_IADE_TUTAR, EN_IADE_SM3, OV_EKS_TUTAR, OV_ASIM_TUTAR,
    ASIM_CNT, TAM_CNT, KISMI_CNT, EKSILTEN_CNT
)' + CASE WHEN @IxOnline = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
        EXEC sys.sp_executesql @IxSql;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_AGR_FRK_KALAN'
    )
    BEGIN
        /* Filtered ABS/OR desteklenmez → key = DELTA_KALAN */
        SET @IxSql = N'
CREATE NONCLUSTERED INDEX IX_AGR_FRK_KALAN
ON energy.dbo.MIG_AGR_FRK_ALL (DELTA_KALAN)
INCLUDE (KIND_FRK, EN_KALAN, AFL_KALAN, DELTA_KALAN_EKS, DELTA_KALAN_NET, DELTA_TAH, ASIM_CNT)'
            + CASE WHEN @IxOnline = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
        EXEC sys.sp_executesql @IxSql;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_AGR_FRK_TAH_NET'
    )
    BEGIN
        SET @IxSql = N'
CREATE NONCLUSTERED INDEX IX_AGR_FRK_TAH_NET
ON energy.dbo.MIG_AGR_FRK_ALL (DELTA_TAH_NET)
INCLUDE (KIND_FRK, DELTA_TAH, DELTA_TAH_EKS, EN_IADE_TUTAR, OV_EKS_TUTAR, OV_ASIM_TUTAR, ASIM_CNT)'
            + CASE WHEN @IxOnline = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
        EXEC sys.sp_executesql @IxSql;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_AGR_FRK_ASIM'
    )
    BEGIN
        SET @IxSql = N'
CREATE NONCLUSTERED INDEX IX_AGR_FRK_ASIM
ON energy.dbo.MIG_AGR_FRK_ALL (ASIM_CNT)
INCLUDE (OV_ASIM_TUTAR, KIND_FRK, DELTA_TAH_EKS, DELTA_KALAN_EKS, DELTA_SM3_EKS)
WHERE ASIM_CNT > 0'
            + CASE WHEN @IxOnline = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
        EXEC sys.sp_executesql @IxSql;
    END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_AGR_FRK_ALL
    @Agr          BIGINT         = NULL,   -- NULL=tum | ornek 197168
    @OnlyDiff     BIT           = 0,      -- 1 = sadece fark
    @Eps          DECIMAL(18,2) = 0.02,
    @WriteTable   BIT           = 1,      -- 1 = MIG_AGR_FRK_ALL
    @ReturnResult BIT           = 0       -- 1 = grid de dondur
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    /* Tablo indeksleri (yoksa; ONLINE edition uygunsa) — deploy ile ayni set */
    IF @WriteTable = 1 AND OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL', 'U') IS NOT NULL
    BEGIN
        DECLARE @IxSql97 NVARCHAR(MAX);
        DECLARE @IxOnline97 BIT = CASE WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) IN (3, 5, 8) THEN 1 ELSE 0 END;

        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_MIG_AGR_FRK_KIND'
        )
        BEGIN
            SET @IxSql97 = N'
CREATE NONCLUSTERED INDEX IX_MIG_AGR_FRK_KIND
ON energy.dbo.MIG_AGR_FRK_ALL (KIND_FRK)
INCLUDE (
    DELTA_TAH, DELTA_TAH_EKS, DELTA_TAH_NET,
    DELTA_KALAN, DELTA_KALAN_EKS, DELTA_KALAN_NET,
    EN_IADE_TUTAR, EN_IADE_SM3, OV_EKS_TUTAR, OV_ASIM_TUTAR,
    ASIM_CNT, TAM_CNT, KISMI_CNT, EKSILTEN_CNT
)' + CASE WHEN @IxOnline97 = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
            EXEC sys.sp_executesql @IxSql97;
        END;

        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_AGR_FRK_KALAN'
        )
        BEGIN
            SET @IxSql97 = N'
CREATE NONCLUSTERED INDEX IX_AGR_FRK_KALAN
ON energy.dbo.MIG_AGR_FRK_ALL (DELTA_KALAN)
INCLUDE (KIND_FRK, EN_KALAN, AFL_KALAN, DELTA_KALAN_EKS, DELTA_KALAN_NET, DELTA_TAH, ASIM_CNT)'
                + CASE WHEN @IxOnline97 = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
            EXEC sys.sp_executesql @IxSql97;
        END;

        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_AGR_FRK_TAH_NET'
        )
        BEGIN
            SET @IxSql97 = N'
CREATE NONCLUSTERED INDEX IX_AGR_FRK_TAH_NET
ON energy.dbo.MIG_AGR_FRK_ALL (DELTA_TAH_NET)
INCLUDE (KIND_FRK, DELTA_TAH, DELTA_TAH_EKS, EN_IADE_TUTAR, OV_EKS_TUTAR, OV_ASIM_TUTAR, ASIM_CNT)'
                + CASE WHEN @IxOnline97 = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
            EXEC sys.sp_executesql @IxSql97;
        END;

        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL') AND name = N'IX_AGR_FRK_ASIM'
        )
        BEGIN
            SET @IxSql97 = N'
CREATE NONCLUSTERED INDEX IX_AGR_FRK_ASIM
ON energy.dbo.MIG_AGR_FRK_ALL (ASIM_CNT)
INCLUDE (OV_ASIM_TUTAR, KIND_FRK, DELTA_TAH_EKS, DELTA_KALAN_EKS, DELTA_SM3_EKS)
WHERE ASIM_CNT > 0'
                + CASE WHEN @IxOnline97 = 1 THEN N' WITH (ONLINE = ON, MAXDOP = 8)' ELSE N' WITH (MAXDOP = 8)' END;
            EXEC sys.sp_executesql @IxSql97;
        END;
    END;

    DECLARE @Cnt     BIGINT;
    DECLARE @Msg     NVARCHAR(200);
    DECLARE @RunId   UNIQUEIDENTIFIER = NEWID();
    DECLARE @Ts      DATETIME2(3) = SYSDATETIME();
    DECLARE @TtkFrom VARCHAR(20) =
        CASE
            WHEN OBJECT_ID('izgazMGR.dbo.TUKETIM_TUTAR_KONTROL', 'U') IS NOT NULL THEN 'izgazMGR'
            WHEN OBJECT_ID('energy.dbo.TUKETIM_TUTAR_KONTROL', 'U') IS NOT NULL THEN 'energy'
            ELSE NULL
        END;

    IF @TtkFrom IS NULL
    BEGIN
        RAISERROR('TUKETIM_TUTAR_KONTROL yok (izgazMGR O59 veya energy 93).', 16, 1);
        RETURN;
    END;

    IF OBJECT_ID('tempdb..#SEED97') IS NOT NULL DROP TABLE #SEED97;
    IF OBJECT_ID('tempdb..#INV_SEED97') IS NOT NULL DROP TABLE #INV_SEED97;
    IF OBJECT_ID('tempdb..#EN97') IS NOT NULL DROP TABLE #EN97;
    IF OBJECT_ID('tempdb..#IADE97') IS NOT NULL DROP TABLE #IADE97;
    IF OBJECT_ID('tempdb..#EKS97') IS NOT NULL DROP TABLE #EKS97;
    IF OBJECT_ID('tempdb..#ABYS97') IS NOT NULL DROP TABLE #ABYS97;
    IF OBJECT_ID('tempdb..#AFL97') IS NOT NULL DROP TABLE #AFL97;
    IF OBJECT_ID('tempdb..#AGR97') IS NOT NULL DROP TABLE #AGR97;

    SET @Msg = N'TTK=' + @TtkFrom
        + N' | AGR=' + CASE WHEN @Agr IS NULL THEN N'TUM' ELSE CONVERT(NVARCHAR(20), @Agr) END
        + N' | OnlyDiff=' + CONVERT(NVARCHAR(1), @OnlyDiff)
        + N' | WriteTable=' + CONVERT(NVARCHAR(1), @WriteTable)
        + N' | SEED=TYPE(119,121,86)/OWNERREF'
        + N' | RUN=' + CONVERT(NVARCHAR(36), @RunId);
    PRINT @Msg;
    PRINT N'SP_AGR_FRK_ALL START ' + CONVERT(VARCHAR(30), @Ts, 121);

    IF OBJECT_ID('tempdb..#RES97') IS NOT NULL DROP TABLE #RES97;

    /* ---------- Sozlesme seed: TYPE 119/121/86 × OWNERREF ---------- */
    /* @Agr verildiğinde OWNERREF=@Agr ile index seek (CAST yok) */
    CREATE TABLE #SEED97 (AGREEMENT_ID BIGINT NOT NULL PRIMARY KEY CLUSTERED);

    /* OWNERREF = INT — BIGINT @Agr ile karsilastirma seek bozar; CONVERT(INT,@Agr) */
    IF @Agr IS NOT NULL
    BEGIN
        INSERT INTO #SEED97 (AGREEMENT_ID)
        SELECT DISTINCT CAST(inv.OWNERREF AS BIGINT)
        FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.TYPE IN (119, 121, 86)
          AND inv.OWNERREF = CONVERT(INT, @Agr)
        OPTION (RECOMPILE, MAXDOP 8);

        IF NOT EXISTS (SELECT 1 FROM #SEED97)
            INSERT INTO #SEED97 (AGREEMENT_ID) VALUES (@Agr);
    END
    ELSE
    BEGIN
        INSERT INTO #SEED97 (AGREEMENT_ID)
        SELECT DISTINCT CAST(inv.OWNERREF AS BIGINT)
        FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.TYPE IN (119, 121, 86)
          AND inv.OWNERREF IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 24);
    END

    SELECT @Cnt = COUNT(*) FROM #SEED97;
    PRINT N'SEED97 OK ' + CONVERT(VARCHAR(20), @Cnt)
        + N' (beklenen ~977757 TYPE 119/121/86 OWNERREF)';

    /*
      Tek AGR: INV once materialize (#INV_SEED97) — 196'da IADE LIKE+OR ~56sn idi.
      Tum AGR: materialize YOK (140M INV); IADE UNION ALL ile ayrilir.
    */
    CREATE TABLE #EN97 (
        AGREEMENT_ID BIGINT NULL,
        ACCOUNT_ID   BIGINT NOT NULL,
        INV_CNT      INT NULL,
        INV_SUM      DECIMAL(18,2) NULL,
        SM3          DECIMAL(18,6) NULL,
        KWH          DECIMAL(18,6) NULL,
        CONSUMPTION  DECIMAL(18,6) NULL,
        PT_KALAN     DECIMAL(18,2) NULL
    );
    CREATE TABLE #IADE97 (
        AGREEMENT_ID BIGINT NULL,
        ACCOUNT_ID   BIGINT NOT NULL,
        IADE_CNT     INT NULL,
        IADE_AMT     DECIMAL(18,2) NULL,
        IADE_SM3     DECIMAL(18,6) NULL,
        IADE_KWH     DECIMAL(18,6) NULL,
        IADE_CONSUMPTION DECIMAL(18,6) NULL
    );

    IF @Agr IS NOT NULL
    BEGIN
        /* 196: OWNERREF index ~0ms; ABYS_AGREEMENT_ID ~1.5s+ */
        SELECT
            inv.LREF,
            CAST(inv.OWNERREF AS BIGINT) AS AGREEMENT_ID,
            inv.ABYS_ACCOUNT_ID AS ACCOUNT_ID,
            inv.TYPE,
            inv.IOCODE,
            inv.CANCELED,
            inv.ABYS_ACTION_TYPE_ID,
            inv.PAYABLETOTAL,
            inv.ABYS_M3,
            inv.ABYS_KWH,
            inv.ABYS_CONSUMPTION,
            inv.EXPLAIN
        INTO #INV_SEED97
        FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        WHERE inv.OWNERREF = CONVERT(INT, @Agr)
          AND inv.ABYS_ACCOUNT_ID IS NOT NULL
        OPTION (RECOMPILE, MAXDOP 8);

        CREATE CLUSTERED INDEX CX_INV_SEED97 ON #INV_SEED97 (LREF);

        SELECT @Cnt = COUNT(*) FROM #INV_SEED97;
        PRINT N'INV_SEED97 OK ' + CONVERT(VARCHAR(20), @Cnt);

        INSERT INTO #EN97 (AGREEMENT_ID, ACCOUNT_ID, INV_CNT, INV_SUM, SM3, KWH, CONSUMPTION, PT_KALAN)
        SELECT
            inv.AGREEMENT_ID,
            inv.ACCOUNT_ID,
            COUNT(*),
            CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_M3, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_KWH, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_CONSUMPTION, 0)))),
            CONVERT(DECIMAL(18,2), SUM(ISNULL(pt.PT_KALAN, 0)))
        FROM #INV_SEED97 inv
        LEFT JOIN (
            SELECT
                p.INVOICEREF,
                SUM(CONVERT(DECIMAL(18,2), ISNULL(p.PAYABLETOTAL, 0)))
              - SUM(CONVERT(DECIMAL(18,2), ISNULL(p.PAID, 0))) AS PT_KALAN
            FROM #INV_SEED97 i2
            INNER JOIN dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
                ON p.INVOICEREF = i2.LREF
            WHERE ISNULL(i2.IOCODE, 0) = 0
              AND ISNULL(i2.CANCELED, 0) = 0
              AND ISNULL(p.IOCODE, 0) = 0
              AND ISNULL(p.CANCELED, 0) = 0
              AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
            GROUP BY p.INVOICEREF
        ) pt ON pt.INVOICEREF = inv.LREF
        WHERE ISNULL(inv.IOCODE, 0) = 0
          AND ISNULL(inv.CANCELED, 0) = 0
        GROUP BY inv.AGREEMENT_ID, inv.ACCOUNT_ID
        OPTION (RECOMPILE, MAXDOP 8);

        INSERT INTO #IADE97 (AGREEMENT_ID, ACCOUNT_ID, IADE_CNT, IADE_AMT, IADE_SM3, IADE_KWH, IADE_CONSUMPTION)
        SELECT
            inv.AGREEMENT_ID,
            inv.ACCOUNT_ID,
            COUNT(*),
            CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_M3, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_KWH, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_CONSUMPTION, 0))))
        FROM #INV_SEED97 inv
        WHERE inv.TYPE = 92
           OR inv.ABYS_ACTION_TYPE_ID = 2
           OR (
                 ISNULL(inv.IOCODE, 0) = 1
             AND ISNULL(inv.TYPE, 0) <> 101
             AND (
                    UPPER(ISNULL(inv.EXPLAIN, '')) LIKE N'%IADE%'
                 OR UPPER(ISNULL(inv.EXPLAIN, '')) LIKE N'%EKSILTEN%'
             )
           )
        GROUP BY inv.AGREEMENT_ID, inv.ACCOUNT_ID
        OPTION (RECOMPILE, MAXDOP 8);
    END
    ELSE
    BEGIN
        /* FULL: PT seed-first; IADE UNION (LIKE ayri) */
        INSERT INTO #EN97 (AGREEMENT_ID, ACCOUNT_ID, INV_CNT, INV_SUM, SM3, KWH, CONSUMPTION, PT_KALAN)
        SELECT
            inv.ABYS_AGREEMENT_ID,
            inv.ABYS_ACCOUNT_ID,
            COUNT(*),
            CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_M3, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_KWH, 0)))),
            CONVERT(DECIMAL(18,6), SUM(CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_CONSUMPTION, 0)))),
            CONVERT(DECIMAL(18,2), SUM(ISNULL(pt.PT_KALAN, 0)))
        FROM dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
        INNER JOIN #SEED97 s ON s.AGREEMENT_ID = inv.ABYS_AGREEMENT_ID
        LEFT JOIN (
            SELECT
                p.INVOICEREF,
                SUM(CONVERT(DECIMAL(18,2), ISNULL(p.PAYABLETOTAL, 0)))
              - SUM(CONVERT(DECIMAL(18,2), ISNULL(p.PAID, 0))) AS PT_KALAN
            FROM #SEED97 s2
            INNER JOIN dbo.LS_005_01_INVOICE i2 WITH (NOLOCK)
                ON i2.ABYS_AGREEMENT_ID = s2.AGREEMENT_ID
            INNER JOIN dbo.LS_005_01_PAYTRANS p WITH (NOLOCK)
                ON p.INVOICEREF = i2.LREF
            WHERE ISNULL(i2.IOCODE, 0) = 0
              AND ISNULL(i2.CANCELED, 0) = 0
              AND ISNULL(p.IOCODE, 0) = 0
              AND ISNULL(p.CANCELED, 0) = 0
              AND ISNULL(p.CANCELLATIONPAYMENT, 0) = 0
            GROUP BY p.INVOICEREF
        ) pt ON pt.INVOICEREF = inv.LREF
        WHERE ISNULL(inv.IOCODE, 0) = 0
          AND ISNULL(inv.CANCELED, 0) = 0
          AND inv.ABYS_ACCOUNT_ID IS NOT NULL
        GROUP BY inv.ABYS_AGREEMENT_ID, inv.ABYS_ACCOUNT_ID
        OPTION (RECOMPILE, MAXDOP 24);

        INSERT INTO #IADE97 (AGREEMENT_ID, ACCOUNT_ID, IADE_CNT, IADE_AMT, IADE_SM3, IADE_KWH, IADE_CONSUMPTION)
        SELECT
            AGREEMENT_ID,
            ACCOUNT_ID,
            COUNT(*),
            CONVERT(DECIMAL(18,2), SUM(PAYABLETOTAL)),
            CONVERT(DECIMAL(18,6), SUM(SM3)),
            CONVERT(DECIMAL(18,6), SUM(KWH)),
            CONVERT(DECIMAL(18,6), SUM(CONSUMPTION))
        FROM (
            SELECT inv.ABYS_AGREEMENT_ID AS AGREEMENT_ID, inv.ABYS_ACCOUNT_ID AS ACCOUNT_ID,
                   CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)) AS PAYABLETOTAL,
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_M3, 0)) AS SM3,
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_KWH, 0)) AS KWH,
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_CONSUMPTION, 0)) AS CONSUMPTION,
                   inv.LREF
            FROM #SEED97 s
            INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
                ON inv.ABYS_AGREEMENT_ID = s.AGREEMENT_ID
            WHERE inv.TYPE = 92 AND inv.ABYS_ACCOUNT_ID IS NOT NULL
            UNION
            SELECT inv.ABYS_AGREEMENT_ID, inv.ABYS_ACCOUNT_ID,
                   CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)),
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_M3, 0)),
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_KWH, 0)),
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_CONSUMPTION, 0)),
                   inv.LREF
            FROM #SEED97 s
            INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
                ON inv.ABYS_AGREEMENT_ID = s.AGREEMENT_ID
            WHERE inv.ABYS_ACTION_TYPE_ID = 2
              AND ISNULL(inv.TYPE, 0) <> 92
              AND inv.ABYS_ACCOUNT_ID IS NOT NULL
            UNION
            SELECT inv.ABYS_AGREEMENT_ID, inv.ABYS_ACCOUNT_ID,
                   CONVERT(DECIMAL(18,2), ISNULL(inv.PAYABLETOTAL, 0)),
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_M3, 0)),
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_KWH, 0)),
                   CONVERT(DECIMAL(18,6), ISNULL(inv.ABYS_CONSUMPTION, 0)),
                   inv.LREF
            FROM #SEED97 s
            INNER JOIN dbo.LS_005_01_INVOICE inv WITH (NOLOCK)
                ON inv.ABYS_AGREEMENT_ID = s.AGREEMENT_ID
            WHERE ISNULL(inv.IOCODE, 0) = 1
              AND ISNULL(inv.TYPE, 0) NOT IN (92, 101)
              AND inv.ABYS_ACCOUNT_ID IS NOT NULL
              AND (
                     UPPER(ISNULL(inv.EXPLAIN, '')) LIKE N'%IADE%'
                  OR UPPER(ISNULL(inv.EXPLAIN, '')) LIKE N'%EKSILTEN%'
              )
        ) u
        GROUP BY AGREEMENT_ID, ACCOUNT_ID
        OPTION (RECOMPILE, MAXDOP 24);
    END

    CREATE CLUSTERED INDEX CX_EN97 ON #EN97 (ACCOUNT_ID);
    CREATE CLUSTERED INDEX CX_IADE97 ON #IADE97 (ACCOUNT_ID);

    SELECT @Cnt = COUNT(*) FROM #EN97;
    PRINT N'EN97 OK ' + CONVERT(VARCHAR(20), @Cnt);

    SELECT @Cnt = COUNT(*) FROM #IADE97;
    PRINT N'IADE97 OK ' + CONVERT(VARCHAR(20), @Cnt);

    /* ---------- Overlay EKS TAM/KISMI ---------- */
    CREATE TABLE #EKS97 (
        AGREEMENT_ID BIGINT NULL,
        ACCOUNT_ID   BIGINT NOT NULL,
        EKS_KIND     VARCHAR(10) NULL,
        EKS_AMT      DECIMAL(18,2) NULL
    );

    IF OBJECT_ID('izgazMGR.dbo.LS_OV_EKS_CLASS', 'U') IS NOT NULL
    BEGIN
        INSERT INTO #EKS97 (AGREEMENT_ID, ACCOUNT_ID, EKS_KIND, EKS_AMT)
        SELECT
            CAST(c.AGREEMENT_ID AS BIGINT),
            CAST(c.ACCOUNT_ID AS BIGINT),
            CASE
                WHEN SUM(CASE WHEN c.KIND = 'KISMI' THEN 1 ELSE 0 END) > 0 THEN 'KISMI'
                WHEN SUM(CASE WHEN c.KIND = 'TAM' THEN 1 ELSE 0 END) > 0 THEN 'TAM'
                WHEN SUM(CASE WHEN c.KIND = 'ASIM' THEN 1 ELSE 0 END) > 0 THEN 'ASIM'
                ELSE MAX(LEFT(CAST(c.KIND AS VARCHAR(10)), 10))
            END,
            CONVERT(DECIMAL(18,2), SUM(ISNULL(c.EKS_AMT, 0)))
        FROM izgazMGR.dbo.LS_OV_EKS_CLASS c WITH (NOLOCK)
        INNER JOIN #SEED97 s ON s.AGREEMENT_ID = c.AGREEMENT_ID
        WHERE ISNULL(c.KIND, '') IN ('TAM', 'KISMI', 'ASIM')
        GROUP BY CAST(c.AGREEMENT_ID AS BIGINT), CAST(c.ACCOUNT_ID AS BIGINT)
        OPTION (RECOMPILE, MAXDOP 8);
    END

    CREATE CLUSTERED INDEX CX_EKS97 ON #EKS97 (ACCOUNT_ID);

    SELECT @Cnt = COUNT(*) FROM #EKS97;
    PRINT N'EKS97 OK ' + CONVERT(VARCHAR(20), @Cnt);

    /* ---------- ABYS TTK (+ tuketim M3/KWH) ---------- */
    CREATE TABLE #ABYS97 (
        AGREEMENT_ID     BIGINT NULL,
        ACCOUNT_ID       BIGINT NOT NULL,
        TOPLAM_TAHAKKUK  DECIMAL(18,2) NULL,
        SM3              DECIMAL(18,6) NULL,
        KWH              DECIMAL(18,6) NULL,
        CONSUMPTION      DECIMAL(18,6) NULL
    );

    IF @TtkFrom = 'izgazMGR'
        INSERT INTO #ABYS97 (AGREEMENT_ID, ACCOUNT_ID, TOPLAM_TAHAKKUK, SM3, KWH, CONSUMPTION)
        SELECT
            CAST(t.AGREEMENT_ID AS BIGINT),
            CAST(t.ACCOUNT_ID AS BIGINT),
            CONVERT(DECIMAL(18,2), t.TOPLAM_TAHAKKUK),
            CONVERT(DECIMAL(18,6), t.M3),
            CONVERT(DECIMAL(18,6), t.KWH),
            CONVERT(DECIMAL(18,6), t.CONSUMPTION)
        FROM izgazMGR.dbo.TUKETIM_TUTAR_KONTROL t WITH (NOLOCK)
        INNER JOIN #SEED97 s ON s.AGREEMENT_ID = t.AGREEMENT_ID
        OPTION (RECOMPILE, MAXDOP 8);
    ELSE
        INSERT INTO #ABYS97 (AGREEMENT_ID, ACCOUNT_ID, TOPLAM_TAHAKKUK, SM3, KWH, CONSUMPTION)
        SELECT
            CAST(t.AGREEMENT_ID AS BIGINT),
            CAST(t.ACCOUNT_ID AS BIGINT),
            CONVERT(DECIMAL(18,2), t.TOPLAM_TAHAKKUK),
            CONVERT(DECIMAL(18,6), t.M3),
            CONVERT(DECIMAL(18,6), t.KWH),
            CONVERT(DECIMAL(18,6), t.CONSUMPTION)
        FROM energy.dbo.TUKETIM_TUTAR_KONTROL t WITH (NOLOCK)
        INNER JOIN #SEED97 s ON s.AGREEMENT_ID = t.AGREEMENT_ID
        OPTION (RECOMPILE, MAXDOP 8);

    CREATE CLUSTERED INDEX CX_ABYS97 ON #ABYS97 (ACCOUNT_ID);

    SELECT @Cnt = COUNT(*) FROM #ABYS97;
    PRINT N'ABYS97 OK ' + CONVERT(VARCHAR(20), @Cnt);

    /* ---------- AFL (kapsamdaki hesaplar) ---------- */
    SELECT
        CAST(a.FATURAID AS BIGINT) AS ACCOUNT_ID,
        CONVERT(DECIMAL(18,2), ISNULL(a.BALANCE, 0)) AS AFL_BALANCE
    INTO #AFL97
    FROM dbo.LS_AFL_OPEN_DEBT a WITH (NOLOCK)
    WHERE @Agr IS NULL
       OR a.FATURAID IN (
            SELECT ACCOUNT_ID FROM #EN97
            UNION
            SELECT ACCOUNT_ID FROM #ABYS97
          )
    OPTION (RECOMPILE, MAXDOP 24);

    CREATE CLUSTERED INDEX CX_AFL97 ON #AFL97 (ACCOUNT_ID);

    /* ---------- Account grain ---------- */
    SELECT
        COALESCE(en.AGREEMENT_ID, abys.AGREEMENT_ID, eks.AGREEMENT_ID, iade.AGREEMENT_ID) AS AGREEMENT_ID,
        COALESCE(en.ACCOUNT_ID, abys.ACCOUNT_ID, eks.ACCOUNT_ID, iade.ACCOUNT_ID) AS ACCOUNT_ID,
        CASE WHEN en.ACCOUNT_ID IS NOT NULL THEN 1 ELSE 0 END AS HAS_EN,
        CASE WHEN abys.ACCOUNT_ID IS NOT NULL THEN 1 ELSE 0 END AS HAS_ABYS,
        ISNULL(en.INV_CNT, 0) AS INV_CNT,
        ISNULL(en.INV_SUM, 0) AS INV_SUM,
        ISNULL(en.SM3, 0) AS EN_SM3,
        ISNULL(en.KWH, 0) AS EN_KWH,
        ISNULL(en.CONSUMPTION, 0) AS EN_CONSUMPTION,
        ISNULL(en.PT_KALAN, 0) AS PT_KALAN,
        ISNULL(abys.TOPLAM_TAHAKKUK, 0) AS ABYS_TAH,
        ISNULL(abys.SM3, 0) AS ABYS_SM3,
        ISNULL(abys.KWH, 0) AS ABYS_KWH,
        ISNULL(abys.CONSUMPTION, 0) AS ABYS_CONSUMPTION,
        ISNULL(iade.IADE_AMT, 0) AS IADE_AMT,
        ISNULL(iade.IADE_CNT, 0) AS IADE_CNT,
        ISNULL(iade.IADE_SM3, 0) AS IADE_SM3,
        ISNULL(iade.IADE_KWH, 0) AS IADE_KWH,
        ISNULL(iade.IADE_CONSUMPTION, 0) AS IADE_CONSUMPTION,
        eks.EKS_KIND,
        ISNULL(eks.EKS_AMT, 0) AS EKS_AMT,
        ISNULL(afl.AFL_BALANCE, 0) AS AFL_BALANCE
    INTO #AGR97
    FROM #EN97 en
    FULL OUTER JOIN #ABYS97 abys
        ON abys.ACCOUNT_ID = en.ACCOUNT_ID
    FULL OUTER JOIN #EKS97 eks
        ON eks.ACCOUNT_ID = COALESCE(en.ACCOUNT_ID, abys.ACCOUNT_ID)
    FULL OUTER JOIN #IADE97 iade
        ON iade.ACCOUNT_ID = COALESCE(en.ACCOUNT_ID, abys.ACCOUNT_ID, eks.ACCOUNT_ID)
    LEFT JOIN #AFL97 afl
        ON afl.ACCOUNT_ID = COALESCE(en.ACCOUNT_ID, abys.ACCOUNT_ID, eks.ACCOUNT_ID, iade.ACCOUNT_ID)
    OPTION (RECOMPILE, MAXDOP 24);

    CREATE NONCLUSTERED INDEX IX_AGR97 ON #AGR97 (AGREEMENT_ID);

    SELECT @Cnt = COUNT(*) FROM #AGR97;
    PRINT N'AGR97 ACC OK ' + CONVERT(VARCHAR(20), @Cnt);

    /* ---------- 1 satir = 1 seed sozlesme → #RES97 ---------- */
    SELECT
        s.AGREEMENT_ID,
        CASE
            WHEN ISNULL(x.ACC_UNION, 0) = 0
                THEN 'NO_DATA'
            WHEN ABS(ISNULL(x.DELTA_TAH, 0)) <= @Eps
             AND ABS(ISNULL(x.DELTA_KALAN, 0)) <= @Eps
             AND ISNULL(x.TAH_DIFF_CNT, 0) = 0
                THEN 'MATCH'
            WHEN ISNULL(x.EKSILTEN_CNT, 0) > 0
             AND ABS(ISNULL(x.DELTA_TAH, 0)) <= @Eps
             AND ABS(ISNULL(x.DELTA_KALAN, 0)) <= @Eps
                THEN 'EKSILTEN_OK'
            WHEN ISNULL(x.EKSILTEN_CNT, 0) > 0
             AND ABS(ISNULL(x.DELTA_TAH, 0)) > @Eps
                THEN 'EKSILTEN_FRK'
            WHEN ISNULL(x.ONLY_EN_CNT, 0) > 0 AND ISNULL(x.ONLY_ABYS_CNT, 0) = 0
             AND ISNULL(x.TAH_DIFF_CNT, 0) = ISNULL(x.ONLY_EN_CNT, 0)
                THEN 'ONLY_EN'
            WHEN ISNULL(x.ONLY_ABYS_CNT, 0) > 0 AND ISNULL(x.ONLY_EN_CNT, 0) = 0
             AND ISNULL(x.TAH_DIFF_CNT, 0) = ISNULL(x.ONLY_ABYS_CNT, 0)
                THEN 'ONLY_ABYS'
            WHEN ISNULL(x.DELTA_TAH, 0) > @Eps
                THEN 'EN_GT_ABYS'
            WHEN ISNULL(x.DELTA_TAH, 0) < -@Eps
                THEN 'ABYS_GT_EN'
            WHEN ABS(ISNULL(x.DELTA_KALAN, 0)) > @Eps
                THEN 'KALAN_FRK'
            WHEN ISNULL(x.TAH_DIFF_CNT, 0) > 0
                THEN 'TAH_FRK'
            ELSE 'OTHER'
        END AS KIND_FRK,
        CASE
            WHEN ISNULL(x.ACC_UNION, 0) = 0
                THEN N'Seed sozlesme (TYPE 119/121/86) var; hesap metrigi yok'
            WHEN ABS(ISNULL(x.DELTA_TAH, 0)) <= @Eps
             AND ABS(ISNULL(x.DELTA_KALAN, 0)) <= @Eps
             AND ISNULL(x.TAH_DIFF_CNT, 0) = 0
                THEN N'Tahakkuk ve kalan birebir (Energy ≈ ABYS/AFL)'
            WHEN ISNULL(x.EKSILTEN_CNT, 0) > 0
             AND ABS(ISNULL(x.DELTA_TAH, 0)) <= @Eps
             AND ABS(ISNULL(x.DELTA_KALAN, 0)) <= @Eps
                THEN N'Eksilten var (TAM='
                   + CONVERT(NVARCHAR(20), ISNULL(x.TAM_CNT, 0))
                   + N' KISMI=' + CONVERT(NVARCHAR(20), ISNULL(x.KISMI_CNT, 0))
                   + N') - tutarlar uyumlu; fark beklenmez'
            WHEN ISNULL(x.EKSILTEN_CNT, 0) > 0
             AND ISNULL(x.DELTA_TAH, 0) > @Eps
                THEN N'Eksiltenli: Energy tahakkuk > ABYS (DELTA='
                   + CONVERT(NVARCHAR(40), x.DELTA_TAH)
                   + N'). Hesap EN=' + CONVERT(NVARCHAR(20), x.EN_ACC_CNT)
                   + N' ABYS=' + CONVERT(NVARCHAR(20), x.ABYS_ACC_CNT)
                   + N' | IADE=' + CONVERT(NVARCHAR(40), x.EN_IADE_TUTAR)
                   + N' IADE_SM3=' + CONVERT(NVARCHAR(40), x.EN_IADE_SM3)
                   + N' OV_EKS=' + CONVERT(NVARCHAR(40), x.OV_EKS_TUTAR)
                   + N' ASIM=' + CONVERT(NVARCHAR(20), x.ASIM_CNT)
                   + N'/' + CONVERT(NVARCHAR(40), x.OV_ASIM_TUTAR)
                   + N' | DELTA_SM3_EKS=' + CONVERT(NVARCHAR(40), x.DELTA_SM3_EKS)
                   + N' NET_SM3=' + CONVERT(NVARCHAR(40), x.DELTA_SM3_NET)
                   + N' KALAN_EKS=' + CONVERT(NVARCHAR(40), x.DELTA_KALAN_EKS)
                   + N' - TAM/ASIM: Energy MAIN INV+M3 kalir, ABYS TTK=0; iptal INV borc suma girmez'
            WHEN ISNULL(x.EKSILTEN_CNT, 0) > 0
             AND ISNULL(x.DELTA_TAH, 0) < -@Eps
                THEN N'Eksiltenli: ABYS tahakkuk > Energy (DELTA='
                   + CONVERT(NVARCHAR(40), x.DELTA_TAH)
                   + N'). Hesap EN=' + CONVERT(NVARCHAR(20), x.EN_ACC_CNT)
                   + N' ABYS=' + CONVERT(NVARCHAR(20), x.ABYS_ACC_CNT)
                   + N' | OV_EKS=' + CONVERT(NVARCHAR(40), x.OV_EKS_TUTAR)
                   + N' - KISMI sonrasi Energy MAIN dusuk / ABYS TTK yuksek olabilir'
            WHEN ISNULL(x.ONLY_EN_CNT, 0) > 0 AND ISNULL(x.ONLY_ABYS_CNT, 0) > 0
                THEN N'Hesap adedi: EN='
                   + CONVERT(NVARCHAR(20), x.EN_ACC_CNT)
                   + N' ABYS=' + CONVERT(NVARCHAR(20), x.ABYS_ACC_CNT)
                   + N' (birlesik=' + CONVERT(NVARCHAR(20), x.ACC_UNION)
                   + N') | sadece EN=' + CONVERT(NVARCHAR(20), x.ONLY_EN_CNT)
                   + N' sadece ABYS=' + CONVERT(NVARCHAR(20), x.ONLY_ABYS_CNT)
                   + N' | DELTA_TAH=' + CONVERT(NVARCHAR(40), x.DELTA_TAH)
            WHEN ISNULL(x.ONLY_EN_CNT, 0) > 0 AND ISNULL(x.DELTA_TAH, 0) > @Eps
                THEN N'Energy de '
                   + CONVERT(NVARCHAR(20), x.ONLY_EN_CNT)
                   + N' hesap var, ABYS TTK yok/0 - Energy fazla tahakkuk (DELTA='
                   + CONVERT(NVARCHAR(40), x.DELTA_TAH) + N')'
            WHEN ISNULL(x.ONLY_ABYS_CNT, 0) > 0 AND ISNULL(x.DELTA_TAH, 0) < -@Eps
                THEN N'ABYS TTK de '
                   + CONVERT(NVARCHAR(20), x.ONLY_ABYS_CNT)
                   + N' hesap var, Energy borc INV yok - ABYS fazla (DELTA='
                   + CONVERT(NVARCHAR(40), x.DELTA_TAH) + N')'
            WHEN ISNULL(x.DELTA_TAH, 0) > @Eps
                THEN N'Energy tahakkuk > ABYS (DELTA='
                   + CONVERT(NVARCHAR(40), x.DELTA_TAH)
                   + N', farkli hesap=' + CONVERT(NVARCHAR(20), x.TAH_DIFF_CNT) + N')'
            WHEN ISNULL(x.DELTA_TAH, 0) < -@Eps
                THEN N'ABYS tahakkuk > Energy (DELTA='
                   + CONVERT(NVARCHAR(40), x.DELTA_TAH)
                   + N', farkli hesap=' + CONVERT(NVARCHAR(20), x.TAH_DIFF_CNT) + N')'
            WHEN ISNULL(x.DELTA_KALAN, 0) > @Eps
                THEN N'Energy acik kalan > AFL (DELTA_KALAN='
                   + CONVERT(NVARCHAR(40), x.DELTA_KALAN)
                   + N') - Energy de kapanmamis borc / AFL eksik'
            WHEN ISNULL(x.DELTA_KALAN, 0) < -@Eps
                THEN N'AFL > Energy kalan (DELTA_KALAN='
                   + CONVERT(NVARCHAR(40), x.DELTA_KALAN)
                   + N') - AFL acik, Energy kapanmis veya eksik'
            WHEN ISNULL(x.TAH_DIFF_CNT, 0) > 0
                THEN N'Tahakkuk satirlari uyumsuz (hesap adedi='
                   + CONVERT(NVARCHAR(20), x.TAH_DIFF_CNT)
                   + N') fakat toplam DELTA~0 - dagilim farki'
            ELSE N'Inceleme gerekli'
        END AS ACIKLAMA,
        @TtkFrom AS TTK_SOURCE,
        ISNULL(x.EN_ACC_CNT, 0) AS EN_ACC_CNT,
        ISNULL(x.ABYS_ACC_CNT, 0) AS ABYS_ACC_CNT,
        ISNULL(x.ACC_UNION, 0) AS ACC_UNION,
        ISNULL(x.INV_CNT, 0) AS INV_CNT,
        ISNULL(x.EN_TAH_TUTAR, 0) AS EN_TAH_TUTAR,
        ISNULL(x.ABYS_TAH_TUTAR, 0) AS ABYS_TAH_TUTAR,
        ISNULL(x.DELTA_TAH, 0) AS DELTA_TAH,
        ISNULL(x.EN_SM3, 0) AS EN_SM3,
        ISNULL(x.ABYS_SM3, 0) AS ABYS_SM3,
        CONVERT(DECIMAL(18,6), ISNULL(x.EN_SM3, 0) - ISNULL(x.ABYS_SM3, 0)) AS DELTA_SM3,
        ISNULL(x.DELTA_SM3_EKS, 0) AS DELTA_SM3_EKS,
        ISNULL(x.DELTA_SM3_NET, 0) AS DELTA_SM3_NET,
        ISNULL(x.EN_KWH, 0) AS EN_KWH,
        ISNULL(x.ABYS_KWH, 0) AS ABYS_KWH,
        CONVERT(DECIMAL(18,6), ISNULL(x.EN_KWH, 0) - ISNULL(x.ABYS_KWH, 0)) AS DELTA_KWH,
        ISNULL(x.DELTA_KWH_EKS, 0) AS DELTA_KWH_EKS,
        ISNULL(x.DELTA_KWH_NET, 0) AS DELTA_KWH_NET,
        ISNULL(x.EN_CONSUMPTION, 0) AS EN_CONSUMPTION,
        ISNULL(x.ABYS_CONSUMPTION, 0) AS ABYS_CONSUMPTION,
        CONVERT(DECIMAL(18,6), ISNULL(x.EN_CONSUMPTION, 0) - ISNULL(x.ABYS_CONSUMPTION, 0)) AS DELTA_CONSUMPTION,
        ISNULL(x.DELTA_CONSUMPTION_EKS, 0) AS DELTA_CONSUMPTION_EKS,
        ISNULL(x.DELTA_CONSUMPTION_NET, 0) AS DELTA_CONSUMPTION_NET,
        ISNULL(x.EN_IADE_TUTAR, 0) AS EN_IADE_TUTAR,
        ISNULL(x.EN_IADE_SM3, 0) AS EN_IADE_SM3,
        ISNULL(x.EN_IADE_KWH, 0) AS EN_IADE_KWH,
        ISNULL(x.EN_IADE_CONSUMPTION, 0) AS EN_IADE_CONSUMPTION,
        ISNULL(x.OV_EKS_TUTAR, 0) AS OV_EKS_TUTAR,
        ISNULL(x.OV_ASIM_TUTAR, 0) AS OV_ASIM_TUTAR,
        ISNULL(x.DELTA_TAH_EKS, 0) AS DELTA_TAH_EKS,
        ISNULL(x.DELTA_TAH_NET, 0) AS DELTA_TAH_NET,
        ISNULL(x.EKSILTEN_CNT, 0) AS EKSILTEN_CNT,
        ISNULL(x.TAM_CNT, 0) AS TAM_CNT,
        ISNULL(x.KISMI_CNT, 0) AS KISMI_CNT,
        ISNULL(x.ASIM_CNT, 0) AS ASIM_CNT,
        ISNULL(x.ONLY_EN_CNT, 0) AS ONLY_EN_CNT,
        ISNULL(x.ONLY_ABYS_CNT, 0) AS ONLY_ABYS_CNT,
        ISNULL(x.TAH_MATCH_CNT, 0) AS TAH_MATCH_CNT,
        ISNULL(x.TAH_DIFF_CNT, 0) AS TAH_DIFF_CNT,
        ISNULL(x.EN_KALAN, 0) AS EN_KALAN,
        ISNULL(x.AFL_KALAN, 0) AS AFL_KALAN,
        ISNULL(x.DELTA_KALAN, 0) AS DELTA_KALAN,
        ISNULL(x.DELTA_KALAN_EKS, 0) AS DELTA_KALAN_EKS,
        ISNULL(x.DELTA_KALAN_NET, 0) AS DELTA_KALAN_NET
    INTO #RES97
    FROM #SEED97 s
    LEFT JOIN (
        SELECT
            a.AGREEMENT_ID,
            SUM(a.HAS_EN) AS EN_ACC_CNT,
            SUM(a.HAS_ABYS) AS ABYS_ACC_CNT,
            COUNT(*) AS ACC_UNION,
            SUM(a.INV_CNT) AS INV_CNT,
            CONVERT(DECIMAL(18,2), SUM(a.INV_SUM)) AS EN_TAH_TUTAR,
            CONVERT(DECIMAL(18,2), SUM(a.ABYS_TAH)) AS ABYS_TAH_TUTAR,
            CONVERT(DECIMAL(18,2), SUM(a.INV_SUM) - SUM(a.ABYS_TAH)) AS DELTA_TAH,
            /* EKS bucket: TAM/KISMI/ASIM overlay veya IADE fis */
            CONVERT(DECIMAL(18,2), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN a.INV_SUM - a.ABYS_TAH
                ELSE 0 END)) AS DELTA_TAH_EKS,
            CONVERT(DECIMAL(18,2), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                ELSE a.INV_SUM - a.ABYS_TAH END)) AS DELTA_TAH_NET,
            CONVERT(DECIMAL(18,6), SUM(a.EN_SM3)) AS EN_SM3,
            CONVERT(DECIMAL(18,6), SUM(a.ABYS_SM3)) AS ABYS_SM3,
            CONVERT(DECIMAL(18,6), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN a.EN_SM3 - a.ABYS_SM3
                ELSE 0 END)) AS DELTA_SM3_EKS,
            CONVERT(DECIMAL(18,6), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                ELSE a.EN_SM3 - a.ABYS_SM3 END)) AS DELTA_SM3_NET,
            CONVERT(DECIMAL(18,6), SUM(a.EN_KWH)) AS EN_KWH,
            CONVERT(DECIMAL(18,6), SUM(a.ABYS_KWH)) AS ABYS_KWH,
            CONVERT(DECIMAL(18,6), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN a.EN_KWH - a.ABYS_KWH
                ELSE 0 END)) AS DELTA_KWH_EKS,
            CONVERT(DECIMAL(18,6), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                ELSE a.EN_KWH - a.ABYS_KWH END)) AS DELTA_KWH_NET,
            CONVERT(DECIMAL(18,6), SUM(a.EN_CONSUMPTION)) AS EN_CONSUMPTION,
            CONVERT(DECIMAL(18,6), SUM(a.ABYS_CONSUMPTION)) AS ABYS_CONSUMPTION,
            CONVERT(DECIMAL(18,6), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0
                    THEN a.EN_CONSUMPTION - a.ABYS_CONSUMPTION
                ELSE 0 END)) AS DELTA_CONSUMPTION_EKS,
            CONVERT(DECIMAL(18,6), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                ELSE a.EN_CONSUMPTION - a.ABYS_CONSUMPTION END)) AS DELTA_CONSUMPTION_NET,
            CONVERT(DECIMAL(18,2), SUM(a.IADE_AMT)) AS EN_IADE_TUTAR,
            CONVERT(DECIMAL(18,6), SUM(a.IADE_SM3)) AS EN_IADE_SM3,
            CONVERT(DECIMAL(18,6), SUM(a.IADE_KWH)) AS EN_IADE_KWH,
            CONVERT(DECIMAL(18,6), SUM(a.IADE_CONSUMPTION)) AS EN_IADE_CONSUMPTION,
            CONVERT(DECIMAL(18,2), SUM(CASE
                WHEN a.EKS_KIND IN ('TAM', 'KISMI') THEN a.EKS_AMT ELSE 0 END)) AS OV_EKS_TUTAR,
            CONVERT(DECIMAL(18,2), SUM(CASE
                WHEN a.EKS_KIND = 'ASIM' THEN a.EKS_AMT ELSE 0 END)) AS OV_ASIM_TUTAR,
            /* KIND_FRK tetikleyici: TAM/KISMI/IADE (saf ASIM ASIM_CNT ile) */
            SUM(CASE
                    WHEN a.EKS_KIND IN ('TAM', 'KISMI') OR a.IADE_CNT > 0 THEN 1
                    ELSE 0
                END) AS EKSILTEN_CNT,
            SUM(CASE WHEN a.EKS_KIND = 'TAM' THEN 1 ELSE 0 END) AS TAM_CNT,
            SUM(CASE WHEN a.EKS_KIND = 'KISMI' THEN 1 ELSE 0 END) AS KISMI_CNT,
            SUM(CASE WHEN a.EKS_KIND = 'ASIM' THEN 1 ELSE 0 END) AS ASIM_CNT,
            SUM(CASE WHEN a.HAS_EN = 1 AND a.HAS_ABYS = 0 THEN 1 ELSE 0 END) AS ONLY_EN_CNT,
            SUM(CASE WHEN a.HAS_EN = 0 AND a.HAS_ABYS = 1 THEN 1 ELSE 0 END) AS ONLY_ABYS_CNT,
            SUM(CASE
                    WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                    WHEN a.HAS_EN = 1 AND a.HAS_ABYS = 1
                     AND ABS(a.INV_SUM - a.ABYS_TAH) <= @Eps THEN 1
                    ELSE 0
                END) AS TAH_MATCH_CNT,
            SUM(CASE
                    WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                    WHEN a.HAS_EN = 1 AND a.HAS_ABYS = 1
                     AND ABS(a.INV_SUM - a.ABYS_TAH) <= @Eps THEN 0
                    WHEN a.HAS_EN = 0 AND a.HAS_ABYS = 0 THEN 0
                    ELSE 1
                END) AS TAH_DIFF_CNT,
            CONVERT(DECIMAL(18,2), SUM(a.PT_KALAN)) AS EN_KALAN,
            CONVERT(DECIMAL(18,2), SUM(a.AFL_BALANCE)) AS AFL_KALAN,
            CONVERT(DECIMAL(18,2), SUM(a.PT_KALAN) - SUM(a.AFL_BALANCE)) AS DELTA_KALAN,
            CONVERT(DECIMAL(18,2), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0
                    THEN a.PT_KALAN - a.AFL_BALANCE
                ELSE 0 END)) AS DELTA_KALAN_EKS,
            CONVERT(DECIMAL(18,2), SUM(CASE
                WHEN a.EKS_KIND IS NOT NULL OR a.IADE_CNT > 0 THEN 0
                ELSE a.PT_KALAN - a.AFL_BALANCE END)) AS DELTA_KALAN_NET
        FROM #AGR97 a
        INNER JOIN #SEED97 sx ON sx.AGREEMENT_ID = a.AGREEMENT_ID
        GROUP BY a.AGREEMENT_ID
    ) x ON x.AGREEMENT_ID = s.AGREEMENT_ID
    WHERE @OnlyDiff = 0
       OR ISNULL(x.TAH_DIFF_CNT, 0) > 0
       OR ABS(ISNULL(x.DELTA_TAH, 0)) > @Eps
       OR ABS(ISNULL(x.DELTA_KALAN, 0)) > @Eps
       OR ABS(ISNULL(x.DELTA_SM3_NET, 0)) > @Eps
       OR ABS(ISNULL(x.DELTA_KWH_NET, 0)) > @Eps
       OR ABS(ISNULL(x.DELTA_CONSUMPTION_NET, 0)) > @Eps
       OR ISNULL(x.ASIM_CNT, 0) > 0
    OPTION (RECOMPILE, MAXDOP 24);

    SELECT @Cnt = COUNT(*) FROM #RES97;
    PRINT N'RES97 OK ' + CONVERT(VARCHAR(20), @Cnt);

    /* ---------- MIG_AGR_FRK_ALL ---------- */
    IF @WriteTable = 1
    BEGIN
        IF OBJECT_ID('energy.dbo.MIG_AGR_FRK_ALL', 'U') IS NULL
        BEGIN
            RAISERROR('MIG_AGR_FRK_ALL yok — 97_agr_frk_all.sql CREATE TABLE bolumunu calistir.', 16, 1);
            RETURN;
        END;

        IF @Agr IS NULL
            TRUNCATE TABLE energy.dbo.MIG_AGR_FRK_ALL;
        ELSE
            DELETE FROM energy.dbo.MIG_AGR_FRK_ALL
            WHERE AGREEMENT_ID = @Agr;

        INSERT INTO energy.dbo.MIG_AGR_FRK_ALL (
            RUN_ID, SNAPSHOT_TS, AGREEMENT_ID, KIND_FRK, ACIKLAMA, TTK_SOURCE,
            EN_ACC_CNT, ABYS_ACC_CNT, ACC_UNION, INV_CNT,
            EN_TAH_TUTAR, ABYS_TAH_TUTAR, DELTA_TAH,
            EN_SM3, ABYS_SM3, DELTA_SM3, DELTA_SM3_EKS, DELTA_SM3_NET,
            EN_KWH, ABYS_KWH, DELTA_KWH, DELTA_KWH_EKS, DELTA_KWH_NET,
            EN_CONSUMPTION, ABYS_CONSUMPTION,
            DELTA_CONSUMPTION, DELTA_CONSUMPTION_EKS, DELTA_CONSUMPTION_NET,
            EN_IADE_TUTAR, EN_IADE_SM3, EN_IADE_KWH, EN_IADE_CONSUMPTION,
            OV_EKS_TUTAR, OV_ASIM_TUTAR, DELTA_TAH_EKS, DELTA_TAH_NET,
            EKSILTEN_CNT, TAM_CNT, KISMI_CNT, ASIM_CNT, ONLY_EN_CNT, ONLY_ABYS_CNT,
            TAH_MATCH_CNT, TAH_DIFF_CNT,
            EN_KALAN, AFL_KALAN, DELTA_KALAN, DELTA_KALAN_EKS, DELTA_KALAN_NET
        )
        SELECT
            @RunId, @Ts, AGREEMENT_ID, KIND_FRK, ACIKLAMA, TTK_SOURCE,
            EN_ACC_CNT, ABYS_ACC_CNT, ACC_UNION, INV_CNT,
            EN_TAH_TUTAR, ABYS_TAH_TUTAR, DELTA_TAH,
            EN_SM3, ABYS_SM3, DELTA_SM3, DELTA_SM3_EKS, DELTA_SM3_NET,
            EN_KWH, ABYS_KWH, DELTA_KWH, DELTA_KWH_EKS, DELTA_KWH_NET,
            EN_CONSUMPTION, ABYS_CONSUMPTION,
            DELTA_CONSUMPTION, DELTA_CONSUMPTION_EKS, DELTA_CONSUMPTION_NET,
            EN_IADE_TUTAR, EN_IADE_SM3, EN_IADE_KWH, EN_IADE_CONSUMPTION,
            OV_EKS_TUTAR, OV_ASIM_TUTAR, DELTA_TAH_EKS, DELTA_TAH_NET,
            EKSILTEN_CNT, TAM_CNT, KISMI_CNT, ASIM_CNT, ONLY_EN_CNT, ONLY_ABYS_CNT,
            TAH_MATCH_CNT, TAH_DIFF_CNT,
            EN_KALAN, AFL_KALAN, DELTA_KALAN, DELTA_KALAN_EKS, DELTA_KALAN_NET
        FROM #RES97
        OPTION (RECOMPILE, MAXDOP 24);

        PRINT N'MIG_AGR_FRK_ALL INSERT n=' + CONVERT(VARCHAR(20), @@ROWCOUNT)
            + N' | RUN=' + CONVERT(NVARCHAR(36), @RunId);

        PRINT N'========== KIND OZET (MIG_AGR_FRK_ALL) ==========';
        SELECT KIND_FRK, COUNT(*) AS CNT
        FROM energy.dbo.MIG_AGR_FRK_ALL WITH (NOLOCK)
        GROUP BY KIND_FRK
        ORDER BY CNT DESC;
    END;

    IF @ReturnResult = 1
    BEGIN
        SELECT *
        FROM #RES97
        ORDER BY
            CASE
                WHEN ACC_UNION = 0 THEN 0
                WHEN ABS(DELTA_TAH) <= @Eps AND ABS(DELTA_KALAN) <= @Eps AND TAH_DIFF_CNT = 0 THEN 2
                ELSE 1
            END,
            ABS(DELTA_TAH) DESC,
            ABS(DELTA_KALAN) DESC,
            AGREEMENT_ID;
    END;

    PRINT N'SP_AGR_FRK_ALL OK ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121)
        + N' | tablo=energy.dbo.MIG_AGR_FRK_ALL';
END;
GO

/* Ornek:
   EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 0;              -- ~977k → MIG_AGR_FRK_ALL
   EXEC dbo.SP_AGR_FRK_ALL @Agr = NULL, @OnlyDiff = 1;              -- sadece FRK
   EXEC dbo.SP_AGR_FRK_ALL @Agr = 197168, @ReturnResult = 1;        -- tek AGR + grid
   SELECT KIND_FRK, COUNT(*) FROM energy.dbo.MIG_AGR_FRK_ALL GROUP BY KIND_FRK;
   -- Fark okuma: EN_IADE_SM3, ASIM_CNT/OV_ASIM_TUTAR, DELTA_*_EKS vs _NET, DELTA_KALAN_EKS
*/
