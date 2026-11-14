// CarteReplay : lit les replays Fortnite (lecture seule) et ecrit les donnees de la page carte.html :
//   - ton trace de partie, - tes coffres (positions), - ou tu atterris, - ou les autres atterrissent.
// Usage : CarteReplay [dossier ou fichier .replay] [--sortie dossier] [--force] [--attente secondes]
//         CarteReplay --surveiller --parent <pid> [--attente 25] [--sortie dossier] [dossier de replays]
// Le mode --surveiller reste en veille (lance UNE fois au demarrage de l'application) : il lit les replays tout seul quand une partie se
// termine, ou sur demande (fichier donnees\demande-lecture.txt). Ainsi l'application n'a plus a lancer de programme pendant le jeu.
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using FortniteReplayReader;
using FortniteReplayReader.Models;
using FortniteReplayReader.Models.NetFieldExports;
using Unreal.Core.Contracts;
using Unreal.Core.Models;
using Unreal.Core.Models.Enums;

string input = Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "", "FortniteGame", "Saved", "Demos");
string outDir = Path.Combine(Directory.GetCurrentDirectory(), "donnees");
bool force = false;
bool surveiller = false;
int parentPid = 0;
int attente = 90;   // secondes sans ecriture avant de lire un replay (25 pour la surveillance : lecture des la fin de partie)
for (int i = 0; i < args.Length; i++)
{
    if (args[i] == "--sortie" && i + 1 < args.Length) outDir = args[++i];
    else if (args[i] == "--force") force = true;
    else if (args[i] == "--surveiller") surveiller = true;
    else if (args[i] == "--parent" && i + 1 < args.Length) parentPid = int.Parse(args[++i]);
    else if (args[i] == "--attente" && i + 1 < args.Length) attente = int.Parse(args[++i]);
    else input = args[i];
}
return surveiller ? Lecteur.Surveiller(input, outDir, attente, parentPid) : Lecteur.Executer(input, outDir, force, attente);

static class Lecteur
{
    /// <summary>Lit les replays une fois et ecrit parties.json / parties.js / compteur.json.</summary>
    public static int Executer(string input, string outDir, bool force, int attente)
    {
        Directory.CreateDirectory(outDir);
        var jsonPath = Path.Combine(outDir, "parties.json");
        var jopt = new JsonSerializerOptions { WriteIndented = false };
        Dictionary<string, MapMatch> all = new();
        if (File.Exists(jsonPath))
        {
            try { all = JsonSerializer.Deserialize<Dictionary<string, MapMatch>>(File.ReadAllText(jsonPath), jopt) ?? new(); }
            catch
            {
                // Ancien format : on le garde de cote et on refait l'analyse des replays encore presents.
                File.Move(jsonPath, Path.Combine(outDir, "parties.ancien.json"), true);
                Console.WriteLine("Ancien format de donnees : sauvegarde dans parties.ancien.json, nouvelle analyse.");
            }
        }

        const string Aide = "  -> Dans Fortnite : Parametres > Jeu > active l'enregistrement des replays, puis joue une partie JUSQU'AU BOUT (ou quitte-la), et relance.\n"
            + "  -> Fortnite sur console (PS5, Xbox, Switch) : aucun replay n'est stocke sur le PC, ca ne marche que sur PC.\n"
            + "  -> Si tes replays sont ailleurs : generer-carte.bat \"D:\\ton\\dossier\"";
        if (!File.Exists(input) && !Directory.Exists(input)) { Console.WriteLine($"Dossier de replays introuvable : {input}\n{Aide}"); }
        var files = File.Exists(input) ? new[] { input } : Directory.Exists(input) ? Directory.GetFiles(input, "*.replay") : Array.Empty<string>();
        Console.WriteLine($"Dossier lu : {input}");
        Console.WriteLine($"{files.Length} replay(s) trouve(s).");
        if (files.Length == 0 && Directory.Exists(input)) Console.WriteLine("Le dossier existe mais il est vide.\n" + Aide);

        foreach (var f in files.OrderBy(f => f))
        {
            var info = new FileInfo(f);
            if (!force && all.TryGetValue(info.Name, out var old) && old.Size == info.Length) { Console.WriteLine($"  deja fait : {info.Name}"); continue; }
            if ((DateTime.Now - info.LastWriteTime).TotalSeconds < attente) { Console.WriteLine($"  ignore (en cours d'ecriture) : {info.Name}"); continue; }
            try
            {
                var m = Analyse.Run(f);
                m.Size = info.Length;
                all[info.Name] = m;
                Console.WriteLine($"  OK {info.Name}");
                Console.WriteLine($"     joueur {m.Player} | trace {m.Path.Count} pts | atterrissage {(m.Landing != null ? "oui" : "non")} | coffres {m.Chests.Count(c => c.K == "coffre")} (+{m.Chests.Count(c => c.K != "coffre")} autres conteneurs) | autres joueurs suivis {m.Others.Count(o => o.Path.Count > 1)} (dont {m.Others.Count(o => o.Landed)} atterris)");
                var mates = string.Join(", ", m.Others.Where(o => o.Mate).Select(o => (o.N ?? "?") + " (" + m.Others.Where(q => q == o).Sum(q => q.Chests.Count(c => c.K == "coffre")) + " coffre(s))"));
                Console.WriteLine($"     equipier(s) : {(mates.Length > 0 ? mates : "aucun")} | joueurs humains : {m.Others.Count(o => !o.Bot)} | conteneurs ouverts par tout le monde : {m.Boxes.Count} | coffres peut-etre tombes/casses par toi (estimation) : {m.Falls.Count(f => f[5] == 0)}");
            }
            catch (Exception e) { Console.WriteLine($"  ECHEC {info.Name} : {e.Message}"); }
        }
        File.WriteAllText(jsonPath, JsonSerializer.Serialize(all, jopt));
        File.WriteAllText(Path.Combine(outDir, "parties.js"), "window.PARTIES = " + JsonSerializer.Serialize(all.Values.OrderBy(v => v.Date), jopt) + ";");
        // Petit fichier lu par la fenetre overlay (overlay\overlay.ps1) : coffres sur de vrais coffres ouverts, et estimes (tombes / casses).
        var totCoffres = all.Values.Sum(v => v.Chests.Count(c => c.K == "coffre"));
        var totTombes = all.Values.Sum(v => v.Falls.Count(f => f[5] == 0));
        var totEquipiers = all.Values.Sum(v => EquipiersCoffres(v));
        File.WriteAllText(Path.Combine(outDir, "compteur.json"),
            JsonSerializer.Serialize(new
            {
                coffres = totCoffres, tombes = totTombes, equipiers = totEquipiers, parties = all.Count, maj = DateTime.Now.ToString("s"),
                // la partie la plus recente : sert a afficher "+N" dans l'overlay a la fin d'une partie
                derniere = all.Values.OrderBy(v => v.Date).Select(v => new
                {
                    fichier = v.Id,
                    coffres = v.Chests.Count(c => c.K == "coffre"),
                    tombes = v.Falls.Count(f => f[5] == 0),
                    equipiers = EquipiersCoffres(v),
                    // le mini-resume de la partie (affiche par le petit compteur a la fin de la partie)
                    place = v.Placement ?? 0,
                    kills = v.Kills ?? 0,
                    tueur = v.Killer?.Kind ?? "",
                    tueurPlat = v.Killer?.Plat ?? "",
                }).LastOrDefault(),
            }));
        Console.WriteLine($"Ecrit : {Path.Combine(outDir, "parties.js")} ({all.Count} partie(s)) | coffres : {totCoffres} + {totTombes} tombes/casses (estimation) | coffres des equipiers (estimation) : {totEquipiers}");
        if (all.Count == 0) Console.WriteLine("Aucune partie analysee : la carte sera vide tant qu'il n'y a pas de replay lu.");
        return 0;
    }

