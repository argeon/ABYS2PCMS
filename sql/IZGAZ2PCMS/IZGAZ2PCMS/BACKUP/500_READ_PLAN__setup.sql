/* ============================================================
   SCRIPT_ID : READ_PLAN_SETUP
   SCRIPT_NO : 500
   FILE      : 500_READ_PLAN__setup.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- izgazMGR.dbo.CS_READING_PLAN → energy.dbo.mgg_cbs_okuma_bolge
-- KonumWkt ← LOCATION (geography → geometry)
-- Diğer kaynak kolonlar → ABYS_* (hedef tabloda)
-- ============================================================
USE energy;
GO

-- KonumWkt ← LOCATION__wkt (Oracle EPSG:4326 WKT) → geometry SRID 3857
-- LOCATION (geography) kullanilmaz — Oracle tarafinda SDO_CS.TRANSFORM(4326) + GIS_TO_WKTGEOMETRY
CREATE OR ALTER FUNCTION dbo.FN_MIG_WKT_TO_GEOM (
    @Wkt NVARCHAR(MAX),
    @TargetSrid INT
)
RETURNS geometry
AS
BEGIN
    DECLARE @g geometry;
    DECLARE @W NVARCHAR(MAX) = LTRIM(RTRIM(@Wkt));

    IF @W IS NULL OR @W = N'' OR @TargetSrid IS NULL
        RETURN NULL;

    IF UPPER(LEFT(@W, 5)) NOT IN (N'POINT', N'LINEST', N'POLYG', N'MULTI', N'GEOME', N'CURVE', N'COMPO')
        RETURN NULL;

    SET @g = geometry::STGeomFromText(@W, @TargetSrid);

    IF @g IS NOT NULL AND @g.STIsValid() = 0
        SET @g = @g.MakeValid();

    RETURN @g;
END
GO

CREATE OR ALTER FUNCTION dbo.FN_MIG_LON_TO_MERC_X (@Lon FLOAT)
RETURNS FLOAT
AS
BEGIN
    RETURN @Lon * 20037508.34 / 180.0;
END
GO

CREATE OR ALTER FUNCTION dbo.FN_MIG_LAT_TO_MERC_Y (@Lat FLOAT)
RETURNS FLOAT
AS
BEGIN
    -- Web Mercator gecerli enlem araligi
    IF @Lat > 85.05112878 SET @Lat = 85.05112878;
    IF @Lat < -85.05112878 SET @Lat = -85.05112878;
    RETURN LOG(TAN((90.0 + @Lat) * PI() / 360.0)) / (PI() / 180.0) * 20037508.34 / 180.0;
END
GO

CREATE OR ALTER FUNCTION dbo.FN_MIG_RING_4326_TO_WKT_3857 (@Ring GEOMETRY)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @Ring IS NULL OR @Ring.STIsEmpty() = 1
        RETURN NULL;

    DECLARE @i INT = 1;
    DECLARE @n INT = @Ring.STNumPoints();
    DECLARE @out NVARCHAR(MAX) = N'';

    WHILE @i <= @n
    BEGIN
        DECLARE @p GEOMETRY = @Ring.STPointN(@i);
        IF @i > 1 SET @out = @out + N', ';
        SET @out = @out
            + CONVERT(NVARCHAR(40), dbo.FN_MIG_LON_TO_MERC_X(@p.STX))
            + N' '
            + CONVERT(NVARCHAR(40), dbo.FN_MIG_LAT_TO_MERC_Y(@p.STY));
        SET @i += 1;
    END

    RETURN @out;
END
GO

CREATE OR ALTER FUNCTION dbo.FN_MIG_POLYGON_4326_TO_WKT_3857 (@Poly GEOMETRY)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @Poly IS NULL OR @Poly.STIsEmpty() = 1
        RETURN NULL;

    DECLARE @ext NVARCHAR(MAX) = dbo.FN_MIG_RING_4326_TO_WKT_3857(@Poly.STExteriorRing());
    IF @ext IS NULL
        RETURN NULL;

    DECLARE @out NVARCHAR(MAX) = N'POLYGON ((' + @ext + N'))';
    DECLARE @ir INT = 1;
    DECLARE @nr INT = @Poly.STNumInteriorRing();

    WHILE @ir <= @nr
    BEGIN
        DECLARE @hole NVARCHAR(MAX) = dbo.FN_MIG_RING_4326_TO_WKT_3857(@Poly.STInteriorRingN(@ir));
        IF @hole IS NOT NULL
            SET @out = @out + N', (' + @hole + N')';
        SET @ir += 1;
    END

    RETURN @out;
END
GO

CREATE OR ALTER FUNCTION dbo.FN_MIG_WKT_4326_TO_GEOM_3857 (
    @Wkt NVARCHAR(MAX)
)
RETURNS geometry
AS
BEGIN
    -- Bu sunucuda SqlGeometry.STTransform yok; EPSG:4326 WKT → 3857 manuel donusum.
    DECLARE @g geometry = dbo.FN_MIG_WKT_TO_GEOM(@Wkt, 4326);
    IF @g IS NULL OR @g.STIsEmpty() = 1
        RETURN NULL;

    DECLARE @sample geometry =
        CASE @g.STGeometryType()
            WHEN 'Point' THEN @g
            WHEN 'LineString' THEN @g.STPointN(1)
            WHEN 'Polygon' THEN @g.STExteriorRing().STPointN(1)
            WHEN 'MultiPolygon' THEN @g.STGeometryN(1).STExteriorRing().STPointN(1)
            ELSE NULL
        END;

    -- Oracle tarafinda zaten 3857 WKT geldiyse yeniden donusturme
    IF @sample IS NOT NULL AND (ABS(@sample.STX) > 180.0 OR ABS(@sample.STY) > 90.0)
        RETURN dbo.FN_MIG_WKT_TO_GEOM(@Wkt, 3857);

    DECLARE @wkt3857 NVARCHAR(MAX);
    DECLARE @type NVARCHAR(20) = @g.STGeometryType();

    IF @type = 'Point'
    BEGIN
        SET @wkt3857 = N'POINT('
            + CONVERT(NVARCHAR(40), dbo.FN_MIG_LON_TO_MERC_X(@g.STX)) + N' '
            + CONVERT(NVARCHAR(40), dbo.FN_MIG_LAT_TO_MERC_Y(@g.STY)) + N')';
    END
    ELSE IF @type = 'LineString'
    BEGIN
        DECLARE @line NVARCHAR(MAX) = dbo.FN_MIG_RING_4326_TO_WKT_3857(@g);
        IF @line IS NULL RETURN NULL;
        SET @wkt3857 = N'LINESTRING(' + @line + N')';
    END
    ELSE IF @type = 'Polygon'
    BEGIN
        SET @wkt3857 = dbo.FN_MIG_POLYGON_4326_TO_WKT_3857(@g);
    END
    ELSE IF @type = 'MultiPolygon'
    BEGIN
        DECLARE @i INT = 1;
        DECLARE @n INT = @g.STNumGeometries();
        DECLARE @polyWkt NVARCHAR(MAX);
        SET @wkt3857 = N'MULTIPOLYGON (';

        WHILE @i <= @n
        BEGIN
            SET @polyWkt = dbo.FN_MIG_POLYGON_4326_TO_WKT_3857(@g.STGeometryN(@i));
            IF @polyWkt IS NULL
                RETURN NULL;
            IF @i > 1 SET @wkt3857 = @wkt3857 + N', ';
            SET @wkt3857 = @wkt3857 + SUBSTRING(@polyWkt, 9, LEN(@polyWkt) - 8);
            SET @i += 1;
        END

        SET @wkt3857 = @wkt3857 + N')';
    END
    ELSE
        RETURN NULL;

    IF @wkt3857 IS NULL OR @wkt3857 = N''
        RETURN NULL;

    DECLARE @t geometry = geometry::STGeomFromText(@wkt3857, 3857);
    IF @t IS NULL OR @t.STIsEmpty() = 1
        RETURN NULL;

    IF @t.STIsValid() = 0
        SET @t = @t.MakeValid();

    RETURN @t;
END
GO

IF OBJECT_ID('dbo.FN_MIG_GEOG_TO_GEOM', 'FN') IS NOT NULL
    DROP FUNCTION dbo.FN_MIG_GEOG_TO_GEOM;
GO
IF OBJECT_ID('dbo.FN_MIG_ABYS_GEOG_WKT_TO_GEOM', 'FN') IS NOT NULL
    DROP FUNCTION dbo.FN_MIG_ABYS_GEOG_WKT_TO_GEOM;
GO
IF OBJECT_ID('dbo.FN_MIG_OFFSET_COORD_LIST', 'FN') IS NOT NULL
    DROP FUNCTION dbo.FN_MIG_OFFSET_COORD_LIST;
GO

-- ------------------------------------------------------------
-- Hedef ABYS kolonları
-- ------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_MIG_ROW_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_MIG_ROW_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_READING_LAYER_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_READING_LAYER_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_BOOK_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_BOOK_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_CODE')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_CODE NVARCHAR(6) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_READING_DAY')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_READING_DAY SMALLINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_TERMINAL_SYNC_CLIENT_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_TERMINAL_SYNC_CLIENT_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_LOCATION_WKT')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_LOCATION_WKT NVARCHAR(MAX) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_MAX_SUBSCRIBER_COUNT')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_MAX_SUBSCRIBER_COUNT BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_CREATED_USER_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_CREATED_USER_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_CREATED_TIMESTAMP')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_CREATED_TIMESTAMP DATETIMEOFFSET(7) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_UPDATED_USER_ID')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_UPDATED_USER_ID BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_UPDATED_TIMESTAMP')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_UPDATED_TIMESTAMP DATETIMEOFFSET(7) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_VERSION')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_VERSION BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_FIRST_READING_ORDER_NUMBER')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_FIRST_READING_ORDER_NUMBER DECIMAL(20, 0) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_LAST_READING_ORDER_NUMBER')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_LAST_READING_ORDER_NUMBER DECIMAL(20, 0) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_TERMINAL_ORDER')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_TERMINAL_ORDER SMALLINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'ABYS_IS_ACTIVE')
    ALTER TABLE energy.dbo.mgg_cbs_okuma_bolge ADD ABYS_IS_ACTIVE SMALLINT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'UX_MGG_OKUMA_BOLGE_ABYS_MIG')
    DROP INDEX UX_MGG_OKUMA_BOLGE_ABYS_MIG ON energy.dbo.mgg_cbs_okuma_bolge;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'UX_MGG_OKUMA_BOLGE_ABYS_MIG')
    CREATE UNIQUE NONCLUSTERED INDEX UX_MGG_OKUMA_BOLGE_ABYS_MIG
        ON energy.dbo.mgg_cbs_okuma_bolge (ABYS_MIG_ROW_ID)
        WHERE ABYS_MIG_ROW_ID IS NOT NULL;
GO
 
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('energy.dbo.mgg_cbs_okuma_bolge') AND name = 'UX_MGG_OKUMA_BOLGE_ABYS_ID')
    CREATE UNIQUE NONCLUSTERED INDEX UX_MGG_OKUMA_BOLGE_ABYS_ID
        ON energy.dbo.mgg_cbs_okuma_bolge (ABYS_ID)
        WHERE ABYS_ID IS NOT NULL;
GO

-- ------------------------------------------------------------
-- Kaynak: MIG_ROW_ID köprüsü
-- ------------------------------------------------------------
IF OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'MIG_ROW_ID') IS NOT NULL
       AND COLUMNPROPERTY(OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN'), 'MIG_ROW_ID', 'IsIdentity') = 1
    BEGIN
        IF EXISTS (
            SELECT 1 FROM izgazMGR.sys.indexes
            WHERE object_id = OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN')
              AND name = 'UX_CS_READING_PLAN_MIG_ROW'
        )
            DROP INDEX UX_CS_READING_PLAN_MIG_ROW ON izgazMGR.dbo.CS_READING_PLAN;

        ALTER TABLE izgazMGR.dbo.CS_READING_PLAN DROP COLUMN MIG_ROW_ID;
    END

    IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'MIG_ROW_ID') IS NULL
        ALTER TABLE izgazMGR.dbo.CS_READING_PLAN ADD MIG_ROW_ID BIGINT NULL;

    IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', '_MIG_UID') IS NULL
        ALTER TABLE izgazMGR.dbo.CS_READING_PLAN ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_PLAN_PREP_SOURCE
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN', 'U') IS NULL
        RETURN;

    IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'MIG_ROW_ID') IS NULL
       OR COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', '_MIG_UID') IS NULL
    BEGIN
        RAISERROR('CS_READING_PLAN: MIG_ROW_ID veya _MIG_UID yok. Once 21_cs_reading_plan_okuma_bolge_setup.sql calistirin.', 16, 1);
        RETURN;
    END

    ;WITH Ordered AS (
        SELECT
            s._MIG_UID,
            ROW_NUMBER() OVER (
                ORDER BY
                    CAST(s.CREATED_TIMESTAMP AS DATETIME2),
                    s.ID,
                    s._MIG_UID
            ) AS NewMigRowId
        FROM izgazMGR.dbo.CS_READING_PLAN s
    )
    UPDATE s
    SET s.MIG_ROW_ID = o.NewMigRowId
    FROM izgazMGR.dbo.CS_READING_PLAN s
    INNER JOIN Ordered o ON o._MIG_UID = s._MIG_UID;

    IF EXISTS (
        SELECT 1 FROM izgazMGR.dbo.CS_READING_PLAN WHERE MIG_ROW_ID IS NULL
    )
        RAISERROR('CS_READING_PLAN: MIG_ROW_ID atamasi tamamlanamadi.', 16, 1);

    IF EXISTS (
        SELECT 1 FROM izgazMGR.sys.indexes
        WHERE object_id = OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN')
          AND name = 'UX_CS_READING_PLAN_MIG_ROW'
    )
        DROP INDEX UX_CS_READING_PLAN_MIG_ROW ON izgazMGR.dbo.CS_READING_PLAN;

    CREATE UNIQUE NONCLUSTERED INDEX UX_CS_READING_PLAN_MIG_ROW
        ON izgazMGR.dbo.CS_READING_PLAN (MIG_ROW_ID);
END
GO

EXEC dbo.SP_MIG_READING_PLAN_PREP_SOURCE;
GO

-- ------------------------------------------------------------
-- Kaynak view — KonumWkt icin LOCATION__wkt (EPSG:4326 Oracle WKT) zorunlu
-- View, MIG_ROW_ID kolonu yokken olusturulursa binding hatasi kalir; once kolonlari garanti et.
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.VW_MIG_READING_PLAN_SOURCE', 'V') IS NOT NULL
    DROP VIEW dbo.VW_MIG_READING_PLAN_SOURCE;
GO

IF OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN', 'U') IS NULL
BEGIN
    RAISERROR('izgazMGR.dbo.CS_READING_PLAN bulunamadi. Once Oracle staging calistirin.', 16, 1);
END
GO

IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'MIG_ROW_ID') IS NULL
    ALTER TABLE izgazMGR.dbo.CS_READING_PLAN ADD MIG_ROW_ID BIGINT NULL;
GO

IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', '_MIG_UID') IS NULL
    ALTER TABLE izgazMGR.dbo.CS_READING_PLAN ADD _MIG_UID INT IDENTITY(1, 1) NOT NULL;
GO

IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'LOCATION__wkt') IS NULL
    ALTER TABLE izgazMGR.dbo.CS_READING_PLAN ADD LOCATION__wkt NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'OKUMA_BOLGE_ADI') IS NULL
    ALTER TABLE izgazMGR.dbo.CS_READING_PLAN ADD OKUMA_BOLGE_ADI NVARCHAR(250) NULL;
GO

IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'MIG_ROW_ID') IS NULL
BEGIN
    RAISERROR('CS_READING_PLAN.MIG_ROW_ID eklenemedi. Setup sirasini kontrol edin.', 16, 1);
END
GO

CREATE VIEW dbo.VW_MIG_READING_PLAN_SOURCE
AS
SELECT
    s.MIG_ROW_ID,
    s.ID                                                      AS ABYS_ID,
    LEFT(COALESCE(NULLIF(LTRIM(RTRIM(s.OKUMA_BOLGE_ADI)), N''), s.CODE), 250) AS OkumaBolgeAdi,
    energy.dbo.FN_MIG_WKT_4326_TO_GEOM_3857(s.LOCATION__wkt)   AS KonumWkt,
    s.READING_LAYER_ID                                        AS ABYS_READING_LAYER_ID,
    s.BOOK_ID                                                 AS ABYS_BOOK_ID,
    s.CODE                                                    AS ABYS_CODE,
    s.READING_DAY                                             AS ABYS_READING_DAY,
    s.TERMINAL_SYNC_CLIENT_ID                                 AS ABYS_TERMINAL_SYNC_CLIENT_ID,
    s.LOCATION__wkt                                           AS ABYS_LOCATION_WKT,
    s.MAX_SUBSCRIBER_COUNT                                    AS ABYS_MAX_SUBSCRIBER_COUNT,
    s.CREATED_USER_ID                                         AS ABYS_CREATED_USER_ID,
    s.CREATED_TIMESTAMP                                       AS ABYS_CREATED_TIMESTAMP,
    s.UPDATED_USER_ID                                         AS ABYS_UPDATED_USER_ID,
    s.UPDATED_TIMESTAMP                                       AS ABYS_UPDATED_TIMESTAMP,
    s.VERSION                                                 AS ABYS_VERSION,
    s.FIRST_READING_ORDER_NUMBER                              AS ABYS_FIRST_READING_ORDER_NUMBER,
    s.LAST_READING_ORDER_NUMBER                               AS ABYS_LAST_READING_ORDER_NUMBER,
    s.TERMINAL_ORDER                                          AS ABYS_TERMINAL_ORDER,
    s.IS_ACTIVE                                               AS ABYS_IS_ACTIVE,
    energy.dbo.FN_SAFE_DT(CAST(s.CREATED_TIMESTAMP AS DATETIME2)) AS ent_datetime
FROM izgazMGR.dbo.CS_READING_PLAN s
WHERE s.MIG_ROW_ID IS NOT NULL;
GO

IF OBJECT_ID('dbo.SP_MIG_READING_PLAN_INSERT_ONE', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIG_READING_PLAN_INSERT_ONE';
IF OBJECT_ID('dbo.SP_MIGRATE_CS_READING_PLAN_OKUMA_BOLGE', 'P') IS NOT NULL
    EXEC sys.sp_refreshsqlmodule N'dbo.SP_MIGRATE_CS_READING_PLAN_OKUMA_BOLGE';
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_READING_PLAN_VALIDATE_SOURCE
    @RaiseOnMissing BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('izgazMGR.dbo.CS_READING_PLAN', 'U') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('izgazMGR.dbo.CS_READING_PLAN bulunamadi.', 16, 1);
        RETURN 1;
    END

    DECLARE @Missing NVARCHAR(MAX) = N'';

    ;WITH Required (COL_NAME) AS (
        SELECT v.COL_NAME FROM (VALUES
            ('ID'), ('READING_LAYER_ID'), ('BOOK_ID'), ('CODE'),
            ('READING_DAY'), ('TERMINAL_SYNC_CLIENT_ID'), ('LOCATION'),
            ('MAX_SUBSCRIBER_COUNT'),
            ('CREATED_USER_ID'), ('CREATED_TIMESTAMP'),
            ('UPDATED_USER_ID'), ('UPDATED_TIMESTAMP'), ('VERSION'),
            ('FIRST_READING_ORDER_NUMBER'), ('LAST_READING_ORDER_NUMBER'),
            ('TERMINAL_ORDER'), ('IS_ACTIVE'), ('OKUMA_BOLGE_ADI')
        ) v(COL_NAME)
    )
    SELECT @Missing = STRING_AGG(r.COL_NAME, ', ')
    FROM Required r
    WHERE NOT EXISTS (
        SELECT 1
        FROM izgazMGR.sys.columns c
        INNER JOIN izgazMGR.sys.tables t ON t.object_id = c.object_id
        INNER JOIN izgazMGR.sys.schemas sch ON sch.schema_id = t.schema_id
        WHERE sch.name = 'dbo' AND t.name = 'CS_READING_PLAN' AND c.name = r.COL_NAME
    );

    IF @Missing IS NOT NULL AND @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(4000) = N'CS_READING_PLAN eksik kolonlar: ' + @Missing;
        IF @RaiseOnMissing = 1 RAISERROR(@Msg, 16, 1);
        RETURN 1;
    END

    IF COL_LENGTH('izgazMGR.dbo.CS_READING_PLAN', 'LOCATION__wkt') IS NULL
    BEGIN
        IF @RaiseOnMissing = 1
            RAISERROR('CS_READING_PLAN: LOCATION__wkt kolonu yok. Oracle staging yeniden calistirin (KeepSpatialWktStagingColumn).', 16, 1);
        RETURN 1;
    END

    DECLARE @WktNullCount BIGINT;
    SELECT @WktNullCount = COUNT_BIG(*)
    FROM izgazMGR.dbo.CS_READING_PLAN
    WHERE LOCATION__wkt IS NULL OR LTRIM(RTRIM(LOCATION__wkt)) = N'';

    IF @WktNullCount > 0
    BEGIN
        DECLARE @WktMsg NVARCHAR(4000) = N'CS_READING_PLAN: LOCATION__wkt bos satir sayisi = '
            + CONVERT(NVARCHAR(20), @WktNullCount)
            + N'. Oracle CS_READING_PLAN staging yeniden yuklenmeli (WKT kolonu silinmeden).';
        IF @RaiseOnMissing = 1 RAISERROR(@WktMsg, 16, 1);
        RETURN 1;
    END

    IF @RaiseOnMissing = 0
        SELECT N'izgazMGR.dbo.CS_READING_PLAN kaynak dogrulama OK' AS VALIDATION_MESSAGE;

    RETURN 0;
END
GO

