import java.nio.file.*;
import java.sql.*;
public class RebuildMah {
  static void run(Connection c, String sql) throws Exception {
    String head = sql.substring(0, Math.min(80, sql.length())).replace('\n',' ');
    System.out.println("--- " + head);
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
      } else System.out.println("ok uc=" + s.getUpdateCount());
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      c.setAutoCommit(true);
      String raw = Files.readString(Path.of(a[0]));
      if (raw.startsWith("\uFEFF")) raw = raw.substring(1);

      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_PAY_PT PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String pay = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_PAY_PT NOLOGGING AS)", "$1");
      pay = pay.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_PAY_PT NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_PAY_PT.*", "$1").trim();
      if (pay.endsWith(";")) pay = pay.substring(0, pay.length()-1);
      run(c, pay);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_PAY_PT ON MIGRATION.LS_OV_PAY_PT (LREF)");
      run(c, "CREATE INDEX MIGRATION.IX_OV_PAY_PT_MAIN ON MIGRATION.LS_OV_PAY_PT (CROSSREF_MAIN_LREF)");
      run(c, "CREATE INDEX MIGRATION.IX_OV_PAY_PT_AGR ON MIGRATION.LS_OV_PAY_PT (ABYS_AGREEMENT_ID)");

      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_DEBT_PAID_UPD PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String debt = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_DEBT_PAID_UPD NOLOGGING AS)", "$1");
      debt = debt.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_DEBT_PAID_UPD NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_DEBT_PAID.*", "$1").trim();
      if (debt.endsWith(";")) debt = debt.substring(0, debt.length()-1);
      run(c, debt);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_DEBT_PAID ON MIGRATION.LS_OV_DEBT_PAID_UPD (MAIN_LREF)");

      // refresh TAM_HAS_PAY VALID_PAY (includes mahsup now)
      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAM_HAS_PAY PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String tam = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_TAM_HAS_PAY NOLOGGING AS)", "$1");
      tam = tam.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_TAM_HAS_PAY NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_TAM_HAS_PAY.*", "$1").trim();
      if (tam.endsWith(";")) tam = tam.substring(0, tam.length()-1);
      run(c, tam);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_TAM_HAS_PAY ON MIGRATION.LS_OV_TAM_HAS_PAY (EKS_ACTION_ID)");

      // cancel pay/rev depend on TAM_HAS_PAY - rebuild
      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_PAY PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String cp = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_CANCEL_PAY NOLOGGING AS)", "$1");
      cp = cp.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_CANCEL_PAY NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_CANCEL_PAY.*", "$1").trim();
      if (cp.endsWith(";")) cp = cp.substring(0, cp.length()-1);
      run(c, cp);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_PAY ON MIGRATION.LS_OV_CANCEL_PAY (LREF)");

      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_REV PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String cr = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_CANCEL_REV NOLOGGING AS)", "$1");
      cr = cr.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_CANCEL_REV NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_CANCEL_REV.*", "$1").trim();
      if (cr.endsWith(";")) cr = cr.substring(0, cr.length()-1);
      run(c, cr);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_REV ON MIGRATION.LS_OV_CANCEL_REV (LREF)");

      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAH_LOG PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String log = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_TAH_LOG NOLOGGING AS)", "$1");
      log = log.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_TAH_LOG NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_TAH_LOG[^_].*", "$1").trim();
      if (log.endsWith(";")) log = log.substring(0, log.length()-1);
      run(c, log);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_LOG ON MIGRATION.LS_OV_TAH_LOG (LOG_ID)");

      run(c, """
SELECT 'PAY_PT' K, COUNT(*) N FROM MIGRATION.LS_OV_PAY_PT
UNION ALL SELECT 'PAY_BANK', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE OV_KIND='PAY' AND NVL(CANCELED,0)=0
UNION ALL SELECT 'PAY_MAHSUP', COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE OV_KIND='MAHSUP'
UNION ALL SELECT 'DEBT_CLOSED', COUNT(*) FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE CLOSED=1
UNION ALL SELECT 'DEBT_OPEN', COUNT(*) FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE CLOSED=0
UNION ALL SELECT 'LOG', COUNT(*) FROM MIGRATION.LS_OV_TAH_LOG
""");
      run(c, "SELECT MAIN_LREF, PAID_AMT, CLOSED FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE MAIN_LREF IN (19115898,19444984)");
      run(c, "SELECT LREF, OV_KIND, PAYTYPE, PAYABLETOTAL, CROSSREF_MAIN_LREF FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IN (19115898,19444984) ORDER BY LREF");
    }
  }
}