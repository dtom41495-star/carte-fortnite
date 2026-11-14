# overlay-lib.ps1 : le petit compteur de coffres par-dessus le jeu, comme SECONDE FENÊTRE du panneau.
# Tout se passe dans le MÊME programme que le panneau : afficher, masquer, déplacer ou redimensionner le compteur ne lance AUCUN programme.
# (Lancé avec le panneau : voir panneau.ps1. Aucun .exe : script texte lisible.)
# Style inspiré de l'univers Fortnite (plaque penchée, jaune et bleu nuit) : aucun logo, aucune police ni image d'Epic Games.
#
# Fourni par le panneau : $donnees, $demos, $cptPath, Lire-Cfg, Ecrire-Cfg, Total-Compteur, Derniere-Compteur.
$ATTENTE_FIN = 25   # secondes sans écriture du replay = la partie est terminée

# Deux fonctions Windows (GetWindowLong / SetWindowLong) pour rendre le compteur "traversable" par la souris.
# Créées en mémoire (Reflection.Emit) : pas de compilation, donc AUCUN programme supplémentaire (Add-Type lance csc.exe).
function Ov-Creer-Api {
    $an = New-Object System.Reflection.AssemblyName("OvApi")
    $da = [AppDomain]::CurrentDomain.DefineDynamicAssembly($an, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $mb = $da.DefineDynamicModule("OvApi")
    $tb = $mb.DefineType("OverlayWin", "Public,Class")
    $attrs = [System.Reflection.MethodAttributes]"Public,Static,PinvokeImpl"
    $m1 = $tb.DefinePInvokeMethod("GetWindowLong", "user32.dll", $attrs, [System.Reflection.CallingConventions]::Standard, [int], [Type[]]@([IntPtr], [int]), [System.Runtime.InteropServices.CallingConvention]::Winapi, [System.Runtime.InteropServices.CharSet]::Auto)
    $m1.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)
    $m2 = $tb.DefinePInvokeMethod("SetWindowLong", "user32.dll", $attrs, [System.Reflection.CallingConventions]::Standard, [int], [Type[]]@([IntPtr], [int], [int]), [System.Runtime.InteropServices.CallingConvention]::Winapi, [System.Runtime.InteropServices.CharSet]::Auto)
    $m2.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)
    return $tb.CreateType()
}
$script:ovApi = Ov-Creer-Api

$script:ovWin = $null
$script:ovAffiche = -1
$script:ovMontre = 0
$script:ovCible = 0
$script:ovDeplace = $false
$script:ovFinDeplacement = $null
$script:ovForceValeur = -1      # test : force le nombre affiché
$script:ovForceEquipeValeur = -1   # test : force le nombre de l'équipe
$script:ovForceEquipeBadge = 0     # test : force le "+N" de l'équipe
$script:ovForceResume = $null      # test : force le mini-résumé (place, kills, tueur, plat)
$script:ovForceBadge = -1       # test : force le "+N"
$script:ovDureeBadgeMin = -1    # test : remplace la durée d'affichage du "+N"
$script:ovAnimer = $true
$script:ovMaxComptage = 5      # au-delà de cette hausse, le nombre change d'un coup (jamais de comptage long)

function Ov-Style([bool]$traversable) {
    # Mode normal : la souris traverse la fenêtre et elle ne prend jamais le focus (le jeu reste actif).
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $script:ovWin).Handle
    if ($h -eq [IntPtr]::Zero) { return }
    $ex = $script:ovApi::GetWindowLong($h, -20)
    $ex = $ex -bor 0x80                                  # WS_EX_TOOLWINDOW : pas dans la barre des tâches
    if ($traversable) { $ex = ($ex -bor 0x20 -bor 0x08000000) }          # WS_EX_TRANSPARENT | WS_EX_NOACTIVATE
    else { $ex = ($ex -band (-bnot 0x20) -band (-bnot 0x08000000)) }     # mode "déplacer" : on peut saisir la fenêtre
    [void]$script:ovApi::SetWindowLong($h, -20, $ex)
}

