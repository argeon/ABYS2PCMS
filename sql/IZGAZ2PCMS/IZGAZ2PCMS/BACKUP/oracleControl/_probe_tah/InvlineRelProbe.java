import java.sql.*;
public class InvlineRelProbe {
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

      q(c, "aa cols sample",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_ACCOUNT_ACTION' "+
        "AND COLUMN_NAME LIKE '%REF%' OR (OWNER='SMS' AND TABLE_NAME='CS_ACCOUNT_ACTION' AND COLUMN_NAME LIKE '%PARENT%') "+
        "OR (OWNER='SMS' AND TABLE_NAME='CS_ACCOUNT_ACTION' AND COLUMN_NAME LIKE '%TYPE%') "+
        "ORDER BY COLUMN_NAME");

      q(c, "aa both",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, ACCRUE_TYPE_ID, "+
        "TO_CHAR(ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, "+
        "REF_ACCOUNT_ACTION_ID, REF_DEPOSIT_ACCOUNT_ACTION_ID, INSTALLATION_ID "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (123045786,58633499)");

      q(c, "income 58633499 detail",
        "SELECT ai.ID, ip.CODE, ai.QUANTITY, ai.AMOUNT, ai.STATUS "+
        "FROM SMS.CS_ACCOUNT_INCOME ai JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID "+
        "WHERE ai.ACCOUNT_ACTION_ID=58633499 ORDER BY ai.ID");

      q(c, "same account actions around date",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, aa.ACCRUE_TYPE_ID, "+
        "TO_CHAR(aa.ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, "+
        "(SELECT COUNT(*) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) INC_CNT, "+
        "(SELECT ROUND(SUM(ai.AMOUNT),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) INC_SUM "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "WHERE aa.ACCOUNT_ID=58633499 "+
        "AND aa.ACTION_DATE BETWEEN DATE '2023-06-18' AND DATE '2023-06-21' "+
        "ORDER BY aa.ACTION_DATE, aa.ID");

      q(c, "MIG invoice both ids",
        "SELECT LREF, ABYS_ACTION_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID, FITNO, TYPE "+
        "FROM MIGRATION.LS_INVOICE WHERE LREF IN (123045786,58633499) OR ABYS_ACCOUNT_ID=58633499");

      q(c, "who refs 58633499",
        "SELECT ID, ACTION_TYPE_ID, ACCOUNT_ID, REF_ACCOUNT_ACTION_ID "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE REF_ACCOUNT_ACTION_ID=58633499 AND ROWNUM<=20");

      q(c, "123045786 ref fields full",
        "SELECT * FROM (SELECT aa.* FROM SMS.CS_ACCOUNT_ACTION aa WHERE aa.ID=123045786)");
    }
  }
}