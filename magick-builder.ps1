<#
.SYNOPSIS
    ImageMagick Command Builder - Installer Test Build
.DESCRIPTION
    This script acts as an installer, using Winget to set up system-wide
    dependencies like ImageMagick before launching the GUI.
    It requires Administrator privileges to run.
.AUTHOR
    brizzle (Converted by Gemini Code Assist)
#>

# --- Admin Rights Check ---
# if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
#     Write-Warning "Administrator privileges are required to install system-wide dependencies."
#     Write-Warning "Attempting to relaunch the script with elevated permissions..."
#     try {
#         Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
#     } catch {
#         Write-Error "Failed to relaunch as Administrator. Please right-click the script and 'Run as Administrator'."
#         Read-Host "Press Enter to exit"
#     }
#     exit
# }

# Set the script's working directory to its own location.
Set-Location -Path $PSScriptRoot

# Force standard C locale to prevent ImageMagick from crashing due to comma/decimal region settings
[Environment]::SetEnvironmentVariable("LC_ALL", "C", "Process")

Write-Host "Starting Magick Builder (Installer Build)..." -ForegroundColor Cyan

# 1. Load the required .NET assemblies for building a GUI
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

Write-Host "[OK] .NET assemblies loaded." -ForegroundColor Green

# --- Dependency Verification ---
Write-Host "`n--- Verifying Dependencies ---" -ForegroundColor Cyan
try {
    # Test 1: CLI Executable
    $magickCheck = Get-Command magick -ErrorAction SilentlyContinue
    if (-not $magickCheck) { 
        Write-Warning "magick.exe not found in standard PATH. Checking default Program Files..."
        $sysImageMagick = Get-ChildItem -Path $env:ProgramFiles -Filter "ImageMagick-*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        
        if ($sysImageMagick -and (Test-Path (Join-Path $sysImageMagick.FullName "magick.exe"))) {
            $env:Path = "$($sysImageMagick.FullName);" + $env:Path
        } else {
            throw "ImageMagick ('magick.exe') was not found in the system PATH or standard Program Files."
        }
        $magickCheck = Get-Command magick
    }
    $cliVersion = if ($magickCheck.FileVersionInfo) { $magickCheck.FileVersionInfo.ProductVersion } else { $magickCheck.Source }
    Write-Host "[OK] magick.exe is accessible: $cliVersion" -ForegroundColor Green

    # Test 2: Magick.NET DLLs
    Write-Host "Attempting to load Magick.NET from local bin or GAC..."
    $localBinDir = if (Test-Path (Join-Path $PSScriptRoot "Magick.NET.Core.dll")) { $PSScriptRoot } else { Join-Path $PSScriptRoot "bin" }
    
    $corePath = Join-Path $localBinDir "Magick.NET.Core.dll"
    $magickPath = Join-Path $localBinDir "Magick.NET-Q16-AnyCPU.dll"
    $nativePath = Join-Path $localBinDir "Magick.Native-Q16-x64.dll"

    if ((Test-Path $corePath) -and (Test-Path $magickPath)) {
        $cVer = (Get-Item $corePath).VersionInfo.ProductVersion
        $mVer = (Get-Item $magickPath).VersionInfo.ProductVersion
        if ($cVer -ne $mVer) {
            throw "DLL Version Mismatch! Core: $cVer | Wrapper: $mVer.`n`nPlease ensure all DLLs in the bin folder are from the exact same release."
        }
    }

    if ((Test-Path $corePath) -and (Test-Path $magickPath) -and (Test-Path $nativePath)) {
        # Ensure native path is in env:path so the Magick.NET C++ engine can load
        $env:Path = "$localBinDir;" + $env:Path
        Get-ChildItem -Path $localBinDir -Filter "*.dll" | Unblock-File -ErrorAction SilentlyContinue
        Add-Type -Path $corePath
        Add-Type -Path $magickPath
    } else {
        Write-Warning "Local DLLs not found. Attempting to load Magick.NET from GAC..."
        try {
            Add-Type -AssemblyName "Magick.NET.Core" -ErrorAction Stop
            Add-Type -AssemblyName "Magick.NET-Q16-AnyCPU" -ErrorAction Stop
        } catch {
            Write-Warning "Could not load Magick.NET. Advanced previews may fail, but continuing to UI..."
        }
    }

    try {
        $netVersion = [ImageMagick.MagickNET]::Version
        if ($netVersion) {
            Write-Host "[OK] Magick.NET DLLs loaded successfully. Version: $netVersion" -ForegroundColor Green
            Write-Host "[OK] Magick.NET Delegates: $([ImageMagick.MagickNET]::Delegates)" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "Skipped Magick.NET version verification."
    }
} catch {
    $errorMessage = "CRITICAL ERROR: Failed to load or verify required dependencies.`n`nDetails: $_"

    # Extract the hidden LoaderExceptions to see exactly which dependency is missing
    $ex = $_.Exception
    while ($null -ne $ex) {
        if ($ex -is [System.Reflection.ReflectionTypeLoadException]) {
            $errorMessage += "`n`nLoader Exceptions:`n"
            foreach ($le in $ex.LoaderExceptions) {
                if ($null -ne $le) { $errorMessage += "- $($le.Message)`n" }
            }
            break
        }
        $ex = $ex.InnerException
    }

    [System.Windows.MessageBox]::Show($errorMessage, "Dependency Verification Failed", "OK", "Error") | Out-Null
    Write-Error $errorMessage
    exit
}

# --- Format Lists for Batch Mode ---
$simpleFormats = @("PNG", "JPG", "WEBP", "TIF")
$advancedFormats = @("JPG", "PNG", "GIF", "WEBP", "TIF", "BMP", "SVG", "PDF", "ICO", "AVIF", "JXL", "DDS")

# --- Data Structure for UI Generation (Translated from JS magickConfig) ---
$MagickConfig = @(
    [pscustomobject]@{
        Category = "Simple Edits";
        Flags    = @(
            [pscustomobject]@{ Flag = "-resize"; Type = "text"; Label = "Resize"; Placeholder = "e.g. 50% or 800x600"; Tooltip = "Resize image by percentage or dimensions." };
            [pscustomobject]@{ Flag = "-rotate"; Type = "range"; Label = "Rotate"; Min = -180; Max = 180; Step = 90; Default = 0; Tooltip = "Rotate image in 90-degree increments." };
            [pscustomobject]@{ Flag = "-quality"; Type = "range"; Label = "JPG/WEBP Quality"; Min = 1; Max = 100; Step = 1; Default = 92; Tooltip = "Set the compression quality."; SupportedFormats = @("JPG", "WEBP", "AVIF", "JXL") };
            [pscustomobject]@{ Flag = "-monochrome"; Type = "boolean"; Label = "Convert to Black & White"; Tooltip = "Make the image monochrome." };
            [pscustomobject]@{ Flag = "-normalize"; Type = "boolean"; Label = "Auto-Improve Contrast"; Tooltip = "Automatically enhances the image contrast." }
        )
    },
    [pscustomobject]@{
        Category = "Geometry & Sizing";
        Flags    = @(
            [pscustomobject]@{ Flag = "-resize"; Type = "text"; Label = "Resize"; Placeholder = "e.g. 800x600&gt;"; Tooltip = "Scale image to given geometry. Use '&gt;' to only shrink larger images." };
            [pscustomobject]@{ Flag = "-crop"; Type = "text"; Label = "Crop"; Placeholder = "e.g. 800x600+10+20"; Tooltip = "Cut out a rectangular region" };
            [pscustomobject]@{ Flag = "-scale"; Type = "text"; Label = "Scale"; Placeholder = "e.g. 50%"; Tooltip = "Resize without filtering" };
            [pscustomobject]@{ Flag = "-extent"; Type = "text"; Label = "Extent"; Placeholder = "e.g. 1024x768"; Tooltip = "Set the image size exactly" };
            [pscustomobject]@{ Flag = "-thumbnail"; Type = "text"; Label = "Thumbnail"; Placeholder = "e.g. 200x200"; Tooltip = "Create a thumbnail (strips profiles)" };
            [pscustomobject]@{ Flag = "-filter"; Type = "select"; Label = "Resize Filter"; Options = @("Lanczos", "Mitchell", "Cubic", "Gaussian", "Point", "Box", "Triangle"); Default = "Lanczos"; Tooltip = "Algorithm used for resizing" };
            [pscustomobject]@{ Flag = "-gravity"; Type = "select"; Label = "Gravity"; Options = @("NorthWest", "North", "NorthEast", "West", "Center", "East", "SouthWest", "South", "SouthEast"); Default = "Center"; Tooltip = "Placement direction for crop/extent/text" }
        )
    },
    [pscustomobject]@{
        Category = "Colors & Channels";
        Flags    = @(
            [pscustomobject]@{ Flag = "-background black -alpha remove -alpha off"; Type = "boolean"; Label = "Ignore Alpha (Flatten)"; Tooltip = "Flattens transparent areas to black to prevent math blowouts." };
            [pscustomobject]@{ Flag = "-colorspace"; Type = "select"; Label = "Colorspace"; Options = @("sRGB", "RGB", "Gray", "LinearGray", "CMYK", "HSL", "HSB", "Lab", "XYZ", "YUV", "Transparent"); Default = "sRGB" };
            [pscustomobject]@{ Flag = "-channel"; Type = "select"; Label = "Channel"; Options = @("RGB", "RGBA", "Alpha", "Red", "Green", "Blue", "Cyan", "Magenta", "Yellow", "Black"); Default = "RGBA" };
            [pscustomobject]@{ Flag = "-depth"; Type = "select"; Label = "Bit Depth"; Options = @("8", "16", "32"); Default = "8" };
            [pscustomobject]@{ Flag = "-alpha"; Type = "select"; Label = "Alpha"; Options = @("On", "Off", "Set", "Opaque", "Transparent", "Extract", "Copy", "Shape"); Default = "Set" };
            [pscustomobject]@{ Flag = "-background"; Type = "color"; Label = "Background Color"; Default = "#ffffff" };
            [pscustomobject]@{ Flag = "-fill"; Type = "color"; Label = "Fill Color"; Default = "#000000" };
            [pscustomobject]@{ Flag = "-bordercolor"; Type = "color"; Label = "Border Color"; Default = "#cccccc" }
        )
    },
    [pscustomobject]@{
        Category = "Adjustments (Sliders)";
        Flags    = @(
            [pscustomobject]@{ Flag = "-quality"; Type = "range"; Label = "Quality (JPEG/WebP)"; Min = 1; Max = 100; Step = 1; Default = 85; SupportedFormats = @("JPG", "WEBP", "AVIF", "JXL") };
            [pscustomobject]@{ Flag = "-density"; Type = "range"; Label = "Density (DPI)"; Min = 72; Max = 600; Step = 1; Default = 72 };
            [pscustomobject]@{ Flag = "-gamma"; Type = "range"; Label = "Gamma"; Min = 0.1; Max = 3.0; Step = 0.1; Default = 1.0 };
            [pscustomobject]@{ Flag = "-channel RGB -evaluate multiply"; Type = "text"; Label = "Exposure (Multiply)"; Placeholder = "e.g. 1.5" };
            [pscustomobject]@{ Flag = "-color-matrix"; Type = "text"; Label = "Color Matrix (Temp/Tint)"; Placeholder = "e.g. 1 0 0 0 1 0 0 0 1" };
            [pscustomobject]@{ Flag = "-modulate"; Type = "text"; Label = "Modulate (B,S,H)"; Placeholder = "e.g. 100,100,100"; Tooltip = "Brightness, Saturation, Hue percentages" };
            [pscustomobject]@{ Flag = "-level"; Type = "text"; Label = "Level Adjustment"; Placeholder = "e.g. 10%,90%"; Tooltip = "Adjust black point, white point, and gamma" };
            [pscustomobject]@{ Flag = "-brightness-contrast"; Type = "text"; Label = "Brightness x Contrast"; Placeholder = "e.g. 10x20"; Tooltip = "Percent values" }
        )
    },
    [pscustomobject]@{
        Category = "Blurs & Sharpening";
        Flags    = @(
            [pscustomobject]@{ Flag = "-blur"; Type = "select"; Label = "Blur"; Options = @("0x1", "0x2", "0x4", "0x8", "0x16"); Default = "0x4"; Tooltip = "Standard blur" };
            [pscustomobject]@{ Flag = "-gaussian-blur"; Type = "select"; Label = "Gaussian Blur"; Options = @("0x1", "0x2", "0x4", "0x8"); Default = "0x2"; Tooltip = "True Gaussian blur" };
            [pscustomobject]@{ Flag = "-radial-blur"; Type = "range"; Label = "Radial Blur (Angle)"; Min = 0; Max = 360; Step = 1; Default = 10 };
            [pscustomobject]@{ Flag = "-motion-blur"; Type = "select"; Label = "Motion Blur"; Options = @("0x4+0", "0x8+0", "0x16+0", "0x8+90", "0x8+45"); Default = "0x8+0"; Tooltip = "radiusxsigma+angle" };
            [pscustomobject]@{ Flag = "-sharpen"; Type = "select"; Label = "Sharpen"; Options = @("0x1", "0x2", "0x3"); Default = "0x1"; Tooltip = "Standard sharpen" };
            [pscustomobject]@{ Flag = "-unsharp"; Type = "select"; Label = "Unsharp Mask"; Options = @("0x2+1+0.05", "0x2+2+0.02", "0x5+2+0.02"); Default = "0x2+1+0.05"; Tooltip = "radiusxsigma+amount+threshold" };
            [pscustomobject]@{ Flag = "+noise"; Type = "select"; Label = "Add Noise"; Options = @("Gaussian", "Uniform", "Impulse", "Laplacian", "Multiplicative", "Poisson"); Default = "Gaussian"; Tooltip = "Add algorithmic noise" };
            [pscustomobject]@{ Flag = "-despeckle"; Type = "boolean"; Label = "Despeckle"; Tooltip = "Reduce speckle noise" }
        )
    },
    [pscustomobject]@{
        Category = "Transformations";
        Flags    = @(
            [pscustomobject]@{ Flag = "-rotate"; Type = "range"; Label = "Rotate (Degrees)"; Min = -360; Max = 360; Step = 1; Default = 90 };
            [pscustomobject]@{ Flag = "-flip"; Type = "boolean"; Label = "Flip (Vertical)"; Tooltip = "Mirror image vertically" };
            [pscustomobject]@{ Flag = "-flop"; Type = "boolean"; Label = "Flop (Horizontal)"; Tooltip = "Mirror image horizontally" };
            [pscustomobject]@{ Flag = "-transpose"; Type = "boolean"; Label = "Transpose"; Tooltip = "Flip and flop" };
            [pscustomobject]@{ Flag = "-transverse"; Type = "boolean"; Label = "Transverse"; Tooltip = "Flop and flip" };
            [pscustomobject]@{ Flag = "-shear"; Type = "text"; Label = "Shear (XxY degrees)"; Placeholder = "e.g. 10x10" };
            [pscustomobject]@{ Flag = "-roll"; Type = "text"; Label = "Roll (+X+Y)"; Placeholder = "e.g. +10+20" };
            [pscustomobject]@{ Flag = "-trim"; Type = "boolean"; Label = "Trim edges"; Tooltip = "Trim solid color edges" }
        )
    },
    [pscustomobject]@{
        Category = "Effects & Artistic";
        Flags    = @(
            [pscustomobject]@{ Flag = "-charcoal"; Type = "range"; Label = "Charcoal Effect"; Min = 1; Max = 10; Step = 0.1; Default = 2 };
            [pscustomobject]@{ Flag = "-edge"; Type = "range"; Label = "Edge Detect"; Min = 1; Max = 10; Step = 1; Default = 1 };
            [pscustomobject]@{ Flag = "-emboss"; Type = "select"; Label = "Emboss"; Options = @("0x1", "0x2", "0x4"); Default = "0x2" };
            [pscustomobject]@{ Flag = "-paint"; Type = "range"; Label = "Oil Paint Effect"; Min = 1; Max = 10; Step = 1; Default = 3 };
            [pscustomobject]@{ Flag = "-sketch"; Type = "select"; Label = "Sketch"; Options = @("0x5+135", "0x10+135", "0x20+135"); Default = "0x10+135" };
            [pscustomobject]@{ Flag = "-vignette"; Type = "select"; Label = "Vignette"; Options = @("0x20+10+10", "0x50+20+20", "0x100+50+50"); Default = "0x50+20+20" };
            [pscustomobject]@{ Flag = "-swirl"; Type = "range"; Label = "Swirl (Degrees)"; Min = -360; Max = 360; Step = 1; Default = 180 };
            [pscustomobject]@{ Flag = "-wave"; Type = "text"; Label = "Wave (amplitudexlength)"; Placeholder = "e.g. 10x100" };
            [pscustomobject]@{ Flag = "-implode"; Type = "range"; Label = "Implode/Explode"; Min = -10; Max = 10; Step = 0.1; Default = 1 }
        )
    },
    [pscustomobject]@{
        Category = "Image Settings & Opts";
        Flags    = @(
            [pscustomobject]@{ Flag = "MAGICK_OCL_DEVICE"; IsEnv = $true; Type = "boolean"; Label = "Hardware Acceleration (OpenCL)"; Tooltip = "Enable OpenCL GPU compute. Can significantly speed up complex filters." };
            [pscustomobject]@{ Flag = "-strip"; Type = "boolean"; Label = "Strip Metadata"; Tooltip = "Remove all profiles and comments" };
            [pscustomobject]@{ Flag = "-interlace"; Type = "select"; Label = "Interlace"; Options = @("None", "Line", "Plane", "Partition", "JPEG", "GIF", "PNG"); Default = "None"; SupportedFormats = @("JPG", "PNG", "GIF") };
            [pscustomobject]@{ Flag = "-compress"; Type = "select"; Label = "Compression"; Options = @("None", "JPEG", "LZW", "Zip", "BZip", "RLE", "Lossless"); Default = "JPEG"; SupportedFormats = @("PNG", "TIF", "GIF", "PDF") };
            [pscustomobject]@{ Flag = "-auto-orient"; Type = "boolean"; Label = "Auto Orient"; Tooltip = "Orient based on EXIF" };
            [pscustomobject]@{ Flag = "-normalize"; Type = "boolean"; Label = "Normalize"; Tooltip = "Expand color contrast to full range" };
            [pscustomobject]@{ Flag = "-negate"; Type = "boolean"; Label = "Negate (Invert Colors)" };
            [pscustomobject]@{ Flag = "-monochrome"; Type = "boolean"; Label = "Monochrome (Black & White)" };
            [pscustomobject]@{ Flag = "-sepia-tone"; Type = "range"; Label = "Sepia Tone Threshold"; Min = 0; Max = 99; Step = 1; Default = 80 };
            [pscustomobject]@{ Flag = "-comment"; Type = "boolean"; Label = "Add Timestamp Comment"; Tooltip = "Embeds a comment in the image metadata with the generation date and time." }
        )
    },
    [pscustomobject]@{
        Category = "Drawing & Text";
        Flags    = @(
            [pscustomobject]@{ Flag = "-font"; Type = "text"; Label = "Font Name/Path"; Placeholder = "e.g. Arial or /path/to/font.ttf" };
            [pscustomobject]@{ Flag = "-pointsize"; Type = "range"; Label = "Pointsize"; Min = 8; Max = 200; Step = 1; Default = 24 };
            [pscustomobject]@{ Flag = "-annotate"; Type = "text"; Label = "Annotate Text"; Placeholder = "e.g. +10+20 'Text'" };
            [pscustomobject]@{ Flag = "-draw"; Type = "text"; Label = "Draw Object"; Placeholder = "e.g. 'circle 50,50 50,10'" };
            [pscustomobject]@{ Flag = "-stroke"; Type = "color"; Label = "Stroke Color"; Default = "#000000" };
            [pscustomobject]@{ Flag = "-strokewidth"; Type = "range"; Label = "Stroke Width"; Min = 0; Max = 20; Step = 1; Default = 1 }
        )
    },
    [pscustomobject]@{
        Category = "Advanced & 'Secret' Magic";
        Flags    = @(
            [pscustomobject]@{ Flag = "-liquid-rescale"; Type = "text"; Label = "Liquid Rescale"; Placeholder = "e.g. 800x600"; Tooltip = "Content-aware seam carving (smart resize)" };
            [pscustomobject]@{ Flag = "-distort"; Type = "select"; Label = "Distortion"; Options = @("Arc 60", "Polar 0", "Barrel 0.2,0.0,0.2", "Perspective 0,0 20,20 256,0 256,0 0,256 0,256 256,256 236,236"); Default = "Arc 60" };
            [pscustomobject]@{ Flag = "-morphology"; Type = "select"; Label = "Morphology"; Options = @("Dilate Diamond", "Erode Diamond", "Edge Diamond", "Smooth Octagon"); Default = "Dilate Diamond"; Tooltip = "Mathematical shape operations" };
            [pscustomobject]@{ Flag = "-lat"; Type = "text"; Label = "Local Adaptive Threshold"; Placeholder = "e.g. 25x25-10%"; Tooltip = "Extracts text from dark/uneven scans" };
            [pscustomobject]@{ Flag = "-fuzz"; Type = "text"; Label = "Fuzz (Color Tolerance)"; Placeholder = "e.g. 5%"; Tooltip = "Color matching tolerance for trim/transparent" };
            [pscustomobject]@{ Flag = "-transparent"; Type = "color"; Label = "Make Color Transparent"; Default = "#ffffff"; Tooltip = "Use with Fuzz to remove backgrounds" };
            [pscustomobject]@{ Flag = "-evaluate"; Type = "select"; Label = "Pixel Math"; Options = @("Add 10%", "Subtract 10%", "Multiply 1.5", "Sine 1"); Default = "Add 10%" };
            [pscustomobject]@{ Flag = "-polaroid"; Type = "text"; Label = "Polaroid Effect (Angle)"; Placeholder = "e.g. -5"; Tooltip = "Wraps image in a tilted Polaroid frame" };
            [pscustomobject]@{ Flag = "-shadow"; Type = "text"; Label = "Drop Shadow"; Placeholder = "e.g. 80x3+5+5"; Tooltip = "opacity x sigma + x + y" }
        )
    },
    [pscustomobject]@{
        Category = "Retro & Halftones";
        Flags    = @(
            [pscustomobject]@{ Flag = "-threshold"; Type = "text"; Label = "Hard Threshold"; Placeholder = "e.g. 50%"; Tooltip = "Pure black and white" };
            [pscustomobject]@{ Flag = "-random-threshold"; Type = "text"; Label = "Random Threshold"; Placeholder = "e.g. 10x90%"; Tooltip = "Granular sand/dither effect" };
            [pscustomobject]@{ Flag = "-ordered-dither"; Type = "select"; Label = "Ordered Dither"; Options = @("h4x4a", "h6x6a", "h8x8a", "o3x3", "o4x4", "o8x8"); Default = "o8x8"; Tooltip = "Retro halftone patterns (like comic books/newspapers)" };
            [pscustomobject]@{ Flag = "-posterize"; Type = "range"; Label = "Posterize (Levels)"; Min = 2; Max = 256; Step = 1; Default = 4; Tooltip = "Reduce number of color levels (retro gaming look)" };
            [pscustomobject]@{ Flag = "-tint"; Type = "text"; Label = "Tint (%)"; Placeholder = "e.g. 100"; Tooltip = "Colorize with the Fill color" }
        )
    },
    [pscustomobject]@{
        Category = "DDS Specific Options";
        RequiredFormat = "DDS"; # This entire category will only show if the output format is DDS
        Flags    = @(
            [pscustomobject]@{ Flag = "dds:compression"; IsDefine = $true; Type = "select"; Label = "DDS Compression"; Options = @("none", "dxt1", "dxt3", "dxt5"); Default = "dxt1"; Tooltip = "Specifies the DXT compression algorithm for DDS files." };
            [pscustomobject]@{ Flag = "dds:mipmaps"; IsDefine = $true; Type = "range"; Label = "Mipmap Levels"; Min = 0; Max = 10; Step = 1; Default = 0; Tooltip = "Number of mipmap levels to generate. 0 means none." };
            [pscustomobject]@{ Flag = "dds:cluster-fit"; IsDefine = $true; Type = "boolean"; Label = "Use Cluster Fit (Higher Quality)"; Tooltip = "Improves DXT compression quality at the cost of speed. May not be supported in all ImageMagick versions." };
            [pscustomobject]@{ Flag = "dds:fast-mipmaps"; IsDefine = $true; Type = "boolean"; Label = "Use Fast Mipmaps"; Tooltip = "Use a faster but lower quality box filter for mipmap generation." };
            [pscustomobject]@{ Flag = "dds:weight-by-alpha"; IsDefine = $true; Type = "boolean"; Label = "Weight by Alpha"; Tooltip = "Weight the color metric by the alpha channel." }
        )
    }
)

# 2. The GUI Blueprint (XAML)
# This multi-line string defines the window layout. It's the equivalent of your HTML structure.
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PowerShell Magick Builder" Height="270" Width="1800" MinHeight="270" MinWidth="1400" AllowDrop="True"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="Height" ResizeMode="CanResizeWithGrip" Foreground="{DynamicResource AppForegroundBrush}">
    
    <!-- Central Resource Dictionary for Theming (like a CSS stylesheet) -->
    <Window.Resources>
        <!-- WinUtil Standalone Dark Theme -->
        <SolidColorBrush x:Key="AppBackgroundBrush" Color="#1E1E1E"/>
        <SolidColorBrush x:Key="AppForegroundBrush" Color="#FFFFFF"/> <!-- Primary Heading Text -->
        <SolidColorBrush x:Key="InputTextBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="AppGrayTextBrush" Color="#AAAAAA"/> <!-- Secondary Text -->
        <SolidColorBrush x:Key="TitleBarTextBrush" Color="#CCCCCC"/>
        <SolidColorBrush x:Key="ControlLabelBrush" Color="#CCCCCC"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#0078D4"/>
        <SolidColorBrush x:Key="AccentHoverBrush" Color="#005A9E"/>
        <SolidColorBrush x:Key="AccentForegroundBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="ControlBackgroundBrush" Color="#1E1E1E"/>
        <SolidColorBrush x:Key="ButtonBackgroundBrush" Color="#333333"/>
        <SolidColorBrush x:Key="ControlBorderBrush" Color="#555555"/>
        <SolidColorBrush x:Key="ButtonHoverBrush" Color="#444444"/>
        <SolidColorBrush x:Key="CloseButtonHoverBrush" Color="#E81123"/>

        <!-- Sizing -->
        <Thickness x:Key="WindowOutlineThickness">1</Thickness>

        <!-- Font Families -->
        <FontFamily x:Key="FontPrimary">"Segoe UI Semibold"</FontFamily>
        <FontFamily x:Key="FontSecondary">"Segoe UI"</FontFamily>
        <FontFamily x:Key="FontInput">"Segoe UI"</FontFamily>

        <!-- Base Text Controls (prevents Windows OS theme ghosting) -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource AppForegroundBrush}"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{StaticResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource InputTextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}" Foreground="{TemplateBinding Foreground}" Focusable="False" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="BgBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="25"/>
                                                </Grid.ColumnDefinitions>
                                                <Border x:Name="ArrowBorder" Grid.Column="1" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1,0,0,0">
                                                    <Path x:Name="Arrow" Fill="{TemplateBinding Foreground}" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z"/>
                                                </Border>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="BgBorder" Property="Background" Value="{StaticResource ButtonHoverBrush}"/>
                                                <Setter TargetName="BgBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                                            </Trigger>
                                            <Trigger Property="IsChecked" Value="True">
                                                <Setter TargetName="BgBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="10,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                            <Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Grid x:Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border x:Name="DropDownBorder" Background="{StaticResource ControlBackgroundBrush}" BorderThickness="1" BorderBrush="{StaticResource ControlBorderBrush}"/>
                                    <ScrollViewer Margin="1" SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained" />
                                    </ScrollViewer>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="{StaticResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource InputTextBrush}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource ButtonHoverBrush}"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
                    <Setter Property="Foreground" Value="{StaticResource AccentForegroundBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{StaticResource AppBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AppForegroundBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
        </Style>
        
        <!-- Popups & Context Menus -->
        <Style TargetType="ToolTip">
            <Setter Property="Background" Value="{StaticResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AppForegroundBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="ContextMenu">
            <Setter Property="Background" Value="{StaticResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AppForegroundBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="MenuItem">
            <Setter Property="Background" Value="{StaticResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AppForegroundBrush}"/>
        </Style>

        <!-- Modern flat style for Tool GroupBoxes (Removes native white 3D bevel) -->
        <Style TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="{StaticResource AppGrayTextBrush}"/>
            <Setter Property="Padding" Value="5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GroupBox">
                        <Grid SnapsToDevicePixels="True">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <ContentPresenter Grid.Row="0" Margin="5,0,0,5" ContentSource="Header" RecognizesAccessKey="True" TextElement.Foreground="{TemplateBinding Foreground}"/>
                            <Border Grid.Row="1" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Background="{TemplateBinding Background}" CornerRadius="4">
                                <ContentPresenter Margin="{TemplateBinding Padding}"/>
                            </Border>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Style for TextBoxes -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource ControlBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource InputTextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="5"/>
            <Setter Property="CaretBrush" Value="{StaticResource AppForegroundBrush}"/>
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="FontFamily" Value="{StaticResource FontInput}"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                </Trigger>
                <Trigger Property="IsKeyboardFocused" Value="True">
                    <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Base Style for standard Buttons (like Browse) -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource ButtonBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AppForegroundBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource ControlBorderBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="FontFamily" Value="{StaticResource FontInput}"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource ButtonHoverBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Style for Accent Buttons (Convert) -->
        <Style x:Key="AccentButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource AccentForegroundBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="FontFamily" Value="{StaticResource FontInput}"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource AccentHoverBrush}"/>
                    <Setter Property="BorderBrush" Value="{StaticResource AccentHoverBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Style for Window Control Buttons (Min, Max) -->
        <Style x:Key="WindowControlButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="45"/>
            <Setter Property="Padding" Value="0"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource ButtonHoverBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Style for the Close Button -->
        <Style x:Key="WindowCloseButton" TargetType="Button" BasedOn="{StaticResource WindowControlButton}">
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource CloseButtonHoverBrush}"/>
                    <Setter Property="Foreground" Value="White"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Border BorderBrush="{StaticResource AccentBrush}" BorderThickness="{StaticResource WindowOutlineThickness}" Background="{StaticResource AppBackgroundBrush}">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2*" MinWidth="400"/> <!-- Image Preview -->
                <ColumnDefinition Width="Auto"/> <!-- GridSplitter -->
                <ColumnDefinition Width="3*" MinWidth="960"/> <!-- Main Content (Input/Output/Controls) -->
            </Grid.ColumnDefinitions>

            <!-- Left Panel: Image Preview -->
            <Border Grid.Column="0" BorderBrush="{StaticResource ControlBorderBrush}" BorderThickness="0,0,1,0" Background="{StaticResource AppBackgroundBrush}">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>   <!-- Top: Image Preview -->
                        <RowDefinition Height="Auto"/> <!-- Middle: Splitter -->
                        <RowDefinition Height="*"/>   <!-- Bottom: Batch List -->
                    </Grid.RowDefinitions>

                    <!-- Top Panel: Image Preview & Layer Selector -->
                    <Grid Grid.Row="0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock x:Name="PreviewPlaceholder" Grid.Row="0" Text="Drag &amp; Drop Image Here" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{StaticResource AppGrayTextBrush}" FontSize="16" />
                        <Image x:Name="ImagePreviewControl" Grid.Row="0" Stretch="Uniform">
                            <Image.ContextMenu>
                                <ContextMenu>
                                    <MenuItem x:Name="MenuDevelopImage" Header="Develop Module..." />
                                </ContextMenu>
                            </Image.ContextMenu>
                        </Image>
                        <Button x:Name="DevelopToolButton" Content="Develop" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="10" Padding="8,4" ToolTip="Open the image adjustment tool" Visibility="Collapsed"/>
                        <Button x:Name="ResetPreviewButton" Content="↺ Original" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="10" Padding="8,4" ToolTip="Restore the original image preview" Visibility="Collapsed"/>
                        
                        <!-- Theme Palette Overlay -->
                        <Border x:Name="ThemePalettePanel" Grid.Row="0" Background="#E61E1E1E" Visibility="Collapsed" Padding="15" Margin="10" CornerRadius="8" BorderThickness="1" BorderBrush="{DynamicResource ControlBorderBrush}">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <TextBlock Text="Theme Palette" Foreground="{DynamicResource AccentBrush}" FontSize="16" FontWeight="Bold" Margin="0,0,0,10" HorizontalAlignment="Center"/>
                                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                                    <WrapPanel x:Name="ThemeColorWrapPanel" HorizontalAlignment="Center"/>
                                </ScrollViewer>
                                <Button x:Name="CloseThemePanelButton" Content="✕" HorizontalAlignment="Right" VerticalAlignment="Top" Background="Transparent" Foreground="{DynamicResource AppForegroundBrush}" BorderThickness="0" FontSize="14" ToolTip="Close Palette" Padding="5"/>
                            </Grid>
                        </Border>
                        <Button x:Name="ThemeButton" Grid.Row="0" Content="🎨 Theme" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="10" Padding="8,4" ToolTip="View current theme colors" />
                        
                        <StackPanel x:Name="LayerPanel" Grid.Row="1" Orientation="Horizontal" Margin="10,5,10,10" Visibility="Collapsed">
                            <Label Content="Select Layer:" VerticalAlignment="Center" Foreground="{StaticResource AppGrayTextBrush}"/>
                            <ComboBox x:Name="LayerSelectorComboBox" MinWidth="150" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Grid>

                    <GridSplitter x:Name="PreviewSplitter" Grid.Row="1" Height="5" HorizontalAlignment="Stretch" VerticalAlignment="Center" Background="{StaticResource ButtonHoverBrush}" ToolTip="Drag to resize panels" Visibility="Collapsed"/>

                    <!-- Bottom Panel: Batch File List -->
                    <Grid Grid.Row="2" x:Name="BatchFilePanel" Visibility="Collapsed">
                        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                        <Grid x:Name="PreviewHeader" Grid.Row="0" Margin="10,5,10,5">
                         <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Batch File List" VerticalAlignment="Center" Foreground="{StaticResource AppGrayTextBrush}" FontWeight="Bold"/>
                        <Button x:Name="ClearBatchButton" Grid.Column="1" Content="Clear Batch" Padding="8,3"/>
                    </Grid>
                        <ScrollViewer x:Name="PreviewListScrollViewer" Grid.Row="1" VerticalScrollBarVisibility="Auto">
                            <ListBox x:Name="PreviewFileListBox" Background="Transparent" BorderThickness="0" Foreground="{StaticResource AppForegroundBrush}" SelectionMode="Single"/>
                        </ScrollViewer>
                    </Grid>
                </Grid>
            </Border>

            <!-- GridSplitter -->
            <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Center" VerticalAlignment="Stretch" Background="{StaticResource ButtonHoverBrush}" ToolTip="Drag to resize panels"/>

            <!-- Right Panel: Main Content -->
            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="30"/> <!-- Custom Title Bar -->
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Custom Draggable Title Bar -->
                <Grid Grid.Row="0" x:Name="TitleBar" Background="Transparent">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="PowerShell Magick Builder" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="{StaticResource TitleBarTextBrush}"/>
                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                        <Button x:Name="MinimizeButton" Style="{StaticResource WindowControlButton}" ToolTip="Minimize"><Path Data="M0,6 H12" Stroke="{Binding Path=Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1"/></Button>
                        <Button x:Name="MaximizeButton" Style="{StaticResource WindowControlButton}" ToolTip="Maximize"><Path Data="M0,0 H10 V10 H0 Z" Stroke="{Binding Path=Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1"/></Button>
                        <Button x:Name="CloseButton" Style="{StaticResource WindowCloseButton}" ToolTip="Close"><Path Data="M0,0 L10,10 M0,10 L10,0" Stroke="{Binding Path=Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.5"/></Button>
                    </StackPanel>
                </Grid>

                <StackPanel Grid.Row="1" Margin="15,15,15,5">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" Margin="0,0,5,0">
                            <Label Content="Input File" Foreground="{StaticResource ControlLabelBrush}" />
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBox x:Name="InputFileTextBox" Grid.Column="0" Text="input.jpg" />
                                <Button x:Name="BrowseInputButton" Grid.Column="1" Content="..." Margin="5,0,0,0" Padding="10,5" ToolTip="Browse for an input file" />
                            </Grid>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Margin="5,0,0,0">
                            <Label Content="Output File" Foreground="{StaticResource ControlLabelBrush}" />
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBox x:Name="OutputFileTextBox" Grid.Column="0" Text="output.png" />
                                <ComboBox x:Name="OutputFormatComboBox" Grid.Column="1" Margin="5,0,0,0" Padding="8,5" Visibility="Visible" ToolTip="Select the output format"/>
                                <Button x:Name="BrowseOutputButton" Grid.Column="2" Content="..." Margin="5,0,0,0" Padding="10,5" ToolTip="Select an output file location" />
                            </Grid>
                        </StackPanel>
                    </Grid>
                </StackPanel>

                <Button x:Name="ModeToggleButton" Grid.Row="2" Content="Advanced Mode" Margin="15,5,15,10" />

                <ScrollViewer Grid.Row="3" x:Name="SimpleScrollViewer" VerticalScrollBarVisibility="Auto" Visibility="Visible" Margin="15,0,15,15" Padding="0,0,5,0">
                    <StackPanel x:Name="SimpleOptionsPanel"/>
                </ScrollViewer>

                <ScrollViewer Grid.Row="3" x:Name="AdvancedScrollViewer" VerticalScrollBarVisibility="Auto" Visibility="Collapsed" Margin="15,0,15,15" Padding="0,0,5,0">
                    <Grid x:Name="AdvancedOptionsPanel">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel x:Name="AdvancedColumn1" Grid.Column="0" Margin="0,0,5,0"/>
                        <StackPanel x:Name="AdvancedColumn2" Grid.Column="1" Margin="5,0,5,0"/>
                        <StackPanel x:Name="AdvancedColumn3" Grid.Column="2" Margin="5,0,5,0"/>
                        <StackPanel x:Name="AdvancedColumn4" Grid.Column="3" Margin="5,0,0,0"/>
                    </Grid>
                </ScrollViewer>

                <GroupBox Grid.Row="4" Header="Live Command Preview" Margin="15,0,15,5" Foreground="{StaticResource AppGrayTextBrush}" BorderBrush="{StaticResource ControlBorderBrush}">
                    <TextBox x:Name="CommandPreviewBox" IsReadOnly="True" Background="{StaticResource AppBackgroundBrush}" Foreground="{StaticResource AccentBrush}" BorderThickness="0" FontFamily="Consolas" TextWrapping="Wrap" MinHeight="40" VerticalScrollBarVisibility="Auto"/>
                </GroupBox>

                <StackPanel Grid.Row="5" Margin="15,0,15,15">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="LivePreviewButton" Grid.Column="0" Content="TEST PREVIEW" Margin="0,0,5,0" Padding="10" ToolTip="Test your current command settings on the image." />
                        <Button x:Name="ConvertButton" Grid.Column="1" Content="CONVERT" Margin="5,0,0,0" Padding="10" Style="{StaticResource AccentButton}" />
                    </Grid>
                    <Label x:Name="StatusLabel" Content="Ready." Margin="0,10,0,0" HorizontalAlignment="Center" Foreground="{StaticResource AppGrayTextBrush}" />
                </StackPanel>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