    /// <summary>Coffres de tes equipiers dans une partie (ESTIMATION : le replay ne dit "debut de fouille" que pour toi, on compte les
    /// coffres ouverts a moins de 4,5 m d'un equipier au moment ou ils s'ouvrent, et pas par toi). Ils ne comptent PAS dans ton total.</summary>
    static int EquipiersCoffres(MapMatch v) => v.Others.Where(o => o.Mate).Sum(o => o.Chests.Count(c => c.K == "coffre"));

    static bool ParentVivant(int pid)
    {
        if (pid <= 0) return true;
        try { using var p = Process.GetProcessById(pid); return !p.HasExited; } catch { return false; }
    }

    static string Signature(string dossier)
    {
        if (!Directory.Exists(dossier)) return "";
        return string.Join(";", Directory.GetFiles(dossier, "*.replay").OrderBy(f => f).Select(f => Path.GetFileName(f) + "|" + new FileInfo(f).Length));
    }

    static double AgeDuPlusRecent(string dossier)
    {
        if (!Directory.Exists(dossier)) return double.MaxValue;
        var fichiers = Directory.GetFiles(dossier, "*.replay");
        if (fichiers.Length == 0) return double.MaxValue;
        return (DateTime.Now - fichiers.Max(f => new FileInfo(f).LastWriteTime)).TotalSeconds;
    }

    /// <summary>
    /// Reste en veille et lit les replays tout seul : quand le replay le plus recent n'est plus ecrit depuis "attente" secondes
    /// (partie terminee), ou quand le panneau le demande (fichier demande-lecture.txt). Se termine quand le panneau se ferme.
    /// </summary>
    public static int Surveiller(string input, string outDir, int attente, int parentPid)
    {
        Directory.CreateDirectory(outDir);
        var demande = Path.Combine(outDir, "demande-lecture.txt");
        var fini = Path.Combine(outDir, "lecture-finie.txt");
        var journal = Path.Combine(outDir, "derniere-lecture.txt");
        string? derniereSignature = null;
        while (ParentVivant(parentPid))
        {
            var demandee = File.Exists(demande);
            string signature;
            try { signature = Signature(input); } catch { signature = ""; }
            var termine = AgeDuPlusRecent(input) >= attente;
            if (demandee || (signature != derniereSignature && termine))
            {
                derniereSignature = signature;
                if (demandee) { try { File.Delete(demande); } catch { } }
                var ecran = new StringWriter();
                var ancien = Console.Out;
                Console.SetOut(ecran);
                try { Executer(input, outDir, false, attente); }
                catch (Exception e) { ecran.WriteLine("ECHEC : " + e.Message); }
                finally { Console.SetOut(ancien); }
                File.WriteAllText(journal, ecran.ToString());
                File.WriteAllText(fini, DateTime.Now.ToString("o"));   // marqueur : le panneau sait que la lecture est terminee
            }
            Thread.Sleep(3000);
        }
        return 0;
    }
}

// ---------------------------------------------------------------------------------------------

