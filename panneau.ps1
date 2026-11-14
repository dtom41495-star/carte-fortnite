# Panneau unique "Carte Fortnite" : tout se fait ici, avec des boutons.
#  - Ouvrir la carte de mes parties (lit d'abord tes replays)
#  - Afficher / masquer le petit compteur de coffres par-dessus le jeu, le déplacer, régler sa taille
# Lancé par Carte-Fortnite.bat (le seul fichier sur lequel cliquer). Aucun .exe : c'est un script texte lisible.
# Style inspiré de l'univers Fortnite (formes penchées, jaune et bleu nuit) : aucun logo, aucune police ni image d'Epic Games.
#
# IMPORTANT (anti-cheat) : ce panneau ne lance AUCUN programme une fois démarré. Au démarrage, il lance UNE seule fois un petit
# programme de surveillance (outil-perso) qui reste en veille et lit les replays quand une partie se termine. Le compteur par-dessus
# le jeu est une seconde fenêtre de CE programme (overlay\overlay-lib.ps1). Il n'interroge pas non plus la liste des programmes
# (pas de WMI) : Easy Anti-Cheat a fait planter Fortnite quand l'ancienne version le faisait. Ouvre-le AVANT de lancer Fortnite.
param(
    [string]$Capture = "",         # test : enregistre une image du panneau puis quitte
    [string]$Test = "",            # test : enchaîne les actions des boutons et écrit le résultat dans ce fichier
    [string]$ChargementTest = "",  # test : enregistre des images de l'animation de chargement dans ce dossier
    [string]$BoiteTest = "",       # test : enregistre une image de la boîte de message "Fortnite est ouvert" puis quitte
    [string]$CarteTest = ""        # test : ouvre la carte dans le panneau, la photographie, revient au panneau et écrit le résultat dans ce dossier
)
$ErrorActionPreference = "Stop"

$racine   = $PSScriptRoot
$donnees  = Join-Path $racine "donnees"
$dll      = Join-Path $racine "outil-perso\bin\Release\net10.0\CarteReplay.dll"
$demos    = Join-Path $env:LOCALAPPDATA "FortniteGame\Saved\Demos"
$cfgPath  = Join-Path $donnees "overlay.json"
$cptPath  = Join-Path $donnees "compteur.json"
$lecture  = Join-Path $donnees "derniere-lecture.txt"
$demande  = Join-Path $donnees "demande-lecture.txt"
$fini     = Join-Path $donnees "lecture-finie.txt"
$carte    = Join-Path $racine "carte.html"
$ico      = Join-Path $racine "ressources\coffre.ico"
$bat      = Join-Path $racine "Carte-Fortnite.bat"
$env:Path += ";C:\Program Files\dotnet"
New-Item -ItemType Directory -Force $donnees | Out-Null
function Journal($m) { try { Add-Content -Path (Join-Path $donnees "panneau-erreurs.txt") -Value ("{0} {1}" -f (Get-Date -Format s), $m) } catch { } }

# Un seul panneau à la fois
if ($Capture -eq "" -and $Test -eq "" -and $BoiteTest -eq "" -and $ChargementTest -eq "" -and $CarteTest -eq "") {
    $script:mutexP = New-Object System.Threading.Mutex($false, "Local\CarteCoffresPanneau")
    if (-not $script:mutexP.WaitOne(0)) { exit 0 }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------- l'apparence : les styles (boutons penchés, cases, curseur...) partagés par le panneau et les messages ----------
# Polices : Bahnschrift (livrée avec Windows 10 et 11) pour les titres et les chiffres ; si elle manque, Segoe UI prend le relais.
$stylesXaml = @'
    <Style x:Key="Titre" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Bahnschrift, Segoe UI"/>
      <Setter Property="FontStretch" Value="Condensed"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontStyle" Value="Italic"/>
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
    </Style>
    <Style x:Key="Etiquette" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Bahnschrift, Segoe UI"/>
      <Setter Property="FontStretch" Value="Condensed"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontStyle" Value="Italic"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Foreground" Value="#FFA9B9FF"/>
    </Style>
    <Style x:Key="Plaque" TargetType="Border">
      <Setter Property="BorderThickness" Value="0,4,0,0"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="RenderTransform"><Setter.Value><SkewTransform AngleX="-10"/></Setter.Value></Setter>
      <Setter Property="Background"><Setter.Value>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#FF2038B8" Offset="0"/>
          <GradientStop Color="#FF131F78" Offset="1"/>
        </LinearGradientBrush>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Principal" TargetType="Button">
      <Setter Property="Foreground" Value="#FF1A1200"/>
      <Setter Property="FontFamily" Value="Bahnschrift, Segoe UI"/>
      <Setter Property="FontStretch" Value="Condensed"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontStyle" Value="Italic"/>
      <Setter Property="FontSize" Value="22"/>
      <Setter Property="Padding" Value="24,10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border Background="#FF03071F" Margin="5,6,-5,-6" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
              </Border>
              <Grid x:Name="face">
                <Border x:Name="fond" RenderTransformOrigin="0.5,0.5" BorderBrush="#FFFFFBC0" BorderThickness="0,2,0,0">
                  <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                      <GradientStop Color="#FFFFF04A" Offset="0"/>
                      <GradientStop Color="#FFFFC400" Offset="1"/>
                    </LinearGradientBrush>
                  </Border.Background>
                  <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
                </Border>
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
              </Grid>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="fond" Property="Background" Value="#FFFFF98A"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="face" Property="RenderTransform">
                  <Setter.Value><TranslateTransform X="3" Y="4"/></Setter.Value>
                </Setter>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Secondaire" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="FontFamily" Value="Bahnschrift, Segoe UI"/>
      <Setter Property="FontStretch" Value="Condensed"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontStyle" Value="Italic"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="fond" Background="#FF17288F" BorderBrush="#FF2AD4FF" BorderThickness="0,0,0,3" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
              </Border>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="fond" Property="Background" Value="#FF2142C9"/>
                <Setter TargetName="fond" Property="BorderBrush" Value="#FFFFE500"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="fond" Property="Background" Value="#FF101C6E"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PisteVide" TargetType="RepeatButton">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PisteRemplie" TargetType="RepeatButton">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Grid Background="Transparent"><Border Height="6" VerticalAlignment="Center" Background="#FFFFE500"/></Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PouceJaune" TargetType="Thumb">
      <Setter Property="Width" Value="16"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border x:Name="p" Background="#FFFFE500" BorderBrush="#FF1A1200" BorderThickness="2" RenderTransformOrigin="0.5,0.5">
              <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="p" Property="Background" Value="#FFFFF6A0"/></Trigger>
              <Trigger Property="IsDragging" Value="True"><Setter TargetName="p" Property="Background" Value="#FFFFFFFF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PouceDefil" TargetType="Thumb">
      <Setter Property="MinHeight" Value="26"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb"><Border Background="#FFFFE500" Margin="1,0"/></ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Slider">
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid Height="28" Background="Transparent">
              <Border Height="6" VerticalAlignment="Center" Background="#FF0A1348" BorderBrush="#FF3A55B8" BorderThickness="1"/>
              <Track x:Name="PART_Track" VerticalAlignment="Center">
                <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Style="{StaticResource PisteRemplie}"/></Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Style="{StaticResource PisteVide}"/></Track.IncreaseRepeatButton>
                <Track.Thumb><Thumb Style="{StaticResource PouceJaune}"/></Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid Width="22" Height="22" Margin="0,1,10,0" VerticalAlignment="Top">
                <Border x:Name="boite" Background="#FF0A1348" BorderBrush="#FF7FA8FF" BorderThickness="2" RenderTransformOrigin="0.5,0.5">
                  <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
                </Border>
                <Path x:Name="coche" Data="M6,11.5 L10,15.5 L17,6.5" Stroke="#FF1A1200" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Grid>
              <ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="boite" Property="BorderBrush" Value="#FFFFE500"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="boite" Property="Background" Value="#FFFFE500"/>
                <Setter TargetName="boite" Property="BorderBrush" Value="#FFFFF9B0"/>
                <Setter TargetName="coche" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="CaretBrush" Value="#FFFFE500"/>
      <Setter Property="SelectionBrush" Value="#FFFFE500"/>
      <Setter Property="FontFamily" Value="Bahnschrift, Segoe UI"/>
      <Setter Property="FontSize" Value="18"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="6,3"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="cadre" Background="#FF0A1348" BorderBrush="#FF5C7DDB" BorderThickness="0,0,0,3" Padding="{TemplateBinding Padding}">
              <ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="cadre" Property="BorderBrush" Value="#FFA9C0FF"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="cadre" Property="BorderBrush" Value="#FFFFE500"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="#33000000">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Style="{StaticResource PisteVide}"/></Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Style="{StaticResource PisteVide}"/></Track.IncreaseRepeatButton>
                <Track.Thumb><Thumb Style="{StaticResource PouceDefil}"/></Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
'@

# Barre de titre de Windows : sombre et aux couleurs du panneau (Windows 11 pour la couleur, Windows 10 pour le thème sombre).
# Une seule fonction système (DwmSetWindowAttribute), créée en mémoire (Reflection.Emit) : aucun programme lancé.
function Creer-Api-Dwm {
    $an = New-Object System.Reflection.AssemblyName("DwmApi")
    $da = [AppDomain]::CurrentDomain.DefineDynamicAssembly($an, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $mb = $da.DefineDynamicModule("DwmApi")
    $tb = $mb.DefineType("DwmWin", "Public,Class")
    $attrs = [System.Reflection.MethodAttributes]"Public,Static,PinvokeImpl"
    $m = $tb.DefinePInvokeMethod("DwmSetWindowAttribute", "dwmapi.dll", $attrs, [System.Reflection.CallingConventions]::Standard, [int], [Type[]]@([IntPtr], [int], [int].MakeByRefType(), [int]), [System.Runtime.InteropServices.CallingConvention]::Winapi, [System.Runtime.InteropServices.CharSet]::Auto)
    $m.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)
    return $tb.CreateType()
}
$script:dwmApi = $null
try { $script:dwmApi = Creer-Api-Dwm } catch { }
function Barre-Titre-Sombre($fenetre) {
    if (-not $script:dwmApi) { return }
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $fenetre).EnsureHandle()
        $v = 1;                                          [void]$script:dwmApi::DwmSetWindowAttribute($h, 20, [ref]$v, 4)   # thème sombre
        $v = 0x0B -bor (0x16 -shl 8) -bor (0x50 -shl 16); [void]$script:dwmApi::DwmSetWindowAttribute($h, 35, [ref]$v, 4)   # fond de la barre (bleu nuit)
        $v = 0xFF -bor (0xFF -shl 8) -bor (0xFF -shl 16); [void]$script:dwmApi::DwmSetWindowAttribute($h, 36, [ref]$v, 4)   # texte de la barre (blanc)
        $v = 0xFF -bor (0xE5 -shl 8);                    [void]$script:dwmApi::DwmSetWindowAttribute($h, 34, [ref]$v, 4)   # liseré de la fenêtre (jaune)
    } catch { }
}