function Ov-KF($v, $ms, $ease) {
    $k = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame($v, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($ms)))
    if ($ease) { $k.EasingFunction = $ease }
    return $k
}
function Ov-Anim-Pop([double]$amp) {
    $quad = New-Object System.Windows.Media.Animation.QuadraticEase; $quad.EasingMode = 'EaseOut'
    $el = New-Object System.Windows.Media.Animation.ElasticEase; $el.Oscillations = 2; $el.Springiness = 5; $el.EasingMode = 'EaseOut'
    $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    [void]$a.KeyFrames.Add((Ov-KF 1.0 0 $null)); [void]$a.KeyFrames.Add((Ov-KF $amp 110 $quad)); [void]$a.KeyFrames.Add((Ov-KF 1.0 560 $el))
    $script:ovEchelle.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $a)
    $script:ovEchelle.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $a)
}
function Ov-Anim-Icone {
    $sin = New-Object System.Windows.Media.Animation.SineEase; $sin.EasingMode = 'EaseInOut'
    $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($p in @(@(0, 0), @(-16, 90), @(13, 210), @(-8, 330), @(4, 430), @(0, 530))) { [void]$a.KeyFrames.Add((Ov-KF $p[0] $p[1] $sin)) }
    $script:ovRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $a)
}
function Ov-Anim-Lueur {
    # le liseré de la plaque passe du jaune au blanc, puis revient
    $c = New-Object System.Windows.Media.Animation.ColorAnimationUsingKeyFrames
    $base = [System.Windows.Media.Color]::FromArgb(0xFF, 0xFF, 0xE5, 0x00)
    $vif  = [System.Windows.Media.Color]::FromArgb(0xFF, 0xFF, 0xFF, 0xFF)
    foreach ($p in @(@($base, 0), @($vif, 130), @($vif, 450), @($base, 1100))) {
        [void]$c.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearColorKeyFrame($p[0], [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($p[1])))))
    }
    $script:ovPinceau.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $c)
}
function Ov-Anim-Badge {
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 1.0, [TimeSpan]::FromMilliseconds(380))
    $script:ovBadge.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    $ease = New-Object System.Windows.Media.Animation.BackEase; $ease.EasingMode = 'EaseOut'
    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation(-16.0, 0.0, [TimeSpan]::FromMilliseconds(420))
    $slide.EasingFunction = $ease
    $script:ovGlisse.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $slide)
}

