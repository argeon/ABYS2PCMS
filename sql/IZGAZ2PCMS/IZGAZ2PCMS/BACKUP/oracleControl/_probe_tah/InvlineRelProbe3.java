import java.sql.*;
public class InvlineRelProbe3 {
  static void q(Connection c, String t, String sql) throws Exception {
    System.out.println("==== "+t);
    try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
      ResultSetMetaData md=rs.getMetaData(); int cols=md.getColumnCount(); int n=0;
      while(rs.next()){
        n++; StringBuilder b=new StringBuilder();
        for(int i=1;i<=cols;i++){
          if(i>1)b.append(" | ");
          b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i));
        }
        System.out.println(b);
      }
      if(n==0) System.out.println("(0 rows)");
    }
  }
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {

      q(c, "aa columns",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_ACCOUNT_ACTION' ORDER BY COLUMN_ID");

      q(c, "aa both * key",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, TO_CHAR(ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, "+
        "REF_DEPOSIT_ACCOUNT_ACTION_ID, REF_DEPOSIT_ACCOUNT_ID, BILL_TYPE_ID "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (123045786,58633499)");

      q(c, "income 58633499",
        "SELECT ai.ID, ip.CODE, ai.QUANTITY, ROUND(ai.AMOUNT,2) AMT, ai.STATUS "+
        "FROM SMS.CS_ACCOUNT_INCOME ai JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID "+
        "WHERE ai.ACCOUNT_ACTION_ID=58633499 ORDER BY ai.ID");

      q(c, "same ACCOUNT_ID actions that day",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, TO_CHAR(aa.ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, "+
        "(SELECT COUNT(*) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) INC_CNT, "+
        "(SELECT ROUND(SUM(ai.AMOUNT),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) INC_SUM "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "WHERE aa.ACCOUNT_ID = (SELECT ACCOUNT_ID FROM SMS.CS_ACCOUNT_ACTION WHERE ID=123045786) "+
        "AND TRUNC(aa.ACTION_DATE)=DATE '2023-06-19' ORDER BY aa.ID");

      q(c, "MIG inv both",
        "SELECT LREF, ABYS_ACTION_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, FITNO, TYPE "+
        "FROM MIGRATION.LS_INVOICE WHERE LREF IN (123045786,58633499)");

      q(c, "type names for both",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, atpl.VALUE "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "LEFT JOIN SMS.CS_ACTION_TYPE_PRM_LNG atpl ON atpl.PRM_ID=aa.ACTION_TYPE_ID AND atpl.LANG_ID=1 "+
        "WHERE aa.ID IN (123045786,58633499)");
    }
  }
}