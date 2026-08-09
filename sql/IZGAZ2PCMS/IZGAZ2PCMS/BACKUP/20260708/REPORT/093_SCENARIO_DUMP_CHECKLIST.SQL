-- =============================================================================
-- prodEnergy / 90_afl_frk / 93_scenario_dump_checklist.sql
-- Faz2: O52–O56 dump → izgazMGR aktarım kontrol listesi (read-only)
-- =============================================================================
USE izgazMGR;
GO

SET NOCOUNT ON;

PRINT '========== Senaryo tablo varlık =========='
SELECT t.name AS TABLE_NAME,
       SUM(p.rows) AS ROW_EST
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE t.name IN (
  'LS_PAYMENT','LS_EKSILTEN','LS_PARTIAL_EKSILTEN',
  'LS_ARTIRAN','LS_EMANET','LS_MAHSUP','LS_TAKSIT',
  'LS_AFL_OPEN_DEBT','LS_STG_INV_PAY_CLOSE'
)
GROUP BY t.name
ORDER BY t.name;

PRINT '========== AGR spot (örnek @AGR) ==========';
DECLARE @AGR BIGINT = NULL; -- doldurun
IF @AGR IS NOT NULL
BEGIN
  SELECT 'PAYMENT' K, COUNT(*) N FROM dbo.LS_PAYMENT WHERE SOZLESME = @AGR
  UNION ALL SELECT 'EKSILTEN', COUNT(*) FROM dbo.LS_EKSILTEN WHERE SOZLESME = @AGR
  UNION ALL SELECT 'PARTIAL', COUNT(*) FROM dbo.LS_PARTIAL_EKSILTEN WHERE SOZLESME = @AGR
  UNION ALL SELECT 'MAHSUP', COUNT(*) FROM dbo.LS_MAHSUP WHERE SOZLESME = @AGR
  UNION ALL SELECT 'TAKSIT', COUNT(*) FROM dbo.LS_TAKSIT WHERE SOZLESME = @AGR
  UNION ALL SELECT 'ARTIRAN', COUNT(*) FROM dbo.LS_ARTIRAN WHERE SOZLESME = @AGR
  UNION ALL SELECT 'EMANET', COUNT(*) FROM dbo.LS_EMANET WHERE SOZLESME = @AGR;
END
ELSE
  PRINT 'AGR NULL — sayım atlandı.';

PRINT 'Sonraki: 00_pre_indexes.sql (izgazMGR senaryo index) + energy 92 apply tek-AGR.';
GO
