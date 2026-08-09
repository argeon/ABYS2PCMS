import java.sql.*;
public class BekProbe {
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
      q(c,"actions",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atp.TYPE ATP, aa.ACTION_DATE, aa.ACCOUNT_ID, "+
        "(SELECT ROUND(SUM(ai.AMOUNT*ai.STATUS),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) TUT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "LEFT JOIN SMS.CS_ACTION_TYPE_PRM atp ON atp.ID=aa.ACTION_TYPE_ID "+
        "WHERE aa.ID IN (16885098,16035090)");
      q(c,"ov pay",
        "SELECT LREF, CROSSREF_MAIN_LREF, OV_KIND, PAYTYPE, PAYABLETOTAL, CANCELED, ABYS_ACTION_TYPE_ID, DATE_ "+
        "FROM MIGRATION.LS_OV_PAY_PT WHERE LREF IN (16035090,16885098) OR CROSSREF_MAIN_LREF=16885098 "+
        "OR ABS(PAYABLETOTAL-21.28)<0.02 OR ABS(PAYABLETOTAL-25)<0.02");
      q(c,"shared income 16035090",
        "SELECT pi.ACCOUNT_ACTION_ID PAY, ai.ACCOUNT_ACTION_ID MAIN, g.ACTION_TYPE_ID, ai.INCOME_ID, ROUND(ai.AMOUNT*ai.STATUS,2) AMT "+
        "FROM SMS.CS_ACCOUNT_INCOME pi "+
        "JOIN SMS.CS_ACCOUNT_INCOME ai ON ai.INCOME_ID=pi.INCOME_ID "+
        "JOIN SMS.CS_ACCOUNT_ACTION g ON g.ID=ai.ACCOUNT_ACTION_ID "+
        "WHERE pi.ACCOUNT_ACTION_ID=16035090 ORDER BY MAIN");
      q(c,"pay amount detail",
        "SELECT ai.ID, ai.INCOME_ID, ai.AMOUNT, ai.STATUS, ROUND(ai.AMOUNT*ai.STATUS,2) AMT "+
        "FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID IN (16035090,16885098)");
    }
  }
}