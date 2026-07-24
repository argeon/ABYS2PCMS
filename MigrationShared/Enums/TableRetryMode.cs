namespace MigrationShared.Enums;

public enum TableRetryMode
{
    Resume,    // Kaldığı yerden devam et (checkpoint'teki partition'lardan)
    Truncate,  // Hedef tabloyu TRUNCATE et, sıfırdan başla
    Recreate   // Hedef tabloyu DROP + CREATE et, sıfırdan başla
}