# 3. Build the UI in Memory
Write-Host "Building UI from XAML..." -ForegroundColor Yellow
try {
    # XamlReader.Parse is the most direct and robust method for loading a XAML string,
    # but can be unreliable in some environments. Loading from a MemoryStream is a more robust alternative that
    # correctly handles special characters in WPF binding expressions.
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($xaml)
    $stream = New-Object System.IO.MemoryStream(,$bytes) # The comma is crucial to pass the byte array as a single object.
    $window = [System.Windows.Markup.XamlReader]::Load($stream)
    Write-Host "[OK] UI built successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to load XAML. Error: $($_.Exception.Message)"
    return
}

# 4. Connect the Wires
Write-Host "Connecting UI control references..." -ForegroundColor Yellow
# Get references to the static controls from the XAML by their names.
$inputFileBox = $window.FindName("InputFileTextBox")
$outputFileBox = $window.FindName("OutputFileTextBox")
$browseInputButton = $window.FindName("BrowseInputButton")
$browseOutputButton = $window.FindName("BrowseOutputButton")
$titleBar = $window.FindName("TitleBar")
$outputFormatComboBox = $window.FindName("OutputFormatComboBox")
$minimizeButton = $window.FindName("MinimizeButton")
$maximizeButton = $window.FindName("MaximizeButton")
$closeButton = $window.FindName("CloseButton")
$convertButton = $window.FindName("ConvertButton")
$statusLabel = $window.FindName("StatusLabel")
$modeToggleButton = $window.FindName("ModeToggleButton")
$advancedScrollViewer = $window.FindName("AdvancedScrollViewer")
$simpleScrollViewer = $window.FindName("SimpleScrollViewer")
$simpleOptionsPanel = $window.FindName("SimpleOptionsPanel")
$imagePreviewControl = $window.FindName("ImagePreviewControl")
$livePreviewButton = $window.FindName("LivePreviewButton")
$resetPreviewButton = $window.FindName("ResetPreviewButton")
$themeButton = $window.FindName("ThemeButton")
$themePalettePanel = $window.FindName("ThemePalettePanel")
$themeColorWrapPanel = $window.FindName("ThemeColorWrapPanel")
$closeThemePanelButton = $window.FindName("CloseThemePanelButton")
$developToolButton = $window.FindName("DevelopToolButton")
$menuDevelopImage = $window.FindName("MenuDevelopImage")
$commandPreviewBox = $window.FindName("CommandPreviewBox")
$previewPlaceholder = $window.FindName("PreviewPlaceholder")
$previewHeader = $window.FindName("PreviewHeader")
$clearBatchButton = $window.FindName("ClearBatchButton")
$batchFilePanel = $window.FindName("BatchFilePanel")
$previewSplitter = $window.FindName("PreviewSplitter")
$layerPanel = $window.FindName("LayerPanel")
$layerSelectorComboBox = $window.FindName("LayerSelectorComboBox")
$previewListScrollViewer = $window.FindName("PreviewListScrollViewer")
$previewFileListBox = $window.FindName("PreviewFileListBox")
$advancedOptionsPanel = $window.FindName("AdvancedOptionsPanel")
$advancedColumn1 = $window.FindName("AdvancedColumn1")
$advancedColumn2 = $window.FindName("AdvancedColumn2")
$advancedColumn3 = $window.FindName("AdvancedColumn3")
$advancedColumn4 = $window.FindName("AdvancedColumn4")
Write-Host "[OK] UI controls connected." -ForegroundColor Green

