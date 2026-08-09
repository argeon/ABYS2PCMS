/* ============================================================
   00e_grow_izgazMGR_log.sql
   Acil: izgazMGR log %100 — aktif 597 CLEAN (session 112) icin nefes

   Mevcut (2026-08-04):
     F:\LOG\izgazMGR_log.ldf  ~42784–43784 MB, used ~99.9–100%
     F:\ free ~330 GB | max_size zaten 2 TB | growth 8192 MB
     Recovery: BULK_LOGGED
     Aktif uzun tran log reuse ENGELLER → BACKUP LOG yetmez; SIZE buyut

   Kullanım (SSMS / sqlcmd, energy veya master fark etmez):
     sqlcmd -S 172.16.1.195 -d master -I -i 00e_grow_izgazMGR_log.sql

   Not:
     - Log grow zero-fill (IFF log'da yok) → +20 GB birkac dk surebilir
     - Session 112 CALISIRKEN calistirilabilir (guvenli)
     - KILL ONERILMEZ (rollback + full log)
   ============================================================ */
USE master;
GO
SET NOCOUNT ON;

PRINT '=== ONCE ===';
SELECT
    mf.name,
    mf.physical_name,
    CAST(mf.size * 8.0 / 1024 AS decimal(12, 1)) AS size_MB,
    CAST(CASE WHEN mf.max_size < 0 THEN -1 ELSE mf.max_size * 8.0 / 1024 END AS decimal(12, 1)) AS max_MB,
    mf.growth,
    mf.is_percent_growth
FROM sys.master_files mf
WHERE mf.database_id = DB_ID(N'izgazMGR')
  AND mf.type_desc = N'LOG';

SELECT
    CAST(total_log_size_in_bytes / 1024. / 1024 AS decimal(12, 1)) AS log_MB,
    CAST(used_log_space_in_bytes / 1024. / 1024 AS decimal(12, 1)) AS used_MB,
    CAST(used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM izgazMGR.sys.dm_db_log_space_usage;

SELECT
    vs.volume_mount_point,
    CAST(vs.available_bytes / 1024. / 1024. / 1024 AS decimal(12, 1)) AS free_GB
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
WHERE mf.database_id = DB_ID(N'izgazMGR')
  AND mf.type_desc = N'LOG';
GO

/* ----------------------------------------------------------
   +20 GB (43784 → 64256 MB). F:\ ~330 GB free — guvenli.
   Daha fazla lazimsa asagidaki 2. adimi da ac.
   ---------------------------------------------------------- */
PRINT '=== GROW #1: SIZE = 64256 MB (~62.75 GB, +~20 GB) ===';
ALTER DATABASE izgazMGR
MODIFY FILE (
    NAME = N'izgazMGR_log',
    SIZE = 64256 MB   /* mevcut ~43784 + 20472 */
);
GO

/* Istege bagli 2. nefes (+20 GB daha → ~82.75 GB). Gerekirse yorumdan cikar.
PRINT '=== GROW #2: SIZE = 84736 MB ===';
ALTER DATABASE izgazMGR
MODIFY FILE (
    NAME = N'izgazMGR_log',
    SIZE = 84736 MB
);
GO
*/

PRINT '=== SONRA ===';
SELECT
    mf.name,
    CAST(mf.size * 8.0 / 1024 AS decimal(12, 1)) AS size_MB
FROM sys.master_files mf
WHERE mf.database_id = DB_ID(N'izgazMGR')
  AND mf.type_desc = N'LOG';

SELECT
    CAST(total_log_size_in_bytes / 1024. / 1024 AS decimal(12, 1)) AS log_MB,
    CAST(used_log_space_in_bytes / 1024. / 1024 AS decimal(12, 1)) AS used_MB,
    CAST(used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM izgazMGR.sys.dm_db_log_space_usage;

PRINT '=== DONE — session 112 devam etsin; KILL etme ===';
GO