# Fortnite est-il ouvert ? (simple recherche par nom : on n'ouvre aucun accès au jeu)
function Fortnite-Ouvert {
    try {
        $p = [System.Diagnostics.Process]::GetProcessesByName('FortniteClient-Win64-Shipping')
        $n = $p.Count
        foreach ($x in $p) { $x.Dispose() }
        return ($n -gt 0)
    } catch { return $false }
}

# Enregistre une image d'un élément de la fenêtre (utilisé seulement par les tests).
function Rendre-Image($element, [string]$fichier) {
    $w = [int][Math]::Ceiling($element.ActualWidth); $h = [int][Math]::Ceiling($element.ActualHeight)
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen(); $dc.DrawRectangle((New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(7, 13, 43))), $null, (New-Object System.Windows.Rect(0, 0, $w, $h))); $dc.Close()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv); $rtb.Render($element)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($fichier); $enc.Save($fs); $fs.Close()
}

# L'icône de la fenêtre est chargée EN MÉMOIRE (OnLoad) : le fichier n'est pas verrouillé, on peut le remplacer pendant que le panneau tourne.
function Charger-Icone($fenetre) {
    if (-not (Test-Path $ico)) { return }
    try {
        $fenetre.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $ico), [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    } catch { }
}

# Petite fenêtre de message aux couleurs du panneau (à la place de la boîte grise de Windows).
function Boite-Message([string]$texte, [string]$titre = "ATTENTION", [string]$fichierImage = "") {
    try {
        [xml]$bx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Carte Fortnite" Width="480" SizeToContent="Height" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#FF070D2B" FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True" Topmost="True">
  <Window.Resources>
$stylesXaml
  </Window.Resources>
  <Grid>
    <Grid.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="0.35,1">
        <GradientStop Color="#FF0E1A5E" Offset="0"/>
        <GradientStop Color="#FF0A1248" Offset="0.55"/>
        <GradientStop Color="#FF1A0E56" Offset="1"/>
      </LinearGradientBrush>
    </Grid.Background>
    <StackPanel Margin="26,22,26,22">
      <TextBlock Name="TitreMsg" Style="{StaticResource Titre}" FontSize="32" Foreground="#FFFFE500"/>
      <Rectangle Width="100" Height="6" HorizontalAlignment="Left" Fill="#FFFFE500" Margin="4,4,0,10" RenderTransformOrigin="0.5,0.5">
        <Rectangle.RenderTransform><SkewTransform AngleX="-10"/></Rectangle.RenderTransform>
      </Rectangle>
      <TextBlock Name="TexteMsg" TextWrapping="Wrap" Foreground="#FFFFFFFF" FontSize="14" Margin="0,4,0,20"/>
      <Button Name="BtnOk" Style="{StaticResource Principal}" Content="COMPRIS" IsDefault="True" IsCancel="True" HorizontalAlignment="Right" Width="180" Margin="0,0,6,6"/>
    </StackPanel>
  </Grid>
</Window>
"@
        $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $bx))
        $w.FindName("TitreMsg").Text = $titre
        $w.FindName("TexteMsg").Text = $texte
        Charger-Icone $w
        $w.Add_SourceInitialized({ param($s, $e) Barre-Titre-Sombre $s })
        $w.FindName("BtnOk").Add_Click({ param($s, $e) [System.Windows.Window]::GetWindow($s).Close() })
        if ($fichierImage -ne "") {      # test : on photographie la boîte puis on la ferme
            $script:boiteW = $w; $script:boiteImg = $fichierImage
            $w.Add_ContentRendered({
                $script:boiteW.Dispatcher.BeginInvoke([Action]{ Rendre-Image $script:boiteW.Content $script:boiteImg; $script:boiteW.Close() }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
            })
        }
        [void]$w.ShowDialog()
    } catch {
        Journal ("Boite-Message : " + $_.Exception.Message)
        [void][System.Windows.MessageBox]::Show($texte, "Carte Fortnite")
    }
}
# Message à l'écran (pas de fenêtre noire). En test, on écrit le message dans un fichier au lieu de l'afficher.
function Dire-Et-Quitter([string]$texte, [string]$titre = "ATTENTION") {
    if ($env:CARTE_TEST_MESSAGE) { Set-Content -Path $env:CARTE_TEST_MESSAGE -Value $texte; exit 1 }
    Boite-Message $texte $titre
    exit 1
}
if ($BoiteTest -ne "") {
    Boite-Message "Fortnite est ouvert : Carte Fortnite ne démarre pas.`n`nOuvrir cette application pendant le jeu peut faire planter Easy Anti-Cheat. Ferme Fortnite, lance Carte Fortnite, PUIS relance Fortnite." "FORTNITE EST OUVERT" $BoiteTest
    exit 0
}
if ($Capture -eq "" -and $Test -eq "") {
    # Protection anti-cheat : on ne démarre RIEN si Fortnite est déjà ouvert (ouvrir l'application pendant le jeu a fait planter Easy Anti-Cheat).
    if (Fortnite-Ouvert) {
        Dire-Et-Quitter "Fortnite est ouvert : Carte Fortnite ne démarre pas.`n`nOuvrir cette application pendant le jeu peut faire planter Easy Anti-Cheat. Ferme Fortnite, lance Carte Fortnite, PUIS relance Fortnite." "FORTNITE EST OUVERT"
    }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue) -and -not (Test-Path "C:\Program Files\dotnet\dotnet.exe")) {
        Dire-Et-Quitter "Le SDK .NET est introuvable. Installe-le une seule fois avec la commande :`n`nwinget install Microsoft.DotNet.SDK.10`n`n(ou depuis https://dotnet.microsoft.com/download), puis relance Carte Fortnite." "OUTIL MANQUANT"
    }
}

# ---------- raccourci avec l'icône de coffre (un .bat ne peut pas avoir d'icône, un raccourci oui) ----------
function Creer-Raccourci([string]$dossier) {
    $lnk = Join-Path $dossier "Carte Fortnite.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    # Le raccourci lance DIRECTEMENT le panneau, sans passer par un .bat (donc sans fenêtre cmd) : conhost --headless = aucune console visible.
    $s.TargetPath = Join-Path $env:SystemRoot "System32\conhost.exe"
    $s.Arguments = '--headless "' + (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") + '" -NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $racine "panneau.ps1") + '"'
    $s.WorkingDirectory = $racine
    $s.WindowStyle = 7
    if (Test-Path $ico) { $s.IconLocation = "$ico,0" }
    $s.Description = "Carte Fortnite : mes coffres, mon trajet, mon atterrissage"
    $s.Save()
    return $lnk
}
# (le raccourci du dossier est remis à jour juste après l'affichage de la fenêtre : voir Charger-Initial)

