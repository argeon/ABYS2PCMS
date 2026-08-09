import java.sql.*;
public class A197 {
  static void q(Connection c,String t,String sql)throws Exception{
    System.out.println("==== "+t);
    try(Statement s=c.createStatement();ResultSet rs=s.executeQuery(sql)){
      var md=rs.getMetaData();int cols=md.getColumnCount();int n=0;
      while(rs.next()){n++;var b=new StringBuilder();
        for(int i=1;i<=cols;i++){if(i>1)b.append(" | ");b.append(md.getColumnLabel(i)).append("=").append(rs.getString(i));}
        System.out.println(b);}
      if(n==0)System.out.println("(0)");
    }
  }
  public static void main(String[] a)throws Exception{
    Class.forName("oracle.jdbc.OracleDriver");
    try(Connection c=DriverManager.getConnection("jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")){
      q(c,"MIG INV","SELECT COUNT(*) INV,ROUND(SUM(NVL(TLTOTAL,0)),2) TL,ROUND(SUM(NVL(GRANDTOTAL,0)),2) GT FROM MIGRATION.LS_INVOICE WHERE ABYS_AGREEMENT_ID=197168");
      q(c,"MIG IL","SELECT COUNT(*) IL,ROUND(SUM(NVL(GRANDTOTAL,0)),2) GT,ROUND(SUM(NVL(ABYS_QUANTITY,0)),2) QTY FROM MIGRATION.LS_INVLINES WHERE ABYS_AGREEMENT_ID=197168");
      q(c,"orphan IL","SELECT COUNT(*) ORPHAN FROM MIGRATION.LS_INVLINES il WHERE ABYS_AGREEMENT_ID=197168 AND NOT EXISTS(SELECT 1 FROM MIGRATION.LS_INVOICE inv WHERE inv.LREF=il.INVOICEREF)");
      q(c,"inv no il","SELECT COUNT(*) INV_NO_IL FROM MIGRATION.LS_INVOICE inv WHERE ABYS_AGREEMENT_ID=197168 AND NOT EXISTS(SELECT 1 FROM MIGRATION.LS_INVLINES il WHERE il.INVOICEREF=inv.LREF)");
      q(c,"SMS AI vs MIG actions","SELECT COUNT(*) SMS_AI,ROUND(SUM(ai.AMOUNT),2) AMT,ROUND(SUM(ai.QUANTITY),2) QTY FROM SMS.CS_ACCOUNT_INCOME ai WHERE ai.ACCOUNT_ACTION_ID IN (SELECT ABYS_ACTION_ID FROM MIGRATION.LS_INVOICE WHERE ABYS_AGREEMENT_ID=197168)");
    }
  }
}