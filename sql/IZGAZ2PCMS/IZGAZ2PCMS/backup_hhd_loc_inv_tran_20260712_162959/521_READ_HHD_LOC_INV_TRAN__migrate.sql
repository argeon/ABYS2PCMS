/* ============================================================
   SCRIPT_ID : READ_HHD_LOC_INV_TRAN_MIGRATE
   SCRIPT_NO : 521
   FILE      : 521_READ_HHD_LOC_INV_TRAN__migrate.sql
   VERSION   : 1
   ============================================================ */
-- ============================================================
-- SP_MIGRATE_LS005_HHD_LOC_INV_TRAN
-- Kaynak  : izgazMGR.dbo.LS_READING_197168
-- Hedef   : energy.dbo.LS_005_01_hhd_loc_inv_tran
-- Kaynak LREF → hedef LREF (IDENTITY_INSERT) + ABYS_ID
-- ============================================================
USE energy;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
    @BatchFrom BIGINT,
    @BatchTo   BIGINT,
    @RowCount  INT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowCount = 0;

    SET IDENTITY_INSERT energy.dbo.LS_005_01_hhd_loc_inv_tran ON;

    INSERT INTO energy.dbo.LS_005_01_hhd_loc_inv_tran (
        LREF, ABYS_ID,
        read_no, loc_region, read_date, loc_id, bina_id, seq_no,
        reader_comp, reader_prsnl, reader_prsnl_id,
        inv_id, inv_date, inv_first_date, inv_last_date, inv_ref,
        cnt_id, cnt_serial, cnt_mbar, cnt_digit, cnt_direction,
        cust_id, cust_suffix, cust_name, cust_address,
        first_read_date, last_read_date, first_read_ind, last_read_ind,
        expend_quantity, corr_coef, corr_volume,
        actual_top_cal_value, avg_top_cal_value, expend_energy,
        retail_price2, retail_price3, price_id, price_desc,
        default_fine, default_fine_tax,
        gas_open_fee, detach_attach_fee, test_fee, spec_serv_fee,
        illegal_use_fee, fixed_fee, fixed_fee_tax,
        expend_fee, expend_fee_tax, discount_addition,
        round_amt, turnover_amt,
        total, total_tax, payable_total,
        KDV, OTV, BHAB, FATSBT,
        discount_rate, interest_rate,
        min_total, min_expend, max_expend,
        rec_status, read_status, cnt_status, read_count,
        cust_type, ADDUSER, ADDDATE,
        gas_open_fee_ref, detach_attach_fee_ref, test_fee_ref,
        spec_serv_fee_ref, discount_addition_ref, illegal_use_fee_ref,
        AGRID, INV_INSTALLMENT_TOTAL, INV_INSTALLMENT_REF,
        real_date, CS_APPREF, UNDERLIMIT, UNDERLIMITSTAT, CANCELLED,
        longitude, latitude,
        SKB_TOTAL_AMOUNT, GAS_TOTAL_AMOUNT,
        SKB_UNITPRICE_KWH, GAS_UNITPRICE_KWH,
        CalculatedRealCost, RealCost, BILLDESCRIPTION, PERIOD
    )
    SELECT
        s.LREF, s.ABYS_ID,
        s.read_no, s.loc_region, s.read_date, s.loc_id, s.bina_id, s.seq_no,
        s.reader_comp, s.reader_prsnl, s.reader_prsnl_id,
        s.inv_id, s.inv_date, s.inv_first_date, s.inv_last_date, s.inv_ref,
        s.cnt_id, s.cnt_serial, s.cnt_mbar, s.cnt_digit, s.cnt_direction,
        s.cust_id, s.cust_suffix, s.cust_name, s.cust_address,
        s.first_read_date, s.last_read_date, s.first_read_ind, s.last_read_ind,
        s.expend_quantity, s.corr_coef, s.corr_volume,
        s.actual_top_cal_value, s.avg_top_cal_value, s.expend_energy,
        s.retail_price2, s.retail_price3, s.price_id, s.price_desc,
        s.default_fine, s.default_fine_tax,
        s.gas_open_fee, s.detach_attach_fee, s.test_fee, s.spec_serv_fee,
        s.illegal_use_fee, s.fixed_fee, s.fixed_fee_tax,
        s.expend_fee, s.expend_fee_tax, s.discount_addition,
        s.round_amt, s.turnover_amt,
        s.total, s.total_tax, s.payable_total,
        s.KDV, s.OTV, s.BHAB, s.FATSBT,
        s.discount_rate, s.interest_rate,
        s.min_total, s.min_expend, s.max_expend,
        s.rec_status, s.read_status, s.cnt_status, s.read_count,
        s.cust_type, s.ADDUSER, s.ADDDATE,
        s.gas_open_fee_ref, s.detach_attach_fee_ref, s.test_fee_ref,
        s.spec_serv_fee_ref, s.discount_addition_ref, s.illegal_use_fee_ref,
        s.AGRID, s.INV_INSTALLMENT_TOTAL, s.INV_INSTALLMENT_REF,
        s.real_date, s.CS_APPREF, s.UNDERLIMIT, s.UNDERLIMITSTAT, s.CANCELLED,
        s.longitude, s.latitude,
        s.SKB_TOTAL_AMOUNT, s.GAS_TOTAL_AMOUNT,
        s.SKB_UNITPRICE_KWH, s.GAS_UNITPRICE_KWH,
        s.CalculatedRealCost, s.RealCost, s.BILLDESCRIPTION, s.PERIOD
    FROM energy.dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE s
    WHERE s.ABYS_ID BETWEEN @BatchFrom AND @BatchTo
      AND NOT EXISTS (
          SELECT 1
          FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t
          WHERE t.LREF = s.LREF
             OR t.ABYS_ID = s.ABYS_ID
      );

    SET @RowCount = @@ROWCOUNT;
    SET IDENTITY_INSERT energy.dbo.LS_005_01_hhd_loc_inv_tran OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_ONE
    @CurID       BIGINT,
    @RowInserted BIT = 0 OUTPUT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET @RowInserted = 0;

    IF EXISTS (
        SELECT 1 FROM energy.dbo.LS_005_01_hhd_loc_inv_tran t
        WHERE t.LREF = @CurID OR t.ABYS_ID = @CurID
    )
        RETURN;

    DECLARE @Rc INT;
    EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
        @BatchFrom = @CurID,
        @BatchTo   = @CurID,
        @RowCount  = @Rc OUTPUT;

    SET @RowInserted = CASE WHEN @Rc > 0 THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIG_HHD_LOC_INV_TRAN_HARD_RESET
    @DELETE_BATCH INT = 10000,
    @DEBUG        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Deleted INT, @TotalDeleted BIGINT = 0, @MaxLref INT, @TotalStr VARCHAR(20);

    IF @DEBUG = 1
        RAISERROR('*** HARD RESET: LS_005_01_hhd_loc_inv_tran ABYS kayitlari (batch=%d) ***', 0, 1, @DELETE_BATCH) WITH NOWAIT;

    SET IDENTITY_INSERT energy.dbo.LS_005_01_hhd_loc_inv_tran OFF;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@DELETE_BATCH)
        FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
        WHERE ABYS_ID IS NOT NULL;

        SET @Deleted = @@ROWCOUNT;
        IF @Deleted = 0 BREAK;

        SET @TotalDeleted += @Deleted;

        IF @DEBUG = 1
        BEGIN
            SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
            RAISERROR('HARD RESET silindi: +%d (toplam %s)', 0, 1, @Deleted, @TotalStr) WITH NOWAIT;
        END
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran;

    DBCC CHECKIDENT('energy.dbo.LS_005_01_hhd_loc_inv_tran', RESEED, @MaxLref) WITH NO_INFOMSGS;

    IF @DEBUG = 1
    BEGIN
        SET @TotalStr = CAST(@TotalDeleted AS VARCHAR(20));
        RAISERROR('HARD RESET tamamlandi. Toplam silinen: %s, CHECKIDENT=%d', 0, 1, @TotalStr, @MaxLref) WITH NOWAIT;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.SP_MIGRATE_LS005_HHD_LOC_INV_TRAN
    @BATCH_SIZE  INT = 10000,
    @RESUME      BIT = 1,
    @HARD_RESET  BIT = 0,
    @MAX_ERROR   INT = 500,
    @BISECT_MIN  INT = 1,
    @DEBUG       BIT = 0
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @MigrationCode  VARCHAR(50)      = 'LS_005_01_HHD_LOC_INV_TRAN',
        @RunID          UNIQUEIDENTIFIER,
        @TableRunID     BIGINT,
        @LastBridgeKey  BIGINT           = 0,
        @MaxBridgeKey   BIGINT,
        @SourceCount    BIGINT,
        @TargetCount    BIGINT,
        @BatchNo        INT              = 0,
        @InsertedCount  BIGINT           = 0,
        @SkippedCount   BIGINT           = 0,
        @ErrorCount     BIGINT           = 0,
        @BatchFrom      BIGINT,
        @BatchTo        BIGINT,
        @RowCount       INT,
        @ErrMsg         NVARCHAR(4000),
        @SingleErrMsg   NVARCHAR(4000),
        @Msg            NVARCHAR(500),
        @BatchStart     DATETIME2(3),
        @ElapsedMs      INT,
        @ExecMode       VARCHAR(20),
        @RunStatus      VARCHAR(25),
        @PhaseStatus    VARCHAR(20),
        @Stopped        BIT              = 0,
        @FinishErrorMsg NVARCHAR(4000),
        @BisectFrom     BIGINT,
        @BisectTo       BIGINT,
        @BisectMid      BIGINT,
        @BisectSize     INT,
        @BisectRows     INT,
        @BisectLogFrom  BIGINT,
        @RowInserted    BIT,
        @MaxLref        INT;

    EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_VALIDATE_ALL @RaiseOnMissing = 1;

    IF @HARD_RESET = 1
    BEGIN
        EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_HARD_RESET @DELETE_BATCH = @BATCH_SIZE, @DEBUG = @DEBUG;
        SET @RESUME = 0;
        SET @ExecMode = 'HARD_RESET';
    END
    ELSE IF @RESUME = 1
        SET @ExecMode = 'RESUME';
    ELSE
        SET @ExecMode = 'FULL';

    SELECT @SourceCount  = COUNT_BIG(*) FROM energy.dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE;
    SELECT @MaxBridgeKey = MAX(ABYS_ID) FROM energy.dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE;

    EXEC energy.dbo.SP_MIG_LOG_START_RUN
        @MigrationCode  = @MigrationCode,
        @SourceDb       = 'izgazMGR',
        @SourceTable    = 'LS_READING_197168',
        @TargetTable    = 'LS_005_01_hhd_loc_inv_tran',
        @RunPhase       = 'INSERT',
        @ExecMode       = @ExecMode,
        @BatchSize      = @BATCH_SIZE,
        @Phase          = 'INSERT',
        @SourceRowCount = @SourceCount,
        @MaxBridgeKey   = @MaxBridgeKey,
        @Resume         = @RESUME,
        @RunID          = @RunID          OUTPUT,
        @TableRunID     = @TableRunID     OUTPUT,
        @LastBridgeKey  = @LastBridgeKey  OUTPUT,
        @BatchNo        = @BatchNo        OUTPUT,
        @InsertedCount  = @InsertedCount  OUTPUT,
        @SkippedCount   = @SkippedCount   OUTPUT,
        @ErrorCount     = @ErrorCount     OUTPUT;

    IF @DEBUG = 1
    BEGIN
        SET @Msg = 'RUN ' + CAST(@RunID AS VARCHAR(36))
            + ' | Kaynak=' + CAST(@SourceCount AS VARCHAR(20))
            + ' | ABYS_ID=' + CAST(@LastBridgeKey AS VARCHAR(20))
            + '-' + CAST(@MaxBridgeKey AS VARCHAR(20));
        RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
    END

    WHILE @LastBridgeKey < ISNULL(@MaxBridgeKey, 0) AND @Stopped = 0
    BEGIN
        SET @BatchNo   += 1;
        SET @BatchStart = SYSDATETIME();
        SET @BatchFrom  = @LastBridgeKey + 1;
        SET @RowCount   = 0;

        SELECT @BatchTo = MAX(ABYS_ID)
        FROM (
            SELECT TOP (@BATCH_SIZE) s.ABYS_ID
            FROM energy.dbo.VW_MIG_LS005_HHD_LOC_INV_TRAN_SOURCE s
            WHERE s.ABYS_ID > @LastBridgeKey
            ORDER BY s.ABYS_ID ASC
        ) t;

        IF @BatchTo IS NULL BREAK;

        IF @DEBUG = 1
        BEGIN
            SET @Msg = 'Batch ' + CAST(@BatchNo AS VARCHAR(10))
                + ' | ' + CAST(@BatchFrom AS VARCHAR(20))
                + '-' + CAST(@BatchTo AS VARCHAR(20));
            RAISERROR('%s', 0, 1, @Msg) WITH NOWAIT;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
                @BatchFrom = @BatchFrom,
                @BatchTo   = @BatchTo,
                @RowCount  = @RowCount OUTPUT;

            COMMIT TRANSACTION;

            SET @LastBridgeKey = @BatchTo;
            SET @ElapsedMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());

            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @RowCount = @RowCount, @ElapsedMs = @ElapsedMs;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            SET IDENTITY_INSERT energy.dbo.LS_005_01_hhd_loc_inv_tran OFF;
            SET @ErrMsg = ERROR_MESSAGE();

            EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                @RunID = @RunID, @TableRunID = @TableRunID,
                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                @BatchNo = @BatchNo, @BridgeFrom = @BatchFrom, @BridgeTo = @BatchTo,
                @ErrorMsg = @ErrMsg;

            IF @DEBUG = 1
                RAISERROR('Batch %d HATA → bisect: %s', 0, 1, @BatchNo, @ErrMsg) WITH NOWAIT;

            SET @BisectFrom = @BatchFrom;
            SET @BisectTo   = @BatchTo;

            WHILE @BisectFrom <= @BisectTo AND @Stopped = 0
            BEGIN
                SET @BisectSize = @BisectTo - @BisectFrom + 1;

                IF @BisectSize <= @BISECT_MIN
                BEGIN
                    BEGIN TRY
                        SET @RowInserted = 0;
                        EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_ONE
                            @CurID = @BisectFrom, @RowInserted = @RowInserted OUTPUT;

                        IF @RowInserted = 1
                        BEGIN
                            EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                                @RunID = @RunID, @TableRunID = @TableRunID,
                                @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                                @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                                @BridgeTo = @BisectFrom, @RowCount = 1;
                        END
                    END TRY
                    BEGIN CATCH
                        SET @ErrMsg = ERROR_MESSAGE();
                        SET @SingleErrMsg = LEFT(
                            N'ABYS_ID=' + CAST(@BisectFrom AS NVARCHAR(20)) + N': ' + @ErrMsg, 4000);

                        EXEC energy.dbo.SP_MIG_LOG_BATCH_ERROR
                            @RunID = @RunID, @TableRunID = @TableRunID,
                            @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                            @BatchNo = @BatchNo, @BridgeFrom = @BisectFrom,
                            @BridgeTo = @BisectFrom, @SourceID = @BisectFrom,
                            @IsSingleRow = 1, @ErrorMsg = @SingleErrMsg;

                        SELECT @ErrorCount = tr.ERROR_COUNT
                        FROM energy.dbo.MIG_TABLE_RUN tr
                        WHERE tr.TABLE_RUN_ID = @TableRunID;

                        IF @ErrorCount >= @MAX_ERROR
                        BEGIN
                            SET @Stopped = 1;
                            RAISERROR('Max hata limiti (%d) asildi. Durduruldu.', 16, 1, @MAX_ERROR);
                        END
                    END CATCH

                    SET @BisectFrom += 1;
                    CONTINUE;
                END

                SET @BisectMid = @BisectFrom + (@BisectSize / 2) - 1;

                BEGIN TRY
                    BEGIN TRANSACTION;

                    EXEC dbo.SP_MIG_HHD_LOC_INV_TRAN_INSERT_RANGE
                        @BatchFrom = @BisectFrom,
                        @BatchTo   = @BisectMid,
                        @RowCount  = @BisectRows OUTPUT;

                    SET @BisectLogFrom = @BisectFrom;
                    COMMIT TRANSACTION;

                    EXEC energy.dbo.SP_MIG_LOG_BATCH_OK
                        @RunID = @RunID, @TableRunID = @TableRunID,
                        @MigrationCode = @MigrationCode, @Phase = 'INSERT',
                        @BatchNo = @BatchNo, @BridgeFrom = @BisectLogFrom,
                        @BridgeTo = @BisectMid, @RowCount = @BisectRows;

                    SET @BisectFrom = @BisectMid + 1;
                END TRY
                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                    SET IDENTITY_INSERT energy.dbo.LS_005_01_hhd_loc_inv_tran OFF;
                    SET @ErrMsg = ERROR_MESSAGE();
                    SET @BisectTo = @BisectMid;
                END CATCH
            END

            IF @Stopped = 0
                SET @LastBridgeKey = @BatchTo;
        END CATCH

        SELECT
            @InsertedCount = tr.INSERTED_COUNT,
            @SkippedCount  = tr.SKIPPED_COUNT,
            @ErrorCount    = tr.ERROR_COUNT
        FROM energy.dbo.MIG_TABLE_RUN tr
        WHERE tr.TABLE_RUN_ID = @TableRunID;
    END

    SELECT @MaxLref = ISNULL(MAX(LREF), 0)
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran;

    IF @MaxLref > 0
        DBCC CHECKIDENT('energy.dbo.LS_005_01_hhd_loc_inv_tran', RESEED, @MaxLref) WITH NO_INFOMSGS;

    SELECT @TargetCount = COUNT_BIG(*)
    FROM energy.dbo.LS_005_01_hhd_loc_inv_tran
    WHERE ABYS_ID IS NOT NULL;

    IF @Stopped = 1
    BEGIN
        SET @RunStatus   = 'STOPPED';
        SET @PhaseStatus = 'PAUSED';
    END
    ELSE IF @ErrorCount > 0
    BEGIN
        SET @RunStatus   = 'COMPLETED_WITH_ERRORS';
        SET @PhaseStatus = 'COMPLETED';
    END
    ELSE
    BEGIN
        SET @RunStatus   = 'COMPLETED';
        SET @PhaseStatus = 'COMPLETED';
    END

    EXEC energy.dbo.SP_MIG_LOG_FINISH_PHASE
        @TableRunID = @TableRunID, @Status = @PhaseStatus;

    SET @FinishErrorMsg = CASE
        WHEN @Stopped = 1 THEN N'Max hata limitine ulasildi. RESUME ile devam edin.'
        ELSE NULL
    END;

    EXEC energy.dbo.SP_MIG_LOG_FINISH_RUN
        @RunID = @RunID, @Status = @RunStatus,
        @TargetRowCount = @TargetCount,
        @ErrorMsg = @FinishErrorMsg;

    EXEC energy.dbo.SP_MIG_LOG_GET_SUMMARY
        @MigrationCode = @MigrationCode, @RunID = @RunID;

    IF @ErrorCount > 0
    BEGIN
        SELECT TOP 10
            l.MIGRATION_CODE,
            l.BATCH_NO,
            l.BRIDGE_FROM,
            l.BRIDGE_TO,
            l.SOURCE_ID,
            l.ERROR_MSG,
            l.LOGGED_AT
        FROM energy.dbo.MIG_BATCH_LOG l
        WHERE l.MIGRATION_CODE = 'LS_005_01_HHD_LOC_INV_TRAN'
          AND l.STATUS = 'ERROR'
        ORDER BY l.LOGGED_AT DESC;
    END
END
GO

 --EXEC energy.dbo.SP_MIGRATE_LS005_HHD_LOC_INV_TRAN
 --     @HARD_RESET = 1, @BATCH_SIZE = 10000, @DEBUG = 1;
