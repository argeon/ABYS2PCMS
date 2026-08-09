/* ============================================================
   LS_ACTION_TYPE_PRM
   Source: CS_ACTION_TYPE_PRM + CS_ACTION_TYPE_PRM_LNG (LANG_ID=1)
   TYPE   : 1=ACCRUE 2=PAYMENT 3=DISCHARGE 4=CANCEL_PAYMENT
            5=DELAYED_FROZEN 6=CUSTODY 7=CANCEL_CUSTODY 8=CANCEL_DISCHARGE
   STATUS : 1=BORC (debit)  -1=ALACAK (credit)
   ============================================================ */

IF OBJECT_ID('dbo.LS_ACTION_TYPE_PRM', 'U') IS NOT NULL
    DROP TABLE dbo.LS_ACTION_TYPE_PRM;
GO

CREATE TABLE dbo.LS_ACTION_TYPE_PRM
(
    ID           INT           NOT NULL PRIMARY KEY,   -- source CS_ACTION_TYPE_PRM.ID (kept as-is, not identity)
    CODE         NVARCHAR(20)  NOT NULL,
    [VALUE]      NVARCHAR(200) NOT NULL,                -- Turkish description from PRM_LNG
    [TYPE]       TINYINT       NOT NULL,
    TYPE_DESC    NVARCHAR(30)  NOT NULL,
    BILL_TYPE_ID INT           NULL,
    IS_ACTIVE    BIT           NOT NULL,
    STATUS       SMALLINT      NOT NULL,
    STATUS_DESC  NVARCHAR(10)  NOT NULL,
    CONSTRAINT CK_LS__ATP_TYPE   CHECK ([TYPE] BETWEEN 1 AND 8),
    CONSTRAINT CK_LS__ATP_STATUS CHECK (STATUS IN (1, -1))
);
GO

SET IDENTITY_INSERT dbo.LS_ACTION_TYPE_PRM OFF; -- not an identity column, no-op safeguard
GO

INSERT INTO dbo.LS_ACTION_TYPE_PRM
    (ID, CODE, [VALUE], [TYPE], TYPE_DESC, BILL_TYPE_ID, IS_ACTIVE, STATUS, STATUS_DESC)