# --- Theme Palette Generation ---
$themeBrushes = @("AppBackgroundBrush", "AppForegroundBrush", "InputTextBrush", "AppGrayTextBrush", "TitleBarTextBrush", "ControlLabelBrush", "AccentBrush", "AccentHoverBrush", "AccentForegroundBrush", "ControlBackgroundBrush", "ButtonBackgroundBrush", "ControlBorderBrush", "ButtonHoverBrush", "CloseButtonHoverBrush")
foreach ($brushKey in $themeBrushes) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = "10"
    $sp.Width = 85
    
    $border = New-Object System.Windows.Controls.Border
    $border.Width = 40
    $border.Height = 40
    $border.BorderThickness = "1"
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "ControlBorderBrush")
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $brushKey)
    $border.CornerRadius = "4"
    $border.HorizontalAlignment = "Center"
    
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $brushKey -replace "Brush",""
    $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AppForegroundBrush")
    $label.FontSize = 11
    $label.TextAlignment = "Center"
    $label.TextWrapping = "Wrap"
    $label.Margin = "0,5,0,0"

    $sp.Children.Add($border) | Out-Null
    $sp.Children.Add($label) | Out-Null
    $themeColorWrapPanel.Children.Add($sp) | Out-Null
}

$themeButton.Add_Click({ $themePalettePanel.Visibility = 'Visible' })
$closeThemePanelButton.Add_Click({ $themePalettePanel.Visibility = 'Collapsed' })

