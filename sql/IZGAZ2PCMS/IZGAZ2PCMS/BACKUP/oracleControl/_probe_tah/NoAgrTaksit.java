import java.sql.*;
public class NoAgrTaksit {
  static void q(Connection c, String title, String sql) throws Exception {
    System.out.println("==== " + title);
    try (Statement s = c.createStatement(); ResultSet rs = s.executeQuery(sql)) {
      ResultSetMetaData md = rs.getMetaData();
      int cols = md.getColumnCount();
      while (rs.next()) {
        StringBuilder b = new StringBuilder();
        for (int i = 1; i <= cols; i++) {
          if (i > 1) b.append(" | ");
          b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i));
        }
        System.out.println(b);
      }
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz", "SMS", "RepSmS26!IzGx")) {
      q(c, "1 INS_NO_AGR",
        "SELECT COUNT(*) INS_NO_AGR FROM SMS.CS_INSTALLMENT WHERE AGREEMENT_ID IS NULL");
      q(c, "2 PLAN_NO_AGR",
        "SELECT COUNT(*) PLAN_NO_AGR FROM SMS.CS_INSTALLMENT_PLAN ip " +
        "JOIN SMS.CS_INSTALLMENT i ON i.ID = ip.INSTALLMENT_ID WHERE i.AGREEMENT_ID IS NULL");
      q(c, "3 INS_NO_AGR active/cancel",
        "SELECT " +
        "SUM(CASE WHEN i.CANCELLATION_DATE IS NULL AND i.CANCEL_CAUSE_ID IS NULL AND i.CANCELLATION_USER_ID IS NULL THEN 1 ELSE 0 END) INS_NO_AGR_ACTIVE, " +
        "SUM(CASE WHEN i.CANCELLATION_DATE IS NOT NULL OR i.CANCEL_CAUSE_ID IS NOT NULL OR i.CANCELLATION_USER_ID IS NOT NULL THEN 1 ELSE 0 END) INS_NO_AGR_CANCEL, " +
        "COUNT(*) INS_NO_AGR_TOTAL " +
        "FROM SMS.CS_INSTALLMENT i WHERE i.AGREEMENT_ID IS NULL");
      q(c, "4 ACC_TAKSIT_NO_AGR",
        "SELECT COUNT(*) ACC_TAKSIT_NO_AGR FROM SMS.CS_ACCOUNT a " +
        "WHERE a.INSTALLMENT_ID IS NOT NULL AND a.AGREEMENT_ID IS NULL");
      q(c, "5 totals vs with AGR",
        "SELECT " +
        "SUM(CASE WHEN AGREEMENT_ID IS NULL THEN 1 ELSE 0 END) INS_NULL_AGR, " +
        "SUM(CASE WHEN AGREEMENT_ID IS NOT NULL THEN 1 ELSE 0 END) INS_WITH_AGR, " +
        "COUNT(*) INS_ALL " +
        "FROM SMS.CS_INSTALLMENT");
    }
  }
}
