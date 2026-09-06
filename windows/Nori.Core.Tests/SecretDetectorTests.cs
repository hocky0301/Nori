using Nori.Core;
using Xunit;

namespace Nori.Core.Tests;

public class SecretDetectorTests
{
    [Theory]
    [InlineData("-----BEGIN RSA PRIVATE KEY-----\nMIIEow...", SecretDetector.Match.PrivateKey)]
    [InlineData("-----BEGIN PRIVATE KEY-----", SecretDetector.Match.PrivateKey)]
    [InlineData("AKIAIOSFODNN7EXAMPLE", SecretDetector.Match.AwsAccessKey)]
    [InlineData("token ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD here", SecretDetector.Match.GitHubToken)]
    [InlineData("github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz", SecretDetector.Match.GitHubFineGrainedToken)]
    [InlineData("sk-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF", SecretDetector.Match.OpenAIKey)]
    [InlineData("xoxb-1234567890-abcdefghij", SecretDetector.Match.SlackToken)]
    [InlineData("AIzaSyD-abcdefghijklmnopqrstuvwxyz01234", SecretDetector.Match.GoogleApiKey)]
    [InlineData("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c", SecretDetector.Match.Jwt)]
    [InlineData("4111 1111 1111 1111", SecretDetector.Match.CardNumber)]
    [InlineData("4242-4242-4242-4242", SecretDetector.Match.CardNumber)]
    [InlineData("378282246310005", SecretDetector.Match.CardNumber)]
    public void Detects(string text, SecretDetector.Match expected)
    {
        Assert.Equal(expected, SecretDetector.Detect(text));
    }

    [Theory]
    [InlineData("4111 1111 1111 1112")]                      // fails Luhn
    [InlineData("1234567890123")]                            // fails Luhn
    [InlineData("9780134685991")]                            // ISBN-13 (Luhn fails)
    [InlineData("3f786850e387550fdab836ed7e6dc881de23001b")] // git SHA
    [InlineData("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")] // SHA-256
    [InlineData("550e8400-e29b-41d4-a716-446655440000")]     // UUID
    [InlineData("SGVsbG8gd29ybGQsIHRoaXMgaXMgYSBiYXNlNjQgc3RyaW5nIQ==")] // base64
    [InlineData("https://example.com/path?token=abc")]
    [InlineData("sk-short")]
    [InlineData("AKIA1234")]
    [InlineData("ghp_short")]
    [InlineData("eyJhbGciOiJIUzI1NiJ9.only-two-parts")]
    [InlineData("The meeting is at 4111 Main Street, room 1111.")]
    [InlineData("brew install --cask nori")]
    [InlineData("12 34 56 78 90 12 34 5")]                   // 15 digits, Luhn fails
    [InlineData("0000 0000 0000 0000 0000")]                 // 20 digits: too long
    [InlineData("")]
    public void Ignores(string text)
    {
        Assert.Null(SecretDetector.Detect(text));
    }

    [Fact]
    public void Masking()
    {
        Assert.Equal("•••• •••• •••• 1111", SecretDetector.Mask("4111 1111 1111 1111"));
        Assert.Equal("•••• •••• •••• •••• MPLE", SecretDetector.Mask("AKIAIOSFODNN7EXAMPLE"));
        var masked = SecretDetector.Mask("ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD");
        Assert.EndsWith("ABCD", masked);
        Assert.DoesNotContain("ghp", masked);
    }

    [Fact]
    public void Luhn()
    {
        Assert.True(SecretDetector.LuhnValid([4, 5, 3, 9, 1, 4, 8, 8, 0, 3, 4, 3, 6, 4, 6, 7]));
        Assert.False(SecretDetector.LuhnValid([4, 5, 3, 9, 1, 4, 8, 8, 0, 3, 4, 3, 6, 4, 6, 8]));
    }

    [Fact]
    public void LabelKeysCoverEveryMatch()
    {
        foreach (var match in Enum.GetValues<SecretDetector.Match>())
        {
            Assert.StartsWith("Secret_", SecretDetector.LabelKey(match));
        }
    }
}
