using Nori.Core;
using Xunit;
using static Nori.Core.Tests.TestRows;

namespace Nori.Core.Tests;

public class SensitiveVaultTests
{
    private const string Card = "4111 1111 1111 1111";
    private const string AwsKey = "AKIAIOSFODNN7EXAMPLE";

    [Fact]
    public void AddProducesAMaskedRowWithExpiry()
    {
        var vault = new SensitiveVault();
        var id = vault.Add(Sensitive(Card), T0);
        Assert.Single(vault.Entries);
        Assert.Equal(1, vault.Version);
        var entry = vault.Find(id)!;
        Assert.Equal(SecretDetector.Match.CardNumber, entry.Match);
        Assert.Equal(T0, entry.CapturedAt);
        Assert.Equal(T0 + SensitiveVault.Lifetime, entry.ExpiresAt);
        Assert.Equal(TimeSpan.FromMinutes(10), SensitiveVault.Lifetime);

        var row = vault.Rows[0];
        Assert.Equal(id, row.Id);
        Assert.True(row.IsSensitive);
        Assert.Equal("•••• •••• •••• 1111", row.Title);
        Assert.DoesNotContain("4111", row.Title);
        Assert.Equal("", row.SearchText);
        Assert.Equal(entry.ExpiresAt, row.ExpiresAt);
        Assert.Null(row.PinnedAt);
        Assert.Equal(T0, row.LastCopiedAt);
    }

    [Fact]
    public void IdenticalHashReAddExtendsExpiryAndMovesToTop()
    {
        var vault = new SensitiveVault();
        var first = vault.Add(Sensitive(Card), T0);
        var second = vault.Add(Sensitive(AwsKey), T0.AddSeconds(1));
        Assert.Equal([second, first], vault.Rows.Select(r => r.Id));

        var again = vault.Add(Sensitive(Card), T0.AddSeconds(300));
        Assert.Equal(first, again);
        Assert.Equal(2, vault.Entries.Count);
        Assert.Equal([first, second], vault.Rows.Select(r => r.Id));
        var entry = vault.Find(first)!;
        Assert.Equal(T0.AddSeconds(300) + SensitiveVault.Lifetime, entry.ExpiresAt);
        Assert.Equal(T0, entry.CapturedAt);
        Assert.Equal(3, vault.Version);
    }

    [Fact]
    public void TouchExtendsExpiryAndMovesToTop()
    {
        var vault = new SensitiveVault();
        var first = vault.Add(Sensitive(Card), T0);
        var second = vault.Add(Sensitive(AwsKey), T0.AddSeconds(1));
        vault.Touch(first, T0.AddSeconds(500));
        Assert.Equal([first, second], vault.Rows.Select(r => r.Id));
        Assert.Equal(T0.AddSeconds(500) + SensitiveVault.Lifetime, vault.Find(first)!.ExpiresAt);
        var version = vault.Version;
        vault.Touch(Guid.NewGuid(), T0);
        Assert.Equal(version, vault.Version);
    }

    [Fact]
    public void SweepDropsOnlyExpiredEntries()
    {
        var vault = new SensitiveVault();
        var old = vault.Add(Sensitive(Card), T0);
        var fresh = vault.Add(Sensitive(AwsKey), T0.AddSeconds(400));
        var version = vault.Version;

        vault.Sweep(T0.AddSeconds(599));
        Assert.Equal(2, vault.Entries.Count);
        Assert.Equal(version, vault.Version);

        vault.Sweep(T0.AddSeconds(600));
        Assert.Equal([fresh], vault.Rows.Select(r => r.Id));
        Assert.Null(vault.Find(old));
        Assert.Equal(version + 1, vault.Version);

        vault.Sweep(T0.AddSeconds(1_000));
        Assert.Empty(vault.Entries);
    }

    [Fact]
    public void TouchKeepsAnEntryAliveAcrossASweep()
    {
        var vault = new SensitiveVault();
        var id = vault.Add(Sensitive(Card), T0);
        vault.Touch(id, T0.AddSeconds(590));
        vault.Sweep(T0.AddSeconds(700));
        Assert.Single(vault.Entries);
        vault.Sweep(T0.AddSeconds(590 + 600));
        Assert.Empty(vault.Entries);
    }

    [Fact]
    public void RemoveAndRemoveAll()
    {
        var vault = new SensitiveVault();
        var a = vault.Add(Sensitive(Card), T0);
        var b = vault.Add(Sensitive(AwsKey), T0);
        vault.Remove(a);
        Assert.Equal([b], vault.Rows.Select(r => r.Id));
        Assert.Null(vault.Find(a));
        var version = vault.Version;
        vault.RemoveAll();
        Assert.Empty(vault.Entries);
        Assert.Empty(vault.Rows);
        Assert.Equal(version + 1, vault.Version);
    }

    [Fact]
    public void RowsCarryTheDraftMetadata()
    {
        var vault = new SensitiveVault();
        var sensitive = Sensitive(AwsKey);
        sensitive.Draft.SourceApp = "WindowsTerminal.exe";
        sensitive.Draft.SourceAppName = "Terminal";
        vault.Add(sensitive, T0);
        var row = vault.Rows[0];
        Assert.Equal("WindowsTerminal.exe", row.SourceApp);
        Assert.Equal("Terminal", row.SourceAppName);
        Assert.Equal(AwsKey.Length, row.CharacterCount);
        Assert.Equal(AwsKey.Length, row.ByteCount);
        Assert.Equal(1, row.CopyCount);
        Assert.EndsWith("MPLE", row.Title);
    }
}
