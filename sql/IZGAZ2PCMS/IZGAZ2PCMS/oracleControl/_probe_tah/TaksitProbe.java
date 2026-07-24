import java.sql.*;
public class TaksitProbe {
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
      q(c,"agr resolve",
        "SELECT ID, AGREEMENT_NUMBER, STATUS FROM SMS.CS_AGREEMENT WHERE AGREEMENT_NUMBER IN (2221,1192595,978259)");
      // find installment-related tables
      q(c,"tables INST",
        "SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER='SMS' AND (UPPER(TABLE_NAME) LIKE '%INST%' OR UPPER(TABLE_NAME) LIKE '%TAKS%' OR UPPER(TABLE_NAME) LIKE '%INSTALL%') ORDER BY 1");
      q(c,"cols INSTALLMENT on ACTION",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_ACCOUNT_ACTION' AND UPPER(COLUMN_NAME) LIKE '%INST%' ORDER BY 1");
    }
  }
}