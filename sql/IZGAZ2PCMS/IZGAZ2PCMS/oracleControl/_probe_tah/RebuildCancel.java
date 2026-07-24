import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.regex.*;
public class RebuildCancel {
  static void run(Connection c, String sql) throws Exception {
    System.out.println("--- " + sql.substring(0, Math.min(90, sql.length())).replace('\n',' '));
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
    String raw = Files.readString(Path.of(a[0]));
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      c.setAutoCommit(true);
      run(c, "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_CANCEL_PAY PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;");
      String pay = raw.replaceAll("(?s).*?(CREATE TABLE MIGRATION\\.LS_OV_CANCEL_PAY NOLOGGING AS)", "$1");
      pay = pay.replaceAll("(?s)(CREATE TABLE MIGRATION\\.LS_OV_CANCEL_PAY NOLOGGING AS.*?)\\s*CREATE UNIQUE INDEX MIGRATION\\.IX_OV_CANCEL_PAY.*", "$1").trim();
      if (pay.endsWith(";")) pay = pay.substring(0, pay.length()-1);
      run(c, pay);
      run(c, "CREATE UNIQUE INDEX MIGRATION.IX_OV_CANCEL_PAY ON MIGRATION.LS_OV_CANCEL_PAY (LREF)");
      run(c, "SELECT LREF, INVOICEREF, CROSSREF_IADE_LREF, CROSSREF_MAIN_LREF, PAYABLETOTAL FROM MIGRATION.LS_OV_CANCEL_PAY");
    }
  }
}