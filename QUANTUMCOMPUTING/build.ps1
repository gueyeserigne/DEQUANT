param([string]$TexFile)
$root = "i:\Mon Drive\Quantum Internship - May-June 2026 - LIA Avignon\QUANTUMCOMPUTING"
Set-Location $root
$outDir = Split-Path $TexFile -Parent
$relTex = $TexFile.Replace($root + "\", "")
$relOut = $outDir.Replace($root + "\", "")
lualatex -interaction=nonstopmode -output-directory="$relOut" "$relTex"
lualatex -interaction=nonstopmode -output-directory="$relOut" "$relTex"
