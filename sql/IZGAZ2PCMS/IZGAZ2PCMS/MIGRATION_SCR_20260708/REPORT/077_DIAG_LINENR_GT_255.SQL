-- =============================================================================
-- prod2 / diag — gelir adedi (LINENR) > 255  (581 TINYINT aday)
-- Ortam: Oracle MIGRATION | Onkosul: LS_INVLINES (12 CTAS)
-- Salt okuma
-- =============================================================================

SELECT
    COUNT(*) AS FATURA_ADET,
    MAX(cnt) AS MAX_GELIR_ADET,
    SUM(cnt) AS TOPLAM_SATIR
FROM (
    SELECT INVOICEREF,
           COUNT(*) AS cnt,
           MAX(LINENR) AS max_linenr
    FROM MIGRATION.LS_INVLINES
    GROUP BY INVOICEREF
    HAVING COUNT(*) > 255 OR MAX(LINENR) > 255
);

SELECT *
FROM (
    SELECT
        INVOICEREF,
        COUNT(*) AS GELIR_ADET,
        MAX(LINENR) AS MAX_LINENR,
        MAX(ABYS_AGREEMENT_ID) AS ABYS_AGREEMENT_ID,
        MIN(LREF) AS MIN_LREF,
        MAX(LREF) AS MAX_LREF
    FROM MIGRATION.LS_INVLINES
    GROUP BY INVOICEREF
    HAVING COUNT(*) > 255 OR MAX(LINENR) > 255
    ORDER BY COUNT(*) DESC
)
WHERE ROWNUM <= 200;

PROMPT ========== diag LINENR>255 OK ==========
/
