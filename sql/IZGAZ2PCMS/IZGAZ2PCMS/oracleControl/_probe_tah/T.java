import java.sql.*;
public class T {
  public static void main(String[] a) throws Exception {
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      String sql =
        "SELECT COUNT(*) PAY_CNT, "+
        "SUM(CASE WHEN EXISTS (SELECT 1 FROM SMS.CS_ACCOUNT_ACTION CAN "+
        " WHERE CAN.ACCOUNT_ID=PAY.ACCOUNT_ID AND CAN.ACTION_TYPE_ID=9 "+
        " AND CAN.CASH_ID=PAY.CASH_ID AND CAN.RECEIPT_NUMBER=PAY.RECEIPT_NUMBER "+
        " AND NVL(CAN.BANK_PAYMENT_DATE,DATE'1900-01-01')=NVL(PAY.BANK_PAYMENT_DATE,DATE'1900-01-01')) THEN 1 ELSE 0 END) CANC_CNT "+
        "FROM SMS.CS_ACCOUNT_ACTION PAY "+
        "JOIN SMS.CS_ACCOUNT A ON A.ID=PAY.ACCOUNT_ID AND A.AGREEMENT_ID=197168 AND NVL(A.ACCRUE_TYPE_ID,-1)<>14 "+
        "JOIN SMS.CS_ACTION_TYPE_PRM ATP ON ATP.ID=PAY.ACTION_TYPE_ID AND ATP.TYPE=2 "+
        "WHERE PAY.ACTION_TYPE_ID NOT IN (36,37,39,44,6,24)";
      try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
        rs.next();
        System.out.println("PAY_CNT="+rs.getLong(1)+" CANC_MARK="+rs.getLong(2));
      }
      sql = "SELECT EC.KIND, EC.EKS_ACTION_ID, EC.MAIN_LREF, EC.ACCOUNT_ID, EC.EKS_AMT, EC.TAH_AMT, "+
            "(SELECT COUNT(*) FROM SMS.CS_ACCOUNT_ACTION PAY JOIN SMS.CS_ACTION_TYPE_PRM ATP ON ATP.ID=PAY.ACTION_TYPE_ID AND ATP.TYPE=2 "+
            " WHERE PAY.ACCOUNT_ID=EC.ACCOUNT_ID AND PAY.ACTION_TYPE_ID NOT IN (36,37,39,44,6,24) "+
            " AND NOT EXISTS (SELECT 1 FROM SMS.CS_ACCOUNT_ACTION CAN WHERE CAN.ACCOUNT_ID=PAY.ACCOUNT_ID AND CAN.ACTION_TYPE_ID=9 "+
            "  AND CAN.CASH_ID=PAY.CASH_ID AND CAN.RECEIPT_NUMBER=PAY.RECEIPT_NUMBER "+
            "  AND NVL(CAN.BANK_PAYMENT_DATE,DATE'1900-01-01')=NVL(PAY.BANK_PAYMENT_DATE,DATE'1900-01-01'))) VALID_PAY "+
            "FROM MIGRATION.LS_OV_EKS_CLASS EC WHERE EC.KIND='TAM'";
      try (Statement s=c.createStatement(); ResultSet rs=s.executeQuery(sql)) {
        while (rs.next()) {
          System.out.println("TAM eks="+rs.getLong(2)+" main="+rs.getLong(3)+" acc="+rs.getLong(4)+
            " eksAmt="+rs.getDouble(5)+" tahAmt="+rs.getDouble(6)+" validPay="+rs.getLong(7));
        }
      }
    }
  }
}
