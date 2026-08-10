/* ============================================================
   prodREADY_ENERGY / 00c_enrich_mgr_kismi_lineexp.sql
   Dump sonrasi (izgazMGR) — KISMI INVLINES LINEEXP'e gelir adi

   Once: Oracle dump → izgazMGR.LS_OV_KISMI_INVLINES
   Sonra: 00b_align_mgr_varchar → BU SCRIPT (batch)
   Sonra: 00_pre_indexes (KISMI IX) → 590

   Format: Kismi Eksilten | {gelir} | EKS={ABYS_EKS_ACTION_ID}
   Kaynak: energy.LS_INCOME_PRM (OLD_REF / LREF)

   128/64 core: MAXDOP 48 (tek statement); 128 CXPACKET riski — artirma.
   ~550K UPDATE: LREF batch (log/lock/timeout guvenli).
   ============================================================ */
USE izgazMGR;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Msg NVARCHAR(400);
DECLARE @N BIGINT = 0;
DECLARE @BatchN INT;
DECLARE @Total BIGINT = 0;
DECLARE @BatchSize INT = 100000;
DECLARE @Lo BIGINT = 0;
DECLARE @Hi BIGINT;
DECLARE @MaxDop INT = 48;   /* makine 64–128 logical: 48 ideal; 128 verme */
DECLARE @Ts VARCHAR(30) = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
DECLARE @sql NVARCHAR(MAX);

SET @Msg = @Ts + N' | 00c KISMI LINEEXP enrich START batch='
         + CAST(@BatchSize AS NVARCHAR(20)) + N' MAXDOP=' + CAST(@MaxDop AS NVARCHAR(10));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

IF OBJECT_ID('dbo.LS_OV_KISMI_INVLINES', 'U') IS NULL
BEGIN
    RAISERROR('izgazMGR.dbo.LS_OV_KISMI_INVLINES yok — once O20 dump.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('energy.dbo.LS_INCOME_PRM', 'U') IS NULL
BEGIN
    RAISERROR('energy.dbo.LS_INCOME_PRM yok — gelir adi kaynagi gerekli.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('dbo.LS_OV_KISMI_INVLINES', 'LINEEXP') IS NULL
   OR COL_LENGTH('dbo.LS_OV_KISMI_INVLINES', 'ABYS_INCOME_ID') IS NULL
BEGIN
    RAISERROR('LINEEXP / ABYS_INCOME_ID kolonu yok.', 16, 1);
    RETURN;
END;

/* Seek yardimci — 00_pre_indexes da ekler; burada idempotent */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.LS_OV_KISMI_INVLINES')
      AND name = 'IX_MIG_LS_OV_KISMI_INVLINES_LREF'
)
    CREATE NONCLUSTERED INDEX IX_MIG_LS_OV_KISMI_INVLINES_LREF
        ON dbo.LS_OV_KISMI_INVLINES (LREF)
        WITH (MAXDOP = 48, SORT_IN_TEMPDB = ON);

/* Prefab gelir adi */
IF OBJECT_ID('tempdb..#INC') IS NOT NULL DROP TABLE #INC;
;WITH src AS (
    SELECT
        CAST(COALESCE(p.OLD_REF, p.LREF) AS INT) AS INCOME_ID,
        LEFT(
            COALESCE(
                NULLIF(LTRIM(RTRIM(p.VALUE_TR)), N''),
                NULLIF(LTRIM(RTRIM(p.CODE)), N''),
                CAST(COALESCE(p.OLD_REF, p.LREF) AS NVARCHAR(20))
            ),
            60
        ) AS INCOME_NAME,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(COALESCE(p.OLD_REF, p.LREF) AS INT)
            ORDER BY CASE WHEN p.OLD_REF IS NOT NULL THEN 0 ELSE 1 END, p.LREF
        ) AS RN
    FROM energy.dbo.LS_INCOME_PRM p WITH (NOLOCK)
    WHERE COALESCE(p.OLD_REF, p.LREF) IS NOT NULL
)
SELECT INCOME_ID, INCOME_NAME
INTO #INC
FROM src
WHERE RN = 1
OPTION (RECOMPILE, MAXDOP 48);

CREATE UNIQUE CLUSTERED INDEX CX_INC ON #INC (INCOME_ID);

SELECT @Hi = ISNULL(MAX(LREF), 0) FROM dbo.LS_OV_KISMI_INVLINES WITH (NOLOCK);
SET @Lo = 0;

WHILE @Lo < @Hi
BEGIN
    SET @sql = N'
UPDATE k
SET k.LINEEXP = LEFT(
        N''Kismi Eksilten | '' +
        COALESCE(
            i.INCOME_NAME,
            i2.INCOME_NAME,
            CASE
                WHEN k.ABYS_INCOME_ID = 958  THEN N''SONRAKI AYA DEVIR''
                WHEN k.ABYS_INCOME_ID = 1929 THEN N''ONCEKI AYDAN DEVIR''
                WHEN k.ABYS_INCOME_ID = 939  THEN N''Gaz Bedeli Indirim''
                WHEN k.ABYS_INCOME_ID = 7658 THEN N''SKB Bedeli Indirim''
                ELSE CAST(ISNULL(k.ABYS_INCOME_ID, k.TRANSTYPE) AS NVARCHAR(20))
            END
        ) +
        N'' | EKS='' + CAST(ISNULL(k.ABYS_EKS_ACTION_ID, 0) AS NVARCHAR(20)),
        100
    )
FROM dbo.LS_OV_KISMI_INVLINES k
LEFT JOIN #INC i  ON i.INCOME_ID = k.ABYS_INCOME_ID
LEFT JOIN #INC i2 ON i2.INCOME_ID = k.TRANSTYPE AND i.INCOME_ID IS NULL
WHERE k.LREF > @pLo AND k.LREF <= @pHi
  AND (
        k.LINEEXP IS NULL
     OR LTRIM(RTRIM(k.LINEEXP)) = N''''
     OR k.LINEEXP IN (N''Kismi Eksilten'', N''Kısmi Eksilten'')
     OR (k.LINEEXP LIKE N''Kismi Eksilten EKS=%'' AND CHARINDEX(N''|'', k.LINEEXP) = 0)
     OR (k.LINEEXP LIKE N''Kısmi Eksilten EKS=%'' AND CHARINDEX(N''|'', k.LINEEXP) = 0)
      )
OPTION (RECOMPILE, MAXDOP ' + CAST(@MaxDop AS NVARCHAR(10)) + N');';

    EXEC sp_executesql @sql,
        N'@pLo BIGINT, @pHi BIGINT',
        @pLo = @Lo,
        @pHi = @Lo + @BatchSize;

    SET @BatchN = @@ROWCOUNT;
    SET @Total += @BatchN;
    SET @Lo += @BatchSize;

    IF @BatchN > 0
    BEGIN
        SET @Msg = N'00c batch LREF<=' + CAST(@Lo AS NVARCHAR(20))
                 + N' rows=' + CAST(@BatchN AS NVARCHAR(20))
                 + N' total=' + CAST(@Total AS NVARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END;

SET @Ts = CONVERT(VARCHAR(30), SYSDATETIME(), 121);
SET @Msg = @Ts + N' | 00c KISMI LINEEXP enrich OK rows=' + CAST(@Total AS NVARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

SELECT TOP (10)
    LREF, INVOICEREF, ABYS_INCOME_ID, TRANSTYPE, ABYS_EKS_ACTION_ID,
    LEFT(LINEEXP, 100) AS LINEEXP
FROM dbo.LS_OV_KISMI_INVLINES WITH (NOLOCK)
ORDER BY LREF DESC;
GO