# ---------- réglages (donnees\overlay.json) ----------
function Lire-Cfg {
    $c = [ordered]@{ x = 20; y = 20; scale = 0.5; opacity = 0.92; compterTombes = $true; dureeBadgeMinutes = 10; depart = 0; equipe = $false; resume = $true }
    if (Test-Path $cfgPath) {
        try { $lu = Get-Content $cfgPath -Raw | ConvertFrom-Json; foreach ($k in @($c.Keys)) { if ($null -ne $lu.$k) { $c[$k] = $lu.$k } } } catch { }
    }
    return $c
}
# La page carte.html lit donnees\reglages.js (nombre de départ, option des coffres tombés) : on le tient à jour avec les réglages.
function Ecrire-Reglages-Js($c) {
    try {
        $o = [ordered]@{ depart = [int]$c.depart; compterTombes = [bool]$c.compterTombes }
        ("window.REGLAGES = " + ($o | ConvertTo-Json -Compress) + ";") | Set-Content -Path (Join-Path $donnees "reglages.js") -Encoding UTF8
    } catch { }
}
function Ecrire-Cfg($c) { ($c | ConvertTo-Json) | Set-Content -Path $cfgPath -Encoding UTF8; Ecrire-Reglages-Js $c }
Ecrire-Reglages-Js (Lire-Cfg)

# Totaux affichés (panneau, compteur, carte) : nombre de départ + coffres lus (+ tombés/cassés si l'option est cochée)
function Total-Compteur($c) {
    $cfg = Lire-Cfg
    $t = [int]$cfg.depart + [int]$c.coffres
    if ($cfg.compterTombes) { $t += [int]$c.tombes }
    return $t
}
function Derniere-Compteur($c) {
    if (-not $c.derniere) { return 0 }
    $n = [int]$c.derniere.coffres
    if ((Lire-Cfg).compterTombes) { $n += [int]$c.derniere.tombes }
    return $n
}

# ---------- coffres de l'ÉQUIPE : moi + mes équipiers ----------
# Mes coffres sont exacts ; ceux des équipiers sont une ESTIMATION (l'outil les écrit dans compteur.json, champ "equipiers"). Mes compteurs
# personnels ne changent pas : l'équipe s'affiche EN PLUS. Même option « tombés / cassés » que pour moi. Le nombre de départ n'est pas compté.
function Equipe-Total($c) {
    $t = [int]$c.coffres + [int]$c.equipiers
    if ((Lire-Cfg).compterTombes) { $t += [int]$c.tombes }
    return $t
}
function Equipe-Derniere($c) {
    if (-not $c.derniere) { return 0 }
    $n = [int]$c.derniere.coffres + [int]$c.derniere.equipiers
    if ((Lire-Cfg).compterTombes) { $n += [int]$c.derniere.tombes }
    return $n
}

# ---------- lancer un programme SANS aucune fenêtre de console ----------
# Avec Windows Terminal comme terminal par défaut, "-WindowStyle Hidden" ne cache pas vraiment la fenêtre : on la voyait rester ouverte,
# et la fermer coupait l'application. CREATE_NO_WINDOW (CreateNoWindow) ne crée aucune fenêtre : il n'y a plus rien à fermer par erreur.
# (Utilisé UNE fois, au démarrage, pour le programme de surveillance.)
function Lancer-Cache([string]$exe, [string]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}
function Chemin-Dotnet {
    $d = (Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $d) { $d = "C:\Program Files\dotnet\dotnet.exe" }
    return $d
}

# ---------- le compteur par-dessus le jeu : seconde fenêtre de CE programme ----------
. (Join-Path $racine "overlay\overlay-lib.ps1")

# ---------- la fenêtre ----------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Carte Fortnite" Width="500" SizeToContent="Height" WindowStartupLocation="CenterScreen"
        ResizeMode="CanMinimize" Background="#FF070D2B" FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
