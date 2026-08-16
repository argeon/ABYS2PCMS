/* =============================================================================
   50e_613_RESUME_OPEN_DEBT_ONLY.sql
   Sadece 613 — acik borclu AGR (~20k). 611/611b YOK.
   Kullanim: mevcut 50e'yi SSMS'te Cancel → bu dosyayi F5.
   ============================================================================= */
USE energy;
GO
SET NOCOUNT ON;
SET IMPLICIT_TRANSACTIONS OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF EXISTS (
    SELECT 1 FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID
      AND (
            t.text LIKE N'%SP_MIG_INSTALLMENT_SPLIT_DEBT%'
         OR t.text LIKE N'%SP_MIG_INSTALLMENT_CANCEL_NORMALIZE%'
         OR t.text LIKE N'%50e_TAKSIT%'
         OR t.text LIKE N'%MIG_613_STG_AGR_LIST%'
          )
)
BEGIN
    RAISERROR('613/50e hala kosuyor — once SSMS Cancel, sonra tekrar F5', 16, 1);
    RETURN;
END
GO

IF OBJECT_ID('dbo.MIG_613_STG_AGR_LIST', 'U') IS NULL
BEGIN
    RAISERROR('MIG_613_STG_AGR_LIST yok — 00e staging', 16, 1);
    RETURN;
END

IF OBJECT_ID('dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR', 'P') IS NULL
   OR OBJECT_ID('dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NULL
BEGIN
    RAISERROR('613 SP yok — 10f deploy', 16, 1);
    RETURN;
END
GO

DECLARE @i INT = 1, @n INT, @agr BIGINT, @try INT, @ok BIT;
DECLARE @Msg NVARCHAR(400);
DECLARE @done_skip INT, @total_agr INT;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + N' | 613 OPEN-DEBT RESUME START';

SELECT @total_agr = COUNT(DISTINCT pl.ABYS_AGREEMENT_ID)
FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL;

SELECT @done_skip = COUNT(DISTINCT pl.ABYS_AGREEMENT_ID)
FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
  AND EXISTS (
        SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
        WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
          AND pt.IOCODE = 0 AND pt.INST_NR > 0
          AND ISNULL(pt.CANCELED, 0) = 0
          AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
      );

TRUNCATE TABLE dbo.MIG_613_STG_AGR_LIST;
INSERT INTO dbo.MIG_613_STG_AGR_LIST (ORD, AGR_ID)
SELECT ROW_NUMBER() OVER (ORDER BY AGR_ID), AGR_ID
FROM (
    SELECT DISTINCT pl.ABYS_AGREEMENT_ID AS AGR_ID
    FROM dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_AGREEMENT_ID IS NOT NULL
      AND NOT EXISTS (
            SELECT 1 FROM dbo.LS_005_01_PAYTRANS pt WITH (NOLOCK)
            WHERE pt.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
              AND pt.IOCODE = 0 AND pt.INST_NR > 0
              AND ISNULL(pt.CANCELED, 0) = 0
              AND ISNULL(pt.CANCELLATIONPAYMENT, 0) = 0
          )
      AND EXISTS (
            SELECT 1 FROM dbo.LS_005_01_PAYTRANS d WITH (NOLOCK)
            WHERE d.ABYS_AGREEMENT_ID = pl.ABYS_AGREEMENT_ID
              AND d.IOCODE = 0
              AND ISNULL(d.INST_NR, 0) = 0
              AND ISNULL(d.CANCELED, 0) = 0
              AND ISNULL(d.CANCELLATIONPAYMENT, 0) = 0
              AND ISNULL(d.PAID, 0) < ISNULL(d.PAYABLETOTAL, 0) - 0.02
          )
) x;

SELECT @n = COUNT(*) FROM dbo.MIG_613_STG_AGR_LIST;
SET @Msg = N'613 OPEN-DEBT pending=' + CAST(@n AS VARCHAR(20))
         + N' done_inst=' + CAST(@done_skip AS VARCHAR(20))
         + N' total_agr=' + CAST(@total_agr AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

IF @n = 0
BEGIN
    RAISERROR('613: open-debt pending=0 — SPLIT_OK', 0, 1) WITH NOWAIT;
END
ELSE
WHILE @i <= @n
BEGIN
    SELECT @agr = AGR_ID FROM dbo.MIG_613_STG_AGR_LIST WHERE ORD = @i;
    SET @try = 0; SET @ok = 0;

    WHILE @ok = 0 AND @try < 5
    BEGIN
        SET @try += 1;
        BEGIN TRY
            EXEC dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
                @AGR_ID = @agr, @DEBUG = 0;
            EXEC dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
                @AGR_ID = @agr, @DEBUG = 0, @DO_RESEED = 0;
            SET @ok = 1;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 1205
                WAITFOR DELAY '00:00:00.200';
            ELSE
            BEGIN
                IF OBJECT_ID('dbo.MIG_613_ERR', 'U') IS NOT NULL
                    INSERT INTO dbo.MIG_613_ERR (AGR_ID, TRY_N, ERR_NUM, ERR_MSG)
                    VALUES (@agr, @try, ERROR_NUMBER(), ERROR_MESSAGE());
                SET @Msg = N'ERR AGR=' + CAST(@agr AS VARCHAR(20)) + N' ' + ERROR_MESSAGE();
                RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
                SET @ok = 1;
            END
        END CATCH
    END

    IF @i = 1 OR @i = @n OR (@i % 50) = 0
    BEGIN
        SET @Msg = N'613 ' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    SET @i += 1;
END

DBCC CHECKIDENT ('dbo.LS_005_01_PAYTRANS', RESEED);

IF OBJECT_ID('dbo.MIG_613_ERR', 'U') IS NOT NULL
BEGIN
    SELECT @n = COUNT(*) FROM dbo.MIG_613_ERR WITH (NOLOCK)
    WHERE RUN_TS >= DATEADD(HOUR, -12, SYSDATETIME());
    SET @Msg = N'613 ERR (12h)=' + CAST(@n AS VARCHAR(20)) + N' → dbo.MIG_613_ERR';
    RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
END

SELECT
  (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_PAYTRANS WITH (NOLOCK)
    WHERE IOCODE = 0 AND INST_NR > 0
      AND ISNULL(CANCELED, 0) = 0 AND ISNULL(CANCELLATIONPAYMENT, 0) = 0) AS EN_INST_GT0;

PRINT CONVERT(VARCHAR(30), SYSDATETIME(), 121) + N' | 613 OPEN-DEBT RESUME END';
GO
