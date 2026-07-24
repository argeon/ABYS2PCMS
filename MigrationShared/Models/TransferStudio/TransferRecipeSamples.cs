namespace MigrationShared.Models.TransferStudio;

/// <summary>
/// Örnek recipe — IT_USER → LS_USER (Oracle ile ilgisi yok; yalnızca MSSQL).
/// </summary>
public static class TransferRecipeSamples
{
    public static TransferRecipeDocument CreateItUserSample() => new()
    {
        MigrationId = "IT_USER",
        Name = "IT_USER → LS_USER",
        SortOrder = 10,
        Endpoints = new TransferEndpoints
        {
            SourceDatabase = "izgazMGR",
            SourceSchema = "dbo",
            SourceTable = "IT_USER",
            TargetDatabase = "energy",
            TargetSchema = "dbo",
            TargetTable = "LS_USER"
        },
        Bridge = new BridgeKeyConfig
        {
            SourceKeyColumn = "ID",
            TargetBridgeColumn = "ABYS_ID",
            TargetIdentityColumn = "USERID"
        },
        PreDeploySteps =
        [
            new TargetDdlStep { Action = "DropIndex", ObjectName = "IX_LS_USER_ABYS_USER_ID" },
            new TargetDdlStep { Action = "DropColumn", ColumnName = "ABYS_USER_ID" },
            new TargetDdlStep { Action = "AddColumn", ColumnName = "ABYS_ID", DataType = "int NULL" },
            new TargetDdlStep { Action = "AddColumn", ColumnName = "REGISTER_ID", DataType = "int NULL" },
            new TargetDdlStep { Action = "AddColumn", ColumnName = "REGISTER_TABLE", DataType = "varchar(10) NULL" },
            new TargetDdlStep { Action = "AddColumn", ColumnName = "USER_TYPE", DataType = "tinyint NULL" },
            new TargetDdlStep { Action = "AddColumn", ColumnName = "WORK_PLACE_ID", DataType = "int NULL" },
            new TargetDdlStep
            {
                Action = "CreateIndex",
                ObjectName = "IX_LS_USER_ABYS_ID",
                Details = "(ABYS_ID) INCLUDE (USERID)"
            }
        ],
        Batch = new TransferBatchConfig
        {
            BatchKeyColumn = "ID",
            BatchSize = 2000,
            Resume = true,
            MaxErrors = 200,
            OnBatchError = "SingleRowRetry"
        },
        Phases =
        [
            new TransferPhaseDefinition
            {
                Name = "INSERT",
                PhaseType = TransferPhaseType.InsertSelect,
                SourceJoins =
                [
                    new SourceJoinDefinition
                    {
                        Alias = "r",
                        TableOrSubquery = "CS_REGISTER",
                        JoinCondition = "r.ID = u.REGISTER_ID"
                    },
                    new SourceJoinDefinition
                    {
                        Alias = "pt",
                        TableOrSubquery =
                            "(SELECT REGISTER_ID, MIN(REGISTER_TYPE_ID) AS PRIMARY_TYPE_ID FROM CS_REGISTER_REGISTER_TYPE GROUP BY REGISTER_ID)",
                        JoinCondition = "pt.REGISTER_ID = u.REGISTER_ID",
                        IsSubquery = true
                    }
                ],
                Lookups =
                [
                    new LookupMapDefinition
                    {
                        Name = "RTypeMap",
                        JoinOn = "tm.REGISTER_TYPE_ID = pt.PRIMARY_TYPE_ID",
                        Rows =
                        [
                            new LookupMapRow { Key = 1, Value = "Kisi" },
                            new LookupMapRow { Key = 2, Value = "Firma" },
                            new LookupMapRow { Key = 13, Value = "Kisi" },
                            new LookupMapRow { Key = 14, Value = "Kisi" }
                        ]
                    }
                ],
                ColumnMappings =
                [
                    new() { TargetColumn = "ABYS_ID", SourceExpression = "u.ID" },
                    new() { TargetColumn = "USERCODE", SourceExpression = "LEFT(u.USER_NAME,20)" },
                    new() { TargetColumn = "USERPASS", SourceExpression = "LEFT(u.PASSWORD,100)" },
                    new() { TargetColumn = "USERNAME", SourceExpression = "LEFT(ISNULL(r.FIRST_NAME,''),20)" },
                    new() { TargetColumn = "USERSNAME", SourceExpression = "LEFT(ISNULL(r.LAST_NAME,''),20)" },
                    new() { TargetColumn = "USEREMAIL", SourceExpression = "LEFT(u.EMAIL,100)" },
                    new() { TargetColumn = "ISACTIVE", SourceExpression = "u.IS_ACTIVE" },
                    new() { TargetColumn = "ACCOUNT_LOCKED", SourceExpression = "u.IS_LOCK" },
                    new() { TargetColumn = "FAILED_LOGIN_ATTEMPTS", SourceExpression = "ISNULL(u.PASSWORD_TRY_NUMBER,0)" },
                    new() { TargetColumn = "R_CREATOR", SourceExpression = "u.CREATED_USER_ID", ResolveInLaterPhase = true, IncludeInContentValidation = false, ValidateAfterPhase = "UPDATE" },
                    new() { TargetColumn = "R_MODIFIER", SourceExpression = "u.UPDATED_USER_ID", ResolveInLaterPhase = true, IncludeInContentValidation = false, ValidateAfterPhase = "UPDATE" },
                    new() { TargetColumn = "REGISTER_TABLE", SourceExpression = "CASE WHEN tm.REG_TYPE='Kisi' THEN 'SUBSCR' WHEN tm.REG_TYPE='Firma' THEN 'FIRM' ELSE NULL END" },
                    new() { TargetColumn = "USER_TYPE", SourceExpression = "CASE WHEN tm.REG_TYPE='Kisi' THEN 1 WHEN tm.REG_TYPE='Firma' THEN 2 ELSE NULL END" }
                ]
            },
            new TransferPhaseDefinition
            {
                Name = "UPDATE",
                PhaseType = TransferPhaseType.FkResolve,
                FkResolves =
                [
                    new FkResolveStep { TargetTable = "LS_USER", Column = "R_CREATOR", LookupTable = "LS_USER", LookupBridgeColumn = "ABYS_ID", LookupTargetColumn = "USERID" },
                    new FkResolveStep { TargetTable = "LS_USER", Column = "R_MODIFIER", LookupTable = "LS_USER", LookupBridgeColumn = "ABYS_ID", LookupTargetColumn = "USERID" },
                    new FkResolveStep { TargetTable = "LS_004_SUBSCR", Column = "ADDUSER", LookupTable = "LS_USER", LookupBridgeColumn = "ABYS_ID", LookupTargetColumn = "USERID" },
                    new FkResolveStep { TargetTable = "LS_004_SUBSCR", Column = "UPDUSER", LookupTable = "LS_USER", LookupBridgeColumn = "ABYS_ID", LookupTargetColumn = "USERID" },
                    new FkResolveStep { TargetTable = "LS_004_FIRM", Column = "ADDUSER", LookupTable = "LS_USER", LookupBridgeColumn = "ABYS_ID", LookupTargetColumn = "USERID" },
                    new FkResolveStep { TargetTable = "LS_004_FIRM", Column = "UPDUSER", LookupTable = "LS_USER", LookupBridgeColumn = "ABYS_ID", LookupTargetColumn = "USERID" }
                ]
            }
        ],
        Validation = new TransferValidationProfile
        {
            Metrics =
            [
                new MetricValidationRule { GateType = MetricGateType.RowCount, Enabled = true },
                new MetricValidationRule { GateType = MetricGateType.MissingByBridge, Enabled = true },
                new MetricValidationRule { GateType = MetricGateType.BridgeNotNull, Enabled = true }
            ],
            Content = new ContentValidationProfile
            {
                Enabled = true,
                Strategy = ContentCompareStrategy.SampleByKey,
                SampleSize = 100,
                Rules =
                [
                    new ContentCompareRule
                    {
                        Label = "USERCODE",
                        SourceExpression = "LEFT(u.USER_NAME,20)",
                        TargetExpression = "t.USERCODE",
                        CompareAs = ContentCompareKind.Exact
                    },
                    new ContentCompareRule
                    {
                        Label = "USERNAME",
                        SourceExpression = "LEFT(ISNULL(r.FIRST_NAME,''),20)",
                        TargetExpression = "t.USERNAME",
                        CompareAs = ContentCompareKind.Exact
                    },
                    new ContentCompareRule
                    {
                        Label = "REGISTER_TABLE",
                        SourceExpression = "CASE WHEN tm.REG_TYPE='Kisi' THEN 'SUBSCR' WHEN tm.REG_TYPE='Firma' THEN 'FIRM' ELSE NULL END",
                        TargetExpression = "t.REGISTER_TABLE",
                        CompareAs = ContentCompareKind.Exact
                    }
                ]
            }
        },
        Execution = new TransferExecutionSettings
        {
            Mode = TransferExecutionMode.Engine,
            DefaultRunPhase = "ALL"
        }
    };
}
