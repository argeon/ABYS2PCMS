/* =============================================================================
   Tablo    : dbo.LS_TRANSACTION_TYPE  (işlem türü lookup - tahakkuk/tahsilat/tediye)
   Amaç     : ACCRUE / PAYMENT / DISCHARGE / CUSTODY vb. işlem tiplerinin tanımı
   Not      : LREF kaynak sistemdeki PK olduğu için IDENTITY_INSERT ON ile
              birebir korunarak yüklenir. Script idempotenttir (re-run safe).
   ========================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;   -- hata anında transaction'ın tamamı geri alınsın

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---------------------------------------------------------------------
       1) DDL - tablo yoksa oluştur
    --------------------------------------------------------------------- */
    IF OBJECT_ID(N'dbo.LS_TRANSACTION_TYPE', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.LS_TRANSACTION_TYPE
        (
            LREF          INT           IDENTITY(1,1) NOT NULL,
            CODE          INT           NOT NULL,
            [VALUE]       NVARCHAR(100) NOT NULL,
            [TYPE]        TINYINT       NOT NULL,          -- 1..8
            TYPE_DESC     VARCHAR(30)   NOT NULL,          -- ACCRUE, PAYMENT, ...
            BILL_TYPE_ID  INT           NOT NULL,
            IS_ACTIVE     BIT           NOT NULL CONSTRAINT DF_LS_TRANSACTION_TYPE_IS_ACTIVE DEFAULT (1),
            [STATUS]      SMALLINT      NOT NULL,          -- 1 = BORC, -1 = ALACAK
            STATUS_DESC   NVARCHAR(10)  NOT NULL,
            ADDDATE       DATETIME      NULL,
            ADDUSER       NVARCHAR(50)  NULL,
            UPDDATE       DATETIME      NULL,
            UPDUSER       NVARCHAR(50)  NULL,

            CONSTRAINT PK_LS_TRANSACTION_TYPE PRIMARY KEY CLUSTERED (LREF),
            CONSTRAINT UQ_LS_TRANSACTION_TYPE_CODE UNIQUE (CODE),
            CONSTRAINT CK_LS_TRANSACTION_TYPE_STATUS CHECK ([STATUS] IN (-1, 1))
        );
    END;

    /* ---------------------------------------------------------------------
       2) DATA LOAD - idempotent: mevcut satırlar atlanır (NOT EXISTS)
          LREF birebir korunur -> IDENTITY_INSERT ON
    --------------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.LS_TRANSACTION_TYPE ON;

    INSERT INTO dbo.LS_TRANSACTION_TYPE
        (LREF, CODE, [VALUE], [TYPE], TYPE_DESC, BILL_TYPE_ID, IS_ACTIVE, [STATUS], STATUS_DESC,
         ADDDATE, ADDUSER, UPDDATE, UPDUSER)
    SELECT S.LREF, S.CODE, S.[VALUE], S.[TYPE], S.TYPE_DESC, S.BILL_TYPE_ID, S.IS_ACTIVE, S.[STATUS], S.STATUS_DESC,
           NULL, NULL, NULL, NULL
    FROM (VALUES
        ( 1,  1, N'TAHAKKUK',                      1, 'ACCRUE',           126, 1,  1, N'BORC'),
        ( 2,  2, N'EKSILTEN',                      1, 'ACCRUE',             1, 1, -1, N'ALACAK'),
        ( 3,  3, N'ARTTIRAN',                      1, 'ACCRUE',             1, 1,  1, N'BORC'),
        ( 4,  4, N'NAKİT TAHSILATI',               2, 'PAYMENT',          126, 1, -1, N'ALACAK'),
        ( 5,  5, N'KREDI KARTI TAHSILATI',         2, 'PAYMENT',          126, 1, -1, N'ALACAK'),
        ( 6,  6, N'MAHSUP TAHSILATI',              2, 'PAYMENT',          126, 1, -1, N'ALACAK'),
        ( 7,  7, N'BANKA VİRMAN',                  2, 'PAYMENT',          126, 1, -1, N'ALACAK'),
        ( 8,  8, N'AVANSLI TEDIYE',                3, 'DISCHARGE',        126, 0,  1, N'BORC'),
        ( 9,  9, N'TAHSILAT IPTALI',               4, 'CANCEL_PAYMENT',     1, 1,  1, N'BORC'),
        (10, 10, N'GECİKME ZAMMI TAHAKKUKU',       5, 'DELAYED_FROZEN',   126, 1,  1, N'BORC'),
        (11, 11, N'BANKA TALIMATLI TEDIYE',        3, 'DISCHARGE',        126, 1,  1, N'BORC'),
        (12, 12, N'EMANET ÇIKIŞI',                 7, 'CANCEL_CUSTODY',   126, 1,  1, N'BORC'),
        (13, 13, N'ÇAĞRI MERKEZİ TAHSİLATI',       2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (14, 14, N'BANKA GİŞE',                    2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (16, 16, N'BANKA OTOMATİK',                2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (17, 17, N'PTT GİŞE (ONLINE)',             2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (18, 18, N'TAKSİT İPTALİ',                 4, 'CANCEL_PAYMENT',     1, 1,  1, N'BORC'),
        (19, 19, N'MÜKERRER TAHSİLAT',             2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (20, 20, N'EMANET GİRİŞİ',                 6, 'CUSTODY',            1, 1, -1, N'ALACAK'),
        (21, 21, N'TEDİYE İPTALİ',                 8, 'CANCEL_DISCHARGE',   1, 1, -1, N'ALACAK'),
        (22, 22, N'INTERNET TAHSILATI  (ONLINE)',  2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (23, 23, N'KREDİ KARTI TAKSİT TAHSİLATI',  2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (24, 24, N'MAHSUBEN TAHSİLAT',             2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (25, 25, N'EMANET İPTALİ',                 8, 'CANCEL_DISCHARGE',   1, 1,  1, N'BORC'),
        (26, 26, N'EKS TAHSİLATI',                 2, 'PAYMENT',            1, 0, -1, N'ALACAK'),
        (27, 27, N'EKS KREDİ KARTI TAHSİLATI',     2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (29, 29, N'KASA TEDIYE',                   3, 'DISCHARGE',        126, 1,  1, N'BORC'),
        (30, 30, N'DAMGA VERGİSİ TAHSİLATI',       2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (32, 32, N'BANKA GİŞE (ONLINE)',           2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (33, 33, N'BANKA WEB (ONLINE)',            2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (34, 34, N'ÖDEME NOKTASI (ONLINE)',        2, 'PAYMENT',            1, 0, -1, N'ALACAK'),
        (35, 35, N'BANKA OTOMATİK (ONLINE)',       2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (36, 36, N'ALACAKLANDIRMA (NAKİT)',        2, 'PAYMENT',          126, 1, -1, N'ALACAK'),
        (37, 37, N'BELİRSİZ DEPOZİTO TAHSILATI',   2, 'PAYMENT',            1, 1, -1, N'ALACAK'),
        (39, 39, N'ALACAKLANDIRMA (KREDİ KARTI)',  2, 'PAYMENT',            2, 1, -1, N'ALACAK'),
        (40, 40, N'PTT TALİMATLI TEDİYE',          3, 'DISCHARGE',        126, 1,  1, N'BORC'),
        (41, 41, N'GECİKME IPTALI',                5, 'DELAYED_FROZEN',   127, 1, -1, N'ALACAK'),
        (42, 42, N'ATM TAHSİLATI',                 2, 'PAYMENT',            2, 1, -1, N'ALACAK'),
        (43, 43, N'KIOSK NAKIT TAHSİLATI',         2, 'PAYMENT',            2, 1, -1, N'ALACAK'),
        (44, 44, N'ALACAKLANDIRMA (VİRMAN)',       2, 'PAYMENT',          126, 1, -1, N'ALACAK'),
        (45, 45, N'TEMİNAT MEKTUBU İLE TAHSİLAT',  2, 'PAYMENT',            2, 1, -1, N'ALACAK'),
        (46, 46, N'DAMGA VERGİSİ TAHSİLATI',       2, 'PAYMENT',          126, 1,  1, N'BORC'),
        (47, 47, N'ARTTIRAN GENEL TAHAKKUK',       2, 'PAYMENT',            2, 1,  1, N'BORC'),
        (48, 48, N'GÜNCELLEME EMANETİ',            6, 'CUSTODY',            1, 1, -1, N'ALACAK'),
        (49, 49, N'GÜNCELLEME EMANETİ IPTALİ',     6, 'CUSTODY',            1, 1,  1, N'BORC'),
        (50, 50, N'ÇEK TAHSİLATI',                 2, 'PAYMENT',            1, 1,  1, N'BORC')
    ) AS S (LREF, CODE, [VALUE], [TYPE], TYPE_DESC, BILL_TYPE_ID, IS_ACTIVE, [STATUS], STATUS_DESC)
    WHERE NOT EXISTS (SELECT 1
                      FROM dbo.LS_TRANSACTION_TYPE T
                      WHERE T.LREF = S.LREF);

    SET IDENTITY_INSERT dbo.LS_TRANSACTION_TYPE OFF;

    COMMIT TRANSACTION;

 
 
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- IDENTITY_INSERT açık kalmasın (session bazlıdır, tek tabloda kalabilir)
    IF OBJECT_ID(N'dbo.LS_TRANSACTION_TYPE', N'U') IS NOT NULL
        SET IDENTITY_INSERT dbo.LS_TRANSACTION_TYPE OFF;

    THROW;
END CATCH;



/* =============================================================================
   DELTA 01 - dbo.LS_TRANSACTION_TYPE
   Kapsam :
     1) BILL_TYPE_ID kolonu NULLable yapılır (yeni kayıtlarda kaynak veri boş)
     2) LREF 8 (AVANSLI TEDIYE) kaldırılır, yerine LREF 8 (EMANET / CUSTODY) gelir
     3) LREF 86..140 arası 10 yeni ACCRUE/PAYMENT kaydı eklenir
   Not    : Tabloyu SIFIRDAN kuran ortamlarda bu script GEREKMEZ;
            güncel LS_TRANSACTION_TYPE.sql zaten bu halin tamamını içerir.
   ========================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---------------------------------------------------------------------
       0) Ön kontrol: LREF 8'e referans veren transaction var mı?
          Varsa körlemesine DELETE yapmak orphan üretir -> script durur.
          Referans veren tablo adlarını kendi şemana göre ekle/düzenle.
    --------------------------------------------------------------------- */
    -- Örnek (aktif etmeden önce tablo/kolon adını doğrula):
    -- IF EXISTS (SELECT 1 FROM dbo.LS_IZMIT_01_BILL_TRANSACTION WHERE TRANSACTION_TYPE_REF = 8)
    --     THROW 50001, N'LREF 8 kullanımda: önce bağımlı kayıtları ele al.', 1;

    /* ---------------------------------------------------------------------
       1) BILL_TYPE_ID -> NULLable
    --------------------------------------------------------------------- */
    IF EXISTS (SELECT 1
               FROM sys.columns
               WHERE object_id = OBJECT_ID(N'dbo.LS_TRANSACTION_TYPE')
                 AND name = N'BILL_TYPE_ID'
                 AND is_nullable = 0)
    BEGIN
        ALTER TABLE dbo.LS_TRANSACTION_TYPE ALTER COLUMN BILL_TYPE_ID INT NULL;
    END;

    /* ---------------------------------------------------------------------
       2) LREF 8: AVANSLI TEDIYE -> EMANET (UPDATE ile, DELETE+INSERT yerine)
          UPDATE tercih sebebi: FK varsa kırılmaz, LREF sabit kalır.
    --------------------------------------------------------------------- */
    UPDATE dbo.LS_TRANSACTION_TYPE
    SET [VALUE]      = N'EMANET',
        [TYPE]       = 6,
        TYPE_DESC    = 'CUSTODY',
        BILL_TYPE_ID = NULL,
        IS_ACTIVE    = 1,
        [STATUS]     = -1,
        STATUS_DESC  = N'ALACAK',
        UPDDATE      = GETDATE(),
        UPDUSER      = SUSER_SNAME()
    WHERE LREF = 8
      AND [VALUE] = N'AVANSLI TEDIYE';   -- guard: sadece eski kayıt hedeflenir (idempotent)

    /* ---------------------------------------------------------------------
       3) Yeni kayıtlar (idempotent - NOT EXISTS)
    --------------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.LS_TRANSACTION_TYPE ON;

    INSERT INTO dbo.LS_TRANSACTION_TYPE
        (LREF, CODE, [VALUE], [TYPE], TYPE_DESC, BILL_TYPE_ID, IS_ACTIVE, [STATUS], STATUS_DESC,
         ADDDATE, ADDUSER, UPDDATE, UPDUSER)
    SELECT S.LREF, S.CODE, S.[VALUE], S.[TYPE], S.TYPE_DESC, NULL, 1, S.[STATUS], S.STATUS_DESC,
           GETDATE(), SUSER_SNAME(), NULL, NULL
    FROM (VALUES
        (  8,   8, N'EMANET',              6, 'CUSTODY', -1, N'ALACAK'),  -- tablo boşsa / 8 hiç yoksa
        ( 86,  86, N'HİZMET',              1, 'ACCRUE',   1, N'BORC'),
        ( 92,  92, N'İADE',                1, 'ACCRUE',   1, N'BORC'),
        ( 93,  93, N'FARK',                1, 'ACCRUE',   1, N'BORC'),
        ( 99,  99, N'PROJE ÖN ÖDEME',      1, 'ACCRUE',   1, N'BORC'),
        (109, 109, N'GÜVENCE BEDELİ',      1, 'ACCRUE',   1, N'BORC'),
        (110, 110, N'GÜVENCE BEDELİ İADE', 1, 'ACCRUE',   1, N'BORC'),
        (111, 111, N'GÜVENCE BEDELİ FARK', 1, 'ACCRUE',   1, N'BORC'),
        (119, 119, N'GAZ TÜKETİM',         1, 'ACCRUE',   1, N'BORC'),
        (121, 121, N'KIYAS FATURA',        1, 'ACCRUE',   1, N'BORC'),
        (140, 140, N'ÇEK',                 2, 'PAYMENT', -1, N'ALACAK')
    ) AS S (LREF, CODE, [VALUE], [TYPE], TYPE_DESC, [STATUS], STATUS_DESC)
    WHERE NOT EXISTS (SELECT 1
                      FROM dbo.LS_TRANSACTION_TYPE T
                      WHERE T.LREF = S.LREF);

    SET IDENTITY_INSERT dbo.LS_TRANSACTION_TYPE OFF;

    COMMIT TRANSACTION;
 
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    IF OBJECT_ID(N'dbo.LS_TRANSACTION_TYPE', N'U') IS NOT NULL
        SET IDENTITY_INSERT dbo.LS_TRANSACTION_TYPE OFF;

    THROW;
END CATCH;

