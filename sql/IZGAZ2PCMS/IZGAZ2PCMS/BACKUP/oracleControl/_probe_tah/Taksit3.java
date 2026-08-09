import java.sql.*;
public class Taksit3 {
  static void q(Connection c, String t, String sql) throws Exception {
    System.out.println("==== "+t);
    try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
      ResultSetMetaData md=rs.getMetaData(); int cols=md.getColumnCount(); int n=0;
      while(rs.next()){ n++; StringBuilder b=new StringBuilder();
        for(int i=1;i<=cols;i++){ if(i>1)b.append(" | "); b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i)); }
        System.out.println(b); if(n>=50){ System.out.println("...(trunc)"); break; } }
      if(n==0) System.out.println("(0)");
    } catch(SQLException e){ System.out.println("ERR: "+e.getMessage()); }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try(Connection c=DriverManager.getConnection("jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      q(c,"installment header",
        "SELECT i.ID, a.AGREEMENT_NUMBER AGR, i.INSTALLMENT_TYPE_ID TYP, i.INSTALLMENT_NUMBER CNT, "+
        "TO_CHAR(i.INSTALLMENT_DATE,'YYYY-MM-DD') IDATE, TO_CHAR(i.DUE_DATE,'YYYY-MM-DD') DUE, "+
        "ROUND(i.TOTAL_AMOUNT,2) TOTAL, ROUND(i.MONTHLY_AMOUNT,2) MONTHLY, ROUND(i.FIRST_INSTALLMENT_AMOUNT,2) FIRST_AMT, "+
        "i.CANCEL_CAUSE_ID, TO_CHAR(i.CANCELLATION_DATE,'YYYY-MM-DD') CANCEL_DT, i.DESCRIPTION "+
        "FROM SMS.CS_INSTALLMENT i JOIN SMS.CS_AGREEMENT a ON a.ID=i.AGREEMENT_ID "+
        "WHERE a.AGREEMENT_NUMBER IN (2221,1192595,978259) ORDER BY a.AGREEMENT_NUMBER, i.ID");
      q(c,"plan cols",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_INSTALLMENT_PLAN' AND COLUMN_ID<=25 ORDER BY COLUMN_ID");
      q(c,"plans sample",
        "SELECT p.ID, p.INSTALLMENT_ID, a.AGREEMENT_NUMBER AGR, p.ORDER_NUMBER ORD, "+
        "TO_CHAR(p.DUE_DATE,'YYYY-MM-DD') DUE, ROUND(p.AMOUNT,2) AMT, p.STATUS, p.ACCOUNT_ACTION_ID "+
        "FROM SMS.CS_INSTALLMENT_PLAN p "+
        "JOIN SMS.CS_INSTALLMENT i ON i.ID=p.INSTALLMENT_ID "+
        "JOIN SMS.CS_AGREEMENT a ON a.ID=i.AGREEMENT_ID "+
        "WHERE a.AGREEMENT_NUMBER IN (2221,1192595,978259) "+
        "ORDER BY a.AGREEMENT_NUMBER, p.INSTALLMENT_ID, p.ORDER_NUMBER");
      q(c,"aa with installment",
        "SELECT a.AGREEMENT_NUMBER AGR, COUNT(*) CNT, "+
        "SUM(CASE WHEN aa.INSTALLMENT_ID IS NOT NULL THEN 1 ELSE 0 END) WITH_INST, "+
        "SUM(CASE WHEN NVL(aa.INSTALLMENT_ORDER_NUMBER,0)>0 THEN 1 ELSE 0 END) WITH_ORD "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "JOIN SMS.CS_ACCOUNT ac ON ac.ID=aa.ACCOUNT_ID "+
        "JOIN SMS.CS_AGREEMENT a ON a.ID=ac.AGREEMENT_ID "+
        "WHERE a.AGREEMENT_NUMBER IN (2221,1192595,978259) "+
        "GROUP BY a.AGREEMENT_NUMBER");
      q(c,"type prm",
        "SELECT ID, CODE, VALUE FROM SMS.CS_INSTALLMENT_TYPE_PRM WHERE ROWNUM<=20");
    }
  }
}