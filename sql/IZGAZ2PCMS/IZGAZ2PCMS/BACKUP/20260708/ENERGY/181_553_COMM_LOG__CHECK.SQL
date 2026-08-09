/* ============================================================
   SCRIPT_ID : COMM_LOG_CHECK
   SCRIPT_NO : 553
   FILE      : 553_COMM_LOG__check.sql
   VERSION   : 1
   ============================================================ */
-- Manuel kontrol sorgulari (deploy disi)
USE energy;
GO

-- Kaynak vs ABYS hedef sayim
SELECT
    (SELECT SUM(p.rows)
     FROM izgazMGR.sys.partitions p
     INNER JOIN izgazMGR.sys.tables t ON t.object_id = p.object_id
     INNER JOIN izgazMGR.sys.schemas s ON s.schema_id = t.schema_id
     WHERE s.name = 'dbo' AND t.name = 'IT_COMMUNICATION_LOG' AND p.index_id IN (0, 1)
    ) AS SRC_APPROX,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_COMMUNICATION_LOG WHERE ABYS_ID IS NOT NULL) AS TGT_ABYS,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_COMMUNICATION_LOG WHERE ABYS_ID IS NULL) AS TGT_NATIVE;

-- COMPANY_ID dogrulama
SELECT 'COMPANY_ID <> 5', COUNT(*)
FROM energy.dbo.LS_COMMUNICATION_LOG
WHERE ABYS_ID IS NOT NULL AND (COMPANY_ID IS NULL OR COMPANY_ID <> 5);

-- Eksik kaynak (henuz gelmemis)
SELECT COUNT(*) AS MISSING_IN_TARGET
FROM izgazMGR.dbo.IT_COMMUNICATION_LOG s
WHERE s.ID BETWEEN 1 AND 2147483647
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_COMMUNICATION_LOG t WHERE t.ABYS_ID = CAST(s.ID AS INT)
  );

-- Ornek
SELECT TOP 20
    t.LREF, t.ABYS_ID, t.COMPANY_ID, t.COMMUNICATION_TYPE, t.COMMUNICATION_CAUSE,
    t.REGISTER_ID, t.AGREEMENT_ID, t.STATUS, t.GSM_NUMBER, t.EMAIL,
    t.CREATED_USER, t.CREATED_TIMESTAMP
FROM energy.dbo.LS_COMMUNICATION_LOG t
WHERE t.ABYS_ID IS NOT NULL
ORDER BY t.ABYS_ID;
GO
