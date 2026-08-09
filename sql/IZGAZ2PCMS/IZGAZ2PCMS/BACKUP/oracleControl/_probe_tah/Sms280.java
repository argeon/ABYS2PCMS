import java.sql.*;
public class Sms280 {
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
      q(c,"inv 15876450",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, ACTION_DATE, DUE_DATE FROM SMS.CS_ACCOUNT_ACTION WHERE ID=15876450");
      q(c,"account actions Mar-Jun 2010 type2",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP, aa.ACTION_DATE, aa.CASH_ID, aa.RECEIPT_NUMBER, "+
        "(SELECT ROUND(SUM(ai.AMOUNT*ai.STATUS),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) TUT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "JOIN SMS.CS_ACCOUNT a ON a.ID=aa.ACCOUNT_ID AND a.AGREEMENT_ID=197168 "+
        "JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ACTION_DATE >= DATE '2010-03-01' AND aa.ACTION_DATE < DATE '2010-06-01' "+
        "AND atp.TYPE IN (1,2) "+
        "ORDER BY aa.ACTION_DATE, aa.ID");
      q(c,"pay 50400423 incomes",
        "SELECT ai.ID, ai.INCOME_ID, ai.AMOUNT, ai.STATUS, ai.ACCOUNT_ACTION_ID FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=50400423");
      q(c,"shared income with mains",
        "SELECT pi.ACCOUNT_ACTION_ID PAY, ai.ACCOUNT_ACTION_ID MAIN, ai.INCOME_ID, ai.AMOUNT*ai.STATUS AMT "+
        "FROM SMS.CS_ACCOUNT_INCOME pi "+
        "JOIN SMS.CS_ACCOUNT_INCOME ai ON ai.INCOME_ID=pi.INCOME_ID AND ai.ACCOUNT_ACTION_ID<>pi.ACCOUNT_ACTION_ID "+
        "JOIN SMS.CS_ACCOUNT_ACTION g ON g.ID=ai.ACCOUNT_ACTION_ID AND g.ACTION_TYPE_ID IN (1,3,10,41) "+
        "WHERE pi.ACCOUNT_ACTION_ID=50400423");
    }
  }
}