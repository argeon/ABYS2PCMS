/* Timed probe: 571 INVOICE RESUME, fixed wall-clock window via batch log.
   Expect ~3-5s / 100k (Jul17 baseline). */
USE energy;
GO
SET NOCOUNT ON;
DECLARE @t0 DATETIME2(3) = SYSDATETIME();
DECLARE @inv0 BIGINT = (SELECT COUNT_BIG(*) FROM dbo.LS_005_01_INVOICE WITH (NOLOCK));
DECLARE @log0 BIGINT = (SELECT ISNULL(MAX(LOG_ID),0) FROM dbo.MIG_BATCH_LOG WITH (NOLOCK) WHERE MIGRATION_CODE='LS_005_01_INVOICE');

RAISERROR('PROBE START inv=%I64d log0=%I64d', 0, 1, @inv0, @log0) WITH NOWAIT;

-- Arka planda uzun surecek; probe script sadece kisa olcum icin ayri calisir.
-- Bu dosya: SP'yi baslatmaz — PowerShell N batch bekler.
SELECT @t0 AS probe_t0, @inv0 AS inv0, @log0 AS log0;
GO