$stylesXaml
  </Window.Resources>
  <Grid>
    <Grid.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="0.35,1">
        <GradientStop Color="#FF0E1A5E" Offset="0"/>
        <GradientStop Color="#FF0A1248" Offset="0.55"/>
        <GradientStop Color="#FF1A0E56" Offset="1"/>
      </LinearGradientBrush>
    </Grid.Background>
    <Grid Name="VuePanneau">
    <Canvas IsHitTestVisible="False" ClipToBounds="True">
      <Polygon Points="300,0 430,0 250,1500 120,1500" Fill="#0BFFFFFF"/>
      <Polygon Points="450,0 520,0 340,1500 270,1500" Fill="#08FFFFFF"/>
    </Canvas>
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
      <StackPanel Margin="26,20,26,18">

        <Grid Margin="0,0,0,16">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Viewbox Width="66" Height="58" VerticalAlignment="Top" Margin="0,2,14,0">
            <Canvas Width="46" Height="40">
              <Path Data="M3,17 L3,11 Q3,2 12,2 L34,2 Q43,2 43,11 L43,17 Z" Stroke="#FF3D2400" StrokeThickness="2" StrokeLineJoin="Round">
                <Path.Fill>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#FFFFC531" Offset="0"/><GradientStop Color="#FFF2A71F" Offset="1"/></LinearGradientBrush>
                </Path.Fill>
              </Path>
              <Rectangle Canvas.Left="3" Canvas.Top="16" Width="40" Height="21" Stroke="#FF3D2400" StrokeThickness="2" RadiusX="3" RadiusY="3">
                <Rectangle.Fill>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#FFFFE24A" Offset="0"/><GradientStop Color="#FFFFB800" Offset="1"/></LinearGradientBrush>
                </Rectangle.Fill>
              </Rectangle>
              <Rectangle Canvas.Left="3" Canvas.Top="15" Width="40" Height="4" Fill="#FF7A5200"/>
              <Rectangle Canvas.Left="10" Canvas.Top="3" Width="4" Height="33" Fill="#FF7A5200"/>
              <Rectangle Canvas.Left="32" Canvas.Top="3" Width="4" Height="33" Fill="#FF7A5200"/>
              <Path Data="M6,9 Q7,5 13,4.5 L19,4.5" Stroke="#B3FFFFFF" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
              <Rectangle Canvas.Left="18.5" Canvas.Top="12" Width="9" Height="12" Fill="#FF2A1900" Stroke="#FFFFF08A" StrokeThickness="1.2" RadiusX="2" RadiusY="2"/>
              <Ellipse Canvas.Left="21.2" Canvas.Top="15.4" Width="3.6" Height="3.6" Fill="#FFFFF08A"/>
            </Canvas>
          </Viewbox>
          <StackPanel Grid.Column="1">
            <TextBlock Text="CARTE FORTNITE" Style="{StaticResource Titre}" FontSize="42">
              <TextBlock.Effect><DropShadowEffect Color="#FF000000" Opacity="0.55" ShadowDepth="3" BlurRadius="0" Direction="300"/></TextBlock.Effect>
            </TextBlock>
            <Rectangle Width="120" Height="6" HorizontalAlignment="Left" Fill="#FFFFE500" Margin="4,2,0,8" RenderTransformOrigin="0.5,0.5">
              <Rectangle.RenderTransform><SkewTransform AngleX="-10"/></Rectangle.RenderTransform>
            </Rectangle>
            <TextBlock Text="Tes parties, lues dans tes replays." Foreground="#FFA9B9FF" TextWrapping="Wrap"/>
          </StackPanel>
        </Grid>

        <Border Name="Alerte" Visibility="Collapsed" Background="#FF4A1230" BorderBrush="#FFFF4D6D" BorderThickness="5,0,0,0" Padding="14,10" Margin="0,0,0,14">
          <StackPanel>
            <TextBlock Text="FORTNITE EST OUVERT" Style="{StaticResource Titre}" FontSize="17" Foreground="#FFFF8FA3"/>
            <TextBlock Foreground="#FFFFE0E6" FontSize="12.5" TextWrapping="Wrap" Margin="0,3,0,0"
                       Text="Ouvrir cette application pendant le jeu a fait planter Easy Anti-Cheat : ferme le jeu, ferme et rouvre Carte Fortnite, puis relance Fortnite."/>
          </StackPanel>
        </Border>

        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Grid Grid.Column="0" Margin="0,0,7,0">
            <Border Style="{StaticResource Plaque}" BorderBrush="#FFFFE500"/>
            <StackPanel Margin="18,8,6,10">
              <TextBlock Name="Total" Text="…" Style="{StaticResource Titre}" FontSize="44" Foreground="#FFFFE500"/>
              <TextBlock Text="COFFRES AU TOTAL" Style="{StaticResource Etiquette}"/>
              <TextBlock Name="EquipeTotal" Text="ÉQUIPE  0" Style="{StaticResource Titre}" FontSize="17" Foreground="#FF2AD4FF" Margin="0,5,0,0" ToolTip="Coffres de ton équipe (toi + tes équipiers) dans toutes les parties lues. Les tiens sont exacts, ceux de tes équipiers sont une estimation."/>
            </StackPanel>
          </Grid>
          <Grid Grid.Column="1" Margin="7,0,7,0">
            <Border Style="{StaticResource Plaque}" BorderBrush="#FF5CF08A"/>
            <StackPanel Margin="18,8,6,10">
              <TextBlock Name="Derniere" Text="…" Style="{StaticResource Titre}" FontSize="44" Foreground="#FF5CF08A"/>
              <TextBlock Text="DERNIÈRE PARTIE" Style="{StaticResource Etiquette}"/>
              <TextBlock Name="EquipeDerniere" Text="ÉQUIPE  0" Style="{StaticResource Titre}" FontSize="17" Foreground="#FF2AD4FF" Margin="0,5,0,0" ToolTip="Coffres de ton équipe (toi + tes équipiers) dans la dernière partie. Les tiens sont exacts, ceux de tes équipiers sont une estimation."/>
            </StackPanel>
          </Grid>
          <Grid Grid.Column="2" Margin="7,0,0,0">
            <Border Style="{StaticResource Plaque}" BorderBrush="#FF2AD4FF"/>
            <StackPanel Margin="18,8,6,10">
              <TextBlock Name="Parties" Text="…" Style="{StaticResource Titre}" FontSize="44" Foreground="#FFFFFFFF"/>
              <TextBlock Text="PARTIES LUES" Style="{StaticResource Etiquette}"/>
            </StackPanel>
          </Grid>
        </Grid>

        <Grid Margin="2,14,2,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBlock Text="Coffres déjà ouverts avant l'outil (facultatif)" Foreground="#FFA9B9FF" FontSize="12.5" VerticalAlignment="Center" TextWrapping="Wrap"/>
          <TextBox Name="Depart" Grid.Column="1" Width="92" Text="0" TextAlignment="Center" Margin="12,0,0,0"
                   ToolTip="Ajouté au total (panneau, compteur et carte). Laisse 0 si tu ne veux rien ajouter."/>
        </Grid>

        <Grid Name="Barre" Height="8" Margin="4,14,4,0" Visibility="Collapsed" ClipToBounds="True" RenderTransformOrigin="0.5,0.5">
          <Grid.RenderTransform><SkewTransform AngleX="-10"/></Grid.RenderTransform>
          <Border Background="#33FFFFFF"/>
          <Border Name="Morceau" Width="150" HorizontalAlignment="Left" Background="#FFFFE500">
            <Border.RenderTransform><TranslateTransform X="-150"/></Border.RenderTransform>
          </Border>
        </Grid>

        <Button Name="BtnCarte" Style="{StaticResource Principal}" Content="OUVRIR LA CARTE DE MES PARTIES" Margin="0,14,6,12"/>

        <StackPanel Orientation="Horizontal" Margin="0,18,0,10">
          <Rectangle Width="10" Height="19" Fill="#FFFFE500" RenderTransformOrigin="0.5,0.5" Margin="0,2,10,0">
            <Rectangle.RenderTransform><SkewTransform AngleX="-10"/></Rectangle.RenderTransform>
          </Rectangle>
          <TextBlock Text="COMPTEUR PAR-DESSUS LE JEU" Style="{StaticResource Titre}" FontSize="20"/>
        </StackPanel>
        <Border Background="#B30A1348" BorderBrush="#FFFFE500" BorderThickness="5,0,0,0" Padding="16,14,16,14">
          <StackPanel>
            <CheckBox Name="ChkOverlay"><TextBlock Text="Afficher le compteur de coffres" FontWeight="SemiBold" FontSize="15"/></CheckBox>
            <Grid Margin="0,14,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Text="TAILLE" Style="{StaticResource Etiquette}" FontSize="15" VerticalAlignment="Center" Margin="0,0,14,0"/>
              <Slider Name="Taille" Grid.Column="1" Minimum="30" Maximum="120" TickFrequency="10" IsSnapToTickEnabled="False" VerticalAlignment="Center"/>
              <TextBlock Name="TailleTxt" Grid.Column="2" Text="50 %" Style="{StaticResource Titre}" FontSize="18" Foreground="#FFFFE500" VerticalAlignment="Center" Margin="14,0,0,0" MinWidth="52" TextAlignment="Right"/>
            </Grid>
            <Button Name="BtnDepl" Style="{StaticResource Secondaire}" Content="DÉPLACER LE COMPTEUR SUR L'ÉCRAN" Margin="0,14,4,0"/>
            <CheckBox Name="ChkTombes" Margin="0,14,0,0"><TextBlock Text="Compter aussi les coffres tombés ou cassés (estimation)" TextWrapping="Wrap"/></CheckBox>
            <CheckBox Name="ChkEquipe" Margin="0,12,0,0"><TextBlock Text="Afficher aussi les coffres de l'équipe sur le compteur" TextWrapping="Wrap"/></CheckBox>
            <CheckBox Name="ChkResume" Margin="0,10,0,0" ToolTip="À la fin d'une partie : ton classement, ton nombre de kills et la plateforme de celui qui t'a tué (PC, Xbox, PlayStation...)."><TextBlock Text="Mini-résumé de fin de partie sur le compteur" TextWrapping="Wrap"/></CheckBox>
            <TextBlock Foreground="#FFA9B9FF" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"
                       Text="À la fin d'une partie, un petit « +N » vert montre les coffres de cette partie ; il disparaît quand la suivante commence. Fonctionne en plein écran fenêtré."/>
          </StackPanel>
        </Border>

        <Border Margin="0,16,0,0" Background="#B30A1348" BorderBrush="#FF2AD4FF" BorderThickness="5,0,0,0" Padding="14,9">
          <Border.Style>
            <Style TargetType="Border">
              <Style.Triggers>
                <DataTrigger Binding="{Binding Text, ElementName=Etat}" Value="">
                  <Setter Property="Visibility" Value="Collapsed"/>
                </DataTrigger>
              </Style.Triggers>
            </Style>
          </Border.Style>
          <TextBlock Name="Etat" Text="" Foreground="#FFE8EEFF" TextWrapping="Wrap" MinHeight="18"/>
        </Border>

        <Border Margin="0,16,0,0" Background="#800A1348" BorderBrush="#FFFFB81C" BorderThickness="5,0,0,0" Padding="14,10">
          <StackPanel>
            <TextBlock Text="RÈGLE ANTI-TRICHE" Style="{StaticResource Titre}" FontSize="16" Foreground="#FFFFB81C"/>
            <TextBlock Foreground="#FFB9C6F2" FontSize="11.5" TextWrapping="Wrap" Margin="0,4,0,0"
                       Text="Ouvre cette application AVANT de lancer Fortnite et ne la relance pas pendant que le jeu tourne : Easy Anti-Cheat a fait planter le jeu dans ce cas. Le compteur est une fenêtre de ce programme, il ne touche pas au jeu et ne lit que tes fichiers de replay. La carte ne s'affiche dans ce panneau que si Fortnite est fermé (et se ferme toute seule si le jeu s'ouvre). Epic ne publie pas de liste d'outils autorisés : à utiliser en connaissance de cause. En cas de doute, n'affiche pas le compteur."/>
          </StackPanel>
        </Border>

        <Button Name="BtnRaccourci" Style="{StaticResource Secondaire}" Content="CRÉER UN RACCOURCI SUR LE BUREAU" Margin="0,18,4,0"/>
        <Button Name="BtnQuitter" Style="{StaticResource Secondaire}" Content="RÉDUIRE CE PANNEAU (LE COMPTEUR RESTE AFFICHÉ)" Margin="0,10,4,0"/>
        <TextBlock Text="La croix en haut à droite ferme le panneau ET le compteur." Foreground="#FF8E9FE0" FontSize="11" Margin="2,10,2,0"/>
        <TextBlock Text="Outil de fan, non affilié à Epic Games. « Fortnite » est une marque d'Epic Games." Foreground="#FF6C7DBF" FontSize="10.5" TextWrapping="Wrap" Margin="2,10,2,0"/>
      </StackPanel>
    </ScrollViewer>
    </Grid>

    <!-- la carte, DANS la fenêtre : une barre avec le bouton « Retour », puis la zone où s'affiche la page (le moteur web est créé dans le code) -->
    <DockPanel Name="VueCarte" Visibility="Collapsed" LastChildFill="True">
      <Border DockPanel.Dock="Top" Padding="14,8,14,8" BorderBrush="#FFFFE500" BorderThickness="0,0,0,3">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#FF0E1A5E" Offset="0"/>
            <GradientStop Color="#FF1A0E56" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <Grid>
          <Button Name="BtnRetour" Style="{StaticResource Secondaire}" Content="← RETOUR" HorizontalAlignment="Left" Width="132" Margin="0,0,0,2" ToolTip="Revenir au panneau"/>
          <TextBlock Text="CARTE FORTNITE" Style="{StaticResource Titre}" FontSize="26" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
      </Border>
      <Grid Name="ZoneCarte" Background="#FF070D2B"/>
    </DockPanel>
  </Grid>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
