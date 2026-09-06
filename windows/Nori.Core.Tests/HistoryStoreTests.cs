using Nori.Core;
using Xunit;
using static Nori.Core.Tests.TestRows;

namespace Nori.Core.Tests;

public class HistoryStoreTests
{
    private static DateTimeOffset At(long seconds) => DateTimeOffset.FromUnixTimeSeconds(seconds);

    private static HistoryStore MakeStore(InMemoryClipRepository? repository = null)
    {
        var store = new HistoryStore(repository ?? new InMemoryClipRepository());
        store.Load();
        return store;
    }

    [Fact]
    public void IngestOrdersNewestFirst()
    {
        var store = MakeStore();
        store.Ingest(TextDraft("one"), At(1));
        store.Ingest(TextDraft("two"), At(2));
        Assert.Equal(["two", "one"], store.Rows.Select(r => r.Title));
    }

    [Fact]
    public void DuplicatesBumpInsteadOfInserting()
    {
        var store = MakeStore();
        var first = store.Ingest(TextDraft("same"), At(1));
        store.Ingest(TextDraft("other"), At(2));
        var again = store.Ingest(TextDraft("same", "chrome.exe"), At(3));
        Assert.Equal(first, again);
        Assert.Equal(2, store.Rows.Count);
        var row = store.Row(again)!;
        Assert.Equal(again, store.Rows[0].Id);
        Assert.Equal(2, row.CopyCount);
        Assert.Equal("chrome.exe", row.SourceApp);
        Assert.Equal(At(1), row.FirstCopiedAt);
        Assert.Equal(At(3), row.LastCopiedAt);
    }

    [Fact]
    public void LimitDropsOldestUnpinned()
    {
        var store = MakeStore();
        store.MaxItems = 3;
        for (var i = 0; i < 5; i++) store.Ingest(TextDraft($"item {i}"), At(i));
        Assert.Equal(["item 4", "item 3", "item 2"], store.Rows.Select(r => r.Title));
    }

    [Fact]
    public void PinnedItemsSurviveLimitAndClear()
    {
        var store = MakeStore();
        store.MaxItems = 2;
        var keep = store.Ingest(TextDraft("keep"), At(0));
        store.TogglePin(keep, At(0));
        for (var i = 1; i <= 4; i++) store.Ingest(TextDraft($"item {i}"), At(i));
        Assert.Contains(store.Rows, r => r.Id == keep);
        Assert.Equal(2, store.Rows.Count(r => !r.IsPinned));

        Assert.Equal(2, store.Clear(includingPinned: false));
        Assert.Equal(["keep"], store.Rows.Select(r => r.Title));
        store.Clear(includingPinned: true);
        Assert.Empty(store.Rows);
    }

    [Fact]
    public void DeleteUndoAndPersistence()
    {
        var repository = new InMemoryClipRepository();
        var store = MakeStore(repository);
        var a = store.Ingest(TextDraft("a"), At(1));
        store.TogglePin(a, At(5));
        store.Ingest(TextDraft("b"), At(2));
        var record = store.Delete(a);
        Assert.NotNull(record);
        Assert.Equal(["b"], store.Rows.Select(r => r.Title));
        store.Load();
        Assert.Equal(["b"], store.Rows.Select(r => r.Title));

        var restored = store.Restore(record);
        var row = store.Row(restored)!;
        Assert.Equal("a", row.Title);
        Assert.True(row.IsPinned);
        Assert.Equal(At(1), row.FirstCopiedAt);
        Assert.Equal(["b", "a"], store.Rows.Select(r => r.Title));
        Assert.Equal("a", System.Text.Encoding.UTF8.GetString(store.Contents(restored)[0].Data));
        Assert.Null(store.Delete(Guid.NewGuid()));
    }

    [Fact]
    public void TouchMovesToTop()
    {
        var store = MakeStore();
        var a = store.Ingest(TextDraft("a"), At(1));
        store.Ingest(TextDraft("b"), At(2));
        store.Touch(a, At(3));
        Assert.Equal(a, store.Rows[0].Id);
        Assert.Equal(2, store.Row(a)!.CopyCount);
    }

    [Fact]
    public void ExpiryDropsOldUnpinnedOnly()
    {
        var store = MakeStore();
        store.ExpireAfterDays = 7;
        var now = At(100 * 86_400);
        var old = store.Ingest(TextDraft("old"), now.AddDays(-10));
        var oldPinned = store.Ingest(TextDraft("old pinned"), now.AddDays(-10));
        store.TogglePin(oldPinned, now);
        store.Ingest(TextDraft("fresh"), now.AddDays(-1));
        Assert.Equal(1, store.ExpireOldItems(now));
        Assert.Null(store.Row(old));
        Assert.Equal(["fresh", "old pinned"], store.Rows.Select(r => r.Title).OrderBy(t => t));
        store.ExpireAfterDays = 0;
        Assert.Equal(0, store.ExpireOldItems(now.AddDays(100)));
    }

    [Fact]
    public void LoadRestoresOrderFromTheRepository()
    {
        var repository = new InMemoryClipRepository();
        var store = MakeStore(repository);
        store.Ingest(TextDraft("a"), At(1));
        store.Ingest(TextDraft("b"), At(3));
        store.Ingest(TextDraft("c"), At(2));
        var reloaded = MakeStore(repository);
        Assert.Equal(["b", "c", "a"], reloaded.Rows.Select(r => r.Title));
        Assert.Equal(3, reloaded.Count);
        Assert.Equal(0, reloaded.PinnedCount);
    }

    [Fact]
    public void ClipByHashFindsThePromotedItem()
    {
        var store = MakeStore();
        var draft = TextDraft("promote me");
        var id = store.Ingest(draft, At(1));
        Assert.Equal(id, store.ClipByHash(draft.ContentHash)?.Id);
        Assert.Null(store.ClipByHash("nope"));
    }
}

public class UndoBufferTests
{
    [Fact]
    public void TakeWorksOnlyInsideTheWindowAndOnce()
    {
        var buffer = new UndoBuffer();
        var record = new DeleteRecord(StoredClip.FromDraft(TextDraft("x"), Guid.NewGuid(), T0), []);
        Assert.Null(buffer.Take(T0));
        buffer.Remember(record, T0);
        Assert.True(buffer.HasPending);
        Assert.Same(record, buffer.Take(T0.AddSeconds(3.9)));
        Assert.Null(buffer.Take(T0.AddSeconds(3.9)));
        buffer.Remember(record, T0);
        Assert.Null(buffer.Take(T0.AddSeconds(4.1)));
        Assert.False(buffer.HasPending);
    }
}
