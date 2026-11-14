// Le petit compteur de coffres par-dessus le jeu : une seconde fenetre de CE programme (aucun autre programme n'est lance).
// Style inspire de l'univers Fortnite (plaque penchee, jaune et bleu nuit) : aucun logo, aucune police ni image d'Epic Games.
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CarteFortnite;

public partial class OverlayWindow : Window
{
    const int AttenteFin = 25;     // secondes sans ecriture du replay = la partie est terminee
    const int MaxComptage = 5;     // au-dela de cette hausse, le nombre change d'un coup (jamais de comptage long)

    readonly RotateTransform rot = new(0);
    readonly ScaleTransform echelle = new(1, 1);
    readonly TranslateTransform glisse = new(0, 0);
    readonly SolidColorBrush pinceau;
    readonly DispatcherTimer cptTimer = new() { Interval = TimeSpan.FromMilliseconds(170) };
    int affiche = -1, montre, cible;
    bool animer = true;

    public bool Deplace { get; private set; }
    /// <summary>Appele quand l'utilisateur valide la nouvelle position (clic droit).</summary>
    public Action FinDeplacement { get; set; }

    public OverlayWindow()
    {
        InitializeComponent();
        Icone.RenderTransform = rot; Icone.RenderTransformOrigin = new Point(0.5, 0.9);
        Nombre.RenderTransform = echelle; Nombre.RenderTransformOrigin = new Point(0.3, 0.55);
        Badge.RenderTransform = glisse;
        pinceau = ((SolidColorBrush)Plaque.BorderBrush).Clone();
        Plaque.BorderBrush = pinceau;

        SourceInitialized += (_, _) => Systeme.FenetreTraversable(this, !Deplace);
        MouseLeftButtonDown += (_, _) => { if (Deplace) DragMove(); };
        MouseRightButtonUp += (_, _) => { if (Deplace) DeplacerFin(); };

        // le nombre monte un par un avec un rebond
        cptTimer.Tick += (_, _) =>
        {
            if (montre < cible)
            {
                montre++;
                Nombre.Text = montre.ToString();
                AnimPop(montre >= cible ? 1.4 : 1.2);
            }
            if (montre >= cible) cptTimer.Stop();
        };
        AppliquerCfg();
    }