function Ov-Init {
    if ($script:ovWin) { return }
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" SizeToContent="WidthAndHeight"
        ResizeMode="NoResize" WindowStartupLocation="Manual" UseLayoutRounding="True">
  <Border Name="Cadre" Background="Transparent" Padding="14,8,22,14">
    <Grid>
      <Border Margin="5,6,-5,-6" Background="#B3040928" RenderTransformOrigin="0.5,0.5">
        <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
      </Border>
      <Border Name="Plaque" BorderBrush="#FFFFE500" BorderThickness="3" RenderTransformOrigin="0.5,0.5">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#F51F36B4" Offset="0"/>
            <GradientStop Color="#F52A1068" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <Border.RenderTransform><SkewTransform AngleX="-10"/></Border.RenderTransform>
        <Border Height="20" VerticalAlignment="Top" Background="#1EFFFFFF"/>
      </Border>
      <StackPanel Margin="26,8,30,10">
        <StackPanel Orientation="Horizontal">
          <Viewbox Name="Icone" Width="58" Height="52" VerticalAlignment="Center">
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
          <TextBlock Name="Nombre" Text="0" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="Bold" FontStyle="Italic" FontSize="54" Foreground="#FFFFE500"
                     Margin="14,0,0,0" VerticalAlignment="Center" MinWidth="34" TextAlignment="Left">
            <TextBlock.Effect><DropShadowEffect Color="#FF000000" Opacity="0.6" ShadowDepth="3" BlurRadius="0" Direction="300"/></TextBlock.Effect>
          </TextBlock>
          <TextBlock Name="Badge" Text="" Visibility="Collapsed" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="Bold" FontStyle="Italic" FontSize="32" Foreground="#FF5CF08A"
                     Margin="12,8,0,0" VerticalAlignment="Center">
            <TextBlock.Effect><DropShadowEffect Color="#FF000000" Opacity="0.6" ShadowDepth="2" BlurRadius="0" Direction="300"/></TextBlock.Effect>
          </TextBlock>
        </StackPanel>
        <StackPanel Name="EquipeLigne" Orientation="Horizontal" Visibility="Collapsed" Margin="6,2,0,0">
          <TextBlock Text="ÉQUIPE" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="SemiBold" FontStyle="Italic" FontSize="22" Foreground="#FFA9B9FF" VerticalAlignment="Center"/>
          <TextBlock Name="EquipeNombre" Text="0" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="Bold" FontStyle="Italic" FontSize="36" Foreground="#FF2AD4FF" Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock.Effect><DropShadowEffect Color="#FF000000" Opacity="0.6" ShadowDepth="2" BlurRadius="0" Direction="300"/></TextBlock.Effect>
          </TextBlock>
          <TextBlock Name="EquipeBadge" Text="" Visibility="Collapsed" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="Bold" FontStyle="Italic" FontSize="24" Foreground="#FF5CF08A" Margin="10,6,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Name="ResumeLigne" Orientation="Horizontal" Visibility="Collapsed" Margin="6,4,0,0">
          <TextBlock Name="ResPlace" Text="" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="Bold" FontStyle="Italic" FontSize="32" Foreground="#FFFFE500" VerticalAlignment="Center">
            <TextBlock.Effect><DropShadowEffect Color="#FF000000" Opacity="0.6" ShadowDepth="2" BlurRadius="0" Direction="300"/></TextBlock.Effect>
          </TextBlock>
          <TextBlock Name="ResKills" Text="" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="Bold" FontStyle="Italic" FontSize="26" Foreground="#FFFFFFFF" Margin="16,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Name="ResTueur" Text="" FontFamily="Bahnschrift, Segoe UI" FontStretch="Condensed" FontWeight="SemiBold" FontStyle="Italic" FontSize="22" Foreground="#FFA9B9FF" Margin="16,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock Name="Aide" Visibility="Collapsed" Foreground="#FFC9D5FF" FontSize="12" Margin="0,6,0,0"
                   Text="Glisse pour deplacer - clic droit pour valider"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@
    $script:ovWin = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $script:ovNombre = $script:ovWin.FindName("Nombre")
    $script:ovBadge  = $script:ovWin.FindName("Badge")
    $script:ovCadre  = $script:ovWin.FindName("Cadre")
    $script:ovPlaque = $script:ovWin.FindName("Plaque")
    $script:ovAide   = $script:ovWin.FindName("Aide")
    $script:ovEquipeLigne  = $script:ovWin.FindName("EquipeLigne")
    $script:ovEquipeNombre = $script:ovWin.FindName("EquipeNombre")
    $script:ovEquipeBadge  = $script:ovWin.FindName("EquipeBadge")
    $script:ovResumeLigne  = $script:ovWin.FindName("ResumeLigne")
    $script:ovResPlace     = $script:ovWin.FindName("ResPlace")
    $script:ovResKills     = $script:ovWin.FindName("ResKills")
    $script:ovResTueur     = $script:ovWin.FindName("ResTueur")
    $icone           = $script:ovWin.FindName("Icone")

    $script:ovRot     = New-Object System.Windows.Media.RotateTransform(0)
    $script:ovEchelle = New-Object System.Windows.Media.ScaleTransform(1, 1)
    $script:ovGlisse  = New-Object System.Windows.Media.TranslateTransform(0, 0)
    $icone.RenderTransform = $script:ovRot;               $icone.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.9)
    $script:ovNombre.RenderTransform = $script:ovEchelle; $script:ovNombre.RenderTransformOrigin = New-Object System.Windows.Point(0.3, 0.55)
    $script:ovBadge.RenderTransform = $script:ovGlisse
    $script:ovPinceau = $script:ovPlaque.BorderBrush.Clone(); $script:ovPlaque.BorderBrush = $script:ovPinceau

    $script:ovWin.Add_SourceInitialized({ Ov-Style (-not $script:ovDeplace) })
    $script:ovWin.Add_MouseLeftButtonDown({ if ($script:ovDeplace) { $script:ovWin.DragMove() } })
    $script:ovWin.Add_MouseRightButtonUp({ if ($script:ovDeplace) { Ov-Deplacer-Fin } })

    # le nombre monte un par un avec un rebond
    $script:ovCptTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ovCptTimer.Interval = [TimeSpan]::FromMilliseconds(170)
    $script:ovCptTimer.Add_Tick({
        if ($script:ovMontre -lt $script:ovCible) {
            $script:ovMontre++
            $script:ovNombre.Text = "$($script:ovMontre)"
            Ov-Anim-Pop $(if ($script:ovMontre -ge $script:ovCible) { 1.4 } else { 1.2 })      # (un peu moins qu'avant : les chiffres sont plus gros)
        }
        if ($script:ovMontre -ge $script:ovCible) { $script:ovCptTimer.Stop() }
    })
    Ov-Appliquer-Cfg
}

