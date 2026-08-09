/* prodREADY_ENERGY / 00 — MAP tablolari (izgazMGR + energy mirror) */
USE izgazMGR;
GO
IF OBJECT_ID('dbo.LS_OV_ID_MAP', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.LS_OV_ID_MAP (
        OV_KIND            VARCHAR(20)  NOT NULL,
        SRC_KEY            VARCHAR(80)  NOT NULL,
        LREF_HINT          BIGINT       NULL,
        PARENT_SRC_KEY     VARCHAR(80)  NULL,
        REF_MAIN_LREF      BIGINT       NULL,
        ABYS_AGREEMENT_ID  BIGINT       NULL,
        ABYS_ACCOUNT_ID    BIGINT       NULL,
        ABYS_ID_BUSINESS   BIGINT       NULL,
        ENERGY_LREF        INT          NULL,
        CONSTRAINT PK_LS_OV_ID_MAP PRIMARY KEY (SRC_KEY)
    );
    CREATE INDEX IX_OV_ID_MAP_KIND ON dbo.LS_OV_ID_MAP (OV_KIND);
    CREATE INDEX IX_OV_ID_MAP_AGR  ON dbo.LS_OV_ID_MAP (ABYS_AGREEMENT_ID);
    CREATE INDEX IX_OV_ID_MAP_EL   ON dbo.LS_OV_ID_MAP (ENERGY_LREF) WHERE ENERGY_LREF IS NOT NULL;
END
GO

USE energy;
GO
IF OBJECT_ID('dbo.MIG_OV_ID_MAP', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIG_OV_ID_MAP (
        OV_KIND            VARCHAR(20)  NOT NULL,
        SRC_KEY            VARCHAR(80)  NOT NULL,
        LREF_HINT          BIGINT       NULL,
        PARENT_SRC_KEY     VARCHAR(80)  NULL,
        REF_MAIN_LREF      BIGINT       NULL,
        ABYS_AGREEMENT_ID  BIGINT       NULL,
        ABYS_ACCOUNT_ID    BIGINT       NULL,
        ABYS_ID_BUSINESS   BIGINT       NULL,
        ENERGY_LREF        INT          NULL,
        CONSTRAINT PK_MIG_OV_ID_MAP PRIMARY KEY (SRC_KEY)
    );
    CREATE INDEX IX_MIG_OV_ID_MAP_KIND ON dbo.MIG_OV_ID_MAP (OV_KIND);
    CREATE INDEX IX_MIG_OV_ID_MAP_EL   ON dbo.MIG_OV_ID_MAP (ENERGY_LREF) WHERE ENERGY_LREF IS NOT NULL;
END
GO

/* Dump sonrasi: 00b_align_mgr_varchar.sql (nvarchar→varchar), sonra MAP SYNC SP. */
GO

-- ------------------------------------------------------------
-- Tahsilat: izgazMGR.LS_OV_ID_MAP → energy.MIG_OV_ID_MAP
-- Idempotent (SRC_KEY NOT EXISTS). Zincir CLEAN basinda cagrilir.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SP_MIG_OV_ID_MAP_SYNC_FROM_MGR
    @DEBUG BIT = 1,
    @Force BIT = 0   -- 1: count esitse bile NOT EXISTS insert dene
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.MIG_OV_ID_MAP', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_OV_ID_MAP yok — once 00_map_tables.sql', 16, 1);
        RETURN;
    END
    IF OBJECT_ID('izgazMGR.dbo.LS_OV_ID_MAP', 'U') IS NULL
    BEGIN
        RAISERROR('izgazMGR.LS_OV_ID_MAP yok — CTAS O35 dump kontrol', 16, 1);
        RETURN;
    END

    DECLARE @E BIGINT, @M BIGINT, @N INT, @Msg NVARCHAR(200);
    SELECT @E = COUNT_BIG(*) FROM energy.dbo.MIG_OV_ID_MAP WITH (NOLOCK);
    SELECT @M = COUNT_BIG(*) FROM izgazMGR.dbo.LS_OV_ID_MAP WITH (NOLOCK);

    IF @M = 0
    BEGIN
        RAISERROR('izgazMGR.LS_OV_ID_MAP bos — CTAS O35 kontrol', 16, 1);
        RETURN;
    END

    IF @Force = 0 AND @E >= @M AND @E > 0
    BEGIN
        IF @DEBUG = 1
        BEGIN
            SET @Msg = N'SKIP MAP sync (energy=' + CAST(@E AS NVARCHAR(20))
                     + N' mgr=' + CAST(@M AS NVARCHAR(20)) + N')';
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END
        RETURN;
    END

    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'MAP sync start energy=' + CAST(@E AS NVARCHAR(20))
                 + N' mgr=' + CAST(@M AS NVARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    INSERT INTO energy.dbo.MIG_OV_ID_MAP (
        OV_KIND, SRC_KEY, LREF_HINT, PARENT_SRC_KEY, REF_MAIN_LREF,
        ABYS_AGREEMENT_ID, ABYS_ACCOUNT_ID, ABYS_ID_BUSINESS, ENERGY_LREF
    )
    SELECT
        s.OV_KIND, s.SRC_KEY, s.LREF_HINT, s.PARENT_SRC_KEY, s.REF_MAIN_LREF,
        s.ABYS_AGREEMENT_ID, s.ABYS_ACCOUNT_ID, s.ABYS_ID_BUSINESS, s.ENERGY_LREF
    FROM izgazMGR.dbo.LS_OV_ID_MAP s WITH (NOLOCK)
    WHERE NOT EXISTS (
        SELECT 1 FROM energy.dbo.MIG_OV_ID_MAP t
         WHERE t.SRC_KEY = s.SRC_KEY
    );

    SET @N = @@ROWCOUNT;
    IF @DEBUG = 1
    BEGIN
        SET @Msg = N'MAP insert rows=' + CAST(@N AS NVARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SELECT @E = COUNT_BIG(*) FROM energy.dbo.MIG_OV_ID_MAP WITH (NOLOCK);
    IF @E = 0
        RAISERROR('MAP sync sonrasi energy.MIG_OV_ID_MAP hala 0', 16, 1);
END
GO

PRINT '00_map_tables OK — SP_MIG_OV_ID_MAP_SYNC_FROM_MGR; dump sonrasi: 00b_align + SYNC';
GO