# Hashtable to store all dynamically created controls for easy access later
$dynamicControls = @{}

# --- Central Command Generation & Preview Logic ---
function Get-CommonArguments {
    $commonArgs = @()
    # Iterate through the values to handle controls from all categories, including simple and advanced.
    foreach ($control in $dynamicControls.Values) {
        if ($control.EnableControl.IsChecked) {
            # Special handling for defines
            if ($control.Config.PSObject.Properties.Name -contains 'IsDefine' -and $control.Config.IsDefine) {
                $commonArgs += "-define"
                $defineKey = $control.Config.Flag
                if ($control.Config.Type -eq 'boolean') {
                    $commonArgs += "$($defineKey)=true"
                } else {
                    $valueControl = $control.ValueControl
                    $value = if ($valueControl -is [System.Windows.Controls.Slider]) { $valueControl.Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { $valueControl.SelectedItem }
                    $commonArgs += "$($defineKey)=$($value)"
                }
                continue
            }

            # Special handling for timestamp comment
            if ($control.Config.Flag -eq '-comment' -and $control.Config.Type -eq 'boolean') {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
                $commentText = "Generated by Magick Builder on $timestamp"
                $commonArgs += $control.Config.Flag
                $commonArgs += "`"$commentText`"" # Quote the comment to handle spaces
                continue
            }

            # Special handling for environment variables (they don't go in the command string)
            if ($control.Config.PSObject.Properties.Name -contains 'IsEnv' -and $control.Config.IsEnv) { continue }

            $commonArgs += $control.Config.Flag
            if ($control.ValueControl) {
                if ($control.ValueControl -is [System.Windows.Controls.Slider]) {
                    $commonArgs += $control.ValueControl.Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
                } elseif ($control.ValueControl -is [System.Windows.Controls.ComboBox]) {
                    $commonArgs += $control.ValueControl.SelectedItem
                } elseif ($control.ValueControl -is [System.Windows.Controls.TextBox]) {
                    $textBox = $control.ValueControl
                    $val = $textBox.Text
                    if ($val -eq $textBox.Tag) { $commonArgs += "" } 
                    else {
                        if ($val -match '\s') { $commonArgs += "`"$val`"" } else { $commonArgs += $val }
                    }
                } elseif ($control.ValueControl -is [System.Windows.Controls.Button]) {
                    $commonArgs += $control.ValueControl.Content
                }
            }
        }
    }
    return $commonArgs
}

function Update-CommandPreview {
    if (-not $commandPreviewBox) { return }
    
    $inPath = $inputFileBox.Text
    if ([string]::IsNullOrWhiteSpace($inPath)) { $inPath = "input.jpg" }
    if ($imagePreviewControl.Tag -is [System.Windows.Media.Imaging.BitmapDecoder] -and $layerSelectorComboBox.SelectedIndex -ge 0) {
        $inPath = "$inPath`[$($layerSelectorComboBox.SelectedIndex)]"
    }
    $outPath = $outputFileBox.Text
    if ([string]::IsNullOrWhiteSpace($outPath)) { $outPath = "output.png" }

    $argsArray = Get-CommonArguments
    $cmd = "magick `"$inPath`" " + ($argsArray -join ' ') + " `"$outPath`""
    $commandPreviewBox.Text = $cmd.Replace('  ', ' ')
}

function Update-ControlsForFormat {
    if (-not $outputFormatComboBox.SelectedItem) { return }
    $selectedFormat = $outputFormatComboBox.SelectedItem.ToString().ToUpper()

    # First, handle visibility of entire categories based on format
    $allColumns = @($advancedColumn1, $advancedColumn2, $advancedColumn3, $advancedColumn4)
    foreach ($column in $allColumns) {
        foreach ($groupBox in $column.Children) {
            if ($groupBox.Tag -and $groupBox.Tag.PSObject.Properties.Name -contains 'RequiredFormat') {
                if ($groupBox.Tag.RequiredFormat -eq $selectedFormat) {
                    $groupBox.Visibility = 'Visible'
                } else {
                    $groupBox.Visibility = 'Collapsed'
                }
            }
        }
    }

    # Then, handle visibility of individual flags within categories
    foreach ($control in $dynamicControls.Values) {
        $parentPanel = $control.EnableControl.Parent
        # Use PSObject.Properties to safely check if the property exists
        if ($control.Config.PSObject.Properties.Name -contains 'SupportedFormats') {
            $supported = $control.Config.SupportedFormats
            if ($supported -and ($supported -notcontains $selectedFormat)) {
                $parentPanel.Visibility = 'Collapsed'
            } else {
                $parentPanel.Visibility = 'Visible'
            }
        } else {
            $parentPanel.Visibility = 'Visible'
        }
    }
}

# Helper function to create a SolidColorBrush from a hex string.
function Get-BrushFromHex {
    param([string]$hex)
    try {
        # Using a single-expression return is more robust against unintended pipeline output.
        return ([System.Windows.Media.BrushConverter]::new().ConvertFrom($hex))
    } catch {
        Write-Warning "Invalid hex color '$hex'. Defaulting to Red."
        return [System.Windows.Media.Brushes]::Red
    }
}

# Helper function to update the image preview
function Update-ImagePreview {
    param([string]$ImagePath)

    # Hide layer panel by default and clear any stored decoder
    $layerPanel.Visibility = 'Collapsed'
    $imagePreviewControl.Tag = $null
    if ($null -ne $resetPreviewButton) { $resetPreviewButton.Visibility = 'Collapsed' }

    if ([System.IO.File]::Exists($ImagePath)) {
        try {
            $uri = New-Object System.Uri($ImagePath)
            # Use BitmapDecoder to inspect the image for multiple frames (layers)
            $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create($uri, [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)

            if ($decoder.Frames.Count -gt 1) {
                # Multi-frame image (TIFF, GIF, etc.)
                $imagePreviewControl.Tag = $decoder # Store decoder for layer switching
                $layerPanel.Visibility = 'Visible'
                $layerSelectorComboBox.Items.Clear()
                for ($i = 0; $i -lt $decoder.Frames.Count; $i++) {
                    $layerSelectorComboBox.Items.Add("Layer $i") | Out-Null
                }
                $layerSelectorComboBox.SelectedIndex = 0
                $imagePreviewControl.Source = $decoder.Frames[0]
            } else {
                # Single-frame image
                $imagePreviewControl.Source = New-Object System.Windows.Media.Imaging.BitmapImage($uri)
            }

            $imagePreviewControl.Visibility = 'Visible'
            $previewPlaceholder.Visibility = 'Collapsed'
            $batchFilePanel.Visibility = 'Collapsed'
            $developToolButton.Visibility = 'Visible'
            $previewSplitter.Visibility = 'Collapsed'
        } 
        catch {
            Write-Warning "Native WPF preview failed for '$ImagePath'. Attempting ImageMagick fallback..."
            $statusLabel.Content = "Native preview failed. Generating fallback with ImageMagick..."
            $statusLabel.Foreground = "#FFFF00" # Yellow
            $window.Dispatcher.Invoke([action]{}, "Normal") # Force UI update

            try {
                # Define a consistent path for the temporary preview file
                $tempPreviewPath = [System.IO.Path]::Combine($env:TEMP, "magickbuilder_preview.png")

                # Use Start-Process to convert the unsupported file to a temporary PNG
                $magickArgs = @($ImagePath, $tempPreviewPath)
                $process = Start-Process -FilePath "magick" -ArgumentList $magickArgs -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -ne 0) {
                    throw "ImageMagick also failed to convert the file for preview."
                }

                # If successful, load the temporary PNG, ensuring the file lock is released.
                $uri = New-Object System.Uri($tempPreviewPath)
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.UriSource = $uri
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()
                $bitmap.Freeze() # Release the file lock
                $imagePreviewControl.Source = $bitmap
                
                # Update UI to show the successful fallback preview
                $imagePreviewControl.Visibility = 'Visible'
                $previewPlaceholder.Visibility = 'Collapsed'
                $developToolButton.Visibility = 'Visible'
                $statusLabel.Content = "Showing fallback preview for '$([System.IO.Path]::GetFileName($ImagePath))'."
                $statusLabel.Foreground = $window.FindResource("AppGrayTextBrush")

            } catch {
                # This inner catch block handles the failure of the fallback itself
                $statusLabel.Content = "Could not load preview for '$([System.IO.Path]::GetFileName($ImagePath))'."
                $statusLabel.Foreground = "#FF0000" # Red
                Write-Error "Fallback preview generation failed: $_"
            }
        }
    }
}

# Script-level variable to hold files from a drag-drop operation for batch mode
$droppedFiles = [System.Collections.Generic.List[string]]::new()

# --- Dynamic UI Generation ---
Write-Host "Generating dynamic controls for Simple and Advanced modes..." -ForegroundColor Yellow

# Create arrays to hold the groupboxes for each column for balancing
$columnContents = @(
    [System.Collections.Generic.List[System.Windows.Controls.GroupBox]]::new(),
    [System.Collections.Generic.List[System.Windows.Controls.GroupBox]]::new(),
    [System.Collections.Generic.List[System.Windows.Controls.GroupBox]]::new(),
    [System.Collections.Generic.List[System.Windows.Controls.GroupBox]]::new()
)
# Create arrays to track the total number of flags in each column to determine the "shortest" column
$columnFlagCounts = @(0, 0, 0, 0)

