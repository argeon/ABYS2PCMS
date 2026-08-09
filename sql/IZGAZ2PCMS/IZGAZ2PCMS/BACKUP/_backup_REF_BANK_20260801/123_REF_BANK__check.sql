/* ============================================================
   SCRIPT_ID : REF_BANK_CHECK
   SCRIPT_NO : 123
   FILE      : 123_REF_BANK__check.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- LS_BANK — proje sonu kontrol sorgulari
-- Orphan FK ve kopru tutarliligi (bloklayici degil, rapor)
-- ============================================================
USE energy;
GO

-- Ozet
SELECT 'LS_BANK toplam' AS METRIK, COUNT(*) AS DEGER FROM energy.dbo.LS_BANK
UNION ALL
SELECT 'LS_BANK ABYS kopru', COUNT(*) FROM energy.dbo.LS_BANK WHERE ABYS_ID IS NOT NULL
UNION ALL
SELECT 'MIG_LS_BANK_MAP MAP', COUNT(*) FROM energy.dbo.MIG_LS_BANK_MAP WHERE ACTION_TYPE = 'MAP'
UNION ALL
SELECT 'MIG_LS_BANK_MAP INSERT', COUNT(*) FROM energy.dbo.MIG_LS_BANK_MAP WHERE ACTION_TYPE = 'INSERT';
GO

-- Map durumu (aktarim oncesi/sonrasi)
SELECT MAP_STATUS, COUNT(*) AS SATIR
FROM energy.dbo.VW_MIG_LS_BANK_RESOLVED
GROUP BY MAP_STATUS
ORDER BY MAP_STATUS;
GO

-- Cift ABYS koprusu (tekil olmamali)
SELECT ABYS_ID, COUNT(*) AS CNT, STRING_AGG(CAST(LREF AS VARCHAR(20)), ', ') AS LREF_LIST
FROM energy.dbo.LS_BANK
WHERE ABYS_ID IS NOT NULL
GROUP BY ABYS_ID
HAVING COUNT(*) > 1;
GO

-- MAP: PCMS hedefi yok
SELECT m.*
FROM energy.dbo.MIG_LS_BANK_MAP m
LEFT JOIN energy.dbo.LS_BANK b ON b.LREF = m.PCMS_LREF
WHERE m.ACTION_TYPE = 'MAP'
  AND b.LREF IS NULL;
GO

-- INSERT: henuz LS_BANK'te yok
SELECT m.*
FROM energy.dbo.MIG_LS_BANK_MAP m
WHERE m.ACTION_TYPE = 'INSERT'
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_BANK b WHERE b.ABYS_ID = m.ABYS_BANK_ID
  );
GO

-- MAP listesinde olmayan ABYS banka ID (izgazMGR CS_ACCOUNT_ACTION varsa)
IF OBJECT_ID('izgazMGR.dbo.CS_ACCOUNT_ACTION', 'U') IS NOT NULL
BEGIN
    SELECT DISTINCT aa.BANK_ID AS ABYS_BANK_ID
    FROM izgazMGR.dbo.CS_ACCOUNT_ACTION aa
    WHERE aa.BANK_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM energy.dbo.LS_BANK b WHERE b.ABYS_ID = aa.BANK_ID
      )
    ORDER BY aa.BANK_ID;
END
GO

-- Orphan FK: BANKREF dolu ama LS_BANK'te yok (hedef tablolar eklendikce genislet)
-- LS_005_01_PAYTRANS
IF OBJECT_ID('energy.dbo.LS_005_01_PAYTRANS', 'U') IS NOT NULL
   AND COL_LENGTH('energy.dbo.LS_005_01_PAYTRANS', 'BANKREF') IS NOT NULL
BEGIN
    SELECT 'LS_005_01_PAYTRANS.BANKREF -> LS_BANK' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_PAYTRANS t
    WHERE t.BANKREF IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM energy.dbo.LS_BANK b WHERE b.LREF = t.BANKREF);

    IF COL_LENGTH('energy.dbo.LS_005_01_PAYTRANS', 'ABYS_BANK_ID') IS NOT NULL
    BEGIN
        SELECT 'LS_005_01_PAYTRANS wiring eksik (ABYS var, BANKREF yok)' AS RELATION_NAME,
               COUNT(*) AS ORPHAN_COUNT
        FROM energy.dbo.LS_005_01_PAYTRANS t
        WHERE t.ABYS_BANK_ID IS NOT NULL
          AND t.BANKREF IS NULL;
    END
END
GO

-- LS_005_01_AGR_GUARANTY
IF OBJECT_ID('energy.dbo.LS_005_01_AGR_GUARANTY', 'U') IS NOT NULL
   AND COL_LENGTH('energy.dbo.LS_005_01_AGR_GUARANTY', 'BANKREF') IS NOT NULL
BEGIN
    SELECT 'LS_005_01_AGR_GUARANTY.BANKREF -> LS_BANK' AS RELATION_NAME, COUNT(*) AS ORPHAN_COUNT
    FROM energy.dbo.LS_005_01_AGR_GUARANTY t
    WHERE t.BANKREF IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM energy.dbo.LS_BANK b WHERE b.LREF = t.BANKREF);
END
GO

-- Son LS_BANK migrasyon loglari
SELECT TOP 20
    l.MIGRATION_CODE,
    l.BATCH_NO,
    l.ERROR_MSG,
    l.LOGGED_AT
FROM energy.dbo.MIG_BATCH_LOG l
WHERE l.MIGRATION_CODE = 'LS_BANK'
ORDER BY l.LOGGED_AT DESC;
GO

