/* ============================================================
   SCRIPT_ID : INFRA_SCRIPT_CATALOG
   SCRIPT_NO : 102
   FILE      : 102_INFRA_SCRIPT_CATALOG__setup.sql
   VERSION   : 1
   Amac      : Script versiyon katalogu + ASSERT / MARK_DEPLOYED
   ============================================================ */
USE energy;
GO

IF OBJECT_ID('energy.dbo.MIG_SCRIPT_CATALOG', 'U') IS NULL
BEGIN
    CREATE TABLE energy.dbo.MIG_SCRIPT_CATALOG (
        SCRIPT_ID          VARCHAR(80)   NOT NULL,
        SCRIPT_NO          INT           NOT NULL,
        DOMAIN             VARCHAR(30)   NOT NULL,
        ENTITY             VARCHAR(50)   NOT NULL,
        ROLE               VARCHAR(20)   NOT NULL,
        FILE_NAME          NVARCHAR(260) NOT NULL,
        EXPECTED_VERSION   INT           NOT NULL,
        DEPLOYED_VERSION   INT           NULL,
        DEPLOYED_AT        DATETIME2(3)  NULL,
        DEPLOYED_BY        SYSNAME       NULL,
        CHECKSUM_NOTE      NVARCHAR(200) NULL,
        IS_ACTIVE          BIT           NOT NULL CONSTRAINT DF_MIG_SCRIPT_CATALOG_ACTIVE DEFAULT (1),
        CONSTRAINT PK_MIG_SCRIPT_CATALOG PRIMARY KEY (SCRIPT_ID),
        CONSTRAINT UQ_MIG_SCRIPT_NO UNIQUE (SCRIPT_NO)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_SCRIPT_ASSERT
    @ScriptId VARCHAR(80),
    @ScriptNo INT,
    @Version  INT
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('energy.dbo.MIG_SCRIPT_CATALOG', 'U') IS NULL
    BEGIN
        RAISERROR('MIG_SCRIPT_CATALOG yok. Once 102_INFRA_SCRIPT_CATALOG__setup.sql calistirin.', 16, 1);
        RETURN;
    END

    DECLARE
        @Expected INT,
        @Deployed INT,
        @Active   BIT,
        @FileName NVARCHAR(260),
        @Msg      NVARCHAR(400);

    SELECT
        @Expected = c.EXPECTED_VERSION,
        @Deployed = c.DEPLOYED_VERSION,
        @Active   = c.IS_ACTIVE,
        @FileName = c.FILE_NAME
    FROM energy.dbo.MIG_SCRIPT_CATALOG c
    WHERE c.SCRIPT_ID = @ScriptId;

    IF @Expected IS NULL
    BEGIN
        SET @Msg = N'SCRIPT_ID bulunamadi: ' + @ScriptId
            + N'. 103_INFRA_SCRIPT_CATALOG__seed.sql calistirin.';
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    IF ISNULL(@Active, 0) = 0
    BEGIN
        SET @Msg = N'Script pasif: ' + @ScriptId;
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM energy.dbo.MIG_SCRIPT_CATALOG c
        WHERE c.SCRIPT_ID = @ScriptId AND c.SCRIPT_NO = @ScriptNo
    )
    BEGIN
        SET @Msg = N'SCRIPT_NO uyusmuyor: ' + @ScriptId
            + N' dosya=' + CAST(@ScriptNo AS NVARCHAR(10));
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END

    IF @Version <> @Expected
    BEGIN
        SET @Msg = N'Version mismatch [' + @ScriptId + N' / ' + ISNULL(@FileName, N'?') + N']'
            + N' file=' + CAST(@Version AS NVARCHAR(10))
            + N' catalog.EXPECTED=' + CAST(@Expected AS NVARCHAR(10));
        RAISERROR('%s', 16, 1, @Msg);
        RETURN;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_SCRIPT_MARK_DEPLOYED
    @ScriptId VARCHAR(80),
    @Version  INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE energy.dbo.MIG_SCRIPT_CATALOG
    SET DEPLOYED_VERSION = @Version,
        DEPLOYED_AT      = SYSUTCDATETIME(),
        DEPLOYED_BY      = SUSER_SNAME()
    WHERE SCRIPT_ID = @ScriptId
      AND EXPECTED_VERSION = @Version
      AND IS_ACTIVE = 1;

    IF @@ROWCOUNT = 0
        RAISERROR('MARK_DEPLOYED basarisiz (SCRIPT_ID/VERSION katalog ile eslesmedi).', 16, 1);
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_SCRIPT_AUDIT
    @RaiseOnDrift BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.SCRIPT_NO,
        c.SCRIPT_ID,
        c.FILE_NAME,
        c.EXPECTED_VERSION,
        c.DEPLOYED_VERSION,
        c.DEPLOYED_AT,
        c.DEPLOYED_BY,
        CASE
            WHEN c.DEPLOYED_VERSION IS NULL THEN N'NOT_DEPLOYED'
            WHEN c.DEPLOYED_VERSION <> c.EXPECTED_VERSION THEN N'DRIFT'
            ELSE N'OK'
        END AS STATUS
    FROM energy.dbo.MIG_SCRIPT_CATALOG c
    WHERE c.IS_ACTIVE = 1
    ORDER BY c.SCRIPT_NO;

    IF @RaiseOnDrift = 1
       AND EXISTS (
           SELECT 1
           FROM energy.dbo.MIG_SCRIPT_CATALOG c
           WHERE c.IS_ACTIVE = 1
             AND (c.DEPLOYED_VERSION IS NULL OR c.DEPLOYED_VERSION <> c.EXPECTED_VERSION)
             AND c.ROLE IN ('setup', 'migrate', 'wire', 'post')
       )
    BEGIN
        RAISERROR('MIG_SCRIPT_CATALOG drift: EXPECTED <> DEPLOYED (veya hic deploy edilmemis).', 16, 1);
    END
END
GO
