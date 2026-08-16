/* =============================================================================
   prodREADY_ENERGY / 00i_mgr_ov_id_map_clustered.sql
   R16 — izgazMGR.dbo.LS_OV_ID_MAP HEAP → UNIQUE CLUSTERED (SRC_KEY)

   Neden: dump sonrasi tablo HEAP + UX NC (SRC_KEY) → 20a/MAP sync
   UPDATE TOP + IS NULL rescan / keyset seek yavas. energy.MIG_OV_ID_MAP
   zaten PK(SRC_KEY); MGR hizasina getir.

   Ne zaman: dump + 00b_align sonrasi, 597 / 20a ONCESI (veya idle pencerede).
   Online: OFF (FULL cutover; buyuk tablo — ETA not al).

   Guvenli:
     - SRC_KEY NULL yok (CTAS O35 gate)
     - Duplicate SRC_KEY yok (UX zaten varsa)
   ============================================================================= */
USE izgazMGR;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'dbo.LS_OV_ID_MAP', N'U') IS NULL
BEGIN
    RAISERROR('izgazMGR.dbo.LS_OV_ID_MAP yok — CTAS O35 dump kontrol', 16, 1);
    RETURN;
END

DECLARE @hasClu BIT =
    CASE WHEN EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP')
          AND type = 1  -- clustered
    ) THEN 1 ELSE 0 END;

DECLARE @rows BIGINT =
    (SELECT COUNT_BIG(*) FROM dbo.LS_OV_ID_MAP WITH (NOLOCK));

RAISERROR('00i LS_OV_ID_MAP rows=%I64d clustered=%d', 0, 1, @rows, @hasClu) WITH NOWAIT;

IF @hasClu = 1
BEGIN
    SELECT i.name, i.type_desc, i.is_unique
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP') AND i.type = 1;
    RAISERROR('00i SKIP — clustered zaten var', 0, 1) WITH NOWAIT;
    RETURN;
END

/* Precheck: SRC_KEY NULL / dup */
IF EXISTS (SELECT 1 FROM dbo.LS_OV_ID_MAP WITH (NOLOCK) WHERE SRC_KEY IS NULL)
BEGIN
    RAISERROR('00i FAIL — SRC_KEY NULL var; CTAS O35 gate', 16, 1);
    RETURN;
END

IF EXISTS (
    SELECT SRC_KEY FROM dbo.LS_OV_ID_MAP WITH (NOLOCK)
    GROUP BY SRC_KEY HAVING COUNT(*) > 1
)
BEGIN
    RAISERROR('00i FAIL — duplicate SRC_KEY; once temizle', 16, 1);
    RETURN;
END

/* Drop NC unique / PK adaylari — clustered yerine gecilecek */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP') AND name = N'UX_LS_OV_ID_MAP_SRC')
BEGIN
    RAISERROR('00i DROP UX_LS_OV_ID_MAP_SRC (NC)', 0, 1) WITH NOWAIT;
    DROP INDEX UX_LS_OV_ID_MAP_SRC ON dbo.LS_OV_ID_MAP;
END

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP') AND name = N'PK_LS_OV_ID_MAP' AND type <> 1)
BEGIN
    RAISERROR('00i DROP PK_LS_OV_ID_MAP (nonclustered)', 0, 1) WITH NOWAIT;
    ALTER TABLE dbo.LS_OV_ID_MAP DROP CONSTRAINT PK_LS_OV_ID_MAP;
END

RAISERROR('00i CREATE UNIQUE CLUSTERED PK_LS_OV_ID_MAP (SRC_KEY) — basladi', 0, 1) WITH NOWAIT;

ALTER TABLE dbo.LS_OV_ID_MAP
ADD CONSTRAINT PK_LS_OV_ID_MAP PRIMARY KEY CLUSTERED (SRC_KEY)
WITH (MAXDOP = 8, ONLINE = OFF, SORT_IN_TEMPDB = ON);

/* Yardimci NC (yoksa) — 00_pre_indexes / 00b ile ayni */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP') AND name = N'IX_OV_ID_MAP_KIND')
    CREATE NONCLUSTERED INDEX IX_OV_ID_MAP_KIND
        ON dbo.LS_OV_ID_MAP (OV_KIND)
        INCLUDE (SRC_KEY, ABYS_AGREEMENT_ID, ENERGY_LREF)
        WITH (MAXDOP = 8, ONLINE = OFF, SORT_IN_TEMPDB = ON);

IF COL_LENGTH(N'dbo.LS_OV_ID_MAP', N'ABYS_AGREEMENT_ID') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP') AND name = N'IX_OV_ID_MAP_AGR')
    CREATE NONCLUSTERED INDEX IX_OV_ID_MAP_AGR
        ON dbo.LS_OV_ID_MAP (ABYS_AGREEMENT_ID, OV_KIND)
        INCLUDE (SRC_KEY, ENERGY_LREF)
        WITH (MAXDOP = 8, ONLINE = OFF, SORT_IN_TEMPDB = ON);

IF COL_LENGTH(N'dbo.LS_OV_ID_MAP', N'ENERGY_LREF') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP') AND name = N'IX_OV_ID_MAP_ELREF_KIND')
    CREATE NONCLUSTERED INDEX IX_OV_ID_MAP_ELREF_KIND
        ON dbo.LS_OV_ID_MAP (ENERGY_LREF, OV_KIND)
        INCLUDE (ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, SRC_KEY)
        WHERE ENERGY_LREF IS NOT NULL
        WITH (MAXDOP = 8, ONLINE = OFF, SORT_IN_TEMPDB = ON);

SELECT i.name, i.type_desc, i.is_unique
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID(N'dbo.LS_OV_ID_MAP')
  AND i.type > 0
ORDER BY i.type, i.name;

RAISERROR('00i OK — LS_OV_ID_MAP UNIQUE CLUSTERED (SRC_KEY)', 0, 1) WITH NOWAIT;
GO