foreach ($n in 'VuePanneau','VueCarte','BtnRetour','ZoneCarte','Alerte','Total','Derniere','Parties','Depart','Barre','Morceau','BtnCarte','ChkOverlay','Taille','TailleTxt','BtnDepl','ChkTombes','Etat','BtnRaccourci','BtnQuitter','EquipeTotal','EquipeDerniere','ChkEquipe','ChkResume') { Set-Variable -Name "c$n" -Value $win.FindName($n) -Scope Script }

Charger-Icone $win
$win.Add_SourceInitialized({ param($s, $e) Barre-Titre-Sombre $s })
# Sur un petit écran, la fenêtre ne dépasse pas la zone de travail : une barre de défilement apparaît (pas en test, pour tout photographier).
if ($Capture -eq "" -and $Test -eq "") { $win.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height }

function Attendre([double]$s) {
    $fin = (Get-Date).AddSeconds($s)
    while ((Get-Date) -lt $fin) {
        $f = New-Object System.Windows.Threading.DispatcherFrame
        [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Action]{ $f.Continue = $false }, [System.Windows.Threading.DispatcherPriority]::Background)
        [System.Windows.Threading.Dispatcher]::PushFrame($f)
        Start-Sleep -Milliseconds 15
    }
}
function Image-Panneau([string]$fichier) { Rendre-Image $win.Content $fichier }

$cfg = Lire-Cfg
$script:sync = $true
$cChkTombes.IsChecked = [bool]$cfg.compterTombes
$cChkEquipe.IsChecked = [bool]$cfg.equipe
$cChkResume.IsChecked = [bool]$cfg.resume
$cTaille.Value = [Math]::Round([double]$cfg.scale * 100)
$cTailleTxt.Text = "$([int]$cTaille.Value) %"
$cDepart.Text = "$([int]$cfg.depart)"
$script:sync = $false

# ---------- la barre de chargement : un morceau jaune penché qui glisse tant que l'outil travaille ----------
$script:morceauTr = $cMorceau.RenderTransform
$script:barreAnim = $false
function Barre-Marche([bool]$on) {
    if ($on) {
        $cBarre.Visibility = "Visible"
        if (-not $script:barreAnim) {
            $a = New-Object System.Windows.Media.Animation.DoubleAnimation(-150.0, 470.0, [TimeSpan]::FromMilliseconds(1100))
            $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $script:morceauTr.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
            $script:barreAnim = $true
        }
    } else {
        $cBarre.Visibility = "Collapsed"
        if ($script:barreAnim) {
            $script:morceauTr.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
            $script:barreAnim = $false
        }
    }
}

# ---------- chargement : les chiffres clignotent doucement et une barre tourne, puis les vrais nombres apparaissent d'un coup ----------
$script:chargementActif = $false
function Pulse-Chiffres([bool]$on) {
    foreach ($tb in @($cTotal, $cDerniere, $cParties, $cEquipeTotal, $cEquipeDerniere)) {
        if ($on) {
            $a = New-Object System.Windows.Media.Animation.DoubleAnimation(0.25, 1.0, [TimeSpan]::FromMilliseconds(650))
            $a.AutoReverse = $true; $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $tb.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
        } else {
            $tb.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null); $tb.Opacity = 1
        }
    }
}
function Demarrer-Chargement([string]$message) {
    $script:chargementActif = $true
    $cTotal.Text = "…"; $cDerniere.Text = "…"; $cParties.Text = "…"; $cEquipeTotal.Text = "ÉQUIPE  …"; $cEquipeDerniere.Text = "ÉQUIPE  …"
    Pulse-Chiffres $true
    Barre-Marche $true
    $cEtat.Text = $message
}
function Arreter-Chargement {
    $script:chargementActif = $false
    Pulse-Chiffres $false
    Barre-Marche $false
    if ($cTotal.Text -eq "…") { Afficher-Chiffres ([int](Lire-Cfg).depart) 0 0 }     # pas encore de données : on montre le nombre de départ
}
# Les nombres apparaissent DIRECTEMENT avec leur vraie valeur : pas de comptage depuis 0 (avec 3000 coffres, ce serait long).
function Afficher-Chiffres([int]$t, [int]$d, [int]$p, [int]$et = 0, [int]$ed = 0) {
    $cTotal.Text = "$t"; $cDerniere.Text = "$d"; $cParties.Text = "$p"
    $cEquipeTotal.Text = "ÉQUIPE  $et"; $cEquipeDerniere.Text = "ÉQUIPE  $ed"
}

# ---------- chiffres en haut ----------
function Maj-Chiffres {
    if (-not (Test-Path $cptPath)) {
        # pas encore de données : le total est au moins le nombre de départ
        if ($cTotal.Text -eq "…" -and $script:chargementActif -eq $false) { Afficher-Chiffres ([int](Lire-Cfg).depart) 0 0 }
        return
    }
    try {
        $c = Get-Content $cptPath -Raw | ConvertFrom-Json
        Afficher-Chiffres (Total-Compteur $c) (Derniere-Compteur $c) ([int]$c.parties) (Equipe-Total $c) (Equipe-Derniere $c)
    } catch { }
}
if ($Capture -ne "" -or $Test -ne "" -or $CarteTest -ne "") { Maj-Chiffres }   # en usage normal : voir Charger-Initial (après l'affichage de la fenêtre)

# ---------- le programme de surveillance : lancé UNE fois au démarrage, reste en veille ----------
$script:surv = $null
function Demarrer-Surveillance {
    if (-not (Test-Path $dll)) { return }
    $arguments = '"' + $dll + '" --surveiller --parent ' + $PID + ' --attente 25 --sortie "' + $donnees + '" "' + $demos + '"'
    $script:surv = Lancer-Cache (Chemin-Dotnet) $arguments
}
function Arreter-Tout {
    try { Liberer-Carte } catch { }                  # le moteur web de la carte (s'il est ouvert) s'arrête avec le panneau
    if ($script:surv -and -not $script:surv.HasExited) { try { $script:surv.Kill() } catch { } }
    Ov-Fermer
}
$win.Add_Closing({ Arreter-Tout })

# ---------- la carte DANS l'appli (et plus dans le navigateur) ----------
# La page carte.html s'affiche dans le moteur web de Windows (WebView2, le même qu'Edge), à l'intérieur de CE panneau, avec un bouton « Retour ».
# Anti-cheat : le moteur web n'est démarré QUE quand on ouvre la carte, et seulement si Fortnite est fermé ; il est libéré (ses programmes
# s'arrêtent) dès qu'on clique sur « Retour » ; et la carte se ferme toute seule si Fortnite s'ouvre. Rien de plus ne tourne pendant le jeu.
# Le composant d'affichage (paquet NuGet Microsoft.Web.WebView2) est récupéré par « dotnet build » avec le reste, au premier lancement.
# Si le moteur web n'est pas disponible sur ce PC, la carte s'ouvre dans le navigateur comme avant.
$script:carteOuverte = $false
$script:wv = $null
$script:wvCharge = $false
$script:wvEchec = $false
$script:carteFinie = $false
$script:carteDebutLe = Get-Date
$script:avantGauche = 0; $script:avantHaut = 0; $script:compteurAvant = $false