    // ---------- animations ----------
    static EasingDoubleKeyFrame KF(double v, int ms, IEasingFunction ease)
    {
        var k = new EasingDoubleKeyFrame(v, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(ms)));
        if (ease != null) k.EasingFunction = ease;
        return k;
    }

    void AnimPop(double amp)
    {
        var quad = new QuadraticEase { EasingMode = EasingMode.EaseOut };
        var el = new ElasticEase { Oscillations = 2, Springiness = 5, EasingMode = EasingMode.EaseOut };
        var a = new DoubleAnimationUsingKeyFrames();
        a.KeyFrames.Add(KF(1.0, 0, null)); a.KeyFrames.Add(KF(amp, 110, quad)); a.KeyFrames.Add(KF(1.0, 560, el));
        echelle.BeginAnimation(ScaleTransform.ScaleXProperty, a);
        echelle.BeginAnimation(ScaleTransform.ScaleYProperty, a);
    }

    void AnimIcone()
    {
        var sin = new SineEase { EasingMode = EasingMode.EaseInOut };
        var a = new DoubleAnimationUsingKeyFrames();
        foreach (var (v, ms) in new[] { (0.0, 0), (-16.0, 90), (13.0, 210), (-8.0, 330), (4.0, 430), (0.0, 530) }) a.KeyFrames.Add(KF(v, ms, sin));
        rot.BeginAnimation(RotateTransform.AngleProperty, a);
    }

    void AnimLueur()
    {
        // le lisere de la plaque passe du jaune au blanc, puis revient
        var c = new ColorAnimationUsingKeyFrames();
        var baseC = Color.FromArgb(0xFF, 0xFF, 0xE5, 0x00);
        var vif = Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF);
        foreach (var (col, ms) in new[] { (baseC, 0), (vif, 130), (vif, 450), (baseC, 1100) })
            c.KeyFrames.Add(new LinearColorKeyFrame(col, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(ms))));
        pinceau.BeginAnimation(SolidColorBrush.ColorProperty, c);
    }

    void AnimBadge()
    {
        Badge.BeginAnimation(OpacityProperty, new DoubleAnimation(0.0, 1.0, TimeSpan.FromMilliseconds(380)));
        var slide = new DoubleAnimation(-16.0, 0.0, TimeSpan.FromMilliseconds(420)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut } };
        glisse.BeginAnimation(TranslateTransform.XProperty, slide);
    }

    // ---------- contenu ----------
    void MajNombre()
    {
        int t;
        var c = Donnees.LireCompteur();
        if (c == null) { if (affiche >= 0) return; t = Donnees.LireCfg().Depart; }
        else t = Donnees.Total(c, Donnees.LireCfg());
        if (t == affiche) return;

        int ancien = affiche;
        affiche = t;
        bool enCours = cptTimer.IsEnabled;
        int depuis = enCours ? montre : ancien;
        int ecart = t - depuis;
        if (ancien >= 0 && ecart > 0 && animer && !Deplace)
        {
            if (!enCours) { AnimIcone(); AnimLueur(); }       // le coffre se secoue et la plaque brille
            if (ecart <= MaxComptage)
            {
                // petite hausse (le cas normal : 1 a quelques coffres) : le nombre monte un par un avec un rebond
                if (!enCours) montre = ancien;
                cible = t;
                cptTimer.Start();
            }
            else
            {
                // grosse hausse (plusieurs parties lues d'un coup) : le nombre change d'un coup
                cptTimer.Stop();
                cible = t; montre = t; Nombre.Text = t.ToString();
                AnimPop(1.4);
            }
        }
        else
        {
            cptTimer.Stop();
            cible = t; montre = t; Nombre.Text = t.ToString();
        }
    }

    // La ligne ÉQUIPE (facultative) = mes coffres + ceux de mes equipiers (estimation). Sans animation.
    void MajEquipe()
    {
        var cfg = Donnees.LireCfg();
        if (!cfg.Equipe) { EquipeLigne.Visibility = Visibility.Collapsed; return; }
        var c = Donnees.LireCompteur();
        EquipeNombre.Text = (c != null ? Donnees.EquipeTotal(c, cfg) : 0).ToString();
        EquipeLigne.Visibility = Visibility.Visible;
    }

    // Nom lisible de la plateforme (le replay donne un code : WIN, XBL, PSN...).
    static string NomPlateforme(string code)
    {
        if (string.IsNullOrEmpty(code)) return "?";
        if (Regex.IsMatch(code, "^WIN$")) return "PC";
        if (Regex.IsMatch(code, "^MAC$")) return "MAC";
        if (Regex.IsMatch(code, "^LNX$")) return "LINUX";
        if (Regex.IsMatch(code, "^(PSN|PS4|PS5)$")) return "PLAYSTATION";
        if (Regex.IsMatch(code, "^(XBL|XB1|XSX)$")) return "XBOX";
        if (Regex.IsMatch(code, "^(SWT|NSW)$")) return "SWITCH";
        if (Regex.IsMatch(code, "^AND$")) return "ANDROID";
        if (Regex.IsMatch(code, "^IOS$")) return "IOS";
        return code.ToUpperInvariant();
    }

    // Le mini-resume de la partie, a la fin de la partie : classement, eliminations, plateforme de celui qui m'a elimine.
    void MajResume(bool afficher)
    {
        var cfg = Donnees.LireCfg();
        int place = 0, kills = 0; string tueur = "", plat = "";
        if (afficher)
        {
            var d = Donnees.LireCompteur()?.Derniere;
            if (d != null) { place = d.Place; kills = d.Kills; tueur = d.Tueur ?? ""; plat = d.TueurPlat ?? ""; }
        }
        if (place <= 0 || !afficher || !cfg.Resume) { ResumeLigne.Visibility = Visibility.Collapsed; return; }
        ResPlace.Text = place == 1 ? "VICTOIRE" : "#" + place;
        ResKills.Text = kills + " KILL" + (kills > 1 ? "S" : "");
        ResTueur.Text = place == 1 ? ""
            : tueur == "joueur" ? "TUÉ PAR " + NomPlateforme(plat)
            : tueur == "bot" ? "TUÉ PAR UN BOT"
            : tueur == "zone" ? "ZONE / CHUTE"
            : "";
        ResumeLigne.Visibility = Visibility.Visible;
    }

    // Le "+N" de la derniere partie. Regle (sans memoire, donc robuste) : on l'affiche si le replay le plus recent est TERMINE (plus ecrit
    // depuis AttenteFin s), deja lu, et pas plus vieux que dureeBadgeMinutes. Des qu'une nouvelle partie commence, un replay plus recent
    // apparait, il n'est ni termine ni lu : le "+N" disparait tout seul.
    void MajBadge()
    {
        var cfg = Donnees.LireCfg();
        int n = 0, ne = 0; bool afficher = false;
        try
        {
            var c = Donnees.LireCompteur();
            if (Directory.Exists(Chemins.Demos) && c?.Derniere != null)
            {
                var recent = new DirectoryInfo(Chemins.Demos).GetFiles("*.replay").OrderByDescending(f => f.LastWriteTime).FirstOrDefault();
                if (recent != null)
                {
                    var age = (DateTime.Now - recent.LastWriteTime).TotalSeconds;
                    if (recent.Name == c.Derniere.Fichier && age >= AttenteFin && age <= cfg.DureeBadgeMinutes * 60)
                    {
                        n = Donnees.Derniere(c, cfg);
                        ne = Donnees.EquipeDerniere(c, cfg);
                        afficher = true;
                    }
                }
            }
        }
        catch { }

        if (afficher && n > 0)
        {
            bool nouveau = ("+" + n) != Badge.Text || Badge.Visibility != Visibility.Visible;
            Badge.Text = "+" + n; Badge.Visibility = Visibility.Visible;
            if (nouveau && animer) AnimBadge();
        }
        else { Badge.Visibility = Visibility.Collapsed; Badge.Text = ""; }

        // le "+N" de l'equipe : meme regle, seulement si la ligne ÉQUIPE est affichee
        if (afficher && ne > 0 && EquipeLigne.Visibility == Visibility.Visible) { EquipeBadge.Text = "+" + ne; EquipeBadge.Visibility = Visibility.Visible; }
        else { EquipeBadge.Visibility = Visibility.Collapsed; EquipeBadge.Text = ""; }
        MajResume(afficher);
    }

    // ---------- utilise par le panneau ----------
    /// <summary>Applique les reglages (taille, position, transparence, options) : appele quand on les change.</summary>
    public void AppliquerCfg()
    {
        var cfg = Donnees.LireCfg();
        if (!Deplace) { Left = cfg.X; Top = cfg.Y; }
        Opacity = cfg.Opacity;
        Cadre.LayoutTransform = new ScaleTransform(cfg.Scale, cfg.Scale);
        affiche = -1;          // recalcule le total sans animation (option "compter les tombes", nombre de depart)
        MajNombre();
        MajEquipe();
        if (IsVisible) MajBadge();
    }

    /// <summary>A l'ouverture du compteur : AUCUNE animation. Le nombre (et le "+N" s'il y en a un) apparait directement.</summary>
    public void Afficher()
    {
        var anim = animer;
        animer = false;
        try
        {
            AppliquerCfg();
            Show();
            Systeme.FenetreTraversable(this, !Deplace);
            MajBadge();
        }
        finally { animer = anim; }
    }

    public void Masquer() => Hide();

    public void Tick()
    {
        if (!IsVisible) return;
        MajNombre();
        MajEquipe();
        MajBadge();
    }

    /// <summary>Mode "deplacer" : on peut saisir le coffre et le glisser ; clic droit pour valider la position.</summary>
    public void DeplacerDebut()
    {
        Deplace = true;
        Aide.Visibility = Visibility.Visible;
        if (!IsVisible) { AppliquerCfg(); Show(); }
        Systeme.FenetreTraversable(this, false);
    }

    void DeplacerFin()
    {
        var c = Donnees.LireCfg(); c.X = (int)Left; c.Y = (int)Top; Donnees.EcrireCfg(c);
        Deplace = false;
        Aide.Visibility = Visibility.Collapsed;
        Systeme.FenetreTraversable(this, true);
        FinDeplacement?.Invoke();
    }
}
