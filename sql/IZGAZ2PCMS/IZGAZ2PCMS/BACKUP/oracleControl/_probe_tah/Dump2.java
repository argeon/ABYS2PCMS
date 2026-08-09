import java.nio.file.*;
import java.sql.*;
import java.util.*;
public class Dump2 {
  static void dump(Connection c, String table, Path out) throws Exception {
    try (Statement s = c.createStatement(); ResultSet rs = s.executeQuery("SELECT * FROM MIGRATION."+table)) {
      ResultSetMetaData md = rs.getMetaData();
      int cols = md.getColumnCount();
      List<String> lines = new ArrayList<>();
      StringBuilder hdr = new StringBuilder();
      for (int i=1;i<=cols;i++) { if(i>1) hdr.append('\t'); hdr.append(md.getColumnLabel(i)); }
      lines.add(hdr.toString());
      while (rs.next()) {
        StringBuilder row = new StringBuilder();
        for (int i=1;i<=cols;i++) {
          if(i>1) row.append('\t');
          String v = rs.getString(i);
          row.append(v==null?"\\N":v.replace("\t"," ").replace("\n"," ").replace("\r"," "));
        }
        lines.add(row.toString());
      }
      Files.write(out, lines);
      System.out.println(table+"="+(lines.size()-1));
    }
  }
  public static void main(String[] a) throws Exception {
    Path dir = Path.of(a[0]);
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      for (String t: new String[]{"LS_OV_PAY_PT","LS_OV_DEBT_PAID_UPD","LS_OV_CANCEL_PAY","LS_OV_CANCEL_REV","LS_OV_TAH_LOG","LS_OV_TAM_HAS_PAY"})
        dump(c, t, dir.resolve(t+".tsv"));
    }
  }
}