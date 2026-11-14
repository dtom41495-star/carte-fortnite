using System.Windows;

namespace CarteFortnite;

/// <summary>Petite fenetre de message aux couleurs du panneau (a la place de la boite grise de Windows).</summary>
public partial class MessageDialog : Window
{
    MessageDialog(string titre, string texte, string ok, string non)
    {
        InitializeComponent();
        TitreMsg.Text = titre;
        TexteMsg.Text = texte;
        BtnOk.Content = ok;
        if (non != null) { BtnNon.Content = non; BtnNon.Visibility = Visibility.Visible; }
        else BtnNon.IsCancel = false;
        SourceInitialized += (_, _) => Systeme.BarreTitreSombre(this);
        BtnOk.Click += (_, _) => DialogResult = true;
        BtnNon.Click += (_, _) => DialogResult = false;
    }

    /// <summary>Affiche le message ; renvoie true si l'utilisateur clique sur le bouton principal.</summary>
    public static bool Afficher(Window parent, string titre, string texte, string ok = "COMPRIS", string non = null)
    {
        var d = new MessageDialog(titre, texte, ok, non);
        if (parent != null && parent.IsVisible) d.Owner = parent;
        return d.ShowDialog() == true;
    }
}
