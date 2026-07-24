import java.sql.*;
public class MahProbe3 {
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
      q(c,"by deposit account",
        "SELECT NVL(pay.REF_DEPOSIT_ACCOUNT_ID,-1) DEP_ACC, "+
        "COUNT(*) MAHSUP_CNT, COUNT(DISTINCT p.CROSSREF_MAIN_LREF) MAIN_CNT, "+
        "ROUND(SUM(p.PAYABLETOTAL),2) AMT, "+
        "LISTAGG(TO_CHAR(p.CROSSREF_MAIN_LREF), ',') WITHIN GROUP (ORDER BY p.CROSSREF_MAIN_LREF) MAINS "+
        "FROM MIGRATION.LS_OV_PAY_PT p "+
        "JOIN SMS.CS_ACCOUNT_ACTION pay ON pay.ID=p.LREF "+
        "WHERE p.OV_KIND='MAHSUP' AND NVL(p.CANCELED,0)=0 AND p.CROSSREF_MAIN_LREF IS NOT NULL "+
        "GROUP BY NVL(pay.REF_DEPOSIT_ACCOUNT_ID,-1) ORDER BY MAIN_CNT DESC");
      q(c,"cash+receipt cluster",
        "SELECT pay.CASH_ID, pay.RECEIPT_NUMBER, COUNT(*) CNT, COUNT(DISTINCT p.CROSSREF_MAIN_LREF) MAIN_CNT, "+
        "ROUND(SUM(p.PAYABLETOTAL),2) AMT "+
        "FROM MIGRATION.LS_OV_PAY_PT p JOIN SMS.CS_ACCOUNT_ACTION pay ON pay.ID=p.LREF "+
        "WHERE p.OV_KIND='MAHSUP' AND NVL(p.CANCELED,0)=0 AND p.CROSSREF_MAIN_LREF IS NOT NULL "+
        "GROUP BY pay.CASH_ID, pay.RECEIPT_NUMBER HAVING COUNT(DISTINCT p.CROSSREF_MAIN_LREF)>1");
      q(c,"closed mains with mahsup vs bank",
        "SELECT d.LREF MAIN, d.PAIDTOTAL, d.PAYABLETOTAL, d.CLOSED, "+
        "NVL(m.MAHSUP_AMT,0) MAHSUP_AMT, NVL(b.BANK_AMT,0) BANK_AMT, "+
        "CASE WHEN NVL(m.MAHSUP_AMT,0)>0 AND NVL(b.BANK_AMT,0)=0 THEN 'MAHSUP_ONLY' "+
        "     WHEN NVL(m.MAHSUP_AMT,0)>0 AND NVL(b.BANK_AMT,0)>0 THEN 'MIXED' "+
        "     ELSE 'BANK_ONLY' END CLOSE_KIND "+
        "FROM MIGRATION.LS_OV_DEBT_PAID_UPD d "+
        "LEFT JOIN (SELECT CROSSREF_MAIN_LREF, SUM(PAYABLETOTAL) MAHSUP_AMT FROM MIGRATION.LS_OV_PAY_PT "+
        "  WHERE OV_KIND='MAHSUP' AND NVL(CANCELED,0)=0 GROUP BY CROSSREF_MAIN_LREF) m ON m.CROSSREF_MAIN_LREF=d.LREF "+
        "LEFT JOIN (SELECT CROSSREF_MAIN_LREF, SUM(PAYABLETOTAL) BANK_AMT FROM MIGRATION.LS_OV_PAY_PT "+
        "  WHERE OV_KIND='BANK' AND NVL(CANCELED,0)=0 GROUP BY CROSSREF_MAIN_LREF) b ON b.CROSSREF_MAIN_LREF=d.LREF "+
        "WHERE NVL(m.MAHSUP_AMT,0)>0 ORDER BY CLOSE_KIND, d.LREF");
    }
  }
}