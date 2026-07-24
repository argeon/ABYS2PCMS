import java.nio.file.*;
import java.sql.*;
public class RebuildLogDirect {
  public static void main(String[] a) throws Exception {
    String drop = "BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIGRATION.LS_OV_TAH_LOG PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;";
    String create = Files.readString(Path.of(a[0])).trim();
    if (create.endsWith(";")) create = create.substring(0, create.length()-1);
    create = create.replace('\u2014','-').replace('\u2013','-');
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement()) {
      System.out.println("DROP...");
      s.execute(drop);
      System.out.println("CREATE len="+create.length());
      long t0=System.currentTimeMillis();
      s.execute(create);
      System.out.println("CREATE ok ms="+(System.currentTimeMillis()-t0));
      try { s.execute("CREATE UNIQUE INDEX MIGRATION.IX_OV_TAH_LOG ON MIGRATION.LS_OV_TAH_LOG (LOG_ID)"); } catch(SQLException e){ System.out.println("ix1 "+e.getErrorCode()); }
      try { s.execute("CREATE INDEX MIGRATION.IX_OV_TAH_LOG_RSN ON MIGRATION.LS_OV_TAH_LOG (REASON)"); } catch(SQLException e){ System.out.println("ix2 "+e.getErrorCode()); }
      try { s.execute("CREATE INDEX MIGRATION.IX_OV_TAH_LOG_AGR ON MIGRATION.LS_OV_TAH_LOG (AGREEMENT_ID)"); } catch(SQLException e){ System.out.println("ix3 "+e.getErrorCode()); }
      try (ResultSet rs = s.executeQuery(
          "SELECT REASON, SEVERITY, COUNT(*) N FROM MIGRATION.LS_OV_TAH_LOG GROUP BY REASON, SEVERITY ORDER BY 1")) {
        while (rs.next()) System.out.println(rs.getString(1)+"|"+rs.getString(2)+"|"+rs.getInt(3));
      }
      try (ResultSet rs = s.executeQuery("SELECT COUNT(*) FROM MIGRATION.LS_OV_TAH_LOG")) {
        rs.next(); System.out.println("TOTAL="+rs.getInt(1));
      }
    }
  }
}