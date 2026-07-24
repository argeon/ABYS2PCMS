import java.sql.*;
public class MahProbe {
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
      q(c,"AA cols mahsup-ish",
        "SELECT column_name FROM all_tab_columns WHERE owner='SMS' AND table_name='CS_ACCOUNT_ACTION' "+
        "AND (UPPER(column_name) LIKE '%REF%' OR UPPER(column_name) LIKE '%DEPOSIT%' OR UPPER(column_name) LIKE '%CASH%' OR UPPER(column_name) LIKE '%RECEIPT%' OR UPPER(column_name) LIKE '%PARENT%') ORDER BY 1");
      q(c,"sample mahsup 60940043",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, ACTION_DATE, CASH_ID, RECEIPT_NUMBER, "+
        "REF_DEPOSIT_ACCOUNT_ID, REF_DEPOSIT_ACCOUNT_ACTION_ID, REF_ACCOUNT_ACTION_ID, PARENT_ID, DESCRIPTION "+
        "FROM SMS.CS_ACCOUNT_ACTION WHERE ID IN (60940043,60940054,60940061)");
      q(c,"same cash/receipt cluster for 60940043",
        "SELECT ID, ACCOUNT_ID, ACTION_TYPE_ID, CASH_ID, RECEIPT_NUMBER, REF_DEPOSIT_ACCOUNT_ACTION_ID, "+
        "ROUND((SELECT SUM(ai.AMOUNT*ai.STATUS) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=aa.ID),2) AMT "+
        "FROM SMS.CS_ACCOUNT_ACTION aa WHERE aa.CASH_ID=(SELECT CASH_ID FROM SMS.CS_ACCOUNT_ACTION WHERE ID=60940043) "+
        "AND aa.RECEIPT_NUMBER=(SELECT RECEIPT_NUMBER FROM SMS.CS_ACCOUNT_ACTION WHERE ID=60940043) ORDER BY ID");
      q(c,"pilot mahsup groups by REF_DEPOSIT",
        "SELECT NVL(pay.REF_DEPOSIT_ACCOUNT_ACTION_ID,0) DEP_ACT, COUNT(*) CNT, "+
        "ROUND(SUM(ABS((SELECT SUM(ai.AMOUNT*ai.STATUS) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=pay.ID))),2) AMT "+
        "FROM SMS.CS_ACCOUNT_ACTION pay "+
        "JOIN SMS.CS_ACCOUNT a ON a.ID=pay.ACCOUNT_ID AND a.AGREEMENT_ID=197168 "+
        "WHERE pay.ACTION_TYPE_ID IN (6,24) "+
        "AND ABS(NVL((SELECT SUM(ai.AMOUNT*ai.STATUS) FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID=pay.ID),0))>0.0001 "+
        "GROUP BY NVL(pay.REF_DEPOSIT_ACCOUNT_ACTION_ID,0) ORDER BY CNT DESC");
      q(c,"one deposit covering many mains",
        "SELECT pay.ID MAHSUP, pay.ACCOUNT_ID, pay.REF_DEPOSIT_ACCOUNT_ACTION_ID DEP, "+
        "p.CROSSREF_MAIN_LREF MAIN, p.PAYABLETOTAL "+
        "FROM MIGRATION.LS_OV_PAY_PT p "+
        "JOIN SMS.CS_ACCOUNT_ACTION pay ON pay.ID=p.LREF "+
        "WHERE p.OV_KIND='MAHSUP' ORDER BY NVL(pay.REF_DEPOSIT_ACCOUNT_ACTION_ID,0), p.LREF");
    }
  }
}