public sealed class MapChest
{
    [JsonPropertyName("t")] public int T { get; set; }
    [JsonPropertyName("x")] public int X { get; set; }
    [JsonPropertyName("y")] public int Y { get; set; }
    /// <summary>coffre (une arme ou un objet est sorti) | munitions (que des munitions) | inconnu (rien vu sortir)</summary>
    [JsonPropertyName("k")] public string K { get; set; } = "";
    [JsonPropertyName("items")] public List<string> Items { get; set; } = new();
    /// <summary>Meilleure rarete d'arme sortie : 0 commun, 1 peu commun, 2 rare, 3 epique, 4 legendaire, -1 aucune arme.</summary>
    [JsonPropertyName("r")] public int R { get; set; } = -1;
}

public sealed class MapMatch
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("size")] public long Size { get; set; }
    [JsonPropertyName("date")] public string Date { get; set; }
    [JsonPropertyName("playlist")] public string Playlist { get; set; }
    [JsonPropertyName("map")] public string Map { get; set; }
    [JsonPropertyName("version")] public string Version { get; set; }
    [JsonPropertyName("player")] public string Player { get; set; }
    [JsonPropertyName("placement")] public int? Placement { get; set; }
    [JsonPropertyName("kills")] public int? Kills { get; set; }
    /// <summary>[t, x, y, z] une fois par seconde.</summary>
    [JsonPropertyName("path")] public List<int[]> Path { get; set; } = new();
    /// <summary>[t, x, y] premier contact avec le sol.</summary>
    [JsonPropertyName("landing")] public int[] Landing { get; set; }
    [JsonPropertyName("chests")] public List<MapChest> Chests { get; set; } = new();
    /// <summary>Tous les conteneurs vus ouverts dans la partie, par n'importe qui : [t, x, y, genre(1=coffre,2=munitions,0=?), a moi(0/1)].</summary>
    [JsonPropertyName("boxes")] public List<int[]> Boxes { get; set; } = new();
    /// <summary>Coffres peut-etre tombes / casses par toi sans fouille (ESTIMATION) : [t, x, y, distance horizontale (unites, 100 = 1 m),
    /// hauteur du loot moins ta hauteur (unites), un autre joueur suivi etait plus proche (0/1)].</summary>
    [JsonPropertyName("falls")] public List<int[]> Falls { get; set; } = new();
    /// <summary>Qui t'a elimine (plateforme de l'adversaire). Absent si tu as gagne ou si le replay ne le dit pas.</summary>
    [JsonPropertyName("killer")] public MapKiller Killer { get; set; }
    /// <summary>Les autres joueurs de la partie (humains : avec pseudo ; bots : sans).</summary>
    [JsonPropertyName("others")] public List<MapPlayer> Others { get; set; } = new();
}

/// <summary>Celui qui t'a elimine.</summary>
public sealed class MapKiller
{
    [JsonPropertyName("plat")] public string Plat { get; set; }
    [JsonPropertyName("bot")] public bool Bot { get; set; }
    /// <summary>"joueur", "bot" ou "zone" (pas d'adversaire : zone, chute...).</summary>
    [JsonPropertyName("kind")] public string Kind { get; set; }
}

public sealed class MapPlayer
{
    [JsonPropertyName("n")] public string N { get; set; }
    /// <summary>Dans la meme equipe que toi.</summary>
    [JsonPropertyName("mate")] public bool Mate { get; set; }
    [JsonPropertyName("bot")] public bool Bot { get; set; }
    [JsonPropertyName("plat")] public string Plat { get; set; }
    [JsonPropertyName("pl")] public int? Pl { get; set; }
    [JsonPropertyName("k")] public int? K { get; set; }
    /// <summary>Vu au sol (sinon il etait encore en l'air quand le replay l'a perdu de vue).</summary>
    [JsonPropertyName("landed")] public bool Landed { get; set; }
    /// <summary>[x, y] la ou on l'a vu toucher le sol (absent s'il etait encore en l'air quand le replay l'a perdu).</summary>
    [JsonPropertyName("land")] public int[] Land { get; set; }
    /// <summary>[t, x, y, z] chaque seconde, tant que le joueur est suivi.</summary>
    [JsonPropertyName("path")] public List<int[]> Path { get; set; } = new();
    /// <summary>Coffres ouverts (seulement calcules pour ton equipe).</summary>
    [JsonPropertyName("chests")] public List<MapChest> Chests { get; set; } = new();
}

sealed class Pawn
{
    public uint Ch;
    public List<(float t, float x, float y, float z)> Track = new();
    public List<(float t, float x, float y)> Searches = new();
    public bool LastSearch;
    public int Player = -1;
}

sealed class Loot
{
    public float T; public string Item = ""; public (double x, double y)? Pos; public double Z;
}

sealed class Spy : ReplayReader
{
    public readonly List<Pawn> Pawns = new();
    public readonly List<Loot> Loots = new();
    /// <summary>FortPlayerState (numero d'acteur) -> numero de joueur : sert a retrouver qui a enregistre le replay.</summary>
    public readonly Dictionary<uint, int> PsToPlayerId = new();

