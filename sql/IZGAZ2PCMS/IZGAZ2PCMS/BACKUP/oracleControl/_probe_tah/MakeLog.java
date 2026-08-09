import java.sql.*;
public class MakeLog {
  static void run(Connection c, String sql) throws Exception {
    System.out.println("--- " + sql.substring(0, Math.min(70, sql.length())).replace('\n',' '));
    try (Statement s = c.createStatement()) {
      boolean has = s.execute(sql);
      if (has) {
        try (ResultSet rs = s.getResultSet()) {
          ResultSetMetaData md = rs.getMetaData();
          int cols = md.getColumnCount();
          while (rs.next()) {
            StringBuilder row = new StringBuilder();
            for (int i=1;i<=cols;i++) {
              if (i>1) row.append(" | ");
              row.append(md.getColumnLabel(i)).append("=").append(rs.getString(i));
            }
            System.out.println(row);
          }
        }
      } else System.out.println("ok");
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      c.setAutoCommit(true);
      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAH_LOG PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      run(c, """
CREATE TABLE MIGRATION.LS_OV_TAH_LOG NOLOGGING AS
SELECT
    ROW_NUMBER() OVER (ORDER BY x.REASON, x.PAY_LREF, x.MAIN_LREF) AS LOG_ID,
    x.REASON, x.SEVERITY, x.PAY_LREF, x.MAIN_LREF, x.ACCOUNT_ID, x.AGREEMENT_ID,
    x.ACTION_TYPE_ID, x.PAYABLETOTAL, x.PAID_AMT, x.DETAIL,
    CAST('TAH_LOG' AS VARCHAR2(10)) AS OV_KIND
FROM (
    SELECT CAST('NO_XREF' AS VARCHAR2(20)) REASON, CAST('WARN' AS VARCHAR2(10)) SEVERITY,
           p.LREF PAY_LREF, CAST(NULL AS NUMBER) MAIN_LREF, p.ABYS_ACCOUNT_ID ACCOUNT_ID,
           p.ABYS_AGREEMENT_ID AGREEMENT_ID, p.ABYS_ACTION_TYPE_ID ACTION_TYPE_ID,
           p.PAYABLETOTAL, CAST(NULL AS NUMBER) PAID_AMT,
           CAST('Ortak INCOME_ID yok; CROSSREF/PAID uygulanmadi' AS VARCHAR2(200)) DETAIL
    FROM MIGRATION.LS_OV_PAY_PT p WHERE p.CROSSREF_MAIN_LREF IS NULL
    UNION ALL
    SELECT CAST('PAY_CANCELED' AS VARCHAR2(20)), CAST('INFO' AS VARCHAR2(10)),
           p.LREF, p.CROSSREF_MAIN_LREF, p.ABYS_ACCOUNT_ID, p.ABYS_AGREEMENT_ID,
           p.ABYS_ACTION_TYPE_ID, p.PAYABLETOTAL, CAST(NULL AS NUMBER),
           CAST('ACTION_TYPE=9 makbuz eslesmesi; CANCELED=1' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_PAY_PT p WHERE NVL(p.CANCELED,0)=1
    UNION ALL
    SELECT CAST('MAIN_MISSING' AS VARCHAR2(20)), CAST('WARN' AS VARCHAR2(10)),
           p.LREF, p.CROSSREF_MAIN_LREF, p.ABYS_ACCOUNT_ID, p.ABYS_AGREEMENT_ID,
           p.ABYS_ACTION_TYPE_ID, p.PAYABLETOTAL, CAST(NULL AS NUMBER),
           CAST('CROSSREF_MAIN_LREF LS_INVOICE da yok' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_PAY_PT p
    WHERE p.CROSSREF_MAIN_LREF IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MIGRATION.LS_INVOICE inv WHERE inv.LREF=p.CROSSREF_MAIN_LREF)
    UNION ALL
    SELECT CAST('DEBT_PARTIAL' AS VARCHAR2(20)), CAST('INFO' AS VARCHAR2(10)),
           CAST(NULL AS NUMBER), d.MAIN_LREF, CAST(NULL AS NUMBER), d.ABYS_AGREEMENT_ID,
           CAST(NULL AS NUMBER), NVL(inv.PAYABLETOTAL,0), d.PAID_AMT,
           CAST('PAID < PAYABLE; CLOSED=0' AS VARCHAR2(200))
    FROM MIGRATION.LS_OV_DEBT_PAID_UPD d
    LEFT JOIN MIGRATION.LS_INVOICE inv ON inv.LREF=d.MAIN_LREF
    WHERE NVL(d.CLOSED,0)=0
) x
""");
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_LOG ON MIGRATION.LS_OV_TAH_LOG (LOG_ID)");
      run(c, "CREATE INDEX MIGRATION.IX_OV_TAH_LOG_RSN ON MIGRATION.LS_OV_TAH_LOG (REASON)");
      run(c, "SELECT REASON, COUNT(*) N FROM MIGRATION.LS_OV_TAH_LOG GROUP BY REASON ORDER BY 1");
      run(c, "SELECT LOG_ID, REASON, SEVERITY, PAY_LREF, MAIN_LREF, ACTION_TYPE_ID, PAYABLETOTAL, PAID_AMT, DETAIL FROM MIGRATION.LS_OV_TAH_LOG ORDER BY LOG_ID");
    }
  }
}