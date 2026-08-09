import java.nio.file.*;
import java.sql.*;
public class RebuildDebt {
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
    String raw = Files.readString(Path.of(a[0]));
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      c.setAutoCommit(true);
      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_DEBT_PAID_UPD PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String debt = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_DEBT_PAID_UPD NOLOGGING AS)", "$1");
      debt = debt.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_DEBT_PAID_UPD NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_DEBT_PAID.*", "$1").trim();
      if (debt.endsWith(";")) debt = debt.substring(0, debt.length()-1);
      run(c, debt);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_DEBT_PAID ON MIGRATION.LS_OV_DEBT_PAID_UPD (MAIN_LREF)");
      run(c, "SELECT COUNT(*) ZERO_CLOSED FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE ABS(PAID_AMT)<0.01 AND CLOSED=1");
      run(c, "SELECT COUNT(*) OPEN_CNT FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE CLOSED=0");
    }
  }
}