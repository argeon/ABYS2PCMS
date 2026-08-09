/* =============================================================================
   Tablo    : dbo.LS_ACCRUE_TYPE_PRM  (tahakkuk turu parametre tablosu)
   Kural    : LREF = CODE = kaynak PRM_ID  (IDENTITY_INSERT ON ile birebir)
   Kapsam   : 45 kayit. Onceki taslaktaki ek satirlar (8-EMANET, 86, 92, 93,
              99, 109, 110, 111, 119, 121, 140, 875) BU TABLOYA DAHIL DEGILDIR.
   Script   : Idempotent (re-run safe), XACT_ABORT + TRY/CATCH ile atomik.
   ========================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RowCountTotal INT;

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---------------------------------------------------------------------
       1) DDL
    --------------------------------------------------------------------- */
    IF OBJECT_ID(N'dbo.LS_ACCRUE_TYPE_PRM', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.LS_ACCRUE_TYPE_PRM
        (
            LREF          INT           IDENTITY(1,1) NOT NULL,   -- = PRM_ID
            CODE          INT           NOT NULL,                 -- = PRM_ID
            [VALUE]       NVARCHAR(100) NOT NULL,
            IS_ACTIVE     BIT           NOT NULL CONSTRAINT DF_LS_ACCRUE_TYPE_PRM_IS_ACTIVE DEFAULT (1),
            [STATUS]      SMALLINT      NOT NULL,                 -- 1 = BORC, -1 = ALACAK
            STATUS_DESC   NVARCHAR(10)  NULL,
            ADDDATE       DATETIME      NULL,
            ADDUSER       NVARCHAR(50)  NULL,
            UPDDATE       DATETIME      NULL,
            UPDUSER       NVARCHAR(50)  NULL,

            CONSTRAINT PK_LS_ACCRUE_TYPE_PRM PRIMARY KEY CLUSTERED (LREF),
            CONSTRAINT UQ_LS_ACCRUE_TYPE_PRM_CODE UNIQUE (CODE),
            CONSTRAINT CK_LS_ACCRUE_TYPE_PRM_STATUS CHECK ([STATUS] IN (-1, 1)),
            CONSTRAINT CK_LS_ACCRUE_TYPE_PRM_LREF_CODE CHECK (LREF = CODE)   -- kural tabloda da garanti
        );
    END;

    /* ---------------------------------------------------------------------
       2) DATA LOAD - LREF = CODE = PRM_ID, idempotent
    --------------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.LS_ACCRUE_TYPE_PRM ON;

    INSERT INTO dbo.LS_ACCRUE_TYPE_PRM
        (LREF, CODE, [VALUE], IS_ACTIVE, [STATUS], STATUS_DESC, ADDDATE, ADDUSER, UPDDATE, UPDUSER)
    SELECT S.PRM_ID, S.PRM_ID, S.[VALUE], S.IS_ACTIVE, S.[STATUS], NULL, NULL, NULL, NULL, NULL
    FROM (VALUES
        ( 22, N'ÖN ÖDEMELİ TÜKETİM TAHAKKUKU',           1, 1),
        (331, N'ÖN ÖDEMELİ İŞLEMLER',                    1, 1),
        (334, N'ZEMİN TAHRİP GİDERİ',                    1, 1),
        ( 10, N'TAKSIT',                                 1, 1),
        (  5, N'SÖZLEŞME TAHAKKUKU',                     1, 1),
        (332, N'SAYAÇ BEDELİ',                           1, 1),
        ( 25, N'SANAYİ TÜKETİM FARKI',                   1, 1),
        ( 19, N'RANDEVU BEDELLERİ',                      1, 1),
        ( 18, N'PROJE BEDELLERİ',                        1, 1),
        (  9, N'PEGASUS TÜKETİM TAHAKKUKU',              1, 1),
        ( 28, N'PEGASUS İLK ABONELİK TAHAKKUKU',         1, 1),
        ( 16, N'OTO. AÇMA ÜCRETİ',                       1, 1),
        (543, N'ORTALAMA TÜKETİM TAHAKKUKU MANUEL',      1, 1),
        (338, N'ORTALAMA TÜKETİM TAHAKKUKU',             1, 1),
        ( 11, N'MUACCEL',                                1, 1),
        (335, N'MHA ABONELİK BEDELİ',                    1, 1),
        (  2, N'MERKEZ TÜKETİM TAHAKKUKU',               1, 1),
        (330, N'MEKANİK KONTORLU SAYAÇ DEĞİŞİMİ',        1, 1),
        (443, N'KIYAS TAHAKKUKU',                        1, 1),
        (  6, N'KİRACI DEĞİŞİMİ DEPOZİTO',               1, 1),
        (333, N'KAPAMA BEDELİ',                          1, 1),
        (342, N'KADEME FARKI',                           1, 1),
        ( 26, N'İŞ EMRİ TÜKETİM TAHAKKUKU TÜRÜ',         1, 1),
        (329, N'İŞ EMRİ TÜKETİM TAHAKKUKU',              1, 1),
        (  4, N'ILK ABONELIK BEDELİ (KBA)',              1, 1),
        (  8, N'ICRA',                                   1, 1),
        ( 15, N'HASAR BEDELİ TAHAKKUKU',                 1, 1),
        (  7, N'GENEL',                                  1, 1),
        ( 12, N'GECIKME BEDELİ TAHAKKUKU',               1, 1),
        ( 20, N'FİRMA VİZE',                             1, 1),
        ( 17, N'FİRMA SERTİFİKA TAH.',                   1, 1),
        ( 46, N'FİRMA SERTİFİKA TADİLAT BEDELİ',         1, 1),
        ( 14, N'EMANET',                                 1, 1),
        (  1, N'EL TERMİNALİ TÜKETİM TAHAKKUKU',         1, 1),
        (341, N'DEPOZİTO FARK(MANUEL)',                  1, 1),
        ( 21, N'DEPOZİTO FARK BEDELİ',                   1, 1),
        ( 47, N'DEPLASE TAHAKKUKU',                      1, 1),
        (  3, N'CEZA BEDELİ',                            1, 1),   -- kaynaktaki sondaki bosluk trim edildi
        (339, N'CEZA BEDELİ',                            1, 1),
        ( 23, N'BEDELSİZ ÖN ÖDEMELİ TÜKETİM TAHAKKUKU',  1, 1),
        ( 13, N'AÇMA KAPAMA BEDELİ',                     1, 1),
        (336, N'AÇMA BEDELİ',                            1, 1),
        ( 24, N'ANALİZ TAHAKKUKU',                       1, 1),
        (544, N'ABONELİK BBS FARK BEDELİ (MANUEL)',      1, 1),
        ( 27, N'ABONELİK BBS FARK BEDELİ',               1, 1)
    ) AS S (PRM_ID, [VALUE], IS_ACTIVE, [STATUS])
    WHERE NOT EXISTS (SELECT 1
                      FROM dbo.LS_ACCRUE_TYPE_PRM T
                      WHERE T.LREF = S.PRM_ID);

    SET IDENTITY_INSERT dbo.LS_ACCRUE_TYPE_PRM OFF;

    COMMIT TRANSACTION;

    SELECT @RowCountTotal = COUNT(*) FROM dbo.LS_ACCRUE_TYPE_PRM;
    PRINT CONCAT('LS_ACCRUE_TYPE_PRM yukleme tamamlandi. Toplam satir: ', @RowCountTotal, ' (beklenen: 45)');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    IF OBJECT_ID(N'dbo.LS_ACCRUE_TYPE_PRM', N'U') IS NOT NULL
        SET IDENTITY_INSERT dbo.LS_ACCRUE_TYPE_PRM OFF;

    THROW;
END CATCH;



