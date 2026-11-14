// Panneau unique "Carte Fortnite" : tout se fait ici, avec des boutons.
//  - Ouvrir la carte de mes parties (lit d'abord tes replays)
//  - Afficher / masquer le petit compteur de coffres par-dessus le jeu, le deplacer, regler sa taille
//
// IMPORTANT (anti-cheat) : l'application ne lance AUCUN autre programme. La lecture des replays tourne dans un fil de CE programme
// (en veille, elle lit les replays quand une partie se termine) et le compteur est une seconde fenetre de CE programme.
// Elle n'interroge pas la liste des programmes (pas de WMI) : Easy Anti-Cheat a fait planter Fortnite quand l'ancienne version le faisait.
// Le moteur web de la carte n'est demarre que quand on ouvre la carte ET que Fortnite est ferme.
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace CarteFortnite;

public partial class MainWindow : Window
{
    OverlayWindow ov;
    CancellationTokenSource survCts;
    Task surv;

    bool sync;                 // vrai pendant qu'on remplit les controles : leurs evenements ne font rien
    bool chargementActif;
    bool barreAnim;
    int tickN;
    int nbPoints;
    bool lectureAttend;
    bool ouvrirApresLecture = true;
    DateTime lectureDemandeLe = DateTime.Now;
    bool tailleSale, departSale;
    DateTime tailleLe = DateTime.Now, departLe = DateTime.Now;
    bool deplRelance;

    // la carte dans l'appli
    bool carteOuverte, wvEchec, carteFinie;
    WebView2 wv;
    DateTime carteDebutLe = DateTime.Now;
    double avantGauche, avantHaut;
    bool compteurAvant;

    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    readonly DispatcherTimer timerPoints = new() { Interval = TimeSpan.FromMilliseconds(450) };
    readonly bool apresMaj;

    public MainWindow(bool apresMaj)
    {
        this.apresMaj = apresMaj;
        InitializeComponent();
        ChargerIcone();
        SourceInitialized += (_, _) => Systeme.BarreTitreSombre(this);
        MaxHeight = SystemParameters.WorkArea.Height;      // sur un petit ecran, une barre de defilement apparait

        var cfg = Donnees.LireCfg();
        sync = true;
        ChkTombes.IsChecked = cfg.CompterTombes;
        ChkEquipe.IsChecked = cfg.Equipe;
        ChkResume.IsChecked = cfg.Resume;
        Taille.Value = Math.Round(cfg.Scale * 100);
        TailleTxt.Text = (int)Taille.Value + " %";
        Depart.Text = cfg.Depart.ToString();
        sync = false;

        BtnRetour.Click += (_, _) => FermerCarte();
        BtnCarte.Click += (_, _) => LancerLecture();
        ChkOverlay.Checked += ChkOverlay_Checked;
        ChkOverlay.Unchecked += ChkOverlay_Unchecked;
        ChkTombes.Click += (_, _) => { var c = Donnees.LireCfg(); c.CompterTombes = ChkTombes.IsChecked == true; Donnees.EcrireCfg(c); MajChiffres(); ov?.AppliquerCfg(); };
        ChkEquipe.Click += (_, _) => { var c = Donnees.LireCfg(); c.Equipe = ChkEquipe.IsChecked == true; Donnees.EcrireCfg(c); ov?.AppliquerCfg(); };
        ChkResume.Click += (_, _) => { var c = Donnees.LireCfg(); c.Resume = ChkResume.IsChecked == true; Donnees.EcrireCfg(c); ov?.AppliquerCfg(); };
        Taille.ValueChanged += (_, _) =>
        {
            TailleTxt.Text = (int)Taille.Value + " %";
            if (!sync) { tailleSale = true; tailleLe = DateTime.Now; }
        };
        Depart.TextChanged += (_, _) => { if (!sync) { departSale = true; departLe = DateTime.Now; } };
        BtnDepl.Click += BtnDepl_Click;
        BtnRaccourci.Click += (_, _) =>
        {
            try { CreerRaccourci(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)); Etat.Text = "Raccourci « Carte Fortnite » créé sur le Bureau, avec l'icône de coffre."; }
            catch (Exception e) { Donnees.Journal("Raccourci : " + e.Message); Etat.Text = "Impossible de créer le raccourci : " + e.Message; }
        };
        BtnQuitter.Click += (_, _) => WindowState = WindowState.Minimized;

