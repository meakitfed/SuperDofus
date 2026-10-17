# Suite complete decoupee en lots : un processus Godot par lot (pas de fuite d'etat, un echec n'attend pas 30 min).
#   powershell -File tools/test_all.ps1                 # tout, lots de 12 fichiers
#   powershell -File tools/test_all.ps1 -Tier fast      # contrats de sorts + cas + scenarios (moins de 5 min)
#   powershell -File tools/test_all.ps1 -BatchSize 6 -Godot "C:\chemin\godot_console.exe"
# Code de sortie 1 si un lot echoue (y compris erreur de parse ou baisse du nombre de tests, voir tests/baseline.json).
param(
	[ValidateSet("full", "fast")] [string]$Tier = "full",
	[int]$BatchSize = 12,
	[string]$Godot = "C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe"
)
$root = Split-Path -Parent $PSScriptRoot
$game = Join-Path $root "game"
$files = Get-ChildItem (Join-Path $game "tests") -Filter "test_*.gd" | Where-Object { $_.Name -ne "test_case.gd" } | Sort-Object Name | ForEach-Object { $_.Name }
if ($Tier -eq "fast") {
	$env:TEST_TIER = "fast"
	& $Godot --headless --path $game -s res://tests/run_tests.gd | Select-String -CaseSensitive "    FAIL|tests, "
	$code = $LASTEXITCODE
	Remove-Item Env:TEST_TIER
	exit $code
}
$failed = @()
$started = Get-Date
for ($i = 0; $i -lt $files.Count; $i += $BatchSize) {
	$batch = $files[$i..([Math]::Min($i + $BatchSize, $files.Count) - 1)]
	$env:TEST_ONLY = ($batch -join ",")   # ".gd" in each name makes the substring match exact
	$log = Join-Path $env:TEMP ("sd_tests_{0}.log" -f $i)
	& $Godot --headless --path $game -s res://tests/run_tests.gd *> $log
	$code = $LASTEXITCODE
	$summary = (Select-String -Path $log -Pattern "^\d+ tests, \d+ failures" | Select-Object -Last 1).Line
	"lot {0}-{1} : {2} (code {3})" -f $i, ($i + $batch.Count - 1), $summary, $code
	if ($code -ne 0) {
		$failed += $batch
		Select-String -Path $log -CaseSensitive "    FAIL|ECHEC" | ForEach-Object { "  " + $_.Line }
	}
}
Remove-Item Env:TEST_ONLY -ErrorAction SilentlyContinue
"Duree : {0:N0} s" -f ((Get-Date) - $started).TotalSeconds
if ($failed.Count -gt 0) { "Lots en echec : " + ($failed -join ", "); exit 1 }
"Tout est vert."
exit 0
