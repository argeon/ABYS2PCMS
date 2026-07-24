import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.regex.*;
public class RunTah {
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
    Matcher m = Pattern.compile("(?im)^\\s*ALTER SESSION[^;]*;").matcher(raw);
    while (m.find()) out.add(m.group().trim().replaceAll(";\\s*$",""));
    raw = m.replaceAll("");
    String[] parts = stripComments(raw).split("(?m)^\\s*/\\s*$");
    for (String part : parts) {
      String p = part.trim();
      if (p.isEmpty()) continue;
      String up = p.toUpperCase(Locale.ROOT);
      // Slash bolumu CREATE+BEGIN karisik olabilir; BEGIN...END blogunu ayir.
      boolean hasPlsql = up.startsWith("DECLARE") || up.startsWith("BEGIN")
          || up.contains("\nBEGIN") || up.contains("\r\nBEGIN")
          || (up.contains("BEGIN") && up.contains("END"));
      if (hasPlsql && (up.startsWith("DECLARE") || up.startsWith("BEGIN"))) {
        if (!p.trim().endsWith(";")) p = p + ";";
        out.add(p);
      } else if (hasPlsql) {
        // Once saf SQL (;), sonra trailing BEGIN...END
        int bi = Math.max(up.lastIndexOf("\nBEGIN"), up.indexOf("BEGIN"));
        if (bi > 0) {
          String head = p.substring(0, bi).trim();
          String tail = p.substring(bi).trim();
          for (String s : head.split(";")) {
            String t = s.trim();
            if (t.isEmpty()) continue;
            String tu = t.toUpperCase(Locale.ROOT);
            if (tu.startsWith("PROMPT ") || tu.equals("PROMPT")
                || tu.startsWith("SET ") || tu.startsWith("EXIT")
                || tu.startsWith("SPOOL ") || tu.startsWith("HOST "))
              continue;
            out.add(t);
          }
          if (!tail.endsWith(";")) tail = tail + ";";
          out.add(tail);
        } else {
          if (!p.trim().endsWith(";")) p = p + ";";
          out.add(p);
        }
      } else {
        for (String s : p.split(";")) {
          String t = s.trim();
          if (t.isEmpty()) continue;
          String tu = t.toUpperCase(Locale.ROOT);
          if (tu.startsWith("PROMPT ") || tu.equals("PROMPT")
              || tu.startsWith("SET ") || tu.startsWith("EXIT")
              || tu.startsWith("SPOOL ") || tu.startsWith("HOST "))
            continue;
          out.add(t);
        }
      }
    }
    return out;
  }
  public static void main(String[] a) throws Exception {
    String raw = Files.readString(Path.of(a[0]));
    if (raw.startsWith("\uFEFF")) raw = raw.substring(1);
    Class.forName("oracle.jdbc.OracleDriver");
    try (Connection c = DriverManager.getConnection(
        "jdbc:oracle:thin:@//172.16.1.201:1521/izgaz","SMS","RepSmS26!IzGx")) {
      c.setAutoCommit(true);
      List<String> list = stmts(raw);
      int i=0;
      for (String sql : list) {
        i++;
        System.out.println("--- " + i + "/" + list.size() + " ---");
        System.out.println(sql.substring(0, Math.min(100, sql.length())).replace('\n',' '));
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
        } catch (SQLException e) {
          System.out.println("ERROR: " + e.getMessage());
          throw e;
        }
      }
      System.out.println("DONE");
    }
  }
}