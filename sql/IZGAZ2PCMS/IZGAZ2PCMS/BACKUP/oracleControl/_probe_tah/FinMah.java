import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.regex.*;
public class FinMah {
  static String stripComments(String s) {
    StringBuilder b = new StringBuilder();
    for (String line : s.split("\n", -1)) {
      if (line.trim().startsWith("--")) continue;
      b.append(line).append('\n');
    }
    return b.toString();
  }
  static List<String> stmts(String raw) {
    List<String> out = new ArrayList<>();
    String[] parts = stripComments(raw).split("(?m)^\\s*/\\s*$");
    for (String part : parts) {
      String p = part.trim();
      if (p.isEmpty()) continue;
      String up = p.toUpperCase(Locale.ROOT);
      if (up.contains("DECLARE") || up.trim().startsWith("BEGIN")) {
        if (!p.trim().endsWith(";")) p = p + ";";
        out.add(p);
      } else {
        for (String s : p.split(";")) {
          String t = s.trim();
          if (!t.isEmpty()) out.add(t);
        }
      }
    }
    return out;
  }
  public static void main(String[] a) throws Exception {
    String raw = Files.readString(Path.of(a[0]));
    if (raw.startsWith("\uFEFF")) raw = raw.substring(1);
    int idx = raw.indexOf("LS_OV_MAHSUP_CLOSED");
    // find DROP for MAHSUP_CLOSED
    int drop = raw.lastIndexOf("DROP TABLE MIGRATION.LS_OV_MAHSUP_CLOSED", idx+1);
    if (drop < 0) drop = raw.indexOf("DROP TABLE MIGRATION.LS_OV_MAHSUP_CLOSED");
    // go back to BEGIN
    int begin = raw.lastIndexOf("BEGIN", drop);
    raw = raw.substring(begin);
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      c.setAutoCommit(true);
      List<String> list = stmts(raw);
      int i=0;
      for (String sql : list) {
        i++;
        System.out.println("--- " + i + "/" + list.size() + " ---");
        System.out.println(sql.substring(0, Math.min(90, sql.length())).replace('\n',' '));
        try (Statement s = c.createStatement()) {
          boolean has = s.execute(sql);
          if (has) {
            try (ResultSet rs = s.getResultSet()) {
              ResultSetMetaData md = rs.getMetaData();
              int cols = md.getColumnCount();
              while (rs.next()) {
                StringBuilder row = new StringBuilder();
                for (int col=1; col<=cols; col++) {
                  if (col>1) row.append(" | ");
                  row.append(md.getColumnLabel(col)).append("=").append(rs.getString(col));
                }
                System.out.println(row);
              }
            }
          } else System.out.println("ok uc=" + s.getUpdateCount());
        }
      }
      System.out.println("DONE");
    }
  }
}