        timerPoints.Tick += (_, _) =>
        {
            nbPoints = (nbPoints + 1) % 4;
            Etat.Text = "Lecture de tes replays" + new string('.', nbPoints) + "  (quelques secondes)";
        };
        timer.Tick += (_, _) => { try { Boucle(); } catch (Exception e) { Donnees.Journal("tick : " + e.Message); } };
        Closing += (_, _) => ArreterTout();

        // la fenetre s'affiche TOUT DE SUITE avec l'animation de chargement, puis les donnees arrivent
        DemarrerChargement("Chargement de tes données…");
        ContentRendered += (_, _) => Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(ChargerInitial));
    }

    void ChargerIcone()
    {
        try
        {
            var ico = Path.Combine(Chemins.Site, "ressources", "coffre.ico");
            if (File.Exists(ico)) Icon = BitmapFrame.Create(new Uri(ico), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        }
        catch { }
    }

    // ---------- demarrage ----------
    async void ChargerInitial()
    {
        DemarrerSurveillance();        // la lecture des replays reste en veille jusqu'a la fermeture du panneau
        MajChiffres();
        ArreterChargement();
        Etat.Text = "";
        timer.Start();
        await VerifierMajAsync();
    }

    /// <summary>Au lancement : une version plus recente sur GitHub ? On propose, on ne force rien.</summary>
    async Task VerifierMajAsync()
    {
        if (apresMaj) { Etat.Text = "Mise à jour installée : version " + Updater.VersionTexte + "."; return; }
        var maj = await Updater.VerifierAsync();
        if (maj == null) return;
        if (Systeme.FortniteOuvert()) return;                 // jamais pendant le jeu
        var note = string.IsNullOrWhiteSpace(maj.Notes) ? "" : "\n\n" + (maj.Notes.Length > 600 ? maj.Notes.Substring(0, 600) + "…" : maj.Notes);
        if (!MessageDialog.Afficher(this, "MISE À JOUR",
                $"La version {maj.Version.ToString(3)} est disponible (tu as la {Updater.VersionTexte}).{note}\n\nLe programme se télécharge depuis GitHub, est vérifié, puis se relance tout seul.",
                "METTRE À JOUR", "PLUS TARD"))
            return;
        try
        {
            BarreMarche(true);
            BtnCarte.IsEnabled = false;
            var p = new Progress<int>(v => Etat.Text = $"Téléchargement de la version {maj.Version.ToString(3)}… {v} %");
            Etat.Text = "Téléchargement de la mise à jour…";
            await Updater.AppliquerAsync(maj, p);
            Application.Current.Shutdown();            // le nouvel exe est deja lance
        }
        catch (Exception e)
        {
            Donnees.Journal("Mise a jour : " + e.Message);
            BarreMarche(false);
            BtnCarte.IsEnabled = true;
            Etat.Text = "La mise à jour a échoué (" + e.Message + "). Ton programme actuel reste inchangé ; réessaie au prochain lancement.";
        }
    }

    // ---------- surveillance : un fil de CE programme, pas un autre programme ----------
    void DemarrerSurveillance()
    {
        survCts?.Dispose();
        survCts = new CancellationTokenSource();
        var jeton = survCts.Token;
        surv = Task.Factory.StartNew(() =>
        {
            try
            {
                Thread.CurrentThread.Priority = ThreadPriority.BelowNormal;
                Lecteur.Surveiller(Chemins.Demos, Chemins.Donnees, 25, jeton);
            }
            catch (Exception e) { Donnees.Journal("Surveillance : " + e.Message); }
        }, TaskCreationOptions.LongRunning);
    }

    void ArreterTout()
    {
        try { LibererCarte(); } catch { }
        try { survCts?.Cancel(); } catch { }
        try { ov?.Close(); } catch { }
        ov = null;
    }

    // ---------- barre de chargement et chiffres qui clignotent ----------
    void BarreMarche(bool on)
    {
        if (on)
        {
            Barre.Visibility = Visibility.Visible;
            if (!barreAnim)
            {
                var a = new DoubleAnimation(-150.0, 470.0, TimeSpan.FromMilliseconds(1100)) { RepeatBehavior = RepeatBehavior.Forever };
                ((TranslateTransform)Morceau.RenderTransform).BeginAnimation(TranslateTransform.XProperty, a);
                barreAnim = true;
            }
        }
        else
        {
            Barre.Visibility = Visibility.Collapsed;
            if (barreAnim)
            {
                ((TranslateTransform)Morceau.RenderTransform).BeginAnimation(TranslateTransform.XProperty, null);
                barreAnim = false;
            }
        }
    }

    void PulseChiffres(bool on)
    {
        foreach (var tb in new[] { Total, Derniere, Parties, EquipeTotal, EquipeDerniere })
        {
            if (on) tb.BeginAnimation(OpacityProperty, new DoubleAnimation(0.25, 1.0, TimeSpan.FromMilliseconds(650)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
            else { tb.BeginAnimation(OpacityProperty, null); tb.Opacity = 1; }
        }
    }

    void DemarrerChargement(string message)
    {
        chargementActif = true;
        Total.Text = "…"; Derniere.Text = "…"; Parties.Text = "…"; EquipeTotal.Text = "ÉQUIPE  …"; EquipeDerniere.Text = "ÉQUIPE  …";
        PulseChiffres(true);
        BarreMarche(true);
        Etat.Text = message;
    }

    void ArreterChargement()
    {
        chargementActif = false;
        PulseChiffres(false);
        BarreMarche(false);
        if (Total.Text == "…") AfficherChiffres(Donnees.LireCfg().Depart, 0, 0);     // pas encore de donnees : on montre le nombre de depart
    }

    // Les nombres apparaissent DIRECTEMENT avec leur vraie valeur : pas de comptage depuis 0.
    void AfficherChiffres(int t, int d, int p, int et = 0, int ed = 0)
    {
        Total.Text = t.ToString(); Derniere.Text = d.ToString(); Parties.Text = p.ToString();
        EquipeTotal.Text = "ÉQUIPE  " + et; EquipeDerniere.Text = "ÉQUIPE  " + ed;
    }

    void MajChiffres()
    {
        var c = Donnees.LireCompteur();
        if (c == null)
        {
            if (Total.Text == "…" && !chargementActif) AfficherChiffres(Donnees.LireCfg().Depart, 0, 0);
            return;
        }
        var cfg = Donnees.LireCfg();
        AfficherChiffres(Donnees.Total(c, cfg), Donnees.Derniere(c, cfg), c.Parties, Donnees.EquipeTotal(c, cfg), Donnees.EquipeDerniere(c, cfg));
    }

    // ---------- lire les replays, puis ouvrir la carte ----------
    bool LancerLecture()
    {
        if (surv == null || surv.IsCompleted)
        {
            if (Systeme.FortniteOuvert()) { Etat.Text = "Le programme de lecture n'est plus actif. Ferme Fortnite, puis ferme et rouvre Carte Fortnite avant de relancer le jeu."; return false; }
            DemarrerSurveillance();
        }
        BtnCarte.IsEnabled = false;
        Etat.Text = "Lecture de tes replays";
        BarreMarche(true);
        nbPoints = 0; timerPoints.Start();
        lectureDemandeLe = DateTime.Now;
        try { Directory.CreateDirectory(Chemins.Donnees); File.WriteAllText(Chemins.Demande, "demande"); }      // la surveillance la voit dans les 3 secondes
        catch (Exception e) { Donnees.Journal("Demande : " + e.Message); }
        lectureAttend = true;
        return true;
    }

    void FinLecture()
    {
        string txt = "";
        try { if (File.Exists(Chemins.DerniereLecture)) txt = File.ReadAllText(Chemins.DerniereLecture); } catch { }
        int n = -1;
        var m = Regex.Match(txt, @"(\d+) replay\(s\) trouve");
        if (m.Success) n = int.Parse(m.Groups[1].Value);
        string msg;
        if (n == 0 || txt.Contains("introuvable"))
            msg = "Aucun replay trouvé. Dans Fortnite : Paramètres > Jeu, active l'enregistrement des replays, puis joue une partie jusqu'au bout. (Sur console, il n'y a pas de replay.)";
        else if (txt.Contains("ECHEC"))
            msg = "Certains replays n'ont pas pu être lus (voir donnees\\derniere-lecture.txt dans " + Chemins.Site + ").";
        else if (txt.Contains("Aucune partie analysee"))
            msg = "Aucune partie lue pour l'instant : joue une partie avec les replays activés.";
        else
            msg = "Carte mise à jour.";
        bool ouvrir = ouvrirApresLecture && n != 0 && !txt.Contains("introuvable");
        if (ouvrir && Systeme.FortniteOuvert())
        {
            ouvrir = false;
            msg = "Données mises à jour. Ouvre la carte après avoir fermé Fortnite (ouvrir un programme pendant le jeu peut faire réagir l'anti-cheat).";
        }
        else if (ouvrir) msg += " Ouverture de la carte…";
        timerPoints.Stop(); BarreMarche(false);
        Etat.Text = msg;
        MajChiffres();
        BtnCarte.IsEnabled = true;
        if (ouvrir) OuvrirCarte();
    }

    // ---------- la carte DANS l'appli (moteur web de Windows, WebView2) ----------
    // Anti-cheat : le moteur web n'est demarre QUE quand on ouvre la carte, et seulement si Fortnite est ferme ; il est libere (ses programmes
    // s'arretent) des qu'on clique sur « Retour » ; et la carte se ferme toute seule si Fortnite s'ouvre.
    // Si le moteur web n'est pas disponible sur ce PC, la carte s'ouvre dans le navigateur.
    static bool WebView2Disponible()
    {
        try { return !string.IsNullOrEmpty(CoreWebView2Environment.GetAvailableBrowserVersionString()); }
        catch (Exception e) { Donnees.Journal("WebView2 : " + e.Message); return false; }
    }

    void LibererCarte()
    {
        var w = wv; wv = null;
        if (w == null) return;
        try { ZoneCarte.Children.Remove(w); } catch { }
        try { w.Dispose(); } catch (Exception e) { Donnees.Journal("WebView2 Dispose : " + e.Message); }
    }

    void RendrePanneau()
    {
        VueCarte.Visibility = Visibility.Collapsed; VuePanneau.Visibility = Visibility.Visible;
        MinWidth = 0; MinHeight = 0;
        ResizeMode = ResizeMode.CanMinimize; SizeToContent = SizeToContent.Height; Width = 500;
        Left = avantGauche; Top = avantHaut;
        if (compteurAvant) { compteurAvant = false; try { AfficherCompteur(); } catch (Exception e) { Donnees.Journal("Afficher compteur : " + e.Message); } }
    }

    /// <summary>true = la carte est ouverte dans l'appli ; false = pas possible ici (l'appelant l'ouvre alors dans le navigateur).</summary>
    bool AfficherCarte()
    {
        if (carteOuverte) return true;
        if (Systeme.FortniteOuvert()) return false;            // jamais pendant le jeu
        if (!WebView2Disponible()) return false;
        try
        {
            var w = new WebView2
            {
                CreationProperties = new CoreWebView2CreationProperties { UserDataFolder = Chemins.WebView, IsInPrivateModeEnabled = true },
                DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 7, 13, 43),
            };
            w.CoreWebView2InitializationCompleted += (s, e) =>
            {
                if (!e.IsSuccess) { Donnees.Journal("WebView2 demarrage : " + e.InitializationException?.Message); wvEchec = true; return; }
                try
                {
                    var c = w.CoreWebView2;
                    c.SetVirtualHostNameToFolderMapping("carte.local", Chemins.Site, CoreWebView2HostResourceAccessKind.Allow);
                    var st = c.Settings;
                    st.AreDevToolsEnabled = false; st.IsStatusBarEnabled = false; st.AreDefaultContextMenusEnabled = false;
                    st.IsZoomControlEnabled = false; st.AreBrowserAcceleratorKeysEnabled = false;
                    c.Navigate("https://carte.local/carte.html");
                }
                catch (Exception ex) { Donnees.Journal("WebView2 navigation : " + ex.Message); wvEchec = true; }
            };
            w.NavigationStarting += (s, e) => { if (!e.Uri.StartsWith("https://carte.local/")) e.Cancel = true; };     // la carte ne va nulle part ailleurs
            w.NavigationCompleted += (s, e) => { if (e.IsSuccess) carteFinie = true; else wvEchec = true; };
            wvEchec = false; carteFinie = false; carteDebutLe = DateTime.Now;
            wv = w;
            // on passe a la vue « carte » : fenetre plus grande, compteur masque le temps de regarder la carte
            avantGauche = Left; avantHaut = Top;
            compteurAvant = ov != null && ov.IsVisible; if (compteurAvant) ov.Masquer();
            VuePanneau.Visibility = Visibility.Collapsed; VueCarte.Visibility = Visibility.Visible;
            var zone = SystemParameters.WorkArea;
            MinWidth = 800; MinHeight = 500;
            ResizeMode = ResizeMode.CanResize; SizeToContent = SizeToContent.Manual;
            Width = Math.Min(1600, zone.Width * 0.94); Height = Math.Min(1000, zone.Height * 0.94);
            Left = zone.Left + (zone.Width - Width) / 2; Top = zone.Top + (zone.Height - Height) / 2;
            ZoneCarte.Children.Add(w);
            _ = w.EnsureCoreWebView2Async();
            carteOuverte = true;
            return true;
        }
        catch (Exception e)
        {
            Donnees.Journal("Afficher carte : " + e.Message);
            LibererCarte(); RendrePanneau();
            return false;
        }
    }

    void FermerCarte(string message = "")
    {
        if (!carteOuverte) return;
        carteOuverte = false;
        LibererCarte();
        RendrePanneau();
        if (message != "") Etat.Text = message;
    }

    void OuvrirDansNavigateur()
    {
        try { Process.Start(new ProcessStartInfo(Chemins.CarteHtml) { UseShellExecute = true }); }
        catch (Exception e) { Donnees.Journal("Navigateur : " + e.Message); }
    }

    /// <summary>Ouvre la carte : dans l'appli si possible, sinon dans le navigateur (jamais pendant le jeu).</summary>
    void OuvrirCarte()
    {
        if (AfficherCarte()) return;
        if (Systeme.FortniteOuvert()) return;
        OuvrirDansNavigateur();
        Etat.Text = "L'affichage intégré n'est pas disponible sur ce PC : la carte s'ouvre dans ton navigateur.";
    }

    // ---------- compteur par-dessus le jeu ----------
    OverlayWindow Overlay()
    {
        if (ov == null) ov = new OverlayWindow();
        return ov;
    }

    void AfficherCompteur() => Overlay().Afficher();

    void ChkOverlay_Checked(object s, RoutedEventArgs e)
    {
        if (sync) return;
        try { AfficherCompteur(); Etat.Text = "Compteur affiché en haut à gauche de l'écran (glisse-le avec « Déplacer »)."; }
        catch (Exception ex) { Donnees.Journal("Afficher compteur : " + ex.Message); Etat.Text = "Impossible d'afficher le compteur : " + ex.Message; }
    }

    void ChkOverlay_Unchecked(object s, RoutedEventArgs e)
    {
        if (sync) return;
        try { ov?.Masquer(); Etat.Text = "Compteur masqué."; } catch (Exception ex) { Donnees.Journal("Masquer compteur : " + ex.Message); }
    }

    void BtnDepl_Click(object s, RoutedEventArgs e)
    {
        var o = Overlay();
        deplRelance = o.IsVisible;
        BtnDepl.IsEnabled = false; ChkOverlay.IsEnabled = false;
        Etat.Text = "Glisse le petit coffre où tu veux sur l'écran, puis fais un clic droit dessus pour valider.";
        o.FinDeplacement = () =>
        {
            if (!deplRelance) o.Masquer();
            BtnDepl.IsEnabled = true; ChkOverlay.IsEnabled = true;
            sync = true; ChkOverlay.IsChecked = o.IsVisible; sync = false;
            Etat.Text = "Position enregistrée.";
        };
        o.DeplacerDebut();
    }

    /// <summary>Raccourci avec l'icone de coffre (celle de l'exe) : il lance directement CarteFortnite.exe.</summary>
    static void CreerRaccourci(string dossier)
    {
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Chemin de l'exe introuvable.");
        var t = Type.GetTypeFromProgID("WScript.Shell") ?? throw new InvalidOperationException("WScript.Shell indisponible.");
        dynamic ws = Activator.CreateInstance(t);
        dynamic lnk = ws.CreateShortcut(Path.Combine(dossier, "Carte Fortnite.lnk"));
        lnk.TargetPath = exe;
        lnk.WorkingDirectory = Path.GetDirectoryName(exe);
        lnk.IconLocation = exe + ",0";
        lnk.Description = "Carte Fortnite : mes coffres, mon trajet, mon atterrissage";
        lnk.Save();
    }

    // ---------- boucle (toutes les 2 s) : chiffres, fin de lecture, reglages en attente, compteur ----------
    void Boucle()
    {
        tickN++;
        if (lectureAttend)
        {
            if (File.Exists(Chemins.LectureFinie) && File.GetLastWriteTime(Chemins.LectureFinie) > lectureDemandeLe) { lectureAttend = false; FinLecture(); }
            else if ((DateTime.Now - lectureDemandeLe).TotalSeconds > 120)
            {
                lectureAttend = false; timerPoints.Stop(); BarreMarche(false); BtnCarte.IsEnabled = true;
                Etat.Text = "La lecture prend trop de temps : réessaie dans un instant.";
            }
        }
        if (tailleSale && (DateTime.Now - tailleLe).TotalMilliseconds > 500)
        {
            tailleSale = false;
            var c = Donnees.LireCfg(); c.Scale = Math.Round(Taille.Value / 100, 2); Donnees.EcrireCfg(c); ov?.AppliquerCfg();
        }
        if (departSale && (DateTime.Now - departLe).TotalMilliseconds > 600)
        {
            departSale = false;
            if (int.TryParse(Depart.Text.Trim(), out var v) && v >= 0 && v <= 999999)
            {
                var c = Donnees.LireCfg(); c.Depart = v; Donnees.EcrireCfg(c); MajChiffres(); ov?.AppliquerCfg();
                Etat.Text = v > 0 ? $"Nombre de départ enregistré : {v} coffres ajoutés au total." : "Nombre de départ remis à 0.";
            }
            else Etat.Text = "Tape un nombre entier (0 ou plus) pour les coffres déjà ouverts.";
        }
        MajChiffres();
        if (tickN % 2 == 0) ov?.Tick();                      // le compteur par-dessus le jeu se met a jour toutes les 4 s
        bool ouvert = Systeme.FortniteOuvert();
        Alerte.Visibility = ouvert ? Visibility.Visible : Visibility.Collapsed;
        if (ouvert && carteOuverte) FermerCarte("Fortnite s'est ouvert : la carte a été fermée pour que rien de plus ne tourne pendant le jeu.");
        else if (carteOuverte && (wvEchec || (!carteFinie && (DateTime.Now - carteDebutLe).TotalSeconds > 25)))
        {
            // le moteur web ne demarre pas : on referme et on ouvre la carte dans le navigateur
            FermerCarte();
            OuvrirDansNavigateur();
            Etat.Text = "L'affichage intégré ne répond pas : la carte s'ouvre dans ton navigateur.";
        }
        if (surv != null && surv.IsCompleted && !ouvert && survCts is { IsCancellationRequested: false }) DemarrerSurveillance();   // filet de securite (hors jeu seulement)
    }
}