function Ov-Lire-Compteur {
    if (-not (Test-Path $cptPath)) { return $null }
    try { return (Get-Content $cptPath -Raw | ConvertFrom-Json) } catch { return $null }
}

function Ov-Maj-Nombre {
    if ($script:ovForceValeur -ge 0) { $t = $script:ovForceValeur }
    else {
        $c = Ov-Lire-Compteur
        if ($null -eq $c) { if ($script:ovAffiche -ge 0) { return }; $t = [int](Lire-Cfg).depart }
        else { $t = Total-Compteur $c }
    }
    if ($t -ne $script:ovAffiche) {
        $ancien = $script:ovAffiche
        $script:ovAffiche = $t
        $enCours = $script:ovCptTimer.IsEnabled
        $depuis = if ($enCours) { $script:ovMontre } else { $ancien }
        $ecart = $t - $depuis
        if ($ancien -ge 0 -and $ecart -gt 0 -and $script:ovAnimer -and -not $script:ovDeplace) {
            if (-not $enCours) { Ov-Anim-Icone; Ov-Anim-Lueur }          # le coffre se secoue et la plaque brille
            if ($ecart -le $script:ovMaxComptage) {
                # petite hausse (le cas normal : 1 à quelques coffres) : le nombre monte un par un avec un rebond, en moins d'une seconde
                if (-not $enCours) { $script:ovMontre = $ancien }
                $script:ovCible = $t
                $script:ovCptTimer.Start()
            } else {
                # grosse hausse (plusieurs parties lues d'un coup) : le nombre change d'un coup, jamais de comptage long
                $script:ovCptTimer.Stop()
                $script:ovCible = $t; $script:ovMontre = $t; $script:ovNombre.Text = "$t"
                Ov-Anim-Pop 1.4
            }
        } else {
            $script:ovCptTimer.Stop()
            $script:ovCible = $t; $script:ovMontre = $t; $script:ovNombre.Text = "$t"
        }
    }
}

# La ligne « ÉQUIPE » du compteur (facultative : case du panneau) = mes coffres + ceux de mes équipiers (estimation). Sans animation.
function Ov-Maj-Equipe {
    if (-not $script:ovWin) { return }
    $cfg = Lire-Cfg
    if (-not [bool]$cfg.equipe) { $script:ovEquipeLigne.Visibility = "Collapsed"; return }
    if ($script:ovForceEquipeValeur -ge 0) { $t = $script:ovForceEquipeValeur }
    else {
        $c = Ov-Lire-Compteur
        $t = if ($null -ne $c) { Equipe-Total $c } else { 0 }
    }
    $script:ovEquipeNombre.Text = "$t"
    $script:ovEquipeLigne.Visibility = "Visible"
}

