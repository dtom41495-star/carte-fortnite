using System.IO;
using System.Reflection;
using System.Windows;

namespace CarteFortnite;

public partial class App : Application
{
    Mutex mutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        bool apresMaj = e.Args.Contains("--apres-maj");
        Updater.Nettoyer();

        // Un seul panneau a la fois (apres une mise a jour, on laisse le temps a l'ancien de se fermer)
        mutex = new Mutex(false, "Local\\CarteCoffresPanneau");
        bool ok;
        try { ok = mutex.WaitOne(apresMaj ? 10000 : 0); } catch (AbandonedMutexException) { ok = true; }
        if (!ok) { Shutdown(); return; }

        // Protection anti-cheat : on ne demarre RIEN si Fortnite est deja ouvert (ouvrir l'application pendant le jeu a fait planter Easy Anti-Cheat).
        if (Systeme.FortniteOuvert())
        {
            MessageDialog.Afficher(null, "FORTNITE EST OUVERT",
                "Fortnite est ouvert : Carte Fortnite ne démarre pas.\n\nOuvrir cette application pendant le jeu peut faire planter Easy Anti-Cheat. Ferme Fortnite, lance Carte Fortnite, PUIS relance Fortnite.");
            Shutdown();
            return;
        }

        try { Extraire(); }
        catch (Exception ex) { Donnees.Journal("Extraction : " + ex.Message); }
        Donnees.EcrireReglagesJs(Donnees.LireCfg());

        var fenetre = new MainWindow(apresMaj);
        MainWindow = fenetre;
        fenetre.Closed += (_, _) => Shutdown();
        fenetre.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try { mutex?.ReleaseMutex(); } catch { }
        base.OnExit(e);
    }

    /// <summary>Recopie la page de la carte et ses images (embarquees dans l'exe) dans %LOCALAPPDATA%\CarteFortnite\site.</summary>
    static void Extraire()
    {
        var asm = Assembly.GetExecutingAssembly();
        foreach (var nom in asm.GetManifestResourceNames())
        {
            if (!nom.StartsWith("site/")) continue;
            var cible = Path.Combine(Chemins.Racine, nom.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(cible)!);
            using var src = asm.GetManifestResourceStream(nom)!;
            using var ms = new MemoryStream();
            src.CopyTo(ms);
            var octets = ms.ToArray();
            if (File.Exists(cible) && File.ReadAllBytes(cible).AsSpan().SequenceEqual(octets)) continue;
            File.WriteAllBytes(cible, octets);
        }
        Directory.CreateDirectory(Chemins.Donnees);
    }
}
