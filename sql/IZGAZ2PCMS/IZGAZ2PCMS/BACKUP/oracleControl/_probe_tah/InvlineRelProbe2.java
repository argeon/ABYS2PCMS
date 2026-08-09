import java.sql.*;
public class InvlineRelProbe2 {
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

      q(c, "aa both",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, ACCRUE_TYPE_ID, "+
        "TO_CHAR(ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, "+
        "REF_DEPOSIT_ACCOUNT_ACTION_ID, REF_DEPOSIT_ACCOUNT_ID "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (123045786,58633499)");

      q(c, "income 58633499",
        "SELECT ai.ID, ip.CODE, ai.QUANTITY, ai.AMOUNT, ai.STATUS "+
        "FROM SMS.CS_ACCOUNT_INCOME ai JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID "+
        "WHERE ai.ACCOUNT_ACTION_ID=58633499 ORDER BY ai.ID");

      q(c, "account 58633499 actions near date",
        "SELECT aa.ID, aa.ACTION_TYPE_ID, aa.ACCRUE_TYPE_ID, "+
        "TO_CHAR(aa.ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, "+
        "(SELECT COUNT(*) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) INC_CNT, "+
        "(SELECT ROUND(SUM(ai.AMOUNT),2) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID) INC_SUM "+
        "FROM SMS.CS_ACCOUNT_ACTION aa "+
        "WHERE aa.ACCOUNT_ID = (SELECT ACCOUNT_ID FROM SMS.CS_ACCOUNT_ACTION WHERE ID=123045786) "+
        "AND aa.ACTION_DATE BETWEEN TIMESTAMP '2023-06-19 00:00:00' AND TIMESTAMP '2023-06-19 23:59:59' "+
        "ORDER BY aa.ID");

      q(c, "MIG inv",
        "SELECT LREF, ABYS_ACTION_ID, ABYS_ACCOUNT_ID, ABYS_ACTION_TYPE_ID, ABYS_ACCRUE_TYPE_ID, FITNO, TYPE "+
        "FROM MIGRATION.LS_INVOICE WHERE LREF IN (123045786,58633499)");

      q(c, "is 58633499 in MIG invoice?",
        "SELECT COUNT(*) C FROM MIGRATION.LS_INVOICE WHERE LREF=58633499 OR ABYS_ACTION_ID=58633499");

      q(c, "type names",
        "SELECT atp.ID, atpl.VALUE FROM SMS.CS_ACTION_TYPE_PRM atp "+
        "LEFT JOIN SMS.CS_ACTION_TYPE_PRM_LNG atpl ON atpl.PRM_ID=atp.ID AND atpl.LANG_ID=1 "+
        "WHERE atp.ID IN (SELECT ACTION_TYPE_ID FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (123045786,58633499))");

      q(c, "account_id of both",
        "SELECT ID, ACCOUNT_ID FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (123045786,58633499)");

      // Why 268 x 941? Check if installment plan expands
      q(c, "income 941 extra cols",
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS WHERE OWNER='SMS' AND TABLE_NAME='CS_ACCOUNT_INCOME' "+
        "AND (COLUMN_NAME LIKE '%INSTALL%' OR COLUMN_NAME LIKE '%PLAN%' OR COLUMN_NAME LIKE '%PARENT%' "+
        "OR COLUMN_NAME LIKE '%REF%' OR COLUMN_NAME LIKE '%GROUP%' OR COLUMN_NAME LIKE '%SEQ%') ORDER BY 1");
    }
  }
}