    uint? ActorIdOf(uint ch)
    {
        try
        {
            var f = typeof(Unreal.Core.ReplayReader<FortniteReplay>).GetField("Channels", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
            var chan = (f?.GetValue(this) as Array)?.GetValue((int)ch);
            var v = chan?.GetType().GetProperty("ActorId")?.GetValue(chan);
            return v == null ? null : Convert.ToUInt32(v);
        }
        catch { return null; }
    }
    readonly Dictionary<uint, Pawn> cur = new();
    readonly Dictionary<uint, Loot> curLoot = new();

    public Spy() : base(null, ParseMode.Full) { }

    float clock; // horloge du monde (GameState), mise a jour environ chaque seconde
    float Now => clock;

    public static (double x, double y, double z)? Loc(object g)
    {
        var rm = g.GetType().GetProperty("ReplicatedMovement")?.GetValue(g);
        if (rm == null) return null;
        var loc = rm.GetType().GetProperty("Location")?.GetValue(rm) ?? rm;
        var t = loc.GetType();
        var x = t.GetProperty("X")?.GetValue(loc); var y = t.GetProperty("Y")?.GetValue(loc); var z = t.GetProperty("Z")?.GetValue(loc);
        return x == null || y == null ? null : (Convert.ToDouble(x), Convert.ToDouble(y), z == null ? 0 : Convert.ToDouble(z));
    }

    static string ItemName(object d)
    {
        if (d == null) return "?";
        foreach (var pn in new[] { "Name", "PathName", "Path" })
        {
            var v = d.GetType().GetProperty(pn)?.GetValue(d)?.ToString();
            if (!string.IsNullOrEmpty(v)) return v;
        }
        return "?";
    }

    // Un numero de canal est reutilise pour d'autres objets : a chaque ouverture on repart de zero.
    // Position ou l'objet est apparu (la ou se trouvait le conteneur), lue sur le canal du reseau.
    (double x, double y, double z)? SpawnPos(uint ch)
    {
        try
        {
            var f = typeof(Unreal.Core.ReplayReader<FortniteReplay>).GetField("Channels", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
            var arr = f?.GetValue(this) as Array;
            var chan = arr?.GetValue((int)ch);
            var actor = chan?.GetType().GetProperty("Actor")?.GetValue(chan);
            var loc = actor?.GetType().GetProperty("Location")?.GetValue(actor);
            if (loc == null) return null;
            return (Convert.ToDouble(loc.GetType().GetProperty("X").GetValue(loc)), Convert.ToDouble(loc.GetType().GetProperty("Y").GetValue(loc)),
                    Convert.ToDouble(loc.GetType().GetProperty("Z")?.GetValue(loc) ?? 0.0));
        }
        catch { return null; }
    }

    protected override void OnChannelOpened(uint channelIndex, NetworkGUID guid)
    {
        base.OnChannelOpened(channelIndex, guid);
        cur.Remove(channelIndex);
        curLoot.Remove(channelIndex);
    }

    protected override void OnExportRead(uint ch, INetFieldExportGroup g)
    {
        base.OnExportRead(ch, g);
        if (g is GameState gs)
        {
            if (gs.ReplicatedWorldTimeSecondsDouble is double dd && dd > 0) clock = (float)dd;
            else if (gs.ReplicatedWorldTimeSeconds is float ff && ff > 0) clock = ff;
        }
        var t = Now;
        var name = g.GetType().Name;
        if (name is "PlayerPawn" or "PhoebePlayerPawn")
        {
            if (!cur.TryGetValue(ch, out var pawn)) { cur[ch] = pawn = new Pawn { Ch = ch }; Pawns.Add(pawn); }
            var l = Loc(g);
            if (l is { } p && (pawn.Track.Count == 0 || t - pawn.Track[^1].t >= 0.5f))
                pawn.Track.Add((t, (float)p.x, (float)p.y, (float)p.z));
            if (g is PlayerPawn pp && pp.bStartedInteractSearch is bool now)
            {
                if (now && !pawn.LastSearch)
                {
                    var last = pawn.Track.Count > 0 ? pawn.Track[^1] : default;
                    pawn.Searches.Add((t, last.x, last.y));
                }
                pawn.LastSearch = now;
            }
        }
        else if (name == "FortPlayerState")
        {
            var pid = g.GetType().GetProperty("PlayerId")?.GetValue(g) ?? g.GetType().GetProperty("PlayerID")?.GetValue(g);
            if (pid != null && ActorIdOf(ch) is uint actor) PsToPlayerId[actor] = Convert.ToInt32(pid);
        }
        else if (g is FortPickup fp)
        {
            if (fp.bTossedFromContainer == true && !curLoot.ContainsKey(ch))
            {
                var sp0 = SpawnPos(ch);
                var e = new Loot { T = t, Item = ItemName(fp.ItemDefinition), Pos = sp0 == null ? null : (sp0.Value.x, sp0.Value.y), Z = sp0?.z ?? 0 };
                curLoot[ch] = e; Loots.Add(e);
            }
            if (curLoot.TryGetValue(ch, out var ev))
            {
                if (ev.Item == "?") ev.Item = ItemName(fp.ItemDefinition);
                if (ev.Pos == null && SpawnPos(ch) is { } sp1) { ev.Pos = (sp1.x, sp1.y); ev.Z = sp1.z; }
            }
        }
    }
}

static class Analyse
{
    /// <summary>Premier contact avec le sol : une vraie chute (&gt;50 m), puis la hauteur ne bouge plus pendant 3 s.</summary>
    static (float t, float x, float y)? Landing(List<(float t, float x, float y, float z)> tr)
    {
        if (tr.Count < 12) return null;
        int peak = 0;
        for (int i = 1; i < tr.Count; i++) if (tr[i].z > tr[peak].z) peak = i;
        for (int i = peak; i < tr.Count - 6; i++)
        {
            if (tr[peak].z - tr[i].z < 5000f) continue;
            bool stable = true;
            for (int j = i + 1; j <= i + 6; j++) if (Math.Abs(tr[j].z - tr[i].z) > 300f) { stable = false; break; }
            if (stable) return (tr[i].t, tr[i].x, tr[i].y);
        }
        return null;
    }

    static (float x, float y)? At(List<(float t, float x, float y, float z)> tr, float t)
    {
        if (tr.Count == 0) return null;
        int lo = 0, hi = tr.Count - 1;
        while (lo < hi) { int mid = (lo + hi) / 2; if (tr[mid].t < t) lo = mid + 1; else hi = mid; }
        var a = tr[lo];
        if (lo == 0 || a.t <= t) return Math.Abs(a.t - t) <= 3 ? (a.x, a.y) : null;
        var b = tr[lo - 1];
        if (a.t - b.t > 3) return null;
        var f = (t - b.t) / (a.t - b.t);
        return (b.x + (a.x - b.x) * f, b.y + (a.y - b.y) * f);
    }

    /// <summary>Positions d'un joueur (horloge du monde), une par seconde.</summary>
    static List<(float t, float x, float y, float z)> Series(PlayerData p)
    {
        var res = new List<(float, float, float, float)>();
        float last = float.MinValue;
        foreach (var l in (p.Locations ?? new List<PlayerMovement>()).Where(l => l.ReplicatedMovement?.Location != null)
            .OrderBy(l => l.ReplicatedWorldTimeSecondsDouble ?? l.ReplicatedWorldTimeSeconds ?? 0))
        {
            var t = (float)(l.ReplicatedWorldTimeSecondsDouble ?? l.ReplicatedWorldTimeSeconds ?? 0);
            if (t - last < 1f) continue;
            last = t;
            var loc = l.ReplicatedMovement.Value.Location;
            res.Add((t, (float)loc.X, (float)loc.Y, (float)loc.Z));
        }
        return res;
    }

    static bool IsWeapon(string item) =>
        item.StartsWith("WID_", StringComparison.Ordinal) && !System.Text.RegularExpressions.Regex.IsMatch(item, "Paprika_|Consumable|Stimpulse|Shield|Bandage|Medkit|Grenade", System.Text.RegularExpressions.RegexOptions.IgnoreCase);

    /// <summary>Coffres d'un joueur : chaque debut de fouille. Le loot qui sort juste a cote (a quelques metres) dit de quoi il s'agit :
    /// une arme => coffre ; que des munitions / soins => caisse de munitions ; rien vu => inconnu.</summary>
    static List<MapChest> ChestsFor(Spy spy, List<Pawn> pawns, List<(float t, float x, float y, float z)> track)
    {
        var res = new List<MapChest>();
        var searches = pawns.SelectMany(p => p.Searches).OrderBy(s => s.t).ToList();
        var mePos = searches.Select(s => At(track, s.t) ?? (s.x, s.y)).ToList();
        // Chaque objet est attribue a UNE seule fouille : la plus recente qui le precede (deux coffres voisins ne se melangent pas).
        var lootOf = searches.Select(_ => new List<Loot>()).ToList();
        foreach (var l in spy.Loots.Where(l => l.Pos != null))
        {
            int best = -1;
            for (int i = 0; i < searches.Count; i++)
            {
                // Le loot d'un coffre sort environ 0,9 s apres le debut de la fouille (mesure sur plusieurs parties) :
                // on ne prend que ce qui sort dans cette fenetre, ce qui separe deux coffres ouverts de suite.
                var delay = l.T - searches[i].t;
                if (searches[i].t > l.T) break;                         // fouille posterieure
                if (delay < 0.3f || delay > 1.6f) continue;
                if (Math.Sqrt(Math.Pow(l.Pos.Value.x - mePos[i].Item1, 2) + Math.Pow(l.Pos.Value.y - mePos[i].Item2, 2)) >= 700) continue;
                best = i;                                               // on garde la plus recente
            }
            if (best >= 0) lootOf[best].Add(l);
        }
        for (int i = 0; i < searches.Count; i++)
        {
            var s = searches[i]; var me = mePos[i]; var loot = lootOf[i];
            var items = loot.Select(l => l.Item).ToList();
            var kind = loot.Count == 0 ? "inconnu" : items.Any(IsWeapon) ? "coffre" : "munitions";
            var cx = loot.Count > 0 ? loot.Average(l => l.Pos.Value.x) : me.Item1;
            var cy = loot.Count > 0 ? loot.Average(l => l.Pos.Value.y) : me.Item2;
            res.Add(new MapChest { T = (int)s.t, X = (int)cx, Y = (int)cy, K = kind, Items = items, R = BestRarity(items) });
        }
        return res;
    }

    /// <summary>Meilleure rarete d'arme dans le loot : 0 commun, 1 peu commun, 2 rare, 3 epique, 4 legendaire ; -1 si aucune arme.</summary>
    public static int BestRarity(IEnumerable<string> items)
    {
        var best = -1;
        foreach (var it in items.Where(IsWeapon))
        {
            var m = System.Text.RegularExpressions.Regex.Match(it, @"_(C|UC|R|VR|SR)(?:_|$)");
            if (!m.Success) continue;
            var r = m.Groups[1].Value switch { "C" => 0, "UC" => 1, "R" => 2, "VR" => 3, _ => 4 };
            if (r > best) best = r;
        }
        return best;
    }

    static List<MapChest> ChestsNear(List<int[]> boxes, List<(float t, float x, float y, float z)> ss)
    {
        var res = new List<MapChest>();
        foreach (var b in boxes)
        {
            if (b[3] != 1 || b[4] == 1) continue;
            if (At(ss, b[0]) is not { } p) continue;
            if (Math.Sqrt(Math.Pow(p.x - b[1], 2) + Math.Pow(p.y - b[2], 2)) < 450) res.Add(new MapChest { T = b[0], X = b[1], Y = b[2], K = "coffre" });
        }
        return res;
    }

    public static MapMatch Run(string file)
    {
        var spy = new Spy();
        using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var replay = spy.ReadReplay(fs);
        var players = replay.PlayerData.ToList();
        // Qui a enregistre ce replay ? Trois methodes, de la plus sure a la plus approximative.
        var skip = Environment.GetEnvironmentVariable("CARTE_TEST_OWNER"); // pour tester les methodes de secours
        PlayerData owner = skip is "1" or "2" ? null : players.FirstOrDefault(p => p.IsReplayOwner);
        string how = "le replay le designe (IsReplayOwner)";
        if (owner == null && skip != "2" && replay.GameData?.RecorderId is uint rid && spy.PsToPlayerId.TryGetValue(rid, out var rpid))
        {
            owner = players.FirstOrDefault(p => p.Id == rpid);
            how = "identifiant de l'enregistreur (RecorderId)";
        }
        if (owner == null)
        {
            // Le joueur qui a enregistre est le seul dont le replay a la trace complete (des dizaines de positions par seconde).
            owner = players.Where(p => !p.IsBot).OrderByDescending(p => p.Locations?.Count ?? 0).FirstOrDefault();
            how = "joueur le mieux suivi (methode de secours)";
        }
        if (owner == null) throw new Exception("aucun joueur humain trouve dans ce replay (replay d'un autre mode ?)");
        Console.WriteLine($"     joueur retrouve : {owner.PlayerName} - par {how}");

        // Quel pion appartient a quel joueur ? On compare les positions exactes avec la trace de chaque joueur.
        var coord = new Dictionary<(int, int), int>();
        for (int i = 0; i < players.Count; i++)
            foreach (var l in players[i].Locations ?? Enumerable.Empty<PlayerMovement>())
            {
                var loc = l.ReplicatedMovement?.Location;
                if (loc != null) coord[((int)Math.Round(loc.X), (int)Math.Round(loc.Y))] = i;
            }
        foreach (var pawn in spy.Pawns.Where(p => p.Track.Count >= 5))
        {
            var votes = new Dictionary<int, int>();
            foreach (var pt in pawn.Track)
                if (coord.TryGetValue(((int)Math.Round(pt.x), (int)Math.Round(pt.y)), out var pi)) votes[pi] = votes.GetValueOrDefault(pi) + 1;
            if (votes.Count == 0) continue;
            var best = votes.OrderByDescending(v => v.Value).First();
            if (best.Value >= Math.Max(5, pawn.Track.Count * 0.3)) pawn.Player = best.Key;
        }
        int ownerIdx = players.IndexOf(owner);
        if (Environment.GetEnvironmentVariable("CARTE_DEBUG") == "2")
            for (int i = 0; i < players.Count; i++)
            {
                var ss = Series(players[i]); var raw = players[i].Locations ?? new List<PlayerMovement>();
                if (ss.Count == 0) { Console.WriteLine($"p{i} bot={players[i].IsBot} aucune position"); continue; }
                var firstFalse = raw.Where(l => l.bIsSkydiving == false).Select(l => l.ReplicatedWorldTimeSecondsDouble).FirstOrDefault();
                Console.WriteLine($"p{i} bot={players[i].IsBot} pts1Hz={ss.Count} t={ss[0].t:F0}..{ss[^1].t:F0} z={ss.Max(x => x.z):F0}->{ss.Min(x => x.z):F0} zfin={ss[^1].z:F0} skyTrue={raw.Count(l => l.bIsSkydiving == true)} skyFalse={raw.Count(l => l.bIsSkydiving == false)} landing={(Landing(ss) != null)} dead={players[i].DeathTime}");
            }
        if (Environment.GetEnvironmentVariable("CARTE_DEBUG") == "1")
        {
            Console.WriteLine("PlayerMovement props: " + string.Join(", ", typeof(PlayerMovement).GetProperties().Select(p => p.Name)));
            var ls = owner.Locations.ToList();
            Console.WriteLine($"owner locations: {ls.Count}");
            foreach (var l in ls.Take(2).Concat(ls.Skip(ls.Count / 2).Take(2)).Concat(ls.TakeLast(2)))
                Console.WriteLine($"   t={l.ReplicatedWorldTimeSeconds}/{l.ReplicatedWorldTimeSecondsDouble}/{l.LastUpdateTime} loc=({l.ReplicatedMovement?.Location?.X:F0},{l.ReplicatedMovement?.Location?.Y:F0},{l.ReplicatedMovement?.Location?.Z:F0})");
            Console.WriteLine($"players with locations: {players.Count(p => p.Locations.Count > 0)} / {players.Count}");
            foreach (var p in spy.Pawns.Where(p => p.Player == ownerIdx)) { Console.WriteLine($"owner pawn ch{p.Ch}: track {p.Track.Count} pts, t {p.Track.FirstOrDefault().t}..{p.Track.LastOrDefault().t}, searches {string.Join(";", p.Searches.Select(s => s.t))}"); }
            Console.WriteLine("loots: " + string.Join(" ", spy.Loots.Take(40).Select(l => $"{l.T}:{l.Item.Replace("WID_","").Replace("AthenaAmmoData","")}")));
            foreach (var se in spy.Pawns.Where(p => p.Player == ownerIdx).SelectMany(p => p.Searches))
            {
                Console.WriteLine($"search t={se.t:F1} pos=({se.x:F0},{se.y:F0})");
                foreach (var lo in spy.Loots.Where(l => l.T > se.t - 3 && l.T < se.t + 12)) Console.WriteLine($"     loot t={lo.T:F1} {lo.Item} pos={(lo.Pos is { } q ? $"({q.x:F0},{q.y:F0})" : "?")}");
            }
            Console.WriteLine($"pawn instances: {spy.Pawns.Count}, with >=5 pts {spy.Pawns.Count(p => p.Track.Count >= 5)}, matched {spy.Pawns.Count(p => p.Player >= 0)}");
        }
        var mine = spy.Pawns.Where(p => p.Player == ownerIdx).ToList();

        var date = replay.GameData?.UtcTimeStartedMatch;
        var m = new MapMatch
        {
            Id = Path.GetFileName(file),
            Date = date?.ToString("o") ?? File.GetLastWriteTime(file).ToString("o"),
            Playlist = replay.GameData?.CurrentPlaylist,
            Map = replay.GameData?.MapInfo,
            Version = null,
            Player = owner.PlayerName,
            Placement = (int?)owner.Placement,
            Kills = (int?)owner.Kills,
        };

        var track = Series(owner);
        foreach (var p in track) m.Path.Add(new[] { (int)p.t, (int)p.x, (int)p.y, (int)p.z });
        if (Landing(track) is { } L) m.Landing = new[] { (int)L.t, (int)L.x, (int)L.y };

        m.Chests = ChestsFor(spy, mine, track);
        if (Environment.GetEnvironmentVariable("CARTE_DEBUG") == "5")
        {
            foreach (var se in mine.SelectMany(p => p.Searches).OrderBy(s => s.t)) Console.WriteLine($"SEARCH t={se.t:F2} pos=({se.x:F0},{se.y:F0})");
            foreach (var l in spy.Loots.Where(l => l.T > 455 && l.T < 466 && l.Pos != null)) Console.WriteLine($"LOOT t={l.T:F2} ({l.Pos.Value.x:F0},{l.Pos.Value.y:F0},z{l.Z:F0}) {l.Item}");
        }

        // Tous les conteneurs ouverts par tout le monde : le loot qui sort d'un meme conteneur apparait au meme endroit au meme instant.
        var clusters = new List<(float t, float last, double sx, double sy, int n, List<string> items)>();
        foreach (var l in spy.Loots.Where(l => l.Pos != null).OrderBy(l => l.T))
        {
            int found = -1;
            for (int k = clusters.Count - 1; k >= 0 && k >= clusters.Count - 60; k--)
            {
                var c = clusters[k];
                if (l.T - c.last > 2.5f) continue;
                if (Math.Sqrt(Math.Pow(c.sx / c.n - l.Pos.Value.x, 2) + Math.Pow(c.sy / c.n - l.Pos.Value.y, 2)) < 250) { found = k; break; }
            }
            if (found < 0) clusters.Add((l.T, l.T, l.Pos.Value.x, l.Pos.Value.y, 1, new List<string> { l.Item }));
            else { var c = clusters[found]; c.items.Add(l.Item); clusters[found] = (c.t, l.T, c.sx + l.Pos.Value.x, c.sy + l.Pos.Value.y, c.n + 1, c.items); }
        }
        // Fausses ouvertures a ecarter :
        //  - avant que quiconque ait pu toucher le sol (chute depuis le bus : environ 15 s apres le saut) ;
        //  - un conteneur deja vu au meme endroit dans les 150 dernieres secondes (le replay le "revoit" en le rechargeant ;
        //    un vrai coffre ne se remplit qu'a peu pres toutes les 3 minutes).
        var busStart = track.Count > 0 ? track[0].t : 0f;
        if (Environment.GetEnvironmentVariable("CARTE_DEBUG") == "3")
            foreach (var c in clusters.OrderBy(c => c.t))
                Console.WriteLine($"CL t={c.t:F1} n={c.n} pos=({c.sx / c.n:F0},{c.sy / c.n:F0}) {string.Join(" ", c.items.Select(i => i.Replace("WID_", "").Replace("AthenaAmmoData", "Ammo:").Replace("_Athena", "")))}");
        var accepted = new List<(double x, double y, float t)>();
        foreach (var c in clusters.OrderBy(c => c.t))
        {
            if (c.n < 2) continue; // un seul objet : probablement pas un conteneur
            if (c.t < busStart + 15f) continue;
            // Equipement de depart : chaque joueur (humain ou bot) apparait avec UNE arme + ses munitions, ce qui ressemble a
            // un conteneur de 2 objets. Un vrai coffre en contient 3 ou plus (arme, munitions, soin). Plusieurs armes d'un coup =
            // plusieurs joueurs qui apparaissent au meme endroit. Une caisse de munitions n'a pas d'arme.
            var weapons = c.items.Count(IsWeapon);
            // (les coffres riches, legendaires par exemple, sortent 6 objets ou plus dont 2 armes : on les garde apres la phase d'apparition)
            if (weapons >= 2 && !(c.n >= 6 && c.t > busStart + 45f)) continue;
            if (weapons == 1 && c.n < 3) continue;
            // Sans arme, ce n'est une caisse de munitions que si au moins 2 sortes de munitions en sortent
            // (munition seule + petit soin = equipement de depart qui se melange a un autre).
            if (weapons == 0 && c.items.Count(i => i.Contains("Ammo", StringComparison.OrdinalIgnoreCase)) < 2) continue;
            if (accepted.Any(a => c.t - a.t < 150f && Math.Sqrt(Math.Pow(a.x - c.sx / c.n, 2) + Math.Pow(a.y - c.sy / c.n, 2)) < 250)) continue;
            accepted.Add((c.sx / c.n, c.sy / c.n, c.t));
            double x = c.sx / c.n, y = c.sy / c.n;
            int kind = c.items.Any(IsWeapon) ? 1 : 2;
            bool mineBox = m.Chests.Any(q => Math.Abs(q.T - c.t) <= 3 && Math.Sqrt(Math.Pow(q.X - x, 2) + Math.Pow(q.Y - y, 2)) < 500);
            m.Boxes.Add(new[] { (int)c.t, (int)x, (int)y, kind, mineBox ? 1 : 0 });
        }

        // Coffres peut-etre tombes / casses par toi (ESTIMATION, non comptes dans ton total) : un coffre dont le loot sort a moins de 9 m
        // de toi (a l'horizontale : un coffre a l'etage, sol casse, tombe pres de toi) alors que tu n'as lance AUCUNE fouille a ce moment.
        // On garde l'ecart de hauteur et un drapeau "un autre joueur suivi etait plus proche" pour pouvoir verifier apres un test reel.
        var ownSearchTimes = mine.SelectMany(p => p.Searches).Select(s => s.t).ToList();
        var allSeries = players.Select(Series).ToList();
        foreach (var b in m.Boxes)
        {
            if (b[3] != 1 || b[4] == 1 || track.Count == 0) continue;
            float tb = b[0];
            var me2 = track.OrderBy(p => Math.Abs(p.t - tb)).First();
            if (Math.Abs(me2.t - tb) > 2.5f) continue;
            double dist = Math.Sqrt(Math.Pow(me2.x - b[1], 2) + Math.Pow(me2.y - b[2], 2));
            if (dist > 900) continue;
            if (ownSearchTimes.Any(s => Math.Abs(s - tb) < 8f)) continue;
            bool otherCloser = false;
            for (int i = 0; i < players.Count && !otherCloser; i++)
            {
                if (i == ownerIdx || At(allSeries[i], tb) is not { } q) continue;
                if (Math.Sqrt(Math.Pow(q.x - b[1], 2) + Math.Pow(q.y - b[2], 2)) < dist) otherCloser = true;
            }
            var zs = spy.Loots.Where(l => l.Pos != null && Math.Abs(l.T - tb) <= 3
                && Math.Sqrt(Math.Pow(l.Pos.Value.x - b[1], 2) + Math.Pow(l.Pos.Value.y - b[2], 2)) < 250).Select(l => l.Z).ToList();
            var dz = zs.Count > 0 ? (int)(zs.Average() - me2.z) : 0;
            m.Falls.Add(new[] { b[0], b[1], b[2], (int)dist, dz, otherCloser ? 1 : 0 });
        }

        // Les autres joueurs. Le replay est enregistre de TON point de vue : un adversaire n'est suivi que tant qu'il
        // est assez proche de toi. Les coequipiers (meme equipe que toi) sont suivis plus longtemps et on calcule leurs coffres.
        for (int i = 0; i < players.Count; i++)
        {
            if (i == ownerIdx) continue;
            var pl = players[i];
            var ss = Series(pl);
            if (pl.IsBot && ss.Count < 2) continue;
            var mate = owner.TeamIndex != null && pl.TeamIndex == owner.TeamIndex;
            var mp = new MapPlayer
            {
                N = pl.IsBot ? null : (pl.PlayerName ?? pl.StreamerModeName),
                Mate = mate, Bot = pl.IsBot, Plat = pl.Platform,
                Pl = (int?)pl.Placement, K = (int?)pl.Kills,
                Landed = Landing(ss) != null,
                Land = Landing(ss) is { } lnd ? new[] { (int)lnd.x, (int)lnd.y } : null,
            };
            foreach (var p in ss) mp.Path.Add(new[] { (int)p.t, (int)p.x, (int)p.y, (int)p.z });
            // Le replay ne dit "debut de fouille" que pour toi : pour un coequipier, on estime ses coffres
            // = ceux ouverts juste a cote de lui (moins de 4,5 m) au moment ou ils s'ouvrent, et pas par toi.
            if (mate) mp.Chests = ChestsNear(m.Boxes, ss);
            m.Others.Add(mp);
        }

        // Qui t'a elimine ? La derniere elimination (pas "a terre") qui te concerne ; l'adversaire est retrouve par son identifiant.
        try
        {
            var mesIds = new[] { owner.PlayerId, owner.EpicId, owner.PlatformUniqueNetId }.Where(s => !string.IsNullOrEmpty(s)).ToList();
            var fin = replay.Eliminations?.Where(e => !e.Knocked && e.Eliminated != null && mesIds.Contains(e.Eliminated)).LastOrDefault();
            if (fin != null && owner.Placement != 1)
            {
                var tueur = string.IsNullOrEmpty(fin.Eliminator) ? null : players.FirstOrDefault(p => p.PlayerId == fin.Eliminator || p.EpicId == fin.Eliminator || p.PlatformUniqueNetId == fin.Eliminator);
                if (fin.IsSelfElimination || string.IsNullOrEmpty(fin.Eliminator)) m.Killer = new MapKiller { Kind = "zone" };
                else if (fin.EliminatorInfo != null && fin.EliminatorInfo.IsBot) m.Killer = new MapKiller { Kind = "bot", Bot = true };
                else if (tueur != null) m.Killer = new MapKiller { Kind = tueur.IsBot == true ? "bot" : "joueur", Bot = tueur.IsBot == true, Plat = tueur.Platform };
            }
            Console.WriteLine($"     classement {owner.Placement} | eliminations {owner.Kills} | elimine par : {(m.Killer == null ? "personne / inconnu" : m.Killer.Kind + " " + m.Killer.Plat)}");
        }
        catch (Exception ex) { Console.WriteLine($"     (tueur non lu : {ex.Message})"); }
        return m;
    }
}
