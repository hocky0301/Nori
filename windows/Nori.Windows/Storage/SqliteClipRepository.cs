using System.IO;
using Microsoft.Data.Sqlite;
using Nori.Core;

namespace Nori.Windows.Storage;

/// <summary>
/// SQLite persistence: an <c>items</c> table with the row metadata (thumbnail inline) and a
/// <c>representations</c> table holding the clipboard blobs. One open connection for the app's
/// lifetime (required for <c>:memory:</c>; harmless for the file store).
/// </summary>
internal sealed class SqliteClipRepository : IClipRepository, IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly string? _path;

    private SqliteClipRepository(SqliteConnection connection, string? path)
    {
        _connection = connection;
        _path = path;
    }

    public static SqliteClipRepository InMemory()
    {
        var connection = new SqliteConnection("Data Source=:memory:");
        connection.Open();
        var repository = new SqliteClipRepository(connection, null);
        repository.CreateSchema();
        return repository;
    }

    /// <summary>Opens %LOCALAPPDATA%\Nori\history.db; a corrupt file is moved aside and a fresh one created.</summary>
    public static SqliteClipRepository Open(string path, out bool wasReset)
    {
        wasReset = false;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        try
        {
            return OpenFile(path);
        }
        catch (SqliteException e)
        {
            Log.Error("history.db could not be opened; moving it aside", e);
            var stamp = DateTimeOffset.Now.ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture);
            foreach (var suffix in new[] { "", "-wal", "-shm" })
            {
                var source = path + suffix;
                if (File.Exists(source)) File.Move(source, $"{path}.broken-{stamp}{suffix}", overwrite: true);
            }
            wasReset = true;
            return OpenFile(path);
        }
    }

    private static SqliteClipRepository OpenFile(string path)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Mode = SqliteOpenMode.ReadWriteCreate }.ToString());
        connection.Open();
        using (var pragma = connection.CreateCommand())
        {
            pragma.CommandText = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;";
            pragma.ExecuteNonQuery();
        }
        var repository = new SqliteClipRepository(connection, path);
        repository.CreateSchema();
        // A quick integrity probe so a damaged file is detected at startup rather than mid-capture.
        using var probe = connection.CreateCommand();
        probe.CommandText = "SELECT COUNT(*) FROM items";
        probe.ExecuteScalar();
        return repository;
    }

    private void CreateSchema()
    {
        using var command = _connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY,
                kind INTEGER NOT NULL,
                title TEXT NOT NULL,
                search_text TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                source_app TEXT,
                source_app_name TEXT,
                source_app_path TEXT,
                first_copied_at INTEGER NOT NULL,
                last_copied_at INTEGER NOT NULL,
                copy_count INTEGER NOT NULL DEFAULT 1,
                pinned_at INTEGER,
                is_rich INTEGER NOT NULL DEFAULT 0,
                is_truncated INTEGER NOT NULL DEFAULT 0,
                line_count INTEGER NOT NULL DEFAULT 0,
                char_count INTEGER NOT NULL DEFAULT 0,
                byte_count INTEGER NOT NULL DEFAULT 0,
                link_url TEXT,
                color_hex TEXT,
                file_paths TEXT,
                image_width INTEGER,
                image_height INTEGER,
                thumbnail BLOB
            );
            CREATE INDEX IF NOT EXISTS items_hash ON items(content_hash);
            CREATE INDEX IF NOT EXISTS items_last ON items(last_copied_at);
            CREATE TABLE IF NOT EXISTS representations (
                item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                format TEXT NOT NULL,
                data BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS representations_item ON representations(item_id);
            PRAGMA foreign_keys=ON;
            """;
        command.ExecuteNonQuery();
    }

    public IReadOnlyList<StoredClip> LoadAll()
    {
        var result = new List<StoredClip>();
        using var command = _connection.CreateCommand();
        command.CommandText = "SELECT id, kind, title, search_text, content_hash, source_app, source_app_name, source_app_path, first_copied_at, last_copied_at, copy_count, pinned_at, is_rich, is_truncated, line_count, char_count, byte_count, link_url, color_hex, file_paths, image_width, image_height, thumbnail FROM items";
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            try
            {
                result.Add(new StoredClip
                {
                    Id = Guid.Parse(reader.GetString(0)),
                    Kind = (ClipKind)reader.GetInt32(1),
                    Title = reader.GetString(2),
                    SearchText = reader.GetString(3),
                    ContentHash = reader.GetString(4),
                    SourceApp = reader.IsDBNull(5) ? null : reader.GetString(5),
                    SourceAppName = reader.IsDBNull(6) ? null : reader.GetString(6),
                    SourceAppPath = reader.IsDBNull(7) ? null : reader.GetString(7),
                    FirstCopiedAt = FromMillis(reader.GetInt64(8)),
                    LastCopiedAt = FromMillis(reader.GetInt64(9)),
                    CopyCount = reader.GetInt32(10),
                    PinnedAt = reader.IsDBNull(11) ? null : FromMillis(reader.GetInt64(11)),
                    IsRichText = reader.GetInt32(12) != 0,
                    IsTruncated = reader.GetInt32(13) != 0,
                    LineCount = reader.GetInt32(14),
                    CharacterCount = reader.GetInt32(15),
                    ByteCount = reader.GetInt32(16),
                    LinkUrl = reader.IsDBNull(17) ? null : Uri.TryCreate(reader.GetString(17), UriKind.Absolute, out var uri) ? uri : null,
                    ColorHex = reader.IsDBNull(18) ? null : reader.GetString(18),
                    FilePaths = reader.IsDBNull(19) ? [] : reader.GetString(19).Split('\n', StringSplitOptions.RemoveEmptyEntries),
                    ImagePixelSize = reader.IsDBNull(20) || reader.IsDBNull(21) ? null : (reader.GetInt32(20), reader.GetInt32(21)),
                    Thumbnail = reader.IsDBNull(22) ? null : (byte[])reader[22],
                });
            }
            catch (Exception e) when (e is FormatException or InvalidCastException)
            {
                Log.Warn($"skipping an unreadable history row: {e.Message}");
            }
        }
        return result;
    }

    public void Insert(StoredClip clip, IReadOnlyList<ClipContent> contents)
    {
        using var transaction = _connection.BeginTransaction();
        using (var command = _connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                INSERT OR REPLACE INTO items (id, kind, title, search_text, content_hash, source_app, source_app_name, source_app_path,
                    first_copied_at, last_copied_at, copy_count, pinned_at, is_rich, is_truncated, line_count, char_count, byte_count,
                    link_url, color_hex, file_paths, image_width, image_height, thumbnail)
                VALUES ($id, $kind, $title, $search, $hash, $app, $appName, $appPath, $first, $last, $count, $pinned, $rich, $truncated,
                    $lines, $chars, $bytes, $link, $color, $files, $w, $h, $thumb)
                """;
            Bind(command, clip);
            command.ExecuteNonQuery();
        }
        using (var clear = _connection.CreateCommand())
        {
            clear.Transaction = transaction;
            clear.CommandText = "DELETE FROM representations WHERE item_id = $id";
            clear.Parameters.AddWithValue("$id", clip.Id.ToString());
            clear.ExecuteNonQuery();
        }
        for (var i = 0; i < contents.Count; i++)
        {
            using var command = _connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "INSERT INTO representations (item_id, position, format, data) VALUES ($id, $position, $format, $data)";
            command.Parameters.AddWithValue("$id", clip.Id.ToString());
            command.Parameters.AddWithValue("$position", i);
            command.Parameters.AddWithValue("$format", contents[i].Format);
            command.Parameters.AddWithValue("$data", contents[i].Data);
            command.ExecuteNonQuery();
        }
        transaction.Commit();
    }

    public void Update(StoredClip clip)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = """
            UPDATE items SET kind=$kind, title=$title, search_text=$search, content_hash=$hash, source_app=$app, source_app_name=$appName,
                source_app_path=$appPath, first_copied_at=$first, last_copied_at=$last, copy_count=$count, pinned_at=$pinned, is_rich=$rich,
                is_truncated=$truncated, line_count=$lines, char_count=$chars, byte_count=$bytes, link_url=$link, color_hex=$color,
                file_paths=$files, image_width=$w, image_height=$h, thumbnail=$thumb
            WHERE id=$id
            """;
        Bind(command, clip);
        command.ExecuteNonQuery();
    }

    public void Delete(IReadOnlyList<Guid> ids)
    {
        if (ids.Count == 0) return;
        using var transaction = _connection.BeginTransaction();
        foreach (var id in ids)
        {
            using var command = _connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM representations WHERE item_id = $id; DELETE FROM items WHERE id = $id";
            command.Parameters.AddWithValue("$id", id.ToString());
            command.ExecuteNonQuery();
        }
        transaction.Commit();
    }

    public IReadOnlyList<ClipContent> Contents(Guid id)
    {
        var result = new List<ClipContent>();
        using var command = _connection.CreateCommand();
        command.CommandText = "SELECT format, data FROM representations WHERE item_id = $id ORDER BY position";
        command.Parameters.AddWithValue("$id", id.ToString());
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            result.Add(new ClipContent(reader.GetString(0), (byte[])reader[1]));
        }
        return result;
    }

    public long StorageBytes()
    {
        if (_path is not null && File.Exists(_path))
        {
            try
            {
                return new FileInfo(_path).Length + (File.Exists(_path + "-wal") ? new FileInfo(_path + "-wal").Length : 0);
            }
            catch (IOException)
            {
            }
        }
        using var command = _connection.CreateCommand();
        command.CommandText = "SELECT COALESCE(SUM(LENGTH(data)), 0) FROM representations";
        return Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
    }

    private static void Bind(SqliteCommand command, StoredClip clip)
    {
        var p = command.Parameters;
        p.AddWithValue("$id", clip.Id.ToString());
        p.AddWithValue("$kind", (int)clip.Kind);
        p.AddWithValue("$title", clip.Title);
        p.AddWithValue("$search", clip.SearchText);
        p.AddWithValue("$hash", clip.ContentHash);
        p.AddWithValue("$app", (object?)clip.SourceApp ?? DBNull.Value);
        p.AddWithValue("$appName", (object?)clip.SourceAppName ?? DBNull.Value);
        p.AddWithValue("$appPath", (object?)clip.SourceAppPath ?? DBNull.Value);
        p.AddWithValue("$first", clip.FirstCopiedAt.ToUnixTimeMilliseconds());
        p.AddWithValue("$last", clip.LastCopiedAt.ToUnixTimeMilliseconds());
        p.AddWithValue("$count", clip.CopyCount);
        p.AddWithValue("$pinned", clip.PinnedAt is { } pinned ? pinned.ToUnixTimeMilliseconds() : DBNull.Value);
        p.AddWithValue("$rich", clip.IsRichText ? 1 : 0);
        p.AddWithValue("$truncated", clip.IsTruncated ? 1 : 0);
        p.AddWithValue("$lines", clip.LineCount);
        p.AddWithValue("$chars", clip.CharacterCount);
        p.AddWithValue("$bytes", clip.ByteCount);
        p.AddWithValue("$link", (object?)clip.LinkUrl?.OriginalString ?? DBNull.Value);
        p.AddWithValue("$color", (object?)clip.ColorHex ?? DBNull.Value);
        p.AddWithValue("$files", clip.FilePaths.Count > 0 ? string.Join('\n', clip.FilePaths) : DBNull.Value);
        p.AddWithValue("$w", clip.ImagePixelSize is { } size ? size.Width : DBNull.Value);
        p.AddWithValue("$h", clip.ImagePixelSize is { } size2 ? size2.Height : DBNull.Value);
        p.AddWithValue("$thumb", (object?)clip.Thumbnail ?? DBNull.Value);
    }

    private static DateTimeOffset FromMillis(long millis) => DateTimeOffset.FromUnixTimeMilliseconds(millis).ToLocalTime();

    public void Dispose() => _connection.Dispose();
}
