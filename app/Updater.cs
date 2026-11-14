// Mise a jour : au lancement, on regarde la derniere "Release" du depot GitHub ; si elle est plus recente, on propose de la telecharger.
// L'exe telecharge est verifie (empreinte SHA-256 publiee avec la Release) avant de remplacer l'exe actuel.
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;

namespace CarteFortnite;

public sealed record InfoMaj(Version Version, string Tag, string UrlExe, string Sha256, string Notes);

public static class Updater
{
    const string Depot = "dtom41495-star/carte-fortnite";
    const string PrefixeTelechargement = "https://github.com/" + Depot + "/releases/download/";
    const string NomExe = "CarteFortnite.exe";

    static readonly HttpClient Http = CreerClient();

    static HttpClient CreerClient()
    {
        var h = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        h.DefaultRequestHeaders.UserAgent.ParseAdd("CarteFortnite-Updater");      // GitHub exige un User-Agent (nom generique, aucune donnee perso)
        h.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return h;
    }

    public static Version VersionActuelle
    {
        get
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v == null ? new Version(0, 0, 0) : new Version(v.Major, v.Minor, Math.Max(v.Build, 0));
        }
    }

    public static string VersionTexte => VersionActuelle.ToString(3);

    /// <summary>Supprime l'ancien exe laisse par la derniere mise a jour.</summary>
    public static void Nettoyer()
    {
        try { var old = Environment.ProcessPath + ".old"; if (File.Exists(old)) File.Delete(old); } catch { }
        try { var nw = Environment.ProcessPath + ".new"; if (File.Exists(nw)) File.Delete(nw); } catch { }
    }

    /// <summary>Renvoie la mise a jour disponible, ou null (a jour, hors ligne, rien de publie...). Ne leve jamais d'exception.</summary>
    public static async Task<InfoMaj> VerifierAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            var json = await Http.GetStringAsync($"https://api.github.com/repos/{Depot}/releases/latest", cts.Token);
            using var doc = JsonDocument.Parse(json);
            var r = doc.RootElement;
            var tag = r.GetProperty("tag_name").GetString() ?? "";
            if (!Version.TryParse(tag.TrimStart('v', 'V'), out var v)) return null;
            if (v <= VersionActuelle) return null;

            string url = null, sha = null, urlSha = null;
            foreach (var a in r.GetProperty("assets").EnumerateArray())
            {
                var nom = a.GetProperty("name").GetString();
                var dl = a.GetProperty("browser_download_url").GetString();
                if (nom == NomExe)
                {
                    url = dl;
                    if (a.TryGetProperty("digest", out var d) && d.ValueKind == JsonValueKind.String && d.GetString().StartsWith("sha256:"))
                        sha = d.GetString().Substring(7);
                }
                else if (nom == NomExe + ".sha256") urlSha = dl;
            }
            if (url == null || !url.StartsWith(PrefixeTelechargement)) return null;
            if (sha == null && urlSha != null && urlSha.StartsWith(PrefixeTelechargement))
            {
                var txt = await Http.GetStringAsync(urlSha, cts.Token);
                sha = txt.Trim().Split(' ', '\t', '\r', '\n')[0];
            }
            if (string.IsNullOrWhiteSpace(sha) || sha.Length != 64) return null;      // pas d'empreinte : on ne met pas a jour
            var notes = r.TryGetProperty("body", out var b) && b.ValueKind == JsonValueKind.String ? b.GetString() : "";
            return new InfoMaj(v, tag, url, sha.ToLowerInvariant(), notes ?? "");
        }
        catch (Exception e) { Donnees.Journal("Verification de mise a jour : " + e.Message); return null; }
    }

    /// <summary>Telecharge, verifie, remplace l'exe puis relance. En cas d'erreur : leve une exception et ne change rien.</summary>
    public static async Task AppliquerAsync(InfoMaj maj, IProgress<int> progression)
    {
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Chemin de l'exe introuvable.");
        var nouveau = exe + ".new";
        var old = exe + ".old";
        try
        {
            using (var rep = await Http.GetAsync(maj.UrlExe, HttpCompletionOption.ResponseHeadersRead))
            {
                rep.EnsureSuccessStatusCode();
                var total = rep.Content.Headers.ContentLength ?? 0;
                await using var src = await rep.Content.ReadAsStreamAsync();
                await using var dst = File.Create(nouveau);
                var buf = new byte[81920]; long lu = 0; int n;
                while ((n = await src.ReadAsync(buf)) > 0)
                {
                    await dst.WriteAsync(buf.AsMemory(0, n));
                    lu += n;
                    if (total > 0) progression?.Report((int)(lu * 100 / total));
                }
            }
            string empreinte;
            await using (var f = File.OpenRead(nouveau)) empreinte = Convert.ToHexString(await SHA256.HashDataAsync(f)).ToLowerInvariant();
            if (empreinte != maj.Sha256) throw new InvalidDataException("L'empreinte du fichier telecharge ne correspond pas : mise a jour annulee.");
            var taille = new FileInfo(nouveau).Length;
            if (taille < 1_000_000) throw new InvalidDataException("Le fichier telecharge est trop petit : mise a jour annulee.");

            // Windows permet de renommer un programme en cours d'execution : l'ancien exe devient .old, le nouveau prend sa place.
            if (File.Exists(old)) File.Delete(old);
            File.Move(exe, old);
            try { File.Move(nouveau, exe); }
            catch { File.Move(old, exe); throw; }
        }
        catch
        {
            try { if (File.Exists(nouveau)) File.Delete(nouveau); } catch { }
            throw;
        }
        Process.Start(new ProcessStartInfo(exe, "--apres-maj") { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(exe) });
    }
}
