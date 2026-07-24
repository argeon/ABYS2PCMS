/* ============================================================
   SCRIPT_ID : AGR_BNK_TALIMAT_CHECK
   SCRIPT_NO : 363
   FILE      : 363_AGR_BNK_TALIMAT__check.sql
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
     WHERE s.name = 'dbo' AND t.name = 'CS_AGREEMENT_AUTO_PAYMENT_LOG' AND p.index_id IN (0, 1)
    ) AS SRC_APPROX,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_BNK_TALIMAT WHERE ABYS_ID IS NOT NULL) AS TGT_ABYS,
    (SELECT COUNT_BIG(*) FROM energy.dbo.LS_BNK_TALIMAT WHERE ABYS_ID IS NULL) AS TGT_NATIVE;

-- FIRMA_KODU dogrulama
SELECT 'FIRMA_KODU <> 005', COUNT(*)
FROM energy.dbo.LS_BNK_TALIMAT
WHERE ABYS_ID IS NOT NULL
  AND (FIRMA_KODU IS NULL OR FIRMA_KODU <> N'005');

-- Banka resolve edilmemis
SELECT 'BANKA_KODU NULL (orphan bank)', COUNT(*)
FROM energy.dbo.LS_BNK_TALIMAT
WHERE ABYS_ID IS NOT NULL AND BANKA_KODU IS NULL;

-- IS_ACTIVE vs IPTAL_TARIHI tutarsizlik
SELECT 'IS_ACTIVE/IPTAL tutarsiz', COUNT(*)
FROM energy.dbo.LS_BNK_TALIMAT
WHERE ABYS_ID IS NOT NULL
  AND (
        (IS_ACTIVE = 1 AND IPTAL_TARIHI IS NOT NULL)
     OR (IS_ACTIVE = 0 AND IPTAL_TARIHI IS NULL)
  );

-- Eksik kaynak
SELECT COUNT(*) AS MISSING_IN_TARGET
FROM izgazMGR.dbo.CS_AGREEMENT_AUTO_PAYMENT_LOG s
WHERE s.ID BETWEEN 1 AND 2147483647
  AND NOT EXISTS (
      SELECT 1 FROM energy.dbo.LS_BNK_TALIMAT t WHERE t.ABYS_ID = CAST(s.ID AS INT)
  );

-- Ornek
SELECT TOP 20
    t.ID, t.ABYS_ID, t.FIRMA_KODU, t.BANKA_KODU, t.ABYS_BANK_ID,
    t.SOZLESME_HESABI, t.SOZLESME_NUMARASI, t.TESISAT_NUMARASI, t.ABONE_NUMARASI,
    t.TALIMAT_TARIHI, t.IPTAL_TARIHI, t.IS_ACTIVE,
    t.KULLANICI_KODU, t.IPTAL_KULLANICI_KODU, t.ACIKLAMA
FROM energy.dbo.LS_BNK_TALIMAT t
WHERE t.ABYS_ID IS NOT NULL
ORDER BY t.ABYS_ID;
GO