foreach ($category in $MagickConfig) {
    # Create a container for the category
    $groupBox = New-Object System.Windows.Controls.GroupBox
    $groupBox.Header = $category.Category
    $groupBox.Foreground = $window.FindResource("AppGrayTextBrush")
    $groupBox.Margin = "0,0,0,10"
    $groupBox.Tag = $category # Tag the GroupBox with its config object for later filtering
    $groupBox.BorderBrush = $window.FindResource("ControlBorderBrush")

    # For Simple Mode, make the header invisible to just show the controls
    if ($category.Category -eq "Simple Edits") {
        $groupBox.Header = ""
        $groupBox.BorderThickness = "0"
    }

    $categoryPanel = New-Object System.Windows.Controls.StackPanel
    $categoryPanel.Margin = "5"

    foreach ($flag in $category.Flags) {
        $controlPanel = New-Object System.Windows.Controls.StackPanel
        $controlPanel.Margin = "0,5,0,5"

        $enableCheck = New-Object System.Windows.Controls.CheckBox
        $enableCheck.Content = "$($flag.Label) ($($flag.Flag))"
        $enableCheck.ToolTip = $flag.Tooltip
        $enableCheck.Add_Checked({ Update-CommandPreview }.GetNewClosure())
        $enableCheck.Add_Unchecked({ Update-CommandPreview }.GetNewClosure())
        $controlPanel.Children.Add($enableCheck) | Out-Null
        
        # Create a unique key to prevent overwrites from different categories (e.g., Simple vs. Advanced resize)
        $uniqueKey = "$($category.Category) - $($flag.Flag)"
        $dynamicControls[$uniqueKey] = [pscustomobject]@{
            'EnableControl' = $enableCheck
            'ValueControl'  = $null
            'Config'        = $flag
        }

        if ($flag.Type -eq 'range') {
            $sliderGrid = New-Object System.Windows.Controls.Grid
            $sliderGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = (New-Object System.Windows.GridLength(1, "Star")) })) | Out-Null
            $sliderGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = (New-Object System.Windows.GridLength(1, "Auto")) })) | Out-Null

            $slider = New-Object System.Windows.Controls.Slider
            $slider.Minimum = $flag.Min
            $slider.Maximum = $flag.Max
            $slider.Value = $flag.Default
            $slider.SmallChange = $flag.Step
            $slider.LargeChange = $flag.Step * 10
            $slider.IsSnapToTickEnabled = $true
            $slider.TickFrequency = $flag.Step
            $slider.IsEnabled = $false # Disabled by default
            $slider.VerticalAlignment = "Center"
            
            $valBlock = New-Object System.Windows.Controls.TextBlock
            $valBlock.Text = $flag.Default
            $valBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "AppForegroundBrush")
            $valBlock.Margin = "10,0,0,0"
            $valBlock.MinWidth = 30
            $valBlock.TextAlignment = "Right"
            $valBlock.VerticalAlignment = "Center"

            $sliderGrid.Children.Add($slider) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($slider, 0)
            $sliderGrid.Children.Add($valBlock) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($valBlock, 1)

            $slider.Add_ValueChanged({
                $senderSlider = $args[0]
                $valBlockToUpdate = $senderSlider.Parent.Children[1]
                $valBlockToUpdate.Text = [math]::Round($args[1].NewValue, 2)
                Update-CommandPreview
            }.GetNewClosure())

            $dynamicControls[$uniqueKey].ValueControl = $slider
            $controlPanel.Children.Add($sliderGrid) | Out-Null
            $enableCheck.Add_Checked({ $slider.IsEnabled = $true }.GetNewClosure())
            $enableCheck.Add_Unchecked({ $slider.IsEnabled = $false }.GetNewClosure())
        }
        elseif ($flag.Type -eq 'select') {
            $comboBox = New-Object System.Windows.Controls.ComboBox
            $flag.Options.ForEach({ [void]$comboBox.Items.Add($_) })
            $comboBox.SelectedItem = $flag.Default
            $comboBox.IsEnabled = $false # Disabled by default
            $comboBox.Add_SelectionChanged({ Update-CommandPreview }.GetNewClosure())
            $dynamicControls[$uniqueKey].ValueControl = $comboBox
            $controlPanel.Children.Add($comboBox) | Out-Null
            $enableCheck.Add_Checked({ $comboBox.IsEnabled = $true }.GetNewClosure())
            $enableCheck.Add_Unchecked({ $comboBox.IsEnabled = $false }.GetNewClosure())
        }
        elseif ($flag.Type -eq 'text') {
            $textBox = New-Object System.Windows.Controls.TextBox
            $textBox.ToolTip = $flag.Placeholder
            $textBox.IsEnabled = $false # Disabled by default

            # Placeholder Text Logic
            $placeholderText = $flag.Placeholder
            $textBox.Tag = $placeholderText # Store placeholder for later
            $normalBrush = $window.FindResource("InputTextBrush")
            $placeholderBrush = $window.FindResource("AppGrayTextBrush")

            if ([string]::IsNullOrWhiteSpace($flag.Default)) {
                $textBox.Text = $placeholderText
                $textBox.Foreground = $placeholderBrush
            } else {
                $textBox.Text = $flag.Default
            }

            $textBox.Add_GotFocus({ if ($textBox.Text -eq $textBox.Tag) { $textBox.Text = ''; $textBox.Foreground = $normalBrush } }.GetNewClosure())
            $textBox.Add_LostFocus({ if ([string]::IsNullOrWhiteSpace($textBox.Text)) { $textBox.Text = $textBox.Tag; $textBox.Foreground = $placeholderBrush } }.GetNewClosure())
            $textBox.Add_TextChanged({ Update-CommandPreview }.GetNewClosure())

            $dynamicControls[$uniqueKey].ValueControl = $textBox
            $controlPanel.Children.Add($textBox) | Out-Null
            $enableCheck.Add_Checked({ $textBox.IsEnabled = $true }.GetNewClosure())
            $enableCheck.Add_Unchecked({ $textBox.IsEnabled = $false }.GetNewClosure())
        }
        elseif ($flag.Type -eq 'color') {
            $colorButton = New-Object System.Windows.Controls.Button
            $colorButton.Height = 34
            $colorButton.IsEnabled = $false
            $colorButton.Content = $flag.Default # Store hex in content

            $colorButton.Background = Get-BrushFromHex -hex $flag.Default
            
            $bgColor = [System.Drawing.ColorTranslator]::FromHtml($flag.Default)
            $colorButton.Foreground = if ($bgColor.GetBrightness() -lt 0.5) { [System.Windows.Media.Brushes]::White } else { [System.Windows.Media.Brushes]::Black }

            $dynamicControls[$uniqueKey].ValueControl = $colorButton
            $controlPanel.Children.Add($colorButton) | Out-Null
            
            $enableCheck.Add_Checked({ $colorButton.IsEnabled = $true }.GetNewClosure())
            $enableCheck.Add_Unchecked({ $colorButton.IsEnabled = $false }.GetNewClosure())

            $colorButton.Add_Click({
                $btn = $args[0]
                $dialog = New-Object System.Windows.Forms.ColorDialog
                $dialog.Color = [System.Drawing.ColorTranslator]::FromHtml($btn.Content)
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $newColorHex = [System.Drawing.ColorTranslator]::ToHtml($dialog.Color)
                    $btn.Content = $newColorHex
                    $btn.Background = Get-BrushFromHex -hex $newColorHex
                    $btn.Foreground = if ($dialog.Color.GetBrightness() -lt 0.5) { [System.Windows.Media.Brushes]::White } else { [System.Windows.Media.Brushes]::Black }
                    Update-CommandPreview
                }
            })
        }

        # Handle environment variables (like OpenCL) directly tied to the checkbox state
        if ($flag.PSObject.Properties.Name -contains 'IsEnv' -and $flag.IsEnv) {
            $envVarName = $flag.Flag
            $enableCheck.Add_Checked({ [Environment]::SetEnvironmentVariable($envVarName, "GPU", "Process") }.GetNewClosure())
            $enableCheck.Add_Unchecked({ [Environment]::SetEnvironmentVariable($envVarName, "OFF", "Process") }.GetNewClosure())
        }

        $categoryPanel.Children.Add($controlPanel) | Out-Null
    }
    $groupBox.Content = $categoryPanel

    # Decide where to put the generated GroupBox
    if ($category.Category -eq "Simple Edits") {
        $simpleOptionsPanel.Children.Add($groupBox) | Out-Null
    } else {
        # Distribute advanced categories using a greedy algorithm to balance column heights.
        # This finds the column with the fewest flags so far and adds the new category to it.
        $shortestColumnIndex = 0
        for ($i = 1; $i -lt $columnFlagCounts.Length; $i++) {
            if ($columnFlagCounts[$i] -lt $columnFlagCounts[$shortestColumnIndex]) {
                $shortestColumnIndex = $i
            }
        }

        # Add the new groupbox to the shortest column's temporary list
        $columnContents[$shortestColumnIndex].Add($groupBox) | Out-Null
        # Update the flag count for that column
        $columnFlagCounts[$shortestColumnIndex] += $category.Flags.Count
    }
}

# After the loop, add the sorted groupboxes to the actual UI columns
for ($i = 0; $i -lt $columnContents.Length; $i++) {
    $targetColumn = $window.FindName("AdvancedColumn$($i+1)")
    foreach ($groupBox in $columnContents[$i]) {
        $targetColumn.Children.Add($groupBox) | Out-Null
    }
}

Write-Host "[OK] Dynamic controls generated." -ForegroundColor Green

# 5. Define the Logic (Event Handlers)
Write-Host "Wiring up crop tool logic..." -ForegroundColor Yellow

