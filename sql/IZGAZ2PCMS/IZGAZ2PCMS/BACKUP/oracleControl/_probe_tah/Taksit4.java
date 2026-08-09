import java.sql.*;
public class Taksit4 {
  static void q(Connection c, String t, String sql) throws Exception {
    System.out.println("==== "+t);
    try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
      ResultSetMetaData md=rs.getMetaData(); int cols=md.getColumnCount(); int n=0;
      while(rs.next()){ n++; StringBuilder b=new StringBuilder();
        for(int i=1;i<=cols;i++){ if(i>1)b.append(" | "); b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i)); }
        System.out.println(b); if(n>=60){ System.out.println("...(trunc)"); break; } }
      if(n==0) System.out.println("(0)");
    } catch(SQLException e){ System.out.println("ERR: "+e.getMessage()); }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try(Connection c=DriverManager.getConnection("jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      q(c,"plans",
        "SELECT a.AGREEMENT_NUMBER AGR, p.INSTALLMENT_ID INST, p.ID PLAN_ID, p.ORDER_NUMBER ORD, "+
        "TO_CHAR(p.EXPIRY_DATE,'YYYY-MM-DD') EXP, TO_CHAR(p.DUE_DATE,'YYYY-MM-DD') DUE, "+
        "ROUND(p.AMOUNT,2) AMT, ROUND(NVL(p.LATE_CHARGE,0),2) LATE, TO_CHAR(p.PAYMENT_DATE,'YYYY-MM-DD') PAYDT, "+
        "p.RECEIPT_NUMBER RCPT "+
        "FROM SMS.CS_INSTALLMENT_PLAN p "+
        "JOIN SMS.CS_INSTALLMENT i ON i.ID=p.INSTALLMENT_ID "+
        "JOIN SMS.CS_AGREEMENT a ON a.ID=i.AGREEMENT_ID "+
        "WHERE a.AGREEMENT_NUMBER IN (2221,1192595,978259) "+
        "ORDER BY a.AGREEMENT_NUMBER, p.INSTALLMENT_ID, p.ORDER_NUMBER");
      q(c,"inst-aa link",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_INSTALLMENT_ACCOUNT_ACTION' ORDER BY COLUMN_ID");
      q(c,"inst aa rows",
        "SELECT a.AGREEMENT_NUMBER AGR, iaa.INSTALLMENT_ID, iaa.ACCOUNT_ACTION_ID, aa.ACTION_TYPE_ID, "+
        "aa.INSTALLMENT_ORDER_NUMBER ORD "+
        "FROM SMS.CS_INSTALLMENT_ACCOUNT_ACTION iaa "+
        "JOIN SMS.CS_INSTALLMENT i ON i.ID=iaa.INSTALLMENT_ID "+
        "JOIN SMS.CS_AGREEMENT a ON a.ID=i.AGREEMENT_ID "+
        "JOIN SMS.CS_ACCOUNT_ACTION aa ON aa.ID=iaa.ACCOUNT_ACTION_ID "+
        "WHERE a.AGREEMENT_NUMBER IN (2221,1192595,978259) "+
        "ORDER BY a.AGREEMENT_NUMBER, iaa.INSTALLMENT_ID, aa.INSTALLMENT_ORDER_NUMBER");
      q(c,"type 11",
        "SELECT * FROM SMS.CS_INSTALLMENT_TYPE_PRM WHERE ID=11");
    }
  }
}