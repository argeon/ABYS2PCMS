/* prodREADY_ENERGY / 99_log_status — operator ozeti */
USE energy;
GO
EXEC dbo.SP_MIG_LOG_STATUS @TOP = 50;
GO
