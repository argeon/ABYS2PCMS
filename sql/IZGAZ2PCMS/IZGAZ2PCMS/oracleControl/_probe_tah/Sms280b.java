import java.sql.*;
public class Sms280b {
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
      q(c,"actions 2010 Q2",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP, TO_CHAR(aa.ACTION_DATE,'YYYY-MM-DD') DT, "+
        "(SELECT ROUND(SUM(ai.AMOUNT*ai.STATUS),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) TUT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "JOIN SMS.CS_ACCOUNT ac ON ac.ID=aa.ACCOUNT_ID AND ac.AGREEMENT_ID=197168 "+
        "JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ACTION_DATE >= DATE '2010-03-01' AND aa.ACTION_DATE < DATE '2010-06-01' "+
        "ORDER BY aa.ACTION_DATE, aa.ID");
    }
  }
}