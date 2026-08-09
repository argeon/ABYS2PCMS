import java.sql.*;
public class MahProbe2 {
  static void q(Connection c, String t, String sql) throws Exception {
    System.out.println("==== "+t);
    try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
      ResultSetMetaData md=rs.getMetaData(); int cols=md.getColumnCount(); int n=0;
      while(rs.next()){ n++; StringBuilder b=new StringBuilder();
        for(int i=1;i<=cols;i++){ if(i>1)b.append(" | "); b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i)); }
        System.out.println(b); }
      if(n==0) System.out.println("(0)");
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try(Connection c=DriverManager.getConnection("jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      q(c,"sample mahsup",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, CASH_ID, RECEIPT_NUMBER, RECEIPT_SERIAL, "+
        "REF_DEPOSIT_ACCOUNT_ID, REF_DEPOSIT_ACCOUNT_ACTION_ID "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (60940043,60940054,60940061)");
      q(c,"pilot mahsup by deposit action",
        "SELECT NVL(pay.REF_DEPOSIT_ACCOUNT_ACTION_ID,-1) DEP_ACT, "+
        "COUNT(*) MAHSUP_CNT, COUNT(DISTINCT p.CROSSREF_MAIN_LREF) MAIN_CNT, "+
        "ROUND(SUM(p.PAYABLETOTAL),2) AMT "+
        "FROM MIGRATION.LS_OV_PAY_PT p "+
        "JOIN SMS.CS_ACCOUNT_ACTION pay ON pay.ID=p.LREF "+
        "WHERE p.OV_KIND='MAHSUP' AND NVL(p.CANCELED,0)=0 AND p.CROSSREF_MAIN_LREF IS NOT NULL "+
        "GROUP BY NVL(pay.REF_DEPOSIT_ACCOUNT_ACTION_ID,-1) ORDER BY MAIN_CNT DESC, MAHSUP_CNT DESC");
      q(c,"multi-main same deposit detail",
        "SELECT pay.REF_DEPOSIT_ACCOUNT_ACTION_ID DEP, p.CROSSREF_MAIN_LREF MAIN, p.LREF MAHSUP, p.PAYABLETOTAL "+
        "FROM MIGRATION.LS_OV_PAY_PT p JOIN SMS.CS_ACCOUNT_ACTION pay ON pay.ID=p.LREF "+
        "WHERE p.OV_KIND='MAHSUP' AND pay.REF_DEPOSIT_ACCOUNT_ACTION_ID IN ( "+
        "  SELECT REF_DEPOSIT_ACCOUNT_ACTION_ID FROM ( "+
        "    SELECT pay2.REF_DEPOSIT_ACCOUNT_ACTION_ID, COUNT(DISTINCT p2.CROSSREF_MAIN_LREF) c "+
        "    FROM MIGRATION.LS_OV_PAY_PT p2 JOIN SMS.CS_ACCOUNT_ACTION pay2 ON pay2.ID=p2.LREF "+
        "    WHERE p2.OV_KIND='MAHSUP' AND pay2.REF_DEPOSIT_ACCOUNT_ACTION_ID IS NOT NULL "+
        "    GROUP BY pay2.REF_DEPOSIT_ACCOUNT_ACTION_ID HAVING COUNT(DISTINCT p2.CROSSREF_MAIN_LREF)>1 "+
        "  ) "+
        ") ORDER BY DEP, MAIN");
    }
  }
}