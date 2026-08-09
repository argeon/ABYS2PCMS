import java.sql.*;
public class Ana {
  static void q(Connection c, String title, String sql) throws Exception {
    System.out.println("==== " + title);
    try (Statement s = c.createStatement(); ResultSet rs = s.executeQuery(sql)) {
      ResultSetMetaData md = rs.getMetaData();
      int cols = md.getColumnCount();
      int n=0;
      while (rs.next()) {
        n++;
        StringBuilder row = new StringBuilder();
        for (int i=1;i<=cols;i++) {
          if (i>1) row.append(" | ");
          row.append(md.getColumnLabel(i)).append("=").append(rs.getString(i));
        }
        System.out.println(row);
      }
      if (n==0) System.out.println("(0 rows)");
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      // LS_INVOICE
      q(c, "LS_INVOICE",
        "SELECT LREF, TYPE, IOCODE, PAYABLETOTAL, GRANDTOTAL, CLOSED, CANCELED, RETURN_TARGET_INVREF, ABYS_ID, ABYS_ACCOUNT_ID, FICHENO, DATE_ "+
        "FROM MIGRATION.LS_INVOICE WHERE LREF IN (19115898,19444984)");
      // EKS class for accounts of these mains
      q(c, "EKS_CLASS for accounts",
        "SELECT * FROM MIGRATION.LS_OV_EKS_CLASS WHERE MAIN_LREF IN (19115898,19444984) OR ACCOUNT_ID IN ("+
        "SELECT ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF IN (19115898,19444984))");
      // payments targeting these
      q(c, "PAY_PT xref",
        "SELECT LREF, INVOICEREF, CROSSREF_MAIN_LREF, PAYABLETOTAL, CANCELED, ABYS_ACTION_TYPE_ID, ABYS_ACCOUNT_ID "+
        "FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IN (19115898,19444984) OR LREF IN (19115898,19444984)");
      q(c, "DEBT_PAID",
        "SELECT * FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE MAIN_LREF IN (19115898,19444984)");
      q(c, "TAH_LOG",
        "SELECT * FROM MIGRATION.LS_OV_TAH_LOG WHERE MAIN_LREF IN (19115898,19444984) OR PAY_LREF IN (19115898,19444984)");
      // SMS actions on same accounts
      q(c, "SMS actions on ACC of 19444984",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP_TYPE, aa.ACTION_DATE, "+
        "(SELECT ROUND(SUM(ai.AMOUNT*ai.STATUS),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) AMT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ACCOUNT_ID = (SELECT ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF=19444984) "+
        "ORDER BY aa.ACTION_DATE, aa.ID");
      q(c, "SMS actions on ACC of 19115898",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP_TYPE, aa.ACTION_DATE, "+
        "(SELECT ROUND(SUM(ai.AMOUNT*ai.STATUS),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) AMT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ACCOUNT_ID = (SELECT ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF=19115898) "+
        "ORDER BY aa.ACTION_DATE, aa.ID");
    }
  }
}