VALUES
    (1,  '1',  N'TAHAKKUK',                        1, 'ACCRUE',           126, 1,  1, 'BORC'),
    (2,  '2',  N'EKSILTEN',                         1, 'ACCRUE',           1,   1, -1, 'ALACAK'),
    (3,  '3',  N'ARTTIRAN',                         1, 'ACCRUE',           1,   1,  1, 'BORC'),
    (4,  '4',  N'NAKİT TAHSILATI',                  2, 'PAYMENT',          126, 1, -1, 'ALACAK'),
    (5,  '5',  N'KREDI KARTI TAHSILATI',            2, 'PAYMENT',          126, 1, -1, 'ALACAK'),
    (6,  '6',  N'MAHSUP TAHSILATI',                 2, 'PAYMENT',          126, 1, -1, 'ALACAK'),
    (7,  '7',  N'BANKA VİRMAN',                     2, 'PAYMENT',          126, 1, -1, 'ALACAK'),
    (8,  '8',  N'AVANSLI TEDIYE',                   3, 'DISCHARGE',        126, 0,  1, 'BORC'),
    (9,  '9',  N'TAHSILAT IPTALI',                  4, 'CANCEL_PAYMENT',   1,   1,  1, 'BORC'),
    (10, '10', N'GECİKME ZAMMI TAHAKKUKU',          5, 'DELAYED_FROZEN',   126, 1,  1, 'BORC'),
    (11, '11', N'BANKA TALIMATLI TEDIYE',           3, 'DISCHARGE',        126, 1,  1, 'BORC'),
    (12, '12', N'EMANET ÇIKIŞI',                    7, 'CANCEL_CUSTODY',   126, 1,  1, 'BORC'),
    (13, '13', N'ÇAĞRI MERKEZİ TAHSİLATI',          2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (14, '14', N'BANKA GİŞE',                       2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (16, '16', N'BANKA OTOMATİK',                   2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (17, '17', N'PTT GİŞE (ONLINE)',                2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (18, '18', N'TAKSİT İPTALİ',                    4, 'CANCEL_PAYMENT',   1,   1,  1, 'BORC'),
    (19, '19', N'MÜKERRER TAHSİLAT',                2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (20, '20', N'EMANET GİRİŞİ',                    6, 'CUSTODY',          1,   1, -1, 'ALACAK'),
    (21, '21', N'TEDİYE İPTALİ',                    8, 'CANCEL_DISCHARGE', 1,   1, -1, 'ALACAK'),
    (22, '22', N'INTERNET TAHSILATI  (ONLINE)',     2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (23, '23', N'KREDİ KARTI TAKSİT TAHSİLATI',     2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (24, '24', N'MAHSUBEN TAHSİLAT',                2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (25, '25', N'EMANET İPTALİ',                    8, 'CANCEL_DISCHARGE', 1,   1,  1, 'BORC'),
    (26, '26', N'EKS TAHSİLATI',                    2, 'PAYMENT',          1,   0, -1, 'ALACAK'),
    (27, '27', N'EKS KREDİ KARTI TAHSİLATI',        2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (29, '29', N'KASA TEDIYE',                      3, 'DISCHARGE',        126, 1,  1, 'BORC'),
    (30, '30', N'DAMGA VERGİSİ TAHSİLATI',          2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (32, '32', N'BANKA GİŞE (ONLINE)',              2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (33, '33', N'BANKA WEB (ONLINE)',               2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (34, '34', N'ÖDEME NOKTASI (ONLINE)',           2, 'PAYMENT',          1,   0, -1, 'ALACAK'),
    (35, '35', N'BANKA OTOMATİK (ONLINE)',          2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (36, '36', N'ALACAKLANDIRMA (NAKİT)',           2, 'PAYMENT',          126, 1, -1, 'ALACAK'),
    (37, '37', N'BELİRSİZ DEPOZİTO TAHSILATI',      2, 'PAYMENT',          1,   1, -1, 'ALACAK'),
    (39, '39', N'ALACAKLANDIRMA (KREDİ KARTI)',     2, 'PAYMENT',          2,   1, -1, 'ALACAK'),
    (40, '40', N'PTT TALİMATLI TEDİYE',             3, 'DISCHARGE',        126, 1,  1, 'BORC'),
    (41, '41', N'GECİKME IPTALI',                   5, 'DELAYED_FROZEN',   127, 1, -1, 'ALACAK'),
    (42, '42', N'ATM TAHSİLATI',                    2, 'PAYMENT',          2,   1, -1, 'ALACAK'),
    (43, '43', N'KIOSK NAKIT TAHSİLATI',            2, 'PAYMENT',          2,   1, -1, 'ALACAK'),
    (44, '44', N'ALACAKLANDIRMA (VİRMAN)',          2, 'PAYMENT',          126, 1, -1, 'ALACAK'),
    (45, '45', N'TEMİNAT MEKTUBU İLE TAHSİLAT',     2, 'PAYMENT',          2,   1, -1, 'ALACAK'),
    (46, '46', N'DAMGA VERGİSİ TAHSİLATI',          2, 'PAYMENT',          126, 1,  1, 'BORC'),
    (47, '47', N'ARTTIRAN GENEL TAHAKKUK',          2, 'PAYMENT',          2,   1,  1, 'BORC'),
    (48, '48', N'GÜNCELLEME EMANETİ',               6, 'CUSTODY',          1,   1, -1, 'ALACAK'),
    (49, '49', N'GÜNCELLEME EMANETİ IPTALİ',        6, 'CUSTODY',          1,   1,  1, 'BORC'),
    (50, '50', N'ÇEK TAHSİLATI',                    2, 'PAYMENT',          1,   1,  1, 'BORC');
GO

/* ---- Sanity checks ---- */
-- Row count should be 46
SELECT COUNT(*) AS RowCount_Expect_46 FROM dbo.LS_ACTION_TYPE_PRM;

-- Duplicate ID / CODE check (should return 0 rows)
SELECT ID, COUNT(*) FROM dbo.LS_ACTION_TYPE_PRM GROUP BY ID HAVING COUNT(*) > 1;

-- TYPE/STATUS combinations actually present in this dataset (for downstream mapping validation)
SELECT [TYPE], TYPE_DESC, STATUS, STATUS_DESC, COUNT(*) AS Cnt
FROM dbo.LS_ACTION_TYPE_PRM
GROUP BY [TYPE], TYPE_DESC, STATUS, STATUS_DESC
ORDER BY [TYPE];
