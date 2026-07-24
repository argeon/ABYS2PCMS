import java.sql.*;
public class Ana2 {
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
      q(c, "LS_INVOICE cols sample",
        "SELECT LREF, TYPE, IOCODE, PAYABLETOTAL, GRANDTOTAL, CLOSED, CANCELED, RETURN_TARGET_INVREF, ABYS_ACTION_ID, ABYS_ACCOUNT_ID, FICHENO, DATE_ "+
        "FROM MIGRATION.LS_INVOICE WHERE LREF IN (19115898,19444984)");
      q(c, "EKS_CLASS",
        "SELECT EKS_ACTION_ID, ACCOUNT_ID, KIND, MAIN_LREF, EKS_AMT, TAH_AMT FROM MIGRATION.LS_OV_EKS_CLASS WHERE MAIN_LREF IN (19115898,19444984)");
      q(c, "PAY_PT",
        "SELECT LREF, CROSSREF_MAIN_LREF, PAYABLETOTAL, CANCELED, ABYS_ACTION_TYPE_ID FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF IN (19115898,19444984)");
      q(c, "DEBT_PAID",
        "SELECT MAIN_LREF, PAID_AMT, CLOSED FROM MIGRATION.LS_OV_DEBT_PAID_UPD WHERE MAIN_LREF IN (19115898,19444984)");
      // account ids
      q(c, "ACC ids",
        "SELECT LREF, ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF IN (19115898,19444984)");
      q(c, "SMS timeline 19444984 account",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP, TO_CHAR(aa.ACTION_DATE,'YYYY-MM-DD HH24:MI') DT, "+
        "ROUND((SELECT SUM(ai.AMOUNT*ai.STATUS) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID),2) AMT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ACCOUNT_ID=(SELECT ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF=19444984) "+
        "ORDER BY aa.ACTION_DATE, aa.ID");
      q(c, "SMS timeline 19115898 account",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP, TO_CHAR(aa.ACTION_DATE,'YYYY-MM-DD HH24:MI') DT, "+
        "ROUND((SELECT SUM(ai.AMOUNT*ai.STATUS) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID),2) AMT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ACCOUNT_ID=(SELECT ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF=19115898) "+
        "ORDER BY aa.ACTION_DATE, aa.ID");
      // income breakdown for payments vs main
      q(c, "income IDs MAIN 19444984",
        "SELECT ai.INCOME_ID, ROUND(SUM(ai.AMOUNT),2) AMT FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=19444984 GROUP BY ai.INCOME_ID ORDER BY 1");
      q(c, "income IDs MAIN 19115898",
        "SELECT ai.INCOME_ID, ROUND(SUM(ai.AMOUNT),2) AMT FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=19115898 GROUP BY ai.INCOME_ID ORDER BY 1");
      q(c, "payments on acc 19444984 incomes",
        "SELECT pay.ID PAY, pay.ACTION_TYPE_ID, ROUND(SUM(pi.AMOUNT*pi.STATUS),2) AMT, "+
        "LISTAGG(pi.INCOME_ID, ',') WITHIN GROUP (ORDER BY pi.INCOME_ID) INCS "+
        "FROM SMS.CS_ACCOUNT_ACTION pay "+
        "JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=pay.ACTION_TYPE_ID AND atp.TYPE=2 "+
        "JOIN SMS.CS_ACCOUNT_INCOME pi ON pi.ACCOUNT_ACTION_ID=pay.ID "+
        "WHERE pay.ACCOUNT_ID=(SELECT ABYS_ACCOUNT_ID FROM MIGRATION.LS_INVOICE WHERE LREF=19444984) "+
        "GROUP BY pay.ID, pay.ACTION_TYPE_ID ORDER BY pay.ID");
    }
  }
}