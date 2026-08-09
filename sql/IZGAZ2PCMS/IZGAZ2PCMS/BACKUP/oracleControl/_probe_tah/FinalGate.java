import java.sql.*;
public class FinalGate {
  public static void main(String[] a) throws Exception {
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement()) {
      int pt,al,xr,multi;
      try (ResultSet rs=s.executeQuery("SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_PT")) { rs.next(); pt=rs.getInt(1); }
      try (ResultSet rs=s.executeQuery("SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_ALLOC")) { rs.next(); al=rs.getInt(1); }
      try (ResultSet rs=s.executeQuery("SELECT COUNT(*) FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IS NULL")) { rs.next(); xr=rs.getInt(1); }
      try (ResultSet rs=s.executeQuery("SELECT COUNT(*) FROM (SELECT PAY_LREF FROM MIGRATION.LS_OV_PAY_ALLOC GROUP BY PAY_LREF HAVING COUNT(*)>1)")) { rs.next(); multi=rs.getInt(1); }
      System.out.println("GATE PT="+pt+" ALLOC="+al+" NO_XREF="+xr+" MULTI="+multi);
      if (pt!=al || xr>0 || multi<1) { System.out.println("HARD_GATE=FAIL"); System.exit(2); }
      System.out.println("HARD_GATE=PASS");
      try (ResultSet rs=s.executeQuery("SELECT REASON, COUNT(*) N FROM MIGRATION.LS_OV_TAH_LOG GROUP BY REASON ORDER BY 1")) {
        while (rs.next()) System.out.println("LOG_"+rs.getString(1)+"="+rs.getInt(2));
      } catch (SQLException e) { System.out.println("LOG_SKIP "+e.getErrorCode()); }
    }
  }
}