function Trouver-WebView2 {
    $dossiers = @()
    if ($env:NUGET_PACKAGES) { $dossiers += (Join-Path $env:NUGET_PACKAGES "microsoft.web.webview2") }
    $dossiers += (Join-Path $env:USERPROFILE ".nuget\packages\microsoft.web.webview2")
    foreach ($d in $dossiers) {
        if (-not (Test-Path $d)) { continue }
        $v = Get-ChildItem $d -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName "lib\net462\Microsoft.Web.WebView2.Wpf.dll") } |
            Sort-Object { try { [version]($_.Name -replace '-.*$', '') } catch { [version]'0.0' } } -Descending | Select-Object -First 1
        if ($v) { return $v.FullName }
    }
    return $null
}
function Charger-WebView2 {
    if ($script:wvCharge) { return $true }
    $pkg = Trouver-WebView2
    if (-not $pkg) { Journal "WebView2 : composant introuvable (il est récupéré par dotnet build au premier lancement)"; return $false }
    try {
        $env:Path += ";" + (Join-Path $pkg "runtimes\win-x64\native")                      # WebView2Loader.dll
        Add-Type -AssemblyName System.Drawing
        Add-Type -Path (Join-Path $pkg "lib\net462\Microsoft.Web.WebView2.Core.dll")
        Add-Type -Path (Join-Path $pkg "lib\net462\Microsoft.Web.WebView2.Wpf.dll")
        $v = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()
        if (-not $v) { Journal "WebView2 : moteur web introuvable sur ce PC"; return $false }
        $script:wvCharge = $true
        return $true
    } catch { Journal ("WebView2 : " + $_.Exception.Message); return $false }
}
# Arrête complètement le moteur web (ses programmes s'arrêtent avec lui).
function Liberer-Carte {
    $wv = $script:wv; $script:wv = $null
    if ($wv) {
        try { [void]$cZoneCarte.Children.Remove($wv) } catch { }
        try { $wv.Dispose() } catch { Journal ("WebView2 Dispose : " + $_.Exception.Message) }
    }
}
# Remet le panneau (vue, taille, position, compteur).
function Rendre-Panneau {
    $cVueCarte.Visibility = "Collapsed"; $cVuePanneau.Visibility = "Visible"
    $win.MinWidth = 0; $win.MinHeight = 0
    $win.ResizeMode = 'CanMinimize'; $win.SizeToContent = 'Height'; $win.Width = 500
    $win.Left = $script:avantGauche; $win.Top = $script:avantHaut
    if ($script:compteurAvant) { $script:compteurAvant = $false; try { Ov-Afficher } catch { Journal ("Ov-Afficher : " + $_.Exception.Message) } }
}
# $true = la carte est ouverte dans l'appli ; $false = pas possible ici (l'appelant l'ouvre alors dans le navigateur).
function Afficher-Carte {
    if ($script:carteOuverte) { return $true }
    if (Fortnite-Ouvert) { return $false }                      # jamais pendant le jeu
    if (-not (Charger-WebView2)) { return $false }
    try {
        $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
        $cp = New-Object Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties
        $cp.UserDataFolder = Join-Path $env:LOCALAPPDATA "CarteFortnite\WebView2"
        try { $cp.IsInPrivateModeEnabled = $true } catch { }          # rien n'est gardé : la carte est relue à neuf à chaque ouverture
        $wv.CreationProperties = $cp
        $wv.DefaultBackgroundColor = [System.Drawing.Color]::FromArgb(255, 7, 13, 43)
        $wv.Add_CoreWebView2InitializationCompleted({
            param($s, $e)
            if (-not $e.IsSuccess) { Journal ("WebView2 démarrage : " + $e.InitializationException.Message); $script:wvEchec = $true; return }
            try {
                $c = $s.CoreWebView2
                $c.SetVirtualHostNameToFolderMapping("carte.local", $racine, [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow)
                $st = $c.Settings
                $st.AreDevToolsEnabled = $false; $st.IsStatusBarEnabled = $false; $st.AreDefaultContextMenusEnabled = $false
                $st.IsZoomControlEnabled = $false; $st.AreBrowserAcceleratorKeysEnabled = $false
                $c.Navigate("https://carte.local/carte.html")
            } catch { Journal ("WebView2 navigation : " + $_.Exception.Message); $script:wvEchec = $true }
        })
        $wv.Add_NavigationStarting({ param($s, $e) if ($e.Uri -notlike "https://carte.local/*") { $e.Cancel = $true } })     # la carte ne va nulle part ailleurs
        $wv.Add_NavigationCompleted({ param($s, $e) if ($e.IsSuccess) { $script:carteFinie = $true } else { $script:wvEchec = $true } })
        $script:wvEchec = $false; $script:carteFinie = $false; $script:carteDebutLe = Get-Date
        $script:wv = $wv
        # on passe à la vue « carte » : fenêtre plus grande, compteur masqué le temps de regarder la carte
        $script:avantGauche = $win.Left; $script:avantHaut = $win.Top
        $script:compteurAvant = [bool](Ov-Visible); if ($script:compteurAvant) { Ov-Masquer }
        $cVuePanneau.Visibility = "Collapsed"; $cVueCarte.Visibility = "Visible"
        $zone = [System.Windows.SystemParameters]::WorkArea
        $win.MinWidth = 800; $win.MinHeight = 500
        $win.ResizeMode = 'CanResize'; $win.SizeToContent = 'Manual'
        $win.Width = [Math]::Min(1600, $zone.Width * 0.94); $win.Height = [Math]::Min(1000, $zone.Height * 0.94)
        $win.Left = $zone.Left + ($zone.Width - $win.Width) / 2; $win.Top = $zone.Top + ($zone.Height - $win.Height) / 2
        [void]$cZoneCarte.Children.Add($wv)
        [void]$wv.EnsureCoreWebView2Async()
        $script:carteOuverte = $true
        return $true
    } catch {
        Journal ("Afficher-Carte : " + $_.Exception.Message)
        Liberer-Carte; Rendre-Panneau
        return $false
    }
}
function Fermer-Carte([string]$message = "") {
    if (-not $script:carteOuverte) { return }
    $script:carteOuverte = $false
    Liberer-Carte
    Rendre-Panneau
    if ($message) { $cEtat.Text = $message }
}
# Ouvre la carte : dans l'appli si possible, sinon dans le navigateur (jamais pendant le jeu).
function Ouvrir-Carte {
    if (Afficher-Carte) { return }
    if (Fortnite-Ouvert) { return }
    Start-Process $carte
    $cEtat.Text = "L'affichage intégré n'est pas disponible sur ce PC : la carte s'ouvre dans ton navigateur."
}
$cBtnRetour.Add_Click({ Fermer-Carte })

# ---------- ouvrir la carte : demander une lecture au programme de surveillance, puis ouvrir la page ----------
$script:ouvrirNavigateur = $true
$script:lectureAttend = $false
$script:lectureDemandeLe = Get-Date
$script:nbPoints = 0
$script:timerPoints = New-Object System.Windows.Threading.DispatcherTimer
$script:timerPoints.Interval = [TimeSpan]::FromMilliseconds(450)
$script:timerPoints.Add_Tick({
    $script:nbPoints = ($script:nbPoints + 1) % 4
    $cEtat.Text = "Lecture de tes replays" + ("." * $script:nbPoints) + "  (quelques secondes)"
})
function Lancer-Lecture {
    if (-not (Test-Path $dll)) { $cEtat.Text = "L'outil n'est pas encore préparé : relance Carte-Fortnite.bat."; return $false }
    if (-not $script:surv -or $script:surv.HasExited) {
        if (Fortnite-Ouvert) { $cEtat.Text = "Le programme de lecture n'est plus actif. Ferme Fortnite, puis ferme et rouvre Carte Fortnite avant de relancer le jeu."; return $false }
        Demarrer-Surveillance
    }
    $cBtnCarte.IsEnabled = $false
    $cEtat.Text = "Lecture de tes replays"
    Barre-Marche $true
    $script:nbPoints = 0; $script:timerPoints.Start()
    $script:lectureDemandeLe = Get-Date
    Set-Content -Path $demande -Value "demande"       # le programme de surveillance la voit dans les 3 secondes
    $script:lectureAttend = $true
    return $true
}
function Fin-Lecture {
    $txt = ""; if (Test-Path $lecture) { $txt = Get-Content $lecture -Raw -ErrorAction SilentlyContinue }
    $n = -1; if ($txt -match '(\d+) replay\(s\) trouve') { $n = [int]$Matches[1] }
    $msg = ""
    if ($n -eq 0 -or $txt -match 'introuvable') {
        $msg = "Aucun replay trouvé. Dans Fortnite : Paramètres > Jeu, active l'enregistrement des replays, puis joue une partie jusqu'au bout. (Sur console, il n'y a pas de replay.)"
    } elseif ($txt -match 'ECHEC') {
        $msg = "Certains replays n'ont pas pu être lus (voir donnees\derniere-lecture.txt)."
    } elseif ($txt -match 'Aucune partie analysee') {
        $msg = "Aucune partie lue pour l'instant : joue une partie avec les replays activés."
    } else {
        $msg = "Carte mise à jour."
    }
    $ouvrir = ($script:ouvrirNavigateur -and $n -ne 0 -and $txt -notmatch 'introuvable')
    if ($ouvrir -and (Fortnite-Ouvert)) { $ouvrir = $false; $msg = "Données mises à jour. Ouvre la carte après avoir fermé Fortnite (ouvrir un programme pendant le jeu peut faire réagir l'anti-cheat)." }
    elseif ($ouvrir) { $msg = $msg + " Ouverture de la carte…" }
    $script:timerPoints.Stop(); Barre-Marche $false
    $cEtat.Text = $msg
    Maj-Chiffres
    $cBtnCarte.IsEnabled = $true
    if ($ouvrir) { Ouvrir-Carte }
}
$cBtnCarte.Add_Click({ [void](Lancer-Lecture) })

# ---------- compteur : case, taille, déplacement, options ----------
$cChkOverlay.Add_Checked({
    if ($script:sync) { return }
    try { Ov-Afficher; $cEtat.Text = "Compteur affiché en haut à gauche de l'écran (glisse-le avec « Déplacer »)." }
    catch { Journal ("Ov-Afficher : " + $_.Exception.Message); $cEtat.Text = "Impossible d'afficher le compteur : " + $_.Exception.Message }
})
$cChkOverlay.Add_Unchecked({
    if ($script:sync) { return }
    try { Ov-Masquer; $cEtat.Text = "Compteur masqué." } catch { Journal ("Ov-Masquer : " + $_.Exception.Message) }
})

$cChkTombes.Add_Click({
    $c = Lire-Cfg; $c.compterTombes = [bool]$cChkTombes.IsChecked; Ecrire-Cfg $c; Maj-Chiffres; Ov-Appliquer-Cfg
})
$cChkEquipe.Add_Click({
    $c = Lire-Cfg; $c.equipe = [bool]$cChkEquipe.IsChecked; Ecrire-Cfg $c; Ov-Appliquer-Cfg
})
$cChkResume.Add_Click({
    $c = Lire-Cfg; $c.resume = [bool]$cChkResume.IsChecked; Ecrire-Cfg $c; Ov-Appliquer-Cfg
})
$script:tailleSale = $false; $script:tailleLe = Get-Date
$cTaille.Add_ValueChanged({
    $cTailleTxt.Text = "$([int]$cTaille.Value) %"
    if (-not $script:sync) { $script:tailleSale = $true; $script:tailleLe = Get-Date }
})
$script:departSale = $false; $script:departLe = Get-Date
$cDepart.Add_TextChanged({ if (-not $script:sync) { $script:departSale = $true; $script:departLe = Get-Date } })

$script:deplRelance = $false
$cBtnDepl.Add_Click({
    $script:deplRelance = (Ov-Visible)
    $cBtnDepl.IsEnabled = $false; $cChkOverlay.IsEnabled = $false
    $cEtat.Text = "Glisse le petit coffre où tu veux sur l'écran, puis fais un clic droit dessus pour valider."
    $script:ovFinDeplacement = {
        if (-not $script:deplRelance) { Ov-Masquer }
        $cBtnDepl.IsEnabled = $true; $cChkOverlay.IsEnabled = $true
        $script:sync = $true; $cChkOverlay.IsChecked = (Ov-Visible); $script:sync = $false
        $cEtat.Text = "Position enregistrée."
    }
    Ov-Deplacer-Debut
})
$cBtnRaccourci.Add_Click({
    try { [void](Creer-Raccourci ([Environment]::GetFolderPath('Desktop'))); $cEtat.Text = "Raccourci « Carte Fortnite » créé sur le Bureau, avec l'icône de coffre." }
    catch { Journal ("Raccourci : " + $_.Exception.Message); $cEtat.Text = "Impossible de créer le raccourci : " + $_.Exception.Message }
})
$cBtnQuitter.Add_Click({ $win.WindowState = 'Minimized' })

# ---------- boucle : chiffres, fin de lecture, réglages en attente, compteur ----------
$script:tickN = 0
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    try {
        $script:tickN++
        if ($script:build -and $script:build.HasExited) {
            $script:build = $null
            if (Test-Path $dll) { Fin-Initial }
            else { Arreter-Chargement; $cEtat.Text = "La préparation de l'outil a échoué. Vérifie ta connexion internet (première fois) puis rouvre Carte Fortnite." }
        }
        if ($script:lectureAttend) {
            if ((Test-Path $fini) -and (Get-Item $fini).LastWriteTime -gt $script:lectureDemandeLe) { $script:lectureAttend = $false; Fin-Lecture }
            elseif (((Get-Date) - $script:lectureDemandeLe).TotalSeconds -gt 120) { $script:lectureAttend = $false; $script:timerPoints.Stop(); Barre-Marche $false; $cBtnCarte.IsEnabled = $true; $cEtat.Text = "La lecture prend trop de temps : réessaie dans un instant." }
        }
        if ($script:tailleSale -and ((Get-Date) - $script:tailleLe).TotalMilliseconds -gt 500) {
            $script:tailleSale = $false
            $c = Lire-Cfg; $c.scale = [Math]::Round($cTaille.Value / 100, 2); Ecrire-Cfg $c; Ov-Appliquer-Cfg
        }
        if ($script:departSale -and ((Get-Date) - $script:departLe).TotalMilliseconds -gt 600) {
            $script:departSale = $false
            $v = 0
            if ([int]::TryParse($cDepart.Text.Trim(), [ref]$v) -and $v -ge 0 -and $v -le 999999) {
                $c = Lire-Cfg; $c.depart = $v; Ecrire-Cfg $c; Maj-Chiffres; Ov-Appliquer-Cfg
                $cEtat.Text = if ($v -gt 0) { "Nombre de départ enregistré : $v coffres ajoutés au total." } else { "Nombre de départ remis à 0." }
            } else { $cEtat.Text = "Tape un nombre entier (0 ou plus) pour les coffres déjà ouverts." }
        }
        Maj-Chiffres
        if (($script:tickN % 2) -eq 0) { Ov-Tick }                  # le compteur par-dessus le jeu se met à jour toutes les 4 s
        $ouvert = Fortnite-Ouvert
        $cAlerte.Visibility = if ($ouvert) { "Visible" } else { "Collapsed" }
        if ($ouvert -and $script:carteOuverte) { Fermer-Carte "Fortnite s'est ouvert : la carte a été fermée pour que rien de plus ne tourne pendant le jeu." }
        elseif ($script:carteOuverte -and ($script:wvEchec -or (-not $script:carteFinie -and ((Get-Date) - $script:carteDebutLe).TotalSeconds -gt 25))) {
            # le moteur web ne démarre pas : on referme et on ouvre la carte dans le navigateur
            Fermer-Carte
            Start-Process $carte
            $cEtat.Text = "L'affichage intégré ne répond pas : la carte s'ouvre dans ton navigateur."
        }
        if ($script:surv -and $script:surv.HasExited -and -not $ouvert) { Demarrer-Surveillance }   # filet de sécurité (hors jeu seulement)
    } catch { Journal ("tick : " + $_.Exception.Message) }
})
$timer.Start()

