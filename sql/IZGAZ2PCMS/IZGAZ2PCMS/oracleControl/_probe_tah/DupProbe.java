import java.sql.*;
public class DupProbe {
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
      q(c,"pay 280",
        "SELECT LREF, CROSSREF_MAIN_LREF, OV_KIND, PAYTYPE, PAYABLETOTAL, CANCELED, ABYS_ACTION_TYPE_ID, DATE_ "+
        "FROM MIGRATION.LS_OV_PAY_PT WHERE ABS(PAYABLETOTAL-280)<0.02 ORDER BY LREF");
      q(c,"main 19444984 pays",
        "SELECT LREF, CROSSREF_MAIN_LREF, OV_KIND, PAYTYPE, PAYABLETOTAL, CANCELED, ABYS_ACTION_TYPE_ID, DATE_ "+
        "FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF=19444984 ORDER BY DATE_, LREF");
      q(c,"sms actions around",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, aa.ACTION_DATE, aa.ACCOUNT_ID, "+
        "(SELECT ROUND(SUM(ai.AMOUNT*ai.STATUS),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) TUT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa WHERE aa.ID IN ("+
        " SELECT LREF FROM MIGRATION.LS_OV_PAY_PT WHERE CROSSREF_MAIN_LREF=19444984 OR ABS(PAYABLETOTAL-280)<0.02)");
    }
  }
}