import java.sql.*;
public class InvlineFanoutProbe {
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

      q(c, "1 SMS income raw ACTION=123045786",
        "SELECT COUNT(*) CNT, COUNT(DISTINCT ai.ID) DIST_ID, "+
        "MIN(ai.ID) MIN_ID, MAX(ai.ID) MAX_ID, "+
        "SUM(ai.QUANTITY) SUM_QTY, SUM(ai.AMOUNT) SUM_AMT "+
        "FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=123045786");

      q(c, "2 SMS by INCOME_ID",
        "SELECT ai.INCOME_ID, ip.CODE, COUNT(*) C, SUM(ai.QUANTITY) SUM_Q, "+
        "MIN(ai.QUANTITY) MIN_Q, MAX(ai.QUANTITY) MAX_Q, ROUND(SUM(ai.AMOUNT),2) SUM_A "+
        "FROM SMS.CS_ACCOUNT_INCOME ai "+
        "LEFT JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID "+
        "WHERE ai.ACCOUNT_ACTION_ID=123045786 "+
        "GROUP BY ai.INCOME_ID, ip.CODE ORDER BY COUNT(*) DESC");

      q(c, "3 CTAS join rowcount vs distinct ai",
        "SELECT COUNT(*) JOINED_ROWS, COUNT(DISTINCT ai.ID) DIST_AI "+
        "FROM SMS.CS_ACCOUNT_INCOME ai "+
        "JOIN MIGRATION.LS_INVOICE inv ON inv.ABYS_ACTION_ID=ai.ACCOUNT_ACTION_ID "+
        "LEFT JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID "+
        "LEFT JOIN SMS.CS_INCOME_PRM_LNG ipl ON ipl.PRM_ID=ip.ID AND ipl.LANG_ID=1 "+
        "WHERE ai.ACCOUNT_ACTION_ID=123045786");

      q(c, "4 ipl LANG_ID=1 multi",
        "SELECT ipl.PRM_ID, ip.CODE, COUNT(*) C "+
        "FROM SMS.CS_INCOME_PRM_LNG ipl "+
        "JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ipl.PRM_ID "+
        "WHERE ipl.LANG_ID=1 AND ipl.PRM_ID IN ( "+
        "  SELECT DISTINCT INCOME_ID FROM SMS.CS_ACCOUNT_INCOME WHERE ACCOUNT_ACTION_ID=123045786) "+
        "GROUP BY ipl.PRM_ID, ip.CODE HAVING COUNT(*)>1");

      q(c, "5 MIG LS_INVLINES",
        "SELECT COUNT(*) CNT, COUNT(DISTINCT LREF) DIST_LREF, MIN(LINENR) MN, MAX(LINENR) MX "+
        "FROM MIGRATION.LS_INVLINES WHERE INVOICEREF=123045786");

      q(c, "6 income on 58633499",
        "SELECT COUNT(*) CNT FROM SMS.CS_ACCOUNT_INCOME WHERE ACCOUNT_ACTION_ID=58633499");

      q(c, "7 aa rows",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, TO_CHAR(ACTION_DATE,'YYYY-MM-DD HH24:MI:SS') AD, STATUS "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (123045786,58633499)");

      q(c, "8 global ipl multi LANG1",
        "SELECT COUNT(*) PRM_WITH_MULTI_LANG1 FROM ( "+
        " SELECT PRM_ID FROM SMS.CS_INCOME_PRM_LNG WHERE LANG_ID=1 "+
        " GROUP BY PRM_ID HAVING COUNT(*)>1)");

      q(c, "9 sample 941",
        "SELECT * FROM ( "+
        " SELECT ai.ID, ai.INCOME_ID, ai.QUANTITY, ai.AMOUNT, ai.STATUS "+
        " FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=123045786 AND ai.INCOME_ID=941 "+
        " ORDER BY ai.ID) WHERE ROWNUM<=5");

      q(c, "10 KBAV/1863 rows",
        "SELECT ai.ID, ip.CODE, ai.QUANTITY, ai.AMOUNT, ai.STATUS "+
        "FROM SMS.CS_ACCOUNT_INCOME ai "+
        "JOIN SMS.CS_INCOME_PRM ip ON ip.ID=ai.INCOME_ID "+
        "WHERE ai.ACCOUNT_ACTION_ID=123045786 AND ip.CODE IN ('KBAV','1863') "+
        "ORDER BY ai.ID");
    }
  }
}