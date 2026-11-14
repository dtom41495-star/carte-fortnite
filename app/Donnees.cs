// Dossiers, reglages (overlay.json) et chiffres (compteur.json) de l'application.
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CarteFortnite;

public static class Chemins
{
    static readonly string AppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    /// <summary>Tout ce que l'appli ecrit est ici : %LOCALAPPDATA%\CarteFortnite (rien n'est ecrit a cote de l'exe).</summary>
    public static readonly string Racine = Path.Combine(AppData, "CarteFortnite");
    /// <summary>Le dossier montre au moteur web : carte.html, ressources\ et donnees\.</summary>
    public static readonly string Site = Path.Combine(Racine, "site");
    public static readonly string Donnees = Path.Combine(Site, "donnees");
    public static readonly string WebView = Path.Combine(Racine, "WebView2");
    public static readonly string Demos = Path.Combine(AppData, "FortniteGame", "Saved", "Demos");
    public static readonly string Cfg = Path.Combine(Donnees, "overlay.json");
    public static readonly string Compteur = Path.Combine(Donnees, "compteur.json");
    public static readonly string DerniereLecture = Path.Combine(Donnees, "derniere-lecture.txt");
    public static readonly string Demande = Path.Combine(Donnees, "demande-lecture.txt");
    public static readonly string LectureFinie = Path.Combine(Donnees, "lecture-finie.txt");
    public static readonly string CarteHtml = Path.Combine(Site, "carte.html");
    public static readonly string Journal = Path.Combine(Donnees, "panneau-erreurs.txt");
}

public sealed class Cfg
{
    [JsonPropertyName("x")] public double X { get; set; } = 20;
    [JsonPropertyName("y")] public double Y { get; set; } = 20;
    [JsonPropertyName("scale")] public double Scale { get; set; } = 0.5;
    [JsonPropertyName("opacity")] public double Opacity { get; set; } = 0.92;
    [JsonPropertyName("compterTombes")] public bool CompterTombes { get; set; } = true;
    [JsonPropertyName("dureeBadgeMinutes")] public double DureeBadgeMinutes { get; set; } = 10;
    [JsonPropertyName("depart")] public int Depart { get; set; } = 0;
    [JsonPropertyName("equipe")] public bool Equipe { get; set; } = false;
    [JsonPropertyName("resume")] public bool Resume { get; set; } = true;
}

public sealed class DerniereInfo
{
    [JsonPropertyName("fichier")] public string Fichier { get; set; }
    [JsonPropertyName("coffres")] public int Coffres { get; set; }
    [JsonPropertyName("tombes")] public int Tombes { get; set; }
    [JsonPropertyName("equipiers")] public int Equipiers { get; set; }
    [JsonPropertyName("place")] public int Place { get; set; }
    [JsonPropertyName("kills")] public int Kills { get; set; }
    [JsonPropertyName("tueur")] public string Tueur { get; set; }
    [JsonPropertyName("tueurPlat")] public string TueurPlat { get; set; }
}

public sealed class CompteurInfo
{
    [JsonPropertyName("coffres")] public int Coffres { get; set; }
    [JsonPropertyName("tombes")] public int Tombes { get; set; }
    [JsonPropertyName("equipiers")] public int Equipiers { get; set; }
    [JsonPropertyName("parties")] public int Parties { get; set; }
    [JsonPropertyName("derniere")] public DerniereInfo Derniere { get; set; }
}

public static class Donnees
{
    static readonly JsonSerializerOptions Opt = new() { PropertyNameCaseInsensitive = true, WriteIndented = true };

    public static void Journal(string message)
    {
        try { Directory.CreateDirectory(Chemins.Donnees); File.AppendAllText(Chemins.Journal, $"{DateTime.Now:s} {message}{Environment.NewLine}"); } catch { }
    }

    public static Cfg LireCfg()
    {
        try { if (File.Exists(Chemins.Cfg)) return JsonSerializer.Deserialize<Cfg>(File.ReadAllText(Chemins.Cfg), Opt) ?? new Cfg(); } catch { }
        return new Cfg();
    }

    public static void EcrireCfg(Cfg c)
    {
        try
        {
            Directory.CreateDirectory(Chemins.Donnees);
            File.WriteAllText(Chemins.Cfg, JsonSerializer.Serialize(c, Opt));
            EcrireReglagesJs(c);
        }
        catch (Exception e) { Journal("EcrireCfg : " + e.Message); }
    }

    /// <summary>La page carte.html lit donnees\reglages.js (nombre de depart, option des coffres tombes).</summary>
    public static void EcrireReglagesJs(Cfg c)
    {
        try
        {
            Directory.CreateDirectory(Chemins.Donnees);
            File.WriteAllText(Path.Combine(Chemins.Donnees, "reglages.js"),
                "window.REGLAGES = " + JsonSerializer.Serialize(new { depart = c.Depart, compterTombes = c.CompterTombes }) + ";");
        }
        catch { }
    }

    public static CompteurInfo LireCompteur()
    {
        try { if (File.Exists(Chemins.Compteur)) return JsonSerializer.Deserialize<CompteurInfo>(File.ReadAllText(Chemins.Compteur), Opt); } catch { }
        return null;
    }

    // Totaux affiches (panneau, compteur, carte) : nombre de depart + coffres lus (+ tombes/casses si l'option est cochee)
    public static int Total(CompteurInfo c, Cfg cfg) => cfg.Depart + c.Coffres + (cfg.CompterTombes ? c.Tombes : 0);

    public static int Derniere(CompteurInfo c, Cfg cfg) =>
        c.Derniere == null ? 0 : c.Derniere.Coffres + (cfg.CompterTombes ? c.Derniere.Tombes : 0);

    // Equipe = moi + mes equipiers (estimation). Le nombre de depart n'est pas compte.
    public static int EquipeTotal(CompteurInfo c, Cfg cfg) => c.Coffres + c.Equipiers + (cfg.CompterTombes ? c.Tombes : 0);

    public static int EquipeDerniere(CompteurInfo c, Cfg cfg) =>
        c.Derniere == null ? 0 : c.Derniere.Coffres + c.Derniere.Equipiers + (cfg.CompterTombes ? c.Derniere.Tombes : 0);
}
