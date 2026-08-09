import java.nio.file.*;
import java.sql.*;
import java.util.*;
public class DumpLog2 {
  public static void main(String[] a) throws Exception {
    Path out = Path.of(a[0]);
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx");
         Statement s = c.createStatement();
         ResultSet rs = s.executeQuery("SELECT * FROM MIGRATION.LS_OV_TAH_LOG ORDER BY LOG_ID")) {
      ResultSetMetaData md = rs.getMetaData();
      int cols = md.getColumnCount();
      List<String> lines = new ArrayList<>();
      StringBuilder hdr = new StringBuilder();
      for (int i=1;i<=cols;i++) { if (i>1) hdr.append('\t'); hdr.append(md.getColumnLabel(i)); }
      lines.add(hdr.toString());
      while (rs.next()) {
        StringBuilder row = new StringBuilder();
        for (int i=1;i<=cols;i++) {
          if (i>1) row.append('\t');
          String v = rs.getString(i);
          if (v == null) row.append("\\N");
          else row.append(v.replace("\t"," ").replace("\n"," ").replace("\r"," "));
        }
        lines.add(row.toString());
      }
      Files.write(out, lines);
      System.out.println("dumped rows="+(lines.size()-1));
    }
  }
}