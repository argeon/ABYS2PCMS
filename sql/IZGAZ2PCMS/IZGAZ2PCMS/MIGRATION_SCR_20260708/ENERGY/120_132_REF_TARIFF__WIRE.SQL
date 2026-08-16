/* ============================================================
   SCRIPT_ID : REF_TARIFF_WIRE
   SCRIPT_NO : 132
   FILE      : 132_REF_TARIFF__wire.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- Tarife aktarımında geçici kaldırılan FK'leri geri kur
-- Önce eslesmeyen kayit kontrolu yapar, sonra WITH CHECK ile ekler.
-- ============================================================
USE energy;
GO

IF OBJECT_ID('tempdb..#TariffRestoreState') IS NOT NULL
    DROP TABLE #TariffRestoreState;

CREATE TABLE #TariffRestoreState (
    CAN_RESTORE BIT NOT NULL
);

INSERT INTO #TariffRestoreState (CAN_RESTORE) VALUES (1);
GO

-- ------------------------------------------------------------
-- Ön kontrol: eslesmeyen kayit sayilari
-- ------------------------------------------------------------
SELECT
    'LS_TARIFF_TYPE_PRM -> LS_AGR_TYPE' AS RELATION_NAME,
    COUNT(*) AS ORPHAN_COUNT
FROM energy.dbo.LS_TARIFF_TYPE_PRM c
WHERE c.SUBSCRIBER_TYPE_ID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM energy.dbo.LS_AGR_TYPE p
      WHERE p.LREF = c.SUBSCRIBER_TYPE_ID
  );
GO

SELECT
    'LS_TARIFF_INCOME_PRM -> LS_TARIFF_PRM' AS RELATION_NAME,
    COUNT(*) AS ORPHAN_COUNT
FROM energy.dbo.LS_TARIFF_INCOME_PRM c
WHERE c.TARIFF_ID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM energy.dbo.LS_TARIFF_PRM p
      WHERE p.ID = c.TARIFF_ID
  );
GO

-- ------------------------------------------------------------
-- Eslesmeyen kayit varsa durdur
-- ------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM energy.dbo.LS_TARIFF_TYPE_PRM c
    WHERE c.SUBSCRIBER_TYPE_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_AGR_TYPE p
          WHERE p.LREF = c.SUBSCRIBER_TYPE_ID
      )
)
BEGIN
    PRINT 'FK geri yukleme durdu: LS_TARIFF_TYPE_PRM.SUBSCRIBER_TYPE_ID icin LS_AGR_TYPE eslesmeyen kayitlari var.';
    UPDATE #TariffRestoreState SET CAN_RESTORE = 0;
END
GO

IF EXISTS (
    SELECT 1
    FROM energy.dbo.LS_TARIFF_INCOME_PRM c
    WHERE c.TARIFF_ID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_TARIFF_PRM p
          WHERE p.ID = c.TARIFF_ID
      )
)
BEGIN
    PRINT 'FK geri yukleme durdu: LS_TARIFF_INCOME_PRM.TARIFF_ID icin LS_TARIFF_PRM eslesmeyen kayitlari var.';
    UPDATE #TariffRestoreState SET CAN_RESTORE = 0;
END
GO

-- ------------------------------------------------------------
-- FK'leri geri kur
-- ------------------------------------------------------------
IF EXISTS (SELECT 1 FROM #TariffRestoreState WHERE CAN_RESTORE = 1) AND NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_LS_TARIFF_TYPE_PRM_LS_AGR_TYPE1'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_TARIFF_TYPE_PRM')
)
BEGIN
    ALTER TABLE energy.dbo.LS_TARIFF_TYPE_PRM WITH CHECK
    ADD CONSTRAINT FK_LS_TARIFF_TYPE_PRM_LS_AGR_TYPE1
        FOREIGN KEY (SUBSCRIBER_TYPE_ID)
        REFERENCES energy.dbo.LS_AGR_TYPE (LREF);

    ALTER TABLE energy.dbo.LS_TARIFF_TYPE_PRM
        CHECK CONSTRAINT FK_LS_TARIFF_TYPE_PRM_LS_AGR_TYPE1;
END
GO

IF EXISTS (SELECT 1 FROM #TariffRestoreState WHERE CAN_RESTORE = 1) AND NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_LS_TARIFF_INCOME_PRM_LS_TARIFF_PRM'
      AND parent_object_id = OBJECT_ID('energy.dbo.LS_TARIFF_INCOME_PRM')
)
BEGIN
    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_PRM WITH CHECK
    ADD CONSTRAINT FK_LS_TARIFF_INCOME_PRM_LS_TARIFF_PRM
        FOREIGN KEY (TARIFF_ID)
        REFERENCES energy.dbo.LS_TARIFF_PRM (ID);

    ALTER TABLE energy.dbo.LS_TARIFF_INCOME_PRM
        CHECK CONSTRAINT FK_LS_TARIFF_INCOME_PRM_LS_TARIFF_PRM;
END
GO

IF EXISTS (SELECT 1 FROM #TariffRestoreState WHERE CAN_RESTORE = 1)
    PRINT 'Tarife FK geri yukleme scripti tamamlandi.';
ELSE
    PRINT 'Tarife FK geri yukleme tam yapilmadi. Once eslesmeyen kayitlar duzeltilmeli.';
GO

