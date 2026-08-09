import java.sql.*;
public class G {
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement()) {
      try (ResultSet rs = s.executeQuery(
        "SELECT LREF, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, PAYABLETOTAL, CANCELED "+
        "FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IS NULL")) {
        while (rs.next())
          System.out.println("NO_XREF LREF="+rs.getLong(1)+" ACC="+rs.getLong(2)+
            " TIP="+rs.getLong(3)+" AMT="+rs.getDouble(4)+" CANC="+rs.getInt(5));
      }
      try (ResultSet rs = s.executeQuery(
        "SELECT COUNT(*) OPEN_DEBT FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE CLOSED=0")) {
        rs.next(); System.out.println("DEBT_OPEN="+rs.getLong(1));
      }
      try (ResultSet rs = s.executeQuery(
        "SELECT MAIN_LREF, PAID_AMT, CLOSED FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE CLOSED=0 ORDER BY MAIN_LREF")) {
        while (rs.next())
          System.out.println("OPEN MAIN="+rs.getLong(1)+" PAID="+rs.getDouble(2)+" CLOSED="+rs.getInt(3));
      }
    }
  }
}