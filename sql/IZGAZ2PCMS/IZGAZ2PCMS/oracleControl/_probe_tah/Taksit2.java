import java.sql.*;
public class Taksit2 {
  static void q(Connection c, String t, String sql) throws Exception {
    System.out.println("==== "+t);
    try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
      ResultSetMetaData md=rs.getMetaData(); int cols=md.getColumnCount(); int n=0;
      while(rs.next()){ n++; StringBuilder b=new StringBuilder();
        for(int i=1;i<=cols;i++){ if(i>1)b.append(" | "); b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i)); }
        System.out.println(b); if(n>=40){ System.out.println("...(trunc)"); break; } }
      if(n==0) System.out.println("(0)");
    } catch(SQLException e){ System.out.println("ERR: "+e.getMessage()); }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try(Connection c=DriverManager.getConnection("jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      q(c,"CS_INSTALLMENT cols",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_INSTALLMENT' ORDER BY COLUMN_ID");
      q(c,"installments by agr",
        "SELECT i.ID, i.AGREEMENT_ID, a.AGREEMENT_NUMBER, i.INSTALLMENT_TYPE_ID, i.STATUS, "+
        "i.INSTALLMENT_COUNT, i.START_DATE, i.END_DATE, i.TOTAL_AMOUNT, i.REMAINING_AMOUNT "+
        "FROM SMS.CS_INSTALLMENT i JOIN SMS.CS_AGREEMENT a ON a.ID=i.AGREEMENT_ID "+
        "WHERE a.AGREEMENT_NUMBER IN (2221,1192595,978259) ORDER BY a.AGREEMENT_NUMBER, i.ID");
    }
  }
}