# Nom lisible de la plateforme (le replay donne un code : WIN, XBL, PSN...).
function Nom-Plateforme([string]$code) {
    switch -Regex ($code) {
        '^WIN$'                 { return "PC" }
        '^MAC$'                 { return "MAC" }
        '^LNX$'                 { return "LINUX" }
        '^(PSN|PS4|PS5)$'       { return "PLAYSTATION" }
        '^(XBL|XB1|XSX)$'       { return "XBOX" }
        '^(SWT|NSW)$'           { return "SWITCH" }
        '^AND$'                 { return "ANDROID" }
        '^IOS$'                 { return "IOS" }
        default                 { if ($code) { return $code.ToUpper() } else { return "?" } }
    }
}

# Le mini-résumé de la partie, à la fin de la partie (même règle que le "+N") : classement, éliminations, plateforme de celui qui m'a éliminé.
function Ov-Maj-Resume([bool]$afficher) {
    if (-not $script:ovWin) { return }
    $cfg = Lire-Cfg
    $place = 0; $kills = 0; $tueur = ""; $plat = ""; $ok = $false
    if ($script:ovForceResume) {
        $r = $script:ovForceResume; $place = [int]$r.place; $kills = [int]$r.kills; $tueur = [string]$r.tueur; $plat = [string]$r.plat; $ok = ($place -gt 0)
    } elseif ($afficher) {
        $c = Ov-Lire-Compteur
        if ($c -and $c.derniere -and $null -ne $c.derniere.place) {
            $d = $c.derniere
            $place = [int]$d.place; $kills = [int]$d.kills; $tueur = [string]$d.tueur; $plat = [string]$d.tueurPlat; $ok = ($place -gt 0)
        }
    }
    if (-not $ok -or -not $afficher -or -not [bool]$cfg.resume) { $script:ovResumeLigne.Visibility = "Collapsed"; return }
    $script:ovResPlace.Text = if ($place -eq 1) { "VICTOIRE" } else { "#$place" }
    $script:ovResKills.Text = "$kills KILL" + $(if ($kills -gt 1) { "S" } else { "" })
    $script:ovResTueur.Text = if ($place -eq 1) { "" }
                              elseif ($tueur -eq "joueur") { "TUÉ PAR " + (Nom-Plateforme $plat) }
                              elseif ($tueur -eq "bot") { "TUÉ PAR UN BOT" }
                              elseif ($tueur -eq "zone") { "ZONE / CHUTE" }
                              else { "" }
    $script:ovResumeLigne.Visibility = "Visible"
}

