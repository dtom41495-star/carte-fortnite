// Petites fonctions Windows : Fortnite est-il ouvert ?, barre de titre sombre, fenetre "traversable" pour le compteur.
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace CarteFortnite;

public static class Systeme
{
    /// <summary>Fortnite est-il ouvert ? (simple recherche par nom : on n'ouvre aucun acces au jeu)</summary>
    public static bool FortniteOuvert()
    {
        try
        {
            var p = Process.GetProcessesByName("FortniteClient-Win64-Shipping");
            var n = p.Length;
            foreach (var x in p) x.Dispose();
            return n > 0;
        }
        catch { return false; }
    }

    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);

    /// <summary>Barre de titre sombre et aux couleurs du panneau (Windows 11 pour la couleur, Windows 10 pour le theme sombre).</summary>
    public static void BarreTitreSombre(Window fenetre)
    {
        try
        {
            var h = new WindowInteropHelper(fenetre).EnsureHandle();
            int v = 1; DwmSetWindowAttribute(h, 20, ref v, 4);                                   // theme sombre
            v = 0x0B | (0x16 << 8) | (0x50 << 16); DwmSetWindowAttribute(h, 35, ref v, 4);       // fond de la barre (bleu nuit)
            v = 0xFF | (0xFF << 8) | (0xFF << 16); DwmSetWindowAttribute(h, 36, ref v, 4);       // texte de la barre (blanc)
            v = 0xFF | (0xE5 << 8); DwmSetWindowAttribute(h, 34, ref v, 4);                      // lisere de la fenetre (jaune)
        }
        catch { }
    }

    /// <summary>Compteur : la souris traverse la fenetre et elle ne prend jamais le focus (le jeu reste actif).
    /// En mode "deplacer", on peut la saisir.</summary>
    public static void FenetreTraversable(Window w, bool traversable)
    {
        var h = new WindowInteropHelper(w).Handle;
        if (h == IntPtr.Zero) return;
        int ex = GetWindowLong(h, -20);
        ex |= 0x80;                                   // WS_EX_TOOLWINDOW : pas dans la barre des taches
        if (traversable) ex |= 0x20 | 0x08000000;     // WS_EX_TRANSPARENT | WS_EX_NOACTIVATE
        else ex &= ~(0x20 | 0x08000000);
        SetWindowLong(h, -20, ex);
    }
}
