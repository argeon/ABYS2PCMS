import java.sql.*;
public class LogCnt {
  public static void main(String[] a) throws Exception {
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement();
         ResultSet rs = s.executeQuery(
           "SELECT REASON, SEVERITY, COUNT(*) N FROM MIGRATION.LS_OV_TAH_LOG GROUP BY REASON, SEVERITY ORDER BY 1")) {
      while (rs.next()) System.out.println(rs.getString(1)+"|"+rs.getString(2)+"|"+rs.getInt(3));
    }
  }
}