function Show-CropWindow {
    if (-not $imagePreviewControl.Source -or $imagePreviewControl.Visibility -ne 'Visible') {
        [System.Windows.MessageBox]::Show("Please load an image first.", "No Image", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $cropXaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Interactive Develop &amp; Crop Tool" Width="950" Height="700" WindowStartupLocation="CenterOwner" Background="{DynamicResource AppBackgroundBrush}" Foreground="{DynamicResource AppForegroundBrush}">
        <Grid Margin="10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="320"/>
            </Grid.ColumnDefinitions>
            
            <Border Grid.Column="0" BorderBrush="{DynamicResource ControlBorderBrush}" BorderThickness="1" Background="{DynamicResource AppBackgroundBrush}" Margin="0,0,10,0">
                <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">
                    <Viewbox Stretch="Uniform">
                        <Canvas x:Name="CropCanvas" Cursor="Cross" Background="Transparent">
                            <Image x:Name="CropImage" Stretch="None" />
                            <InkCanvas x:Name="DrawingCanvas" Background="Transparent" IsHitTestVisible="False" />
                            <Rectangle x:Name="CropRect" Stroke="{DynamicResource AccentBrush}" StrokeThickness="2" StrokeDashArray="4 4" Fill="{DynamicResource AccentBrush}" Opacity="0.2" Visibility="Collapsed" />
                        </Canvas>
                    </Viewbox>
                </ScrollViewer>
            </Border>

            <Border Grid.Column="1" BorderBrush="{DynamicResource ControlBorderBrush}" BorderThickness="1,0,0,0">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="0">
                        <TextBlock Text="Active Tool" FontWeight="Bold" FontSize="16" Margin="15,15,15,5" Foreground="{DynamicResource AccentBrush}"/>
                        <WrapPanel Margin="15,0,15,5">
                            <RadioButton x:Name="ToolCrop" Content="Crop" IsChecked="True" Margin="0,0,10,5" VerticalAlignment="Center" Foreground="{DynamicResource AppForegroundBrush}"/>
                            <RadioButton x:Name="ToolPen" Content="Pen" Margin="0,0,10,5" VerticalAlignment="Center" Foreground="{DynamicResource AppForegroundBrush}"/>
                            <RadioButton x:Name="ToolSelect" Content="Select" Margin="0,0,10,5" VerticalAlignment="Center" Foreground="{DynamicResource AppForegroundBrush}"/>
                            <RadioButton x:Name="ToolEraser" Content="Point Eraser" Margin="0,0,10,5" VerticalAlignment="Center" Foreground="{DynamicResource AppForegroundBrush}"/>
                            <RadioButton x:Name="ToolStrokeEraser" Content="Stroke Eraser" Margin="0,0,10,5" VerticalAlignment="Center" Foreground="{DynamicResource AppForegroundBrush}"/>
                            <Button x:Name="BtnClearDraw" Content="Clear Ink" Margin="0,0,0,5" Padding="5,2"/>
                        </WrapPanel>

                        <TextBlock Text="Crop Area" FontWeight="Bold" FontSize="16" Margin="15,15,15,5" Foreground="{DynamicResource AccentBrush}"/>
                        <TextBlock Text="Click and drag on the image to draw a crop box." TextWrapping="Wrap" Margin="15,0,15,5" Foreground="{DynamicResource AppGrayTextBrush}"/>
                        
                        <Grid Margin="15,5">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <Label Grid.Row="0" Grid.Column="0" Content="Width (W):" Foreground="{DynamicResource ControlLabelBrush}" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValW" Grid.Row="0" Grid.Column="1" Margin="5"/>
                            
                            <Label Grid.Row="1" Grid.Column="0" Content="Height (H):" Foreground="{DynamicResource ControlLabelBrush}" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValH" Grid.Row="1" Grid.Column="1" Margin="5"/>
                            
                            <Label Grid.Row="2" Grid.Column="0" Content="Offset X:" Foreground="{DynamicResource ControlLabelBrush}" VerticalAlignment="center"/>
                            <TextBox x:Name="ValX" Grid.Row="2" Grid.Column="1" Margin="5"/>
                            
                            <Label Grid.Row="3" Grid.Column="0" Content="Offset Y:" Foreground="{DynamicResource ControlLabelBrush}" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValY" Grid.Row="3" Grid.Column="1" Margin="5"/>
                        </Grid>

                        <Separator Margin="15,10" Background="{DynamicResource ControlBorderBrush}"/>

                        <TextBlock Text="Pen Settings" FontWeight="Bold" FontSize="16" Margin="15,5,15,5" Foreground="{DynamicResource AccentBrush}"/>
                        <Grid Margin="15,5">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Label Content="Color:" Foreground="{DynamicResource ControlLabelBrush}" VerticalAlignment="Center" Padding="0,0,10,0"/>
                            <Button x:Name="BtnDrawColor" Content="#FF0000" Background="Red" Foreground="White" Grid.Column="1" Height="25" BorderThickness="1"/>
                        </Grid>
                        <Grid Margin="15,5,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Size:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0"/>
                            <TextBlock x:Name="ValDrawSize" Text="5" Grid.Column="1" Foreground="{DynamicResource AppForegroundBrush}"/>
                        </Grid>
                        <Slider x:Name="SldDrawSize" Minimum="1" Maximum="100" Value="5" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Separator Margin="15,5" Background="{DynamicResource ControlBorderBrush}"/>

                        <Grid Margin="15,5,15,5">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Camera Raw Basics" FontWeight="Bold" FontSize="16" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center"/>
                            <Button x:Name="BtnUndoAdjustments" Grid.Column="1" Content="Undo" Padding="8,2" Margin="0,0,5,0" IsEnabled="False" ToolTip="Undo last adjustment"/>
                            <Button x:Name="BtnResetAdjustments" Grid.Column="2" Content="Reset" Padding="8,2" ToolTip="Reset all adjustments"/>
                        </Grid>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Exposure:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValExposure" Text="0.0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldExposure" Minimum="-5" Maximum="5" Value="0" TickFrequency="0.1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Contrast:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValContrast" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldContrast" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Highlights:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValHighlights" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldHighlights" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Shadows:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValShadows" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldShadows" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Whites:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValWhites" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldWhites" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Blacks:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValBlacks" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldBlacks" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>

                        <Separator Margin="15,5" Background="{DynamicResource ControlBorderBrush}"/>
                        <TextBlock Text="Color" FontWeight="Bold" FontSize="14" Margin="15,0,15,5" Foreground="{DynamicResource AccentBrush}"/>

                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Temperature:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValTemperature" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldTemperature" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Tint:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValTint" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldTint" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Vibrance:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValVibrance" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldVibrance" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,10"/>
                        
                        <Grid Margin="15,0,15,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <Label Content="Saturation:" Foreground="{DynamicResource ControlLabelBrush}" Padding="0" VerticalAlignment="Center"/>
                            <TextBox x:Name="ValSaturation" Text="0" Grid.Column="1" Width="45" MinHeight="24" Height="24" TextAlignment="Center" Padding="0,2" Margin="5,0,0,0"/>
                        </Grid>
                        <Slider x:Name="SldSaturation" Minimum="-100" Maximum="100" Value="0" TickFrequency="1" IsSnapToTickEnabled="True" Margin="15,5,15,15"/>

                        <Button x:Name="BtnApplyCrop" Content="Apply Settings" Margin="15,10,15,5" Padding="10" Style="{DynamicResource AccentButton}"/>
                        <Button x:Name="BtnCancelCrop" Content="Cancel" Margin="15,5,15,15" Padding="10"/>
                    </StackPanel>
                </ScrollViewer>
            </Border>
        </Grid>
    </Window>
"@
    $cropBytes = [System.Text.Encoding]::UTF8.GetBytes($cropXaml)
    $cropStream = New-Object System.IO.MemoryStream(,$cropBytes)
    $cropWindow = [System.Windows.Markup.XamlReader]::Load($cropStream)
    $cropWindow.Owner = $window
    $cropWindow.Resources = $window.Resources

    $cImage = $cropWindow.FindName("CropImage")
    $cCanvas = $cropWindow.FindName("CropCanvas")
    $cRect = $cropWindow.FindName("CropRect")
    $btnApply = $cropWindow.FindName("BtnApplyCrop")
    $btnCancel = $cropWindow.FindName("BtnCancelCrop")
    $valW = $cropWindow.FindName("ValW")
    $valH = $cropWindow.FindName("ValH")
    $valX = $cropWindow.FindName("ValX")
    $valY = $cropWindow.FindName("ValY")
    
    $DrawingCanvas = $cropWindow.FindName("DrawingCanvas")
    $ToolCrop = $cropWindow.FindName("ToolCrop")
    $ToolPen = $cropWindow.FindName("ToolPen")
    $ToolSelect = $cropWindow.FindName("ToolSelect")
    $ToolEraser = $cropWindow.FindName("ToolEraser")
    $ToolStrokeEraser = $cropWindow.FindName("ToolStrokeEraser")
    $BtnClearDraw = $cropWindow.FindName("BtnClearDraw")
    $BtnDrawColor = $cropWindow.FindName("BtnDrawColor")
    $SldDrawSize = $cropWindow.FindName("SldDrawSize")
    $ValDrawSize = $cropWindow.FindName("ValDrawSize")

    $sldExposure = $cropWindow.FindName("SldExposure"); $valExposure = $cropWindow.FindName("ValExposure")
    $sldContrast = $cropWindow.FindName("SldContrast"); $valContrast = $cropWindow.FindName("ValContrast")
    $sldHighlights = $cropWindow.FindName("SldHighlights"); $valHighlights = $cropWindow.FindName("ValHighlights")
    $sldShadows = $cropWindow.FindName("SldShadows"); $valShadows = $cropWindow.FindName("ValShadows")
    $sldWhites = $cropWindow.FindName("SldWhites"); $valWhites = $cropWindow.FindName("ValWhites")
    $sldBlacks = $cropWindow.FindName("SldBlacks"); $valBlacks = $cropWindow.FindName("ValBlacks")
    $sldTemperature = $cropWindow.FindName("SldTemperature"); $valTemperature = $cropWindow.FindName("ValTemperature")
    $sldTint = $cropWindow.FindName("SldTint"); $valTint = $cropWindow.FindName("ValTint")
    $sldVibrance = $cropWindow.FindName("SldVibrance"); $valVibrance = $cropWindow.FindName("ValVibrance")
    $sldSaturation = $cropWindow.FindName("SldSaturation"); $valSaturation = $cropWindow.FindName("ValSaturation")
    $BtnUndoAdjustments = $cropWindow.FindName("BtnUndoAdjustments")
    $BtnResetAdjustments = $cropWindow.FindName("BtnResetAdjustments")

    # Setup InkCanvas Default Properties
    $DrawingCanvas.DefaultDrawingAttributes.Color = [System.Windows.Media.Colors]::Red
    $DrawingCanvas.DefaultDrawingAttributes.Width = 5
    $DrawingCanvas.DefaultDrawingAttributes.Height = 5

    # Tool Selection Logic
    $ToolCrop.Add_Checked({ $DrawingCanvas.IsHitTestVisible = $false }.GetNewClosure())
    $ToolPen.Add_Checked({ 
        $DrawingCanvas.IsHitTestVisible = $true 
        $DrawingCanvas.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::Ink
    }.GetNewClosure())
    $ToolSelect.Add_Checked({ 
        $DrawingCanvas.IsHitTestVisible = $true 
        $DrawingCanvas.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::Select
    }.GetNewClosure())
    $ToolEraser.Add_Checked({ 
        $DrawingCanvas.IsHitTestVisible = $true 
        $DrawingCanvas.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::EraseByPoint
    }.GetNewClosure())
    $ToolStrokeEraser.Add_Checked({ 
        $DrawingCanvas.IsHitTestVisible = $true 
        $DrawingCanvas.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::EraseByStroke
    }.GetNewClosure())

    $BtnClearDraw.Add_Click({ $DrawingCanvas.Strokes.Clear() }.GetNewClosure())

    $BtnDrawColor.Add_Click({
        $dialog = New-Object System.Windows.Forms.ColorDialog
        $currentColor = $DrawingCanvas.DefaultDrawingAttributes.Color
        $dialog.Color = [System.Drawing.Color]::FromArgb($currentColor.A, $currentColor.R, $currentColor.G, $currentColor.B)
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $c = $dialog.Color
            $newColor = [System.Windows.Media.Color]::FromArgb($c.A, $c.R, $c.G, $c.B)
            $DrawingCanvas.DefaultDrawingAttributes.Color = $newColor
            $hex = [System.Drawing.ColorTranslator]::ToHtml($dialog.Color)
            $BtnDrawColor.Content = $hex
            $BtnDrawColor.Background = New-Object System.Windows.Media.SolidColorBrush($newColor)
            $BtnDrawColor.Foreground = if ($dialog.Color.GetBrightness() -lt 0.5) { [System.Windows.Media.Brushes]::White } else { [System.Windows.Media.Brushes]::Black }
        }
    }.GetNewClosure())

    $SldDrawSize.Add_ValueChanged({
        $size = [math]::Round($args[1].NewValue)
        $ValDrawSize.Text = $size
        $DrawingCanvas.DefaultDrawingAttributes.Width = $size
        $DrawingCanvas.DefaultDrawingAttributes.Height = $size
    }.GetNewClosure())

    # Setup Live Preview Mechanism
    $baseThumbPath = Join-Path $env:TEMP "magick_crop_base.bmp"
    $liveThumbPath = Join-Path $env:TEMP "magick_crop_live.bmp"
    
    # Save current image preview to disk so ImageMagick can process it
    try {
        # Safely normalize all images (including indexed/transparent) to 32-bit before saving as BMP
        $converted = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap
        $converted.BeginInit()
        $converted.Source = $imagePreviewControl.Source
        $converted.DestinationFormat = [System.Windows.Media.PixelFormats]::Bgr32
        $converted.EndInit()

        $encoder = New-Object System.Windows.Media.Imaging.BmpBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($converted))
        $fs = New-Object System.IO.FileStream($baseThumbPath, [System.IO.FileMode]::Create)
        $encoder.Save($fs)
        $fs.Close()
    } catch {
        Write-Warning "Could not save temp base image for live preview."
    }

    $previewTimer = New-Object System.Windows.Threading.DispatcherTimer
    $previewTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $previewTimer.Add_Tick({
        $previewTimer.Stop()
        if (-not (Test-Path $baseThumbPath)) { return }

        $exp = $sldExposure.Value
        $c = [int][math]::Round($sldContrast.Value)
        $h = [int][math]::Round($sldHighlights.Value)
        $sh = [int][math]::Round($sldShadows.Value)
        $w = [int][math]::Round($sldWhites.Value)
        $bl = [int][math]::Round($sldBlacks.Value)
        $temp = [int][math]::Round($sldTemperature.Value)
        $tint = [int][math]::Round($sldTint.Value)
        $vib = [int][math]::Round($sldVibrance.Value)
        $sat = [int][math]::Round($sldSaturation.Value)
        
        if ($exp -eq 0 -and $c -eq 0 -and $h -eq 0 -and $sh -eq 0 -and $w -eq 0 -and $bl -eq 0 -and $temp -eq 0 -and $tint -eq 0 -and $vib -eq 0 -and $sat -eq 0) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($baseThumbPath)
                $stream = New-Object System.IO.MemoryStream(,$bytes)
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit(); $bitmap.StreamSource = $stream; $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bitmap.EndInit(); $bitmap.Freeze()
                $cImage.Source = $bitmap
            } catch { Out-Null } # Suppress error for this specific case
            return
        }

        try {
            $image = [ImageMagick.MagickImage]::new($baseThumbPath)
            
            $image.BackgroundColor = [ImageMagick.MagickColors]::Black
            $image.Alpha([ImageMagick.AlphaOption]::Remove)
            $image.Alpha([ImageMagick.AlphaOption]::Off)

            if ($temp -ne 0 -or $tint -ne 0) {
                $r = 1.0 + ($temp / 500.0)
                $g = 1.0 - ($tint / 500.0)
                $b = 1.0 - ($temp / 500.0)
                $values = [double[]]@($r, 0, 0, 0, $g, 0, 0, 0, $b)
                $matrix = [ImageMagick.MagickColorMatrix]::new(3, $values)
                $image.ColorMatrix($matrix)
            }
            if ($exp -ne 0) {
                $factor = [math]::Pow(2, $exp)
                $image.Evaluate([ImageMagick.Channels]::RGB, [ImageMagick.EvaluateOperator]::Multiply, $factor)
            }
            if ($sh -ne 0) {
                $gammaVal = 1.0 + ($sh / 100.0)
                if ($gammaVal -le 0.05) { $gammaVal = 0.05 }
                $image.GammaCorrect($gammaVal)
            }

            $bp = $bl * 0.2; $wp = 100 - ($w * 0.2); $wp -= ($h * 0.15)
            $bp = [math]::Max(0, [math]::Min(99, $bp))
            $wp = [math]::Max(1, [math]::Min(100, $wp))
            if ($bp -ne 0 -or $wp -ne 100) {
                $image.Level([ImageMagick.Percentage]::new($bp), [ImageMagick.Percentage]::new($wp))
            }
            if ($c -ne 0) {
                $image.BrightnessContrast([ImageMagick.Percentage]::new(0), [ImageMagick.Percentage]::new($c))
            }

            $image.Clamp()

            if ($vib -ne 0 -or $sat -ne 0) {
                $totalSat = [math]::Max(0, 100 + $sat + ($vib * 0.5))
                $image.Modulate([ImageMagick.Percentage]::new(100), [ImageMagick.Percentage]::new($totalSat), [ImageMagick.Percentage]::new(100))
            }

            $ms = New-Object System.IO.MemoryStream
            $image.Format = [ImageMagick.MagickFormat]::Bmp
            $image.Write($ms)
            $image.Dispose()
            
            $ms.Position = 0
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit(); $bitmap.StreamSource = $ms; $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bitmap.EndInit(); $bitmap.Freeze()
            $cImage.Source = $bitmap
            $ms.Close(); $ms.Dispose()
        } catch {
            Write-Warning "Magick.NET Preview failed: $_"
            if ($_ -match "Unable to find type") {
                Write-Warning "Troubleshooting: The Magick.NET DLL types failed to map into this PowerShell session."
                Write-Warning "FIX: Please COMPLETELY CLOSE this PowerShell window and launch the script in a brand new console."
            }
            Write-Verbose "Exception Details:`n$($_.ScriptStackTrace)`n$($_.Exception | Out-String)"
        }
    }.GetNewClosure())

    $commonHandler = { 
        $senderCtrl = $args[0]
        $eventArgs = $args[1]
        $valBlockName = $senderCtrl.Name -replace "Sld", "Val"
        $valBlock = $cropWindow.FindName($valBlockName)
        # Only update the text box if the user isn't actively typing in it
        if (-not $valBlock.IsKeyboardFocusWithin) {
            if ($senderCtrl.Name -eq "SldExposure") { $valBlock.Text = "{0:N1}" -f $eventArgs.NewValue } 
            else { $valBlock.Text = [math]::Round($eventArgs.NewValue) }
        }
        $previewTimer.Stop(); $previewTimer.Start()
    }.GetNewClosure()

    $sldExposure.Add_ValueChanged($commonHandler)
    $sldContrast.Add_ValueChanged($commonHandler)
    $sldHighlights.Add_ValueChanged($commonHandler)
    $sldShadows.Add_ValueChanged($commonHandler)
    $sldWhites.Add_ValueChanged($commonHandler)
    $sldBlacks.Add_ValueChanged($commonHandler)
    $sldTemperature.Add_ValueChanged($commonHandler)
    $sldTint.Add_ValueChanged($commonHandler)
    $sldVibrance.Add_ValueChanged($commonHandler)
    $sldSaturation.Add_ValueChanged($commonHandler)

    $cropUndoStack = [System.Collections.Generic.List[hashtable]]::new()
    $PushCropUndoState = {
        $state = @{
            "Exposure" = $sldExposure.Value; "Contrast" = $sldContrast.Value;
            "Highlights" = $sldHighlights.Value; "Shadows" = $sldShadows.Value;
            "Whites" = $sldWhites.Value; "Blacks" = $sldBlacks.Value;
            "Temperature" = $sldTemperature.Value; "Tint" = $sldTint.Value;
            "Vibrance" = $sldVibrance.Value; "Saturation" = $sldSaturation.Value
        }
        
        # Prevent flooding the stack with identical consecutive states
        if ($cropUndoStack.Count -gt 0) {
            $last = $cropUndoStack[-1]
            $isSame = $true
            foreach ($k in $state.Keys) { if ($state[$k] -ne $last[$k]) { $isSame = $false; break } }
            if ($isSame) { return }
        }
        
        $cropUndoStack.Add($state)
        if ($cropUndoStack.Count -gt 20) { $cropUndoStack.RemoveAt(0) }
        if ($null -ne $BtnUndoAdjustments) { $BtnUndoAdjustments.IsEnabled = $true }
    }.GetNewClosure()
    
    $BtnUndoAdjustments.Add_Click({
        if ($cropUndoStack.Count -gt 0) {
            $lastState = $cropUndoStack[-1]
            $cropUndoStack.RemoveAt($cropUndoStack.Count - 1)
            $sldExposure.Value = $lastState["Exposure"]; $sldContrast.Value = $lastState["Contrast"]
            $sldHighlights.Value = $lastState["Highlights"]; $sldShadows.Value = $lastState["Shadows"]
            $sldWhites.Value = $lastState["Whites"]; $sldBlacks.Value = $lastState["Blacks"]
            $sldTemperature.Value = $lastState["Temperature"]; $sldTint.Value = $lastState["Tint"]
            $sldVibrance.Value = $lastState["Vibrance"]; $sldSaturation.Value = $lastState["Saturation"]
            if ($cropUndoStack.Count -eq 0) { $BtnUndoAdjustments.IsEnabled = $false }
        }
    }.GetNewClosure())

    $adjustmentSliders = @($sldExposure, $sldContrast, $sldHighlights, $sldShadows, $sldWhites, $sldBlacks, $sldTemperature, $sldTint, $sldVibrance, $sldSaturation)
    $BtnResetAdjustments.Add_Click({ & $PushCropUndoState; $adjustmentSliders | ForEach-Object { $_.Value = 0 } }.GetNewClosure())
    $adjustmentSliders | ForEach-Object { $_.Add_PreviewMouseLeftButtonDown({ & $PushCropUndoState }.GetNewClosure()) }

    $textBoxTextChanged = {
        $tb = $args[0]; $sliderName = $tb.Name -replace "Val", "Sld"; $sl = $cropWindow.FindName($sliderName)
        $val = 0.0
        if ([double]::TryParse($tb.Text, [ref]$val)) {
            try {
                $txt = $tb.Text -replace ',', '.'
                if ($txt -match '^-?\.?$') { return } # allow intermediate typing like "-" or "."
                $val = [double]$txt
                if ($sl.Value -ne $val) { $sl.Value = [math]::Max($sl.Minimum, [math]::Min($sl.Maximum, $val)) }
            } catch { Out-Null }
        }
    }.GetNewClosure()

    $syncTextBoxToSlider = {
        $tb = $args[0]; $sliderName = $tb.Name -replace "Val", "Sld"; $sl = $cropWindow.FindName($sliderName)
        # When losing focus or hitting enter, strictly reformat the text box
        $val = 0.0
        if ([double]::TryParse($tb.Text, [ref]$val)) {
            $tb.Text = if ($sl.Name -eq "SldExposure") { "{0:N1}" -f $sl.Value } else { [math]::Round($sl.Value) }
        } else { 
            $tb.Text = if ($sl.Name -eq "SldExposure") { "{0:N1}" -f $sl.Value } else { [math]::Round($sl.Value) } 
        }
        try {
            $txt = $tb.Text -replace ',', '.'
            $val = [double]$txt
            if ($sl.Value -ne $val) { $sl.Value = [math]::Max($sl.Minimum, [math]::Min($sl.Maximum, $val)) }
        } catch { Out-Null }
        # Strictly reformat the text box on lose focus/enter
        $tb.Text = if ($sl.Name -eq "SldExposure") { "{0:N1}" -f $sl.Value } else { [math]::Round($sl.Value) }
    }.GetNewClosure()

    $adjustmentTextBoxes = @($valExposure, $valContrast, $valHighlights, $valShadows, $valWhites, $valBlacks, $valTemperature, $valTint, $valVibrance, $valSaturation)
    $adjustmentTextBoxes | ForEach-Object {
        $tb = $_
        $tb.Add_GotFocus({ & $PushCropUndoState }.GetNewClosure())
        $tb.Add_TextChanged($textBoxTextChanged)
        $tb.Add_LostFocus($syncTextBoxToSlider)
        $tb.Add_KeyDown({ if ($args[1].Key -eq [System.Windows.Input.Key]::Enter) { & $syncTextBoxToSlider $args[0] } }.GetNewClosure())
    }

    # Load the exact same visual representation from the main UI
    $cImage.Source = $imagePreviewControl.Source
    
    # Size the canvas to exactly match the native image resolution for precise 1:1 cropping
    $cCanvas.Width = $cImage.Source.PixelWidth
    $cCanvas.Height = $cImage.Source.PixelHeight
    $DrawingCanvas.Width = $cImage.Source.PixelWidth
    $DrawingCanvas.Height = $cImage.Source.PixelHeight

    $dragState = @{ IsDragging = $false; StartX = 0; StartY = 0 }

    $cCanvas.Add_MouseLeftButtonDown({
        if ($ToolCrop.IsChecked -ne $true) { return }
        $dragState.IsDragging = $true
        $pos = $args[1].GetPosition($cCanvas)
        $dragState.StartX = $pos.X
        $dragState.StartY = $pos.Y
        [System.Windows.Controls.Canvas]::SetLeft($cRect, $pos.X)
        [System.Windows.Controls.Canvas]::SetTop($cRect, $pos.Y)
        $cRect.Width = 0; $cRect.Height = 0; $cRect.Visibility = 'Visible'
        $cCanvas.CaptureMouse()
    }.GetNewClosure())

    $cCanvas.Add_MouseMove({
        if ($ToolCrop.IsChecked -ne $true) { return }
        if ($dragState.IsDragging) {
            $pos = $args[1].GetPosition($cCanvas)
            $x = [math]::Max(0, [math]::Min([math]::Min($pos.X, $dragState.StartX), $cCanvas.Width))
            $y = [math]::Max(0, [math]::Min([math]::Min($pos.Y, $dragState.StartY), $cCanvas.Height))
            $w = [math]::Abs($pos.X - $dragState.StartX)
            $h = [math]::Abs($pos.Y - $dragState.StartY)
            if ($x + $w -gt $cCanvas.Width) { $w = $cCanvas.Width - $x }
            if ($y + $h -gt $cCanvas.Height) { $h = $cCanvas.Height - $y }
            [System.Windows.Controls.Canvas]::SetLeft($cRect, $x)
            [System.Windows.Controls.Canvas]::SetTop($cRect, $y)
            $cRect.Width = $w; $cRect.Height = $h
            $valW.Text = [math]::Round($w); $valH.Text = [math]::Round($h)
            $valX.Text = [math]::Round($x); $valY.Text = [math]::Round($y)
        }
    }.GetNewClosure())

    $cCanvas.Add_MouseLeftButtonUp({ 
        if ($ToolCrop.IsChecked -ne $true) { return }
        if ($dragState.IsDragging) { $dragState.IsDragging = $false; $cCanvas.ReleaseMouseCapture() } 
    }.GetNewClosure())
    $btnCancel.Add_Click({ $previewTimer.Stop(); $cropWindow.Close() }.GetNewClosure())
    $btnApply.Add_Click({
        $previewTimer.Stop()
        $appliedAny = $false
        
        # Apply Drawings if present
        if ($DrawingCanvas.Strokes.Count -gt 0) {
            $drawingPath = Join-Path $env:TEMP "magickbuilder_drawing.png"
            $rect = New-Object System.Windows.Rect(0, 0, $DrawingCanvas.Width, $DrawingCanvas.Height)
            $DrawingCanvas.Measure($rect.Size)
            $DrawingCanvas.Arrange($rect)
            $RenderTarget = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$DrawingCanvas.Width, [int]$DrawingCanvas.Height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
            $RenderTarget.Render($DrawingCanvas)
            $Encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $Encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($RenderTarget))
            $fs = New-Object System.IO.FileStream($drawingPath, [System.IO.FileMode]::Create)
            $Encoder.Save($fs)
            $fs.Close()
            
            $drawingPathUnix = $drawingPath -replace '\\', '/'
            $drawCmd = "image over 0,0 0,0 '$drawingPathUnix'"
            $key = "Drawing & Text - -draw"
            if ($dynamicControls.ContainsKey($key)) { 
                $ctrl = $dynamicControls[$key]; $ctrl.ValueControl.Text = $drawCmd; $ctrl.ValueControl.Foreground = $window.FindResource("InputTextBrush"); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true 
            }
        }
        
        # Apply Crop
        $w = $valW.Text; $h = $valH.Text; $x = $valX.Text; $y = $valY.Text
        if ($w -and $h -and $x -ne "" -and $y -ne "" -and [int]$w -gt 0 -and [int]$h -gt 0) {
            $cropString = "${w}x${h}+${x}+${y}"
            $targetKey = "Geometry & Sizing - -crop"
            if ($dynamicControls.ContainsKey($targetKey)) {
                $cropControl = $dynamicControls[$targetKey]
                $cropControl.ValueControl.Text = $cropString
                $cropControl.ValueControl.Foreground = $window.FindResource("InputTextBrush")
                $cropControl.EnableControl.IsChecked = $true
                $appliedAny = $true
            }
        }

        # Apply Camera Raw Basics
        $exp = $sldExposure.Value
        $c = [int][math]::Round($sldContrast.Value)
        $h = [int][math]::Round($sldHighlights.Value)
        $sh = [int][math]::Round($sldShadows.Value)
        $w = [int][math]::Round($sldWhites.Value)
        $bl = [int][math]::Round($sldBlacks.Value)
        $temp = [int][math]::Round($sldTemperature.Value)
        $tint = [int][math]::Round($sldTint.Value)
        $vib = [int][math]::Round($sldVibrance.Value)
        $sat = [int][math]::Round($sldSaturation.Value)

        if ($exp -ne 0) {
            $factor = [math]::Round([math]::Pow(2, $exp), 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $key = "Adjustments (Sliders) - -channel RGB -evaluate multiply"
            if ($dynamicControls.ContainsKey($key)) { $ctrl = $dynamicControls[$key]; $ctrl.ValueControl.Text = $factor; $ctrl.ValueControl.Foreground = $window.FindResource("InputTextBrush"); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true }
        }
        if ($temp -ne 0 -or $tint -ne 0) {
            $r = [math]::Round(1.0 + ($temp / 500.0), 3).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $g = [math]::Round(1.0 - ($tint / 500.0), 3).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $b = [math]::Round(1.0 - ($temp / 500.0), 3).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $matrix = "$r 0 0 0 $g 0 0 0 $b"
            $key = "Adjustments (Sliders) - -color-matrix"
            if ($dynamicControls.ContainsKey($key)) { $ctrl = $dynamicControls[$key]; $ctrl.ValueControl.Text = $matrix; $ctrl.ValueControl.Foreground = $window.FindResource("InputTextBrush"); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true }
        }
        if ($sh -ne 0) {
            $gammaVal = 1.0 + ($sh / 100.0)
            if ($gammaVal -le 0.05) { $gammaVal = 0.05 }
            $key = "Adjustments (Sliders) - -gamma"
            if ($dynamicControls.ContainsKey($key)) { $ctrl = $dynamicControls[$key]; $ctrl.ValueControl.Value = [math]::Round($gammaVal, 2); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true }
        }
        
        $bp = $bl * 0.2; $wp = 100 - ($w * 0.2); $wp -= ($h * 0.15)
        $bp = [math]::Max(0, [math]::Min(99, $bp))
        $wp = [math]::Max(1, [math]::Min(100, $wp))
        
        if ($bp -ne 0 -or $wp -ne 100) {
            $lvlStr = "$([int][math]::Round($bp))%,$([int][math]::Round($wp))%"
            $key = "Adjustments (Sliders) - -level"
            if ($dynamicControls.ContainsKey($key)) { $ctrl = $dynamicControls[$key]; $ctrl.ValueControl.Text = $lvlStr; $ctrl.ValueControl.Foreground = $window.FindResource("InputTextBrush"); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true }
        }

        if ($c -ne 0) {
            $bcString = "0x${c}"
            $bcKey = "Adjustments (Sliders) - -brightness-contrast"
            if ($dynamicControls.ContainsKey($bcKey)) { $ctrl = $dynamicControls[$bcKey]; $ctrl.ValueControl.Text = $bcString; $ctrl.ValueControl.Foreground = $window.FindResource("InputTextBrush"); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true }
        }

        if ($vib -ne 0 -or $sat -ne 0) {
            $totalSat = 100 + $sat + ($vib * 0.5)
            $totalSat = [math]::Max(0, $totalSat)
            $modString = "100,$([int][math]::Round($totalSat)),100"
            $modKey = "Adjustments (Sliders) - -modulate"
            if ($dynamicControls.ContainsKey($modKey)) { $ctrl = $dynamicControls[$modKey]; $ctrl.ValueControl.Text = $modString; $ctrl.ValueControl.Foreground = $window.FindResource("InputTextBrush"); $ctrl.EnableControl.IsChecked = $true; $appliedAny = $true }
        }

        if ($appliedAny) {
            if ($advancedScrollViewer.Visibility -eq 'Collapsed') { $modeToggleButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
            $statusLabel.Content = "Image adjustments applied successfully."
            $statusLabel.Foreground = "#00FF00"
            Update-CommandPreview
        }
        
        $cropWindow.Close()
    }.GetNewClosure())
    $cropWindow.WindowState = 'Maximized'
    $cropWindow.ShowDialog() | Out-Null
}

Write-Host "Wiring up event handlers..." -ForegroundColor Yellow

# --- Drag and Drop Handlers ---
$window.Add_DragEnter({
    param($sender, $e)
    # Check if the dragged data is a file drop
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
    }
    else {
        $e.Effects = [System.Windows.DragDropEffects]::None
    }
    $e.Handled = $true
})

$window.Add_Drop({
    param($sender, $e)
    $droppedFilePaths = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
    $validExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif', '.webp') # Define valid extensions
    
    $newlyFoundFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $droppedFilePaths) {
        if (Test-Path -Path $path -PathType Container) {
            # It's a directory, so recursively find all valid image files.
            try {
                Get-ChildItem -Path $path -Recurse -File | Where-Object { $validExtensions -contains $_.Extension.ToLower() } | ForEach-Object { $newlyFoundFiles.Add($_.FullName) }
            } catch {
                Write-Warning "Could not access folder or files in '$path'. Error: $_"
            }
        }
        else {
            # It's a file.
            if ($validExtensions -contains ([System.IO.Path]::GetExtension($path).ToLower())) {
                $newlyFoundFiles.Add($path)
            }
        }
    }

    if ($newlyFoundFiles.Count -eq 0) {
        $statusLabel.Content = "Drop operation found no valid image files."
        $statusLabel.Foreground = "#FF0000" # Red
        return
    }

    # Add newly found files to the main list, avoiding duplicates.
    $filesAdded = 0
    foreach ($file in $newlyFoundFiles) {
        if (-not $droppedFiles.Contains($file)) {
            $droppedFiles.Add($file)
            $filesAdded++
        }
    }

    if ($droppedFiles.Count -eq 1) {
        # Single file drop
        $inputFileBox.Text = $droppedFiles[0]
        Update-ImagePreview -ImagePath $droppedFiles[0]
        
        $dir = [System.IO.Path]::GetDirectoryName($droppedFiles[0])
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($droppedFiles[0])
        $ext = [System.IO.Path]::GetExtension($droppedFiles[0])

        $outputFileBox.Text = [System.IO.Path]::Combine($dir, "${baseName}_converted.png")
        $statusLabel.Content = "Loaded single image: $([System.IO.Path]::GetFileName($droppedFiles[0]))"
        $statusLabel.Foreground = $window.FindResource("AppGrayTextBrush")
    }
    else {
        # Multiple files dropped (batch mode)
        # Morph the preview panel into a file list
        # If it's the first time entering batch mode, show the image preview for the first file.
        if ($batchFilePanel.Visibility -ne 'Visible') { Update-ImagePreview -ImagePath $droppedFiles[0] }
        $batchFilePanel.Visibility = 'Visible'
        $previewSplitter.Visibility = 'Visible'
        $previewFileListBox.Items.Clear()
        $droppedFiles | ForEach-Object { [void]$previewFileListBox.Items.Add(([System.IO.Path]::GetFileName($_))) }

        $firstFileDir = [System.IO.Path]::GetDirectoryName($droppedFiles[0])
        $outputDir = [System.IO.Path]::Combine($firstFileDir, "output")

        $inputFileBox.Text = "$($droppedFiles.Count) files ready for batch processing"
        $inputFileBox.IsEnabled = $false # Disable manual editing in batch mode

        $outputFileBox.Text = $outputDir
        $outputFileBox.ToolTip = "Output directory for batch conversion. Will be created if it doesn't exist."

        if ($filesAdded -gt 0) {
            $statusLabel.Content = "Added $filesAdded file(s). Total in batch: $($droppedFiles.Count)."
        } else {
            $statusLabel.Content = "Batch mode active with $($droppedFiles.Count) images. No new unique files were added."
        }
        $statusLabel.Foreground = $window.FindResource("AppGrayTextBrush")
    }
})