# Le "+N" de la dernière partie. Règle (sans mémoire, donc robuste) : on l'affiche si le replay le plus récent est TERMINÉ (plus écrit
# depuis $ATTENTE_FIN s), déjà lu, et pas plus vieux que dureeBadgeMinutes. Dès qu'une nouvelle partie commence, un replay plus récent
# apparaît, il n'est ni terminé ni lu : le "+N" disparaît tout seul.
function Ov-Maj-Badge {
    $cfg = Lire-Cfg
    $duree = if ($script:ovDureeBadgeMin -ge 0) { $script:ovDureeBadgeMin } else { [double]$cfg.dureeBadgeMinutes }
    $ne = 0
    if ($script:ovForceBadge -ge 0) { $n = $script:ovForceBadge; $ne = $script:ovForceEquipeBadge; $afficher = $true }
    else {
        $afficher = $false; $n = 0
        $fichiers = @(Get-ChildItem $demos -Filter *.replay -ErrorAction SilentlyContinue)
        $c = Ov-Lire-Compteur
        if ($fichiers.Count -gt 0 -and $c -and $c.derniere) {
            $recent = ($fichiers | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            $age = ((Get-Date) - $recent.LastWriteTime).TotalSeconds
            if ($recent.Name -eq $c.derniere.fichier -and $age -ge $ATTENTE_FIN -and $age -le ($duree * 60)) {
                $n = Derniere-Compteur $c
                $ne = Equipe-Derniere $c
                $afficher = $true
            }
        }
    }
    if ($afficher -and $n -gt 0) {
        $nouveau = ("+$n" -ne $script:ovBadge.Text) -or ($script:ovBadge.Visibility -ne "Visible")
        $script:ovBadge.Text = "+$n"; $script:ovBadge.Visibility = "Visible"
        if ($nouveau -and $script:ovAnimer) { Ov-Anim-Badge }
    }
    else { $script:ovBadge.Visibility = "Collapsed"; $script:ovBadge.Text = "" }
    # le "+N" de l'équipe : même règle (partie terminée, lue, récente), seulement si la ligne ÉQUIPE est affichée
    if ($afficher -and $ne -gt 0 -and $script:ovEquipeLigne.Visibility -eq "Visible") {
        $script:ovEquipeBadge.Text = "+$ne"; $script:ovEquipeBadge.Visibility = "Visible"
    } else { $script:ovEquipeBadge.Visibility = "Collapsed"; $script:ovEquipeBadge.Text = "" }
    Ov-Maj-Resume $afficher
}

# Applique les réglages (taille, position, transparence, options) : appelé par le panneau quand on les change.
function Ov-Appliquer-Cfg {
    if (-not $script:ovWin) { return }
    $cfg = Lire-Cfg
    if (-not $script:ovDeplace) { $script:ovWin.Left = [double]$cfg.x; $script:ovWin.Top = [double]$cfg.y }
    $script:ovWin.Opacity = [double]$cfg.opacity
    $script:ovCadre.LayoutTransform = New-Object System.Windows.Media.ScaleTransform([double]$cfg.scale, [double]$cfg.scale)
    $script:ovAffiche = -1          # recalcule le total sans animation (option "compter les tombés", nombre de départ)
    Ov-Maj-Nombre
    Ov-Maj-Equipe
    if ($script:ovWin.IsVisible) { Ov-Maj-Badge }
}

function Ov-Visible { return ($script:ovWin -and $script:ovWin.IsVisible) }
function Ov-Afficher {
    # À l'ouverture du compteur : AUCUNE animation. Le nombre (et le "+N" s'il y en a un) apparaît directement.
    $anim = $script:ovAnimer
    $script:ovAnimer = $false
    try {
        Ov-Init
        Ov-Appliquer-Cfg
        $script:ovWin.Show()
        Ov-Style (-not $script:ovDeplace)
        Ov-Maj-Badge
    } finally { $script:ovAnimer = $anim }
}
function Ov-Masquer { if ($script:ovWin) { $script:ovWin.Hide() } }
function Ov-Tick {
    if (-not (Ov-Visible)) { return }
    Ov-Maj-Nombre
    Ov-Maj-Equipe
    Ov-Maj-Badge
}

# Mode "déplacer" : on peut saisir le coffre et le glisser ; clic droit pour valider la position.
function Ov-Deplacer-Debut {
    Ov-Init
    $script:ovDeplace = $true
    $script:ovAide.Visibility = "Visible"
    if (-not $script:ovWin.IsVisible) { Ov-Appliquer-Cfg; $script:ovWin.Show() }
    Ov-Style $false
}
function Ov-Deplacer-Fin {
    $c = Lire-Cfg; $c.x = [int]$script:ovWin.Left; $c.y = [int]$script:ovWin.Top; Ecrire-Cfg $c
    $script:ovDeplace = $false
    $script:ovAide.Visibility = "Collapsed"
    Ov-Style $true
    if ($script:ovFinDeplacement) { & $script:ovFinDeplacement }
}
function Ov-Fermer { if ($script:ovWin) { try { $script:ovWin.Close() } catch { } ; $script:ovWin = $null } }

# test : image du compteur
function Ov-Image([string]$fichier) {
    $b = $script:ovWin.Content
    $w = [int][Math]::Ceiling($b.ActualWidth) + 40; $h = [int][Math]::Ceiling($b.ActualHeight) + 40
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(($w * 2), ($h * 2), 192, 192, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($b)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($fichier); $enc.Save($fs); $fs.Close()
}