$script:build = $null
function Fin-Initial {
    Demarrer-Surveillance                                      # le SEUL programme lancé : il reste en veille jusqu'à la fermeture du panneau
    Maj-Chiffres
    Arreter-Chargement
    if ($cEtat.Text -like "Chargement*" -or $cEtat.Text -like "Préparation*") { $cEtat.Text = "" }
}
function Charger-Initial {
    try { [void](Creer-Raccourci $racine) } catch { }          # remet à jour le raccourci du dossier (utile si le dossier a été déplacé)
    if (-not (Test-Path $dll)) {
        # première fois : l'outil est livré en texte, on le prépare ici (environ 1 minute), avant tout jeu
        $cEtat.Text = "Préparation de l'outil (première fois : environ 1 minute)…"
        $script:build = Lancer-Cache (Chemin-Dotnet) ('build "' + (Join-Path $racine "outil-perso") + '" -c Release')
        return
    }
    Fin-Initial
}
if ($Capture -ne "" -or $Test -ne "" -or $CarteTest -ne "") {
    # tests : pas de chargement différé
} else {
    # usage normal : la fenêtre s'affiche TOUT DE SUITE avec l'animation de chargement, puis les données arrivent
    Demarrer-Chargement "Chargement de tes données…"
    $win.Add_ContentRendered({
        $win.Dispatcher.BeginInvoke([Action]{
            if ($ChargementTest -ne "") {
                New-Item -ItemType Directory -Force $ChargementTest | Out-Null
                Attendre 0.6; Image-Panneau (Join-Path $ChargementTest "pendant.png")
            }
            Charger-Initial
            if ($ChargementTest -ne "") {
                Attendre 0.25; Image-Panneau (Join-Path $ChargementTest "milieu.png")
                Attendre 1.2;  Image-Panneau (Join-Path $ChargementTest "apres.png")
                $win.Close()
            }
        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    })
}

# ---------- test : image du panneau ----------
if ($Capture -ne "") {
    $win.Add_ContentRendered({
        $win.Dispatcher.BeginInvoke([Action]{
            Image-Panneau $Capture
            $win.Close()
        }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    })
}

# ---------- test : enchaîne les actions des boutons et écrit le résultat ----------
if ($Test -ne "") {
    $script:ouvrirNavigateur = $false
    $win.Add_ContentRendered({
        $win.Dispatcher.BeginInvoke([Action]{
            $log = New-Object System.Collections.Generic.List[string]
            try {
                Demarrer-Surveillance
                $log.Add("SURVEILLANCE_PID=" + $(if ($script:surv) { $script:surv.Id } else { "aucun" }))
                $log.Add("PANNEAU_PID=" + $PID)
                [System.IO.File]::WriteAllLines($Test, $log)      # (le test externe lit le PID et surveille les processus créés)
                Attendre 8
                $log.Add("compteur visible au depart : " + (Ov-Visible))
                $cChkOverlay.IsChecked = $true; Attendre 2
                $log.Add("apres case 'Afficher' : visible = " + (Ov-Visible) + " | nombre = " + $script:ovNombre.Text)
                $h = (New-Object System.Windows.Interop.WindowInteropHelper $script:ovWin).Handle
                $ex = $script:ovApi::GetWindowLong($h, -20)
                $log.Add("styles du compteur : premier plan=" + (($ex -band 0x8) -ne 0) + " | souris traverse=" + (($ex -band 0x20) -ne 0) + " | ne prend pas le focus=" + (($ex -band 0x08000000) -ne 0) + " | hors barre des taches=" + (($ex -band 0x80) -ne 0))
                $cDepart.Text = "10"; Attendre 3.5
                $log.Add("apres nombre de depart 10 : panneau total=" + $cTotal.Text + " | compteur=" + $script:ovNombre.Text + " | reglages.js=" + (Get-Content (Join-Path $donnees "reglages.js") -Raw).Trim())
                $cTaille.Value = 40; Attendre 3
                $log.Add("taille ecrite dans overlay.json : " + (Lire-Cfg).scale + " | compteur pris en compte")
                Ov-Image ($Test + ".compteur.png")
                [void](Lancer-Lecture)
                $t0 = Get-Date
                while ($script:lectureAttend -and ((Get-Date) - $t0).TotalSeconds -lt 40) { Attendre 0.5 }
                $log.Add("message apres lecture : " + $cEtat.Text)
                $log.Add("chiffres : total=" + $cTotal.Text + " derniere=" + $cDerniere.Text + " parties=" + $cParties.Text)
                $cDepart.Text = "0"; Attendre 3
                $cChkOverlay.IsChecked = $false; Attendre 1
                $log.Add("apres case decochee : visible = " + (Ov-Visible))
                $log.Add("TEST_FINI")
            } catch { $log.Add("ERREUR : " + $_.Exception.Message) }
            $c = Lire-Cfg; $c.scale = 0.5; $c.depart = 0; Ecrire-Cfg $c
            [System.IO.File]::WriteAllLines($Test, $log)
            $win.Close()
        }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    })
}

# ---------- test : ouvre la carte dans le panneau, la photographie, appuie sur « Retour » et vérifie que tout s'arrête ----------
if ($CarteTest -ne "") {
    $script:ouvrirNavigateur = $false
    $win.Add_ContentRendered({
        $win.Dispatcher.BeginInvoke([Action]{
            New-Item -ItemType Directory -Force $CarteTest | Out-Null
            $log = New-Object System.Collections.Generic.List[string]
            try {
                $avant = @{}; foreach ($p in Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue) { $avant[$p.Id] = 1 }
                $win.Topmost = $true
                Attendre 0.6; Image-Panneau (Join-Path $CarteTest "1-panneau.png")
                $log.Add("panneau : " + [int]$win.ActualWidth + " x " + [int]$win.ActualHeight + " | vue panneau=" + $cVuePanneau.Visibility + " | vue carte=" + $cVueCarte.Visibility)
                $ok = Afficher-Carte
                $log.Add("Afficher-Carte : " + $ok)
                $t0 = Get-Date
                while (-not $script:carteFinie -and -not $script:wvEchec -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Attendre 0.2 }
                $log.Add("page chargee : " + $script:carteFinie + " en " + [int]((Get-Date) - $t0).TotalSeconds + " s | echec=" + $script:wvEchec)
                Attendre 3.5
                $log.Add("carte : fenetre " + [int]$win.ActualWidth + " x " + [int]$win.ActualHeight + " | vue panneau=" + $cVuePanneau.Visibility + " | vue carte=" + $cVueCarte.Visibility)
                $tj = $script:wv.CoreWebView2.ExecuteScriptAsync("JSON.stringify({titre: document.title, compteur: [...document.querySelectorAll('#counter .card b')].map(b => b.textContent), chargementRetire: !document.getElementById('chargement'), asideHaut: document.querySelector('aside').scrollTop, adresse: location.href, equipe: document.getElementById('counterEq').innerText.replace(/\s+/g, ' '), bilan: [...document.querySelectorAll('#cards .card b')].map(b => b.textContent)})")
                $t1 = Get-Date; while (-not $tj.IsCompleted -and ((Get-Date) - $t1).TotalSeconds -lt 10) { Attendre 0.1 }
                if ($tj.IsCompleted) { $log.Add("page : " + $tj.Result) } else { $log.Add("page : pas de reponse") }
                # une seule partie choisie (la 7e : un classement 2, avec equipier) : le resume et le detail de l'equipe dans le panneau de gauche
                $tn = $script:wv.CoreWebView2.ExecuteScriptAsync("(() => { const s = document.getElementById('game'); s.value = '6'; s.dispatchEvent(new Event('change')); const n = document.getElementById('note').innerText.replace(/\s+/g, ' '); s.value = 'all'; s.dispatchEvent(new Event('change')); return n; })()")
                $t1 = Get-Date; while (-not $tn.IsCompleted -and ((Get-Date) - $t1).TotalSeconds -lt 10) { Attendre 0.1 }
                if ($tn.IsCompleted) { $log.Add("note d'une partie : " + $tn.Result) } else { $log.Add("note d'une partie : pas de reponse") }
                # photo de la fenêtre entière (barre « Retour » + carte)
                $r = New-Object System.Drawing.Rectangle([int]$win.Left, [int]$win.Top, [int]$win.ActualWidth, [int]$win.ActualHeight)
                $bmp = New-Object System.Drawing.Bitmap($r.Width, $r.Height)
                $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.Location, [System.Drawing.Point]::Empty, $r.Size); $g.Dispose()
                $bmp.Save((Join-Path $CarteTest "2-carte.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
                $n = @(Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { -not $avant.ContainsKey($_.Id) }).Count
                $log.Add("programmes du moteur web pendant la carte : " + $n)
                # le bouton « Retour »
                $cBtnRetour.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                Attendre 1
                $log.Add("apres Retour : vue panneau=" + $cVuePanneau.Visibility + " | vue carte=" + $cVueCarte.Visibility + " | fenetre " + [int]$win.ActualWidth + " x " + [int]$win.ActualHeight)
                Image-Panneau (Join-Path $CarteTest "3-retour.png")
                Attendre 4
                $n2 = @(Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { -not $avant.ContainsKey($_.Id) }).Count
                $log.Add("programmes du moteur web 4 s apres Retour : " + $n2)
                # --- le vrai parcours : clic sur « Ouvrir la carte » -> lecture des replays -> carte dans le panneau ---
                $script:ouvrirNavigateur = $true
                Demarrer-Surveillance
                $log.Add("surveillance demarree : " + $(if ($script:surv) { "oui" } else { "non (outil pas construit ?)" }))
                $cBtnCarte.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                $t0 = Get-Date
                while (-not ($script:carteOuverte -and $script:carteFinie) -and ((Get-Date) - $t0).TotalSeconds -lt 90) { Attendre 0.3 }
                $log.Add("parcours complet : carte ouverte=" + $script:carteOuverte + " | page chargee=" + $script:carteFinie + " | en " + [int]((Get-Date) - $t0).TotalSeconds + " s | message='" + $cEtat.Text + "'")
                Attendre 2
                # --- Fortnite s'ouvre pendant que la carte est affichée : la carte doit se fermer toute seule ---
                $faux = Join-Path $env:TEMP "FortniteClient-Win64-Shipping.exe"
                Copy-Item (Join-Path $env:SystemRoot "System32\ping.exe") $faux -Force
                $pf = Start-Process -FilePath $faux -ArgumentList "-n 60 127.0.0.1" -PassThru -WindowStyle Hidden
                $t0 = Get-Date
                while ($script:carteOuverte -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Attendre 0.3 }
                $log.Add("faux Fortnite ouvert -> carte encore ouverte=" + $script:carteOuverte + " apres " + [int]((Get-Date) - $t0).TotalSeconds + " s | vue panneau=" + $cVuePanneau.Visibility + " | alerte=" + $cAlerte.Visibility + " | message='" + $cEtat.Text + "'")
                # le jeu est ouvert : « Ouvrir la carte » doit seulement mettre les données à jour
                Attendre 1
                $cBtnCarte.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                $t0 = Get-Date
                while (-not $cBtnCarte.IsEnabled -or ((Get-Date) - $t0).TotalSeconds -lt 3) { if (((Get-Date) - $t0).TotalSeconds -gt 60) { break }; Attendre 0.3 }
                Attendre 3
                $log.Add("jeu ouvert + clic : carte ouverte=" + $script:carteOuverte + " | message='" + $cEtat.Text + "'")
                try { $pf.Kill() } catch { }
                Remove-Item $faux -Force -ErrorAction SilentlyContinue
                $log.Add("TEST_FINI")
            } catch { $log.Add("ERREUR : " + $_.Exception.Message + " | " + $_.ScriptStackTrace) }
            [System.IO.File]::WriteAllLines((Join-Path $CarteTest "resultat.txt"), $log)
            $win.Close()
        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    })
}

[void]$win.ShowDialog()