# --- Clear Batch Button ---
$clearBatchButton.Add_Click({
    # Clear the internal list of files
    $droppedFiles.Clear()

    # Reset the UI to its initial state
    $batchFilePanel.Visibility = 'Collapsed'
    $previewSplitter.Visibility = 'Collapsed'
    $imagePreviewControl.Visibility = 'Collapsed'
    $developToolButton.Visibility = 'Collapsed'
    $previewPlaceholder.Visibility = 'Visible'
    $layerPanel.Visibility = 'Collapsed'
    $inputFileBox.IsEnabled = $true
    $inputFileBox.Text = "input.jpg"
    $outputFileBox.Text = "output.png"
    $statusLabel.Content = "Ready. Batch cleared."
    $statusLabel.Foreground = $window.FindResource("AppGrayTextBrush")
})

# --- Mode Toggle Button ---
$modeToggleButton.Add_Click({
    if ($advancedScrollViewer.Visibility -eq 'Collapsed') {
        # Switching to Advanced Mode
        $advancedScrollViewer.Visibility = 'Visible'
        $simpleScrollViewer.Visibility = 'Collapsed'
        $modeToggleButton.Content = 'Simple Mode'
        Update-FormatComboBox -Mode 'advanced'
        $window.Height = 750 # Expand window
    }
    else {
        # Switching to Simple Mode
        $advancedScrollViewer.Visibility = 'Collapsed'
        $simpleScrollViewer.Visibility = 'Visible'
        $modeToggleButton.Content = 'Advanced Mode'
        Update-FormatComboBox -Mode 'simple'
        $window.SizeToContent = 'Height' # Shrink window
    }
})

# --- Browse Button Handlers ---
$browseInputButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select Input Image"
    $dialog.Filter = "Image Files (*.jpg, *.png, *.tif, *.webp)|*.jpg;*.jpeg;*.png;*.tif;*.tiff;*.webp|All files (*.*)|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # If we were in batch mode, reset everything
        $droppedFiles.Clear()
        $batchFilePanel.Visibility = 'Collapsed'
        $previewSplitter.Visibility = 'Collapsed'
        $developToolButton.Visibility = 'Collapsed'
        $layerPanel.Visibility = 'Collapsed'
        $inputFileBox.IsEnabled = $true

        Update-ImagePreview -ImagePath $dialog.FileName
        $inputFileBox.Text = $dialog.FileName
        # Auto-suggest an output name
        $dir = [System.IO.Path]::GetDirectoryName($dialog.FileName)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
        $outputFileBox.Text = [System.IO.Path]::Combine($dir, "${baseName}_converted.png")
    }
})

$browseOutputButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = "Save Output Image As"
    $dialog.Filter = "PNG Image (*.png)|*.png|JPEG Image (*.jpg)|*.jpg|WebP Image (*.webp)|*.webp|TIFF Image (*.tif)|*.tif|All files (*.*)|*.*"
    $dialog.FileName = $outputFileBox.Text # Pre-populate with current value
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # Update the format dropdown to match the chosen file extension
        $newExt = [System.IO.Path]::GetExtension($dialog.FileName).TrimStart('.').ToUpper()
        if ($outputFormatComboBox.Items -contains $newExt) {
            $outputFormatComboBox.SelectedItem = $newExt
        }

        $outputFileBox.Text = $dialog.FileName
    }
})

# --- Context Menu & Develop Button Handlers ---
$menuDevelopImage.Add_Click({
    Show-CropWindow
})

$developToolButton.Add_Click({
    Show-CropWindow
})

# --- Title Bar and Window Control Logic ---
$titleBar.Add_MouseLeftButtonDown({
    $window.DragMove()
})

$closeButton.Add_Click({
    $window.Close()
})

$minimizeButton.Add_Click({
    $window.WindowState = 'Minimized'
})

$maximizeButton.Add_Click({
    if ($window.WindowState -eq 'Maximized') {
        $window.WindowState = 'Normal'
    } else {
        $window.WindowState = 'Maximized'
    }
})

# --- Main Window Live Preview Logic ---
$livePreviewButton.Add_Click({
    if (-not $imagePreviewControl.Source -or $imagePreviewControl.Visibility -ne 'Visible') {
        [System.Windows.MessageBox]::Show("Please load an image first to test the settings.", "No Image", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $testInput = $inputFileBox.Text
    if ($droppedFiles.Count -gt 0) { $testInput = $droppedFiles[0] }

    # Accommodate for specific layer selection
    if ($imagePreviewControl.Tag -is [System.Windows.Media.Imaging.BitmapDecoder] -and $layerSelectorComboBox.SelectedIndex -ge 0) {
        $testInput = "$testInput`[$($layerSelectorComboBox.SelectedIndex)]"
    }

    $statusLabel.Content = "Generating preview..."
    $statusLabel.Foreground = "#FFFF00"
    $window.Dispatcher.Invoke([action]{}, "Normal")

    $previewTemp = Join-Path $env:TEMP "magickbuilder_test_preview.png"
    
    $commonArgs = Get-CommonArguments
    $mArgs = @($testInput)
    $mArgs += $commonArgs
    $mArgs += $previewTemp

    try {
        # Clean up any leftover preview frames from operations like crop
        Get-Item (Join-Path $env:TEMP "magickbuilder_test_preview*.png") -ErrorAction SilentlyContinue | Remove-Item -Force
        
        $proc = Start-Process "magick" -ArgumentList $mArgs -Wait -PassThru -WindowStyle Hidden
        
        # Commands like -crop can generate multiple outputs (e.g. preview-0.png, preview-1.png). Target the first frame.
        $finalPreviewPath = $previewTemp
        if (-not (Test-Path $finalPreviewPath)) { $finalPreviewPath = Join-Path $env:TEMP "magickbuilder_test_preview-0.png" }

        if ($proc.ExitCode -eq 0 -and (Test-Path $finalPreviewPath)) {
            $bytes = [System.IO.File]::ReadAllBytes($finalPreviewPath)
            $stream = New-Object System.IO.MemoryStream(,$bytes)
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit(); $bitmap.StreamSource = $stream; $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bitmap.EndInit(); $bitmap.Freeze()
            $imagePreviewControl.Source = $bitmap
            
            $resetPreviewButton.Visibility = 'Visible'
            $statusLabel.Content = "Test preview applied successfully!"
            $statusLabel.Foreground = "#00FF00"
        } else {
            throw "ImageMagick process failed or returned no output. Check arguments."
        }
    } catch {
        $statusLabel.Content = "Preview failed: $_"
        $statusLabel.Foreground = "#FF0000"
    }
})

$resetPreviewButton.Add_Click({
    $src = $inputFileBox.Text
    if ($droppedFiles.Count -gt 0) { $src = $droppedFiles[0] }
    if (Test-Path $src) { Update-ImagePreview -ImagePath $src; $statusLabel.Content = "Preview reset to original."; $statusLabel.Foreground = $window.FindResource("AppGrayTextBrush") }
})

# --- Convert Button ---
$convertButton.Add_Click({
    # --- BATCH PROCESSING LOGIC ---
    if ($droppedFiles.Count -gt 0) {
        $outputDir = $outputFileBox.Text
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $totalFiles = $droppedFiles.Count
        $processedCount = 0
        $hasError = $false

        foreach ($file in $droppedFiles) {
            $processedCount++
            $statusLabel.Content = "Processing $processedCount of ${totalFiles}: $([System.IO.Path]::GetFileName($file))"
            $statusLabel.Foreground = "#FFFF00" # Yellow
            $window.Dispatcher.Invoke([action]{}, "Normal") # Force UI update

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $selectedFormat = $outputFormatComboBox.SelectedItem.ToString().ToLower()
            $outputFilePath = [System.IO.Path]::Combine($outputDir, "${baseName}_converted.$selectedFormat")

            # Manually build the command string with explicit quotes around file paths for maximum reliability.
            $commonArgs = Get-CommonArguments
            $magickArgs = @($file) + $commonArgs + @($outputFilePath)

            try {
                $stdErrFile = Join-Path $env:TEMP "magick_batch_convert_err.txt"
                if (Test-Path $stdErrFile) { Remove-Item $stdErrFile -Force }

                $process = Start-Process -FilePath "magick" -ArgumentList $magickArgs -Wait -PassThru -NoNewWindow -RedirectStandardError $stdErrFile

                if ($process.ExitCode -ne 0) {
                    $errorOutput = if (Test-Path $stdErrFile) { Get-Content $stdErrFile -Raw } else { "Unknown error" }
                    throw $errorOutput
                }

                if (-not (Test-Path $outputFilePath) -or (Get-Item $outputFilePath).Length -eq 0) {
                    throw "Conversion process succeeded, but the output file was not created or is empty."
                }
            }
            catch {
                $errorMessage = "ERROR on file '$([System.IO.Path]::GetFileName($file))': $_"
                $statusLabel.Content = $errorMessage
                $statusLabel.Foreground = "#FF0000" # Red
                [System.Windows.MessageBox]::Show($errorMessage, "Batch Conversion Failed", "OK", "Error") | Out-Null
                $hasError = $true
                break # Stop batch on first error
            }
        }

        if (-not $hasError) {
            $statusLabel.Content = "Batch conversion of $totalFiles files completed successfully!"
            $statusLabel.Foreground = "#00FF00" # Green
        }
        # Reset for next operation
        $droppedFiles.Clear()
        $inputFileBox.IsEnabled = $true
    }
    # --- SINGLE FILE PROCESSING LOGIC ---
    else {
        # Resolve paths to absolute to ensure magick.exe can find them regardless of working directory
        $inputFile = [System.IO.Path]::GetFullPath($inputFileBox.Text)
        $outputFile = [System.IO.Path]::GetFullPath($outputFileBox.Text)

        # Check if we are processing a specific layer from a multi-frame image
        if ($imagePreviewControl.Tag -is [System.Windows.Media.Imaging.BitmapDecoder] -and $layerSelectorComboBox.SelectedIndex -ge 0) {
            $inputFile = "$inputFile`[$($layerSelectorComboBox.SelectedIndex)]"
        }
        
        # Manually build the command string with explicit quotes around file paths for maximum reliability.
        $commonArgs = Get-CommonArguments
        $magickArgs = @($inputFile) + $commonArgs + @($outputFile)

        $statusLabel.Content = "Executing conversion..."
        $statusLabel.Foreground = "#FFFF00" # Yellow
        $window.Dispatcher.Invoke([action]{}, "Normal") # Force UI update

        try {
            $stdErrFile = Join-Path $env:TEMP "magick_convert_err.txt"
            if (Test-Path $stdErrFile) { Remove-Item $stdErrFile -Force }

            $process = Start-Process -FilePath "magick" -ArgumentList $magickArgs -Wait -PassThru -NoNewWindow -RedirectStandardError $stdErrFile
            
            if ($process.ExitCode -ne 0) {
                $errorOutput = if (Test-Path $stdErrFile) { Get-Content $stdErrFile -Raw } else { "Unknown error" }
                throw $errorOutput
            }

            if (-not (Test-Path $outputFile) -or (Get-Item $outputFile).Length -eq 0) {
                throw "Conversion process succeeded, but the output file was not created or is empty."
            }
            $statusLabel.Content = "Conversion successful! Output: $outputFile"
            $statusLabel.Foreground = "#00FF00" # Green
        }
        catch {
            $errorMessage = "ERROR: $_"
            $statusLabel.Content = $errorMessage
            $statusLabel.Foreground = "#FF0000" # Red
            [System.Windows.MessageBox]::Show($errorMessage, "Conversion Failed", "OK", "Error") | Out-Null
        }
    }
})

Write-Host "[OK] Event handlers wired up." -ForegroundColor Green

# Helper function to update the format combo box based on the selected mode
function Update-FormatComboBox {
    param([string]$Mode = 'simple') # Default to simple mode

    $currentSelection = $outputFormatComboBox.SelectedItem
    $outputFormatComboBox.Items.Clear()

    $formatsToShow = if ($Mode -eq 'advanced') { $script:advancedFormats } else { $script:simpleFormats }
    
    foreach ($format in $formatsToShow) {
        $outputFormatComboBox.Items.Add($format) | Out-Null
    }

    # Try to restore the previous selection if it exists in the new list
    if ($currentSelection -and ($formatsToShow -contains $currentSelection.ToString())) {
        $outputFormatComboBox.SelectedItem = $currentSelection
    } else {
        # Default to PNG if the old selection isn't in the new list or if nothing was selected
        $outputFormatComboBox.SelectedItem = "PNG"
    }
}

# Initialize UI states
Update-FormatComboBox -Mode 'simple'
$outputFormatComboBox.Add_SelectionChanged({ Update-ControlsForFormat })
Update-ControlsForFormat # Initial call to set visibility
$layerSelectorComboBox.Add_SelectionChanged({
    # When a new layer is selected, update the preview image
    if ($imagePreviewControl.Tag -is [System.Windows.Media.Imaging.BitmapDecoder] -and $layerSelectorComboBox.SelectedIndex -ge 0) {
        $decoder = $imagePreviewControl.Tag
        $imagePreviewControl.Source = $decoder.Frames[$layerSelectorComboBox.SelectedIndex]
    }
        Update-CommandPreview
})

$inputFileBox.Add_TextChanged({ Update-CommandPreview })
$outputFileBox.Add_TextChanged({ Update-CommandPreview })

Update-CommandPreview # Initial run to populate the box

# 6. Run the Show
Write-Host "Launching application window..." -ForegroundColor Cyan
$window.ShowDialog() | Out-Null
