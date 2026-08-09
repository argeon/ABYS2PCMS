import java.sql.*;
public class Agr197168AbysCheck {
  static void q(Connection c, String t, String sql) throws Exception {
    System.out.println("==== "+t);
    try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
      ResultSetMetaData md=rs.getMetaData(); int cols=md.getColumnCount(); int n=0;
      while(rs.next()){
        n++; StringBuilder b=new StringBuilder();
        for(int i=1;i<=cols;i++){
          if(i>1)b.append(" | ");
          b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i));
        }
        System.out.println(b);
      }
      if(n==0) System.out.println("(0 rows)");
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      long agr = 197168L;

      q(c, "ABYS INV (action type filter via MIG)",
        "SELECT COUNT(*) INV_CNT, ROUND(SUM(NVL(TLTOTAL,0)+NVL((SELECT SUM(CASE WHEN NVL(ip.IS_VAT_INCOME,0)=1 THEN ai.AMOUNT ELSE 0 END) FROM SMS.CS_ACCOUNT_INCOME ai LEFT JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID WHERE ai.ACCOUNT_ACTION_ID=inv.ABYS_ACTION_ID),0)),2) DUMMY "+
        "FROM MIGRATION.LS_INVOICE inv WHERE inv.ABYS_AGREEMENT_ID="+agr);

      q(c, "ABYS SMS tahakkuk count on agr",
        "SELECT COUNT(*) AA_CNT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "JOIN SMS.CS_ACCOUNT acc ON acc.ID=aa.ACCOUNT_ID "+
        "WHERE acc.AGREEMENT_ID="+agr);

      q(c, "ABYS income on agr (via account)",
        "SELECT COUNT(*) AI_CNT, ROUND(SUM(ai.AMOUNT),2) SUM_AMT, ROUND(SUM(ai.QUANTITY),2) SUM_QTY "+
        "FROM SMS.CS_ACCOUNT_INCOME ai "+
        "JOIN SMS.CS_ACCOUNT_ACTION aa ON aa.ID=ai.ACCOUNT_ACTION_ID "+
        "JOIN SMS.CS_ACCOUNT acc ON acc.ID=aa.ACCOUNT_ID "+
        "WHERE acc.AGREEMENT_ID="+agr);

      q(c, "MIG invoice agr",
        "SELECT COUNT(*) INV_CNT, ROUND(SUM(NVL(TLTOTAL,0)),2) SUM_TL, ROUND(SUM(NVL(GRANDTOTAL,0)),2) SUM_GT "+
        "FROM MIGRATION.LS_INVOICE WHERE ABYS_AGREEMENT_ID="+agr);

      q(c, "MIG invlines agr",
        "SELECT COUNT(*) IL_CNT, ROUND(SUM(NVL(GRANDTOTAL,0)),2) SUM_GT, ROUND(SUM(NVL(ABYS_QUANTITY,0)),2) SUM_QTY, ROUND(SUM(NVL(TLTOTAL,0)),2) SUM_TL "+
        "FROM MIGRATION.LS_INVLINES WHERE ABYS_AGREEMENT_ID="+agr);

      q(c, "MIG orphan invlines (no invoice)",
        "SELECT COUNT(*) ORPHAN_IL "+
        "FROM MIGRATION.LS_INVLINES il "+
        "WHERE il.ABYS_AGREEMENT_ID="+agr+" "+
        "AND NOT EXISTS (SELECT 1 FROM MIGRATION.LS_INVOICE inv WHERE inv.LREF=il.INVOICEREF)");

      q(c, "MIG invoice without lines",
        "SELECT COUNT(*) INV_NO_LINES "+
        "FROM MIGRATION.LS_INVOICE inv "+
        "WHERE inv.ABYS_AGREEMENT_ID="+agr+" "+
        "AND NOT EXISTS (SELECT 1 FROM MIGRATION.LS_INVLINES il WHERE il.INVOICEREF=inv.LREF)");

      q(c, "SMS vs MIG income on same actions in MIG inv",
        "SELECT "+
        "(SELECT COUNT(*) FROM SMS.CS_ACCOUNT_INCOME ai "+
        "  WHERE ai.ACCOUNT_ACTION_ID IN (SELECT ABYS_ACTION_ID FROM MIGRATION.LS_INVOICE WHERE ABYS_AGREEMENT_ID="+agr+")) SMS_AI, "+
        "(SELECT COUNT(*) FROM MIGRATION.LS_INVLINES WHERE ABYS_AGREEMENT_ID="+agr+") MIG_IL, "+
        "(SELECT ROUND(SUM(ai.AMOUNT),2) FROM SMS.CS_ACCOUNT_INCOME ai "+
        "  WHERE ai.ACCOUNT_ACTION_ID IN (SELECT ABYS_ACTION_ID FROM MIGRATION.LS_INVOICE WHERE ABYS_AGREEMENT_ID="+agr+")) SMS_AMT, "+
        "(SELECT ROUND(SUM(GRANDTOTAL),2) FROM MIGRATION.LS_INVLINES WHERE ABYS_AGREEMENT_ID="+agr+") MIG_AMT");
    }
  }
}