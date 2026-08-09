import java.sql.*;
public class TestBranch {
  public static void main(String[] a) throws Exception {
    String sql =
      "SELECT COUNT(*) FROM (" +
      " SELECT pay.ID, pay.ACCOUNT_ID, m.AGREEMENT_ID, pay.ACTION_TYPE_ID, " +
      " (SELECT ROUND(ABS(SUM(ai.AMOUNT * ai.STATUS)), 2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID = pay.ID) TUT " +
      " FROM SMS.CS_ACCOUNT_ACTION pay " +
      " JOIN MIGRATION.TMP_MIG_ACC m ON m.ACCOUNT_ID = pay.ACCOUNT_ID " +
      " JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID = pay.ACTION_TYPE_ID AND atp.TYPE = 2 " +
      " WHERE pay.ACTION_TYPE_ID NOT IN (36, 37, 39, 44) " +
      " AND NOT EXISTS (SELECT 1 FROM MIGRATION.TMP_PAY_CANCEL c WHERE c.PAY_ID = pay.ID) " +
      " AND NOT EXISTS (SELECT 1 FROM MIGRATION.LS_OV_PAY_ALLOC a WHERE a.PAY_LREF = pay.ID)" +
      ")";
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement();
         ResultSet rs = s.executeQuery(sql)) {
      rs.next(); System.out.println("PAY_NO_ALLOC branch ok n="+rs.getInt(1));
    }
    String sql2 =
      "SELECT COUNT(*) FROM (" +
      " SELECT pay.ID FROM SMS.CS_ACCOUNT_ACTION pay " +
      " JOIN MIGRATION.TMP_MIG_ACC m ON m.ACCOUNT_ID = pay.ACCOUNT_ID " +
      " WHERE pay.ACTION_TYPE_ID = 12 " +
      " AND EXISTS ( SELECT 1 FROM SMS.CS_ACCOUNT_INCOME pi " +
      "   JOIN SMS.CS_ACCOUNT_ACTION g ON g.ACCOUNT_ID = pay.ACCOUNT_ID AND g.ACTION_TYPE_ID IN (1,3,10,41) " +
      "   JOIN SMS.CS_ACCOUNT_INCOME gi ON gi.ACCOUNT_ACTION_ID = g.ID AND gi.INCOME_ID = pi.INCOME_ID " +
      "   WHERE pi.ACCOUNT_ACTION_ID = pay.ID )" +
      ")";
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement();
         ResultSet rs = s.executeQuery(sql2)) {
      rs.next(); System.out.println("MATCH branch ok n="+rs.getInt(1));
    }
  }
}