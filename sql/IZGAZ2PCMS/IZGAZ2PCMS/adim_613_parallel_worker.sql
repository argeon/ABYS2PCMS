/* ============================================================
   FILE : adim_613_parallel_worker.sql
   Params via sqlcmd: -v WORKER_ID=0 -v WORKER_CNT=6
   AGR listesi ORD % WORKER_CNT = WORKER_ID
   ============================================================ */
USE energy;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @WORKER_ID INT = $(WORKER_ID);
DECLARE @WORKER_CNT INT = $(WORKER_CNT);
DECLARE @Msg NVARCHAR(400);
DECLARE @tAll DATETIME2(3) = SYSDATETIME();
DECLARE @t0 DATETIME2(3);
DECLARE @i INT = 1, @n INT, @AGR_ID BIGINT;

SET @Msg = N'===== 613 WORKER ' + CAST(@WORKER_ID AS VARCHAR(10))
         + N'/' + CAST(@WORKER_CNT AS VARCHAR(10))
         + N' START ' + CONVERT(VARCHAR(30), @tAll, 121) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

IF OBJECT_ID('tempdb..#Agr') IS NOT NULL DROP TABLE #Agr;
CREATE TABLE #Agr (
    ORD INT NOT NULL PRIMARY KEY,
    AGR_ID BIGINT NOT NULL
);

INSERT INTO #Agr (ORD, AGR_ID)
SELECT ROW_NUMBER() OVER (ORDER BY x.AGR_ID), x.AGR_ID
FROM (
    SELECT DISTINCT pl.ABYS_AGREEMENT_ID AS AGR_ID
    FROM energy.dbo.LS_005_01_INSTALLMENT_PLAN pl WITH (NOLOCK)
    WHERE pl.ABYS_ID IS NOT NULL
      AND pl.ABYS_AGREEMENT_ID IS NOT NULL
) x
WHERE ABS(CHECKSUM(x.AGR_ID)) % @WORKER_CNT = @WORKER_ID;

SELECT @n = COUNT(*) FROM #Agr;
SET @Msg = N'WORKER ' + CAST(@WORKER_ID AS VARCHAR(10)) + N' AGR_CNT=' + CAST(@n AS VARCHAR(20));
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;

WHILE @i <= @n
BEGIN
    SELECT @AGR_ID = AGR_ID FROM #Agr WHERE ORD = @i;

    IF @i = 1 OR @i = @n OR @i % 200 = 0
    BEGIN
        SET @Msg = N'W' + CAST(@WORKER_ID AS VARCHAR(10))
                 + N' AGR ' + CAST(@AGR_ID AS VARCHAR(20))
                 + N' (' + CAST(@i AS VARCHAR(10)) + N'/' + CAST(@n AS VARCHAR(10)) + N')'
                 + N' elapsed_sec=' + CAST(DATEDIFF(SECOND, @tAll, SYSDATETIME()) AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    EXEC energy.dbo.SP_MIG_INSTALLMENT_CANCEL_NORMALIZE_BY_AGR
        @AGR_ID = @AGR_ID, @DEBUG = 0;

    IF OBJECT_ID('energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR', 'P') IS NOT NULL
        EXEC energy.dbo.SP_MIG_INSTALLMENT_SPLIT_DEBT_BY_AGR
            @AGR_ID = @AGR_ID, @DEBUG = 0;

    SET @i += 1;
END

SET @Msg = N'===== 613 WORKER ' + CAST(@WORKER_ID AS VARCHAR(10))
         + N' DONE sec=' + CAST(DATEDIFF(SECOND, @tAll, SYSDATETIME()) AS VARCHAR(20))
         + N' agr=' + CAST(@n AS VARCHAR(20)) + N' =====';
RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
GO
