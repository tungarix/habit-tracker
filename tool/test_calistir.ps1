# Testleri dosya dosya (her biri ayri flutter_tester sureci) calistirir.
#
# Neden: bu Windows makinesinde flutter_tester motoru rastgele 0xC0000005 ile cokuyor
# (Flutter motor hatasi, kod suclu degil). Cokme imzasi olan dosya en fazla 3 kez yeniden denenir;
# GERCEK test hatasi (expect/istisna; cokme imzasi yoksa) ASLA yeniden denenmez.
# Kullanim: pwsh tool/test_calistir.ps1 [test/dosya_test.dart | test/klasor]
param([string]$Yol = 'test', [int]$Deneme = 3)

$hedef = Join-Path "$PSScriptRoot\.." $Yol
$dosyalar = if (Test-Path $hedef -PathType Leaf) { Get-Item $hedef }
            else { Get-ChildItem -Path $hedef -Filter '*_test.dart' -Recurse | Sort-Object FullName }
$kok = (Resolve-Path "$PSScriptRoot\..").Path
$gecen = 0; $tekrar = @(); $basarisiz = @()
foreach ($d in $dosyalar) {
    $goreli = $d.FullName.Substring($kok.Length + 1).Replace('\', '/')
    $tamam = $false
    for ($i = 1; $i -le $Deneme -and -not $tamam; $i++) {
        $cikti = flutter test $goreli 2>&1 | Out-String
        if ($cikti -match 'All tests passed!|All tests skipped\.') {
            $tamam = $true; $gecen++
            if ($i -gt 1) { $tekrar += "$goreli ($i. deneme)" }
            Write-Host "OK   $goreli"
        } else {
            $cokme = ($cikti -match 'did not complete|No tests were found|Connection closed before test suite loaded') -and
                     -not ($cikti -match 'EXCEPTION CAUGHT|Expected:|Actual:|TestFailure|Bad state')
            if (-not $cokme) { Write-Host $cikti; break }
        }
    }
    if (-not $tamam) { Write-Host "FAIL $goreli"; $basarisiz += $goreli }
}
Write-Host "OZET: $gecen/$(@($dosyalar).Count) dosya gecti. Yeniden denenen: $(if ($tekrar) { $tekrar -join ', ' } else { 'yok' }). Basarisiz: $(if ($basarisiz) { $basarisiz -join ', ' } else { 'yok' })"
if ($basarisiz.Count -gt 0) { exit 1 }
