/* =============================================================================
   prodREADY_ENERGY / 26e_597_PROBE_BAD_MAP.sql
   CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_PROBE_BAD_MAP  (R24 2026-08-11)
   PAY_PT map → IOCODE=0 borç sayımı. >0 ise severity 16 DUR.
   EXEC dbo.SP_MIG_597_PROBE_BAD_MAP;
   EXEC dbo.SP_MIG_597_PROBE_BAD_MAP @FailIfBad = 0;  -- sadece rapor
   ============================================================================= */
USE energy;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.SP_MIG_597_PROBE_BAD_MAP
    @FailIfBad BIT = 1,
    @DoGate    BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @bad_map BIGINT;
    DECLARE @Msg NVARCHAR(200);

    RAISERROR('========== SP_MIG_597_PROBE_BAD_MAP ==========', 0, 1) WITH NOWAIT;

    SELECT @bad_map = COUNT_BIG(*)
    FROM dbo.MIG_OV_ID_MAP m WITH (NOLOCK)
    JOIN dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK) ON pt.LREF = m.ENERGY_LREF
    WHERE m.OV_KIND = 'PAY_PT'
      AND m.ENERGY_LREF IS NOT NULL
      AND pt.IOCODE = 0;

    SELECT @bad_map AS pay_map_to_debt;

    SELECT
        SUM(CASE WHEN IOCODE <> 0 THEN 1 ELSE 0 END) AS pt_pay,
        SUM(CASE WHEN IOCODE = 0 THEN 1 ELSE 0 END) AS pt_debt
    FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
    WHERE ISNULL(CANCELED, 0) = 0;

    IF @DoGate = 1 AND OBJECT_ID('dbo.SP_MIG_597_GATE', 'P') IS NOT NULL
        EXEC dbo.SP_MIG_597_GATE @AGR_ID = NULL;

    IF @bad_map > 0 AND @FailIfBad = 1
    BEGIN
        RAISERROR('1) EXEC SP_MIG_20E_BAD_MAP_HEAL @DRY_RUN=0', 0, 1) WITH NOWAIT;
        RAISERROR('2) EXEC SP_MIG_597_ALL @CLEAN=0 @BatchSize=250000  ★ CLEAN=1 YASAK', 0, 1) WITH NOWAIT;
        RAISERROR('3) EXEC SP_MIG_597_PROBE_BAD_MAP tekrar (0 sart) sonra NCIX_REBUILD', 0, 1) WITH NOWAIT;
        SET @Msg = N'BAD_MAP=' + CAST(@bad_map AS NVARCHAR(20)) + N' — DUR; NCIX_REBUILD YASAK';
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    IF @bad_map = 0
        RAISERROR('PROBE OK bad_map=0', 0, 1) WITH NOWAIT;
    ELSE
    BEGIN
        SET @Msg = N'PROBE WARN bad_map=' + CAST(@bad_map AS NVARCHAR(20)) + N' (FailIfBad=0)';
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END
END
GO
/* EXEC dbo.SP_MIG_597_PROBE_BAD_MAP; */
