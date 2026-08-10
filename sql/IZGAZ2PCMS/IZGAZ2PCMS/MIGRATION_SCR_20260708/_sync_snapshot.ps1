#Requires -Version 5.1
<#
  MIGRATION_SCR_20260708 yenileme (COPY only — kaynaklari kesmez/tasimaz).
  Repo yuzeyi = 195: C:\www\MIGRATION_SCR_20260708\{CTAS,ENERGY,REPORT}

  Kullanim: pwsh -File sql\IZGAZ2PCMS\IZGAZ2PCMS\MIGRATION_SCR_20260708\_sync_snapshot.ps1

  Kaynak kokleri:
    - prodEnergy  -> paket koku (IZGAZ2PCMS/IZGAZ2PCMS)
    - oracleCTAS* / ProdIzgazMgr2Energy -> BACKUP/
#>
$ErrorActionPreference = 'Stop'
$Snap = $PSScriptRoot
$PkgRoot = Split-Path $Snap -Parent
$BackupRoot = Join-Path $PkgRoot 'BACKUP'
if (-not (Test-Path (Join-Path $PkgRoot 'prodEnergy')) -or -not (Test-Path (Join-Path $BackupRoot 'oracleCTAS3007'))) {
    $PkgRoot = 'c:\Users\HW5536\source\repos\Migratorv0\sql\IZGAZ2PCMS\IZGAZ2PCMS'
    $BackupRoot = Join-Path $PkgRoot 'BACKUP'
    $Snap = Join-Path $PkgRoot 'MIGRATION_SCR_20260708'
}
# CTAS/Mgr kaynaklari icin $Base = BACKUP
$Base = $BackupRoot
$CtasDir = Join-Path $Snap 'CTAS'
$EnergyDir = Join-Path $Snap 'ENERGY'
$ReportDir = Join-Path $Snap 'REPORT'
$Today = Get-Date -Format 'yyyy-MM-dd'

function Resolve-Src([string]$Rel) {
    $relWin = $Rel -replace '/', '\'
    foreach ($root in @($PkgRoot, $BackupRoot)) {
        $p = Join-Path $root $relWin
        if (Test-Path -LiteralPath $p) { return (Get-Item -LiteralPath $p) }
    }
    throw "Kaynak yok: $Rel (PkgRoot/BackupRoot)"
}

function Resolve-SrcPath([string]$Rel) {
    return (Resolve-Src $Rel).FullName
}

function Copy-SnapFile([string]$SrcRel, [string]$DestPath) {
    $src = Resolve-Src $SrcRel
    $destDir = Split-Path $DestPath -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
    Copy-Item -LiteralPath $src.FullName -Destination $DestPath -Force
    return $src
}

function Parse-Manifest([string]$Path) {
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        if ($line -match '^(\S+)\s+<=\s+(\S+)') {
            [PSCustomObject]@{ Dest = $Matches[1]; Src = $Matches[2]; Raw = $line }
        }
    }
}

function Next-NNN([string]$Dir, [int]$From = 1) {
    $max = $From - 1
    Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^(\d{3})_') {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return $max + 1
}

function To-SnapName([string]$SrcFileName) {
    $leaf = Split-Path $SrcFileName -Leaf
    return ($leaf.ToUpperInvariant())
}

# ---------- CTAS: manifest + ayni ad → daha yeni (3007 vs prodREADY) ----------
New-Item -ItemType Directory -Path $CtasDir -Force | Out-Null
$ctasManifestPath = Join-Path $Snap 'MANIFEST_CTAS.txt'
$ctasEntries = @(Parse-Manifest $ctasManifestPath)
$ctasNewLines = New-Object System.Collections.Generic.List[string]
$ctasNewLines.Add("# Yenilendi: $Today") | Out-Null

foreach ($e in $ctasEntries) {
    $srcRel = $e.Src
    if ($srcRel -eq '(generated)' -or $e.Dest -match '^000_RUN_ORDER') { continue }
    $leaf = Split-Path $srcRel -Leaf
    # Overlap: oracleCTAS3007 vs prodREADY — daha yeni kazansin (manifest EXTRA haric)
    # PIN: kritik O30 her zaman 3007 (ACTION_DATE<=PAY kaldirildi; prodREADY eski filtreyi geri getirmesin)
    $pin3007 = @('30_ls_tahsilat_overlay.sql', '41_gate_tahsilat.sql')
    $isExtra = $e.Raw -match 'EXTRA_PRODREADY|DOC|ORCH|PILOT|OPSIYONEL'
    $c7 = Join-Path $Base "oracleCTAS3007\$leaf"
    $pr = Join-Path $Base "oracleCTAS\prodREADY\$leaf"
    if ($pin3007 -contains $leaf -and (Test-Path $c7)) {
        $srcRel = "oracleCTAS3007/$leaf"
    } elseif (-not $isExtra -and (Test-Path $c7) -and (Test-Path $pr) -and ($srcRel -match 'oracleCTAS')) {
        $i7 = Get-Item $c7
        $ipr = Get-Item $pr
        if ($ipr.LastWriteTime -gt $i7.LastWriteTime) {
            $srcRel = "oracleCTAS/prodREADY/$leaf"
        } else {
            $srcRel = "oracleCTAS3007/$leaf"
        }
    }
    $dest = Join-Path $CtasDir $e.Dest
    Copy-SnapFile $srcRel $dest | Out-Null
    $note = ''
    if ($e.Raw -match '#\s*(.+)$') { $note = '  # ' + $Matches[1].Trim() }
    $ctasNewLines.Add("$($e.Dest) <= $srcRel$note") | Out-Null
}

# CTAS eksikler (3007-only onemli)
$ctasExtras = @(
    @{ Src = 'oracleCTAS/LS_PROJECT.sql'; Pref = 26 },
    @{ Src = 'oracleCTAS/LS_PROJECTLINE.sql'; Pref = 27 },
    @{ Src = 'oracleCTAS3007/LS_HHD_MSTR_DIAG.sql'; Pref = 80 },
    @{ Src = 'oracleCTAS3007/VERIFY_SYNTH_GAP.sql'; Pref = 81 },
    @{ Src = 'oracleCTAS3007/PILOT_FINDINGS.md'; Pref = 82 },
    @{ Src = 'oracleCTAS3007/README.md'; Pref = 83 }  # 3007 README (075 prodREADY README ayri)
)
$existingCtasSrc = @{}
foreach ($e in $ctasEntries) { $existingCtasSrc[(Split-Path $e.Src -Leaf).ToUpperInvariant()] = $true }
# also track dest leaves
foreach ($line in $ctasNewLines) {
    if ($line -match '<=\s+(\S+)') {
        $existingCtasSrc[(Split-Path $Matches[1] -Leaf).ToUpperInvariant()] = $true
    }
}
$nnn = Next-NNN $CtasDir 80
foreach ($x in $ctasExtras) {
    $leafU = (Split-Path $x.Src -Leaf).ToUpperInvariant()
    if ($existingCtasSrc.ContainsKey($leafU)) { continue }
    if (-not (Test-Path (Join-Path $Base ($x.Src -replace '/', '\')))) { continue }
    $destName = ('{0:D3}_{1}' -f $nnn, (To-SnapName $x.Src))
    Copy-SnapFile $x.Src (Join-Path $CtasDir $destName) | Out-Null
    $ctasNewLines.Add("$destName <= $($x.Src)  # EXTRA_3007") | Out-Null
    $nnn++
}

# 000_RUN_ORDER.MD regenerate light
$runOrder = @"
# 20260708/CTAS — CALISTIRMA SIRASI (yenilendi $Today)

Kaynak: oracleCTAS3007 omurga + oracleCTAS/prodREADY (ayni ad varsa daha yeni kazanan).
Bu klasor KOPYA arsiv + kosulabilir orchestrator.

| Faz | NNN | Ne |
|-----|-----|----|
| DOC | 000_* | INDEX / SCHEMA / DUMP / CATALOG |
| A | 001–027 | Master CTAS (+ LS_PROJECT / LS_PROJECTLINE) |
| B | 030–060 | Tahsilat / overlay / gate |
| B-opt | 033 / 061 | pilot param / STG cleanup |
| EXTRA | 070+ | prodREADY-only / 3007-extra diag |
| ORCH | 00_RUN_ALL / 090 | tek FULL orchestrator |

## ORCH — bastan FULL

```text
cd ...\20260708\CTAS
sqlplus user/pass@db @00_RUN_ALL.SQL
```

Sira: SESSION → master A01–A19 → O09/READING/HHD → KFACTOR/SPEFEE → O10–O60 → IX → log
MIG_CTAS_LOG: cnt / MB / start / end / sec

Detay: ../MANIFEST_CTAS.txt · SCHEMA: 000_SCHEMA_CTAS_ORDER.MD
"@
$runOrderPath = Join-Path $CtasDir '000_RUN_ORDER.MD'
Set-Content -LiteralPath $runOrderPath -Value $runOrder -Encoding UTF8
# keep 000_RUN_ORDER in manifest first
$ctasFinal = New-Object System.Collections.Generic.List[string]
$ctasFinal.Add('000_RUN_ORDER.MD <= (generated)  # DOC') | Out-Null
foreach ($l in $ctasNewLines) {
    if ($l -match '^# Yenilendi') { continue }
    if ($l -match '^000_RUN_ORDER') { continue }
    $ctasFinal.Add($l) | Out-Null
}
$ctasFinal | Set-Content -LiteralPath $ctasManifestPath -Encoding UTF8

# CTAS snapshot orchestrator: numarali @@ adlari
$leafToDest = @{}
foreach ($l in $ctasFinal) {
    if ($l -match '^(\S+)\s+<=\s+(\S+)') {
        $d = $Matches[1]; $s = $Matches[2]
        if ($s -eq '(generated)') { continue }
        $leafToDest[(Split-Path ($s -replace '/', '\') -Leaf).ToUpperInvariant()] = $d
    }
}

function Rewrite-CtasRefs([string]$body) {
    return [regex]::Replace($body, '@@([^\s\r\n]+)', {
        param($m)
        $ref = $m.Groups[1].Value
        if ($ref.StartsWith('&')) { return $m.Value }
        $leaf = (Split-Path ($ref -replace '/', '\') -Leaf).ToUpperInvariant()
        if ($leafToDest.ContainsKey($leaf)) { return '@@' + $leafToDest[$leaf] }
        return $m.Value
    })
}

$srcRunAll = Join-Path $Base 'oracleCTAS3007\00_run_all.sql'
if (Test-Path -LiteralPath $srcRunAll) {
    $runBody = Rewrite-CtasRefs (Get-Content -LiteralPath $srcRunAll -Raw -Encoding UTF8)
    $runBody = $runBody -replace 'oracleCTAS3007 FULL RUN', 'CTAS 20260708 FULL RUN'
    $runBody = $runBody -replace '^-- oracleCTAS3007 / 00_run_all.sql', '-- 20260708/CTAS / 00_RUN_ALL.SQL (FULL)'
    $runAllSnap = Join-Path $CtasDir '00_RUN_ALL.SQL'
    Set-Content -LiteralPath $runAllSnap -Value $runBody -Encoding UTF8
    Copy-Item -LiteralPath $runAllSnap -Destination (Join-Path $CtasDir '090_00_RUN_ALL.SQL') -Force
    Write-Host "CTAS orchestrator: 00_RUN_ALL.SQL (+ 090_00_RUN_ALL.SQL)"
}

# Eski resume/noop/full/steps artiklari temizle
@(
    '00_ctas_noop.sql','00_CTAS_NOOP.SQL','00_RUN_ALL_FULL.SQL','00_RUN_ALL_STEPS.SQL',
    '028_00_CTAS_NOOP.SQL','029_00_CTAS_RESET_FROM.SQL','087_00_RUN_FROM_A04.SQL',
    '088_00_RUN_ALL_FULL.SQL','089_00_RUN_ALL_STEPS.SQL'
) | ForEach-Object {
    $p = Join-Path $CtasDir $_
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Write-Host "removed orphan $_" }
}

# Tum CTAS SQL icindeki @@leaf.sql → numarali dest
Get-ChildItem -LiteralPath $CtasDir -Filter '*.SQL' -File | ForEach-Object {
    $p = $_.FullName
    if ($_.Name -match '^(00_RUN_ALL|090_00_RUN_ALL)\.SQL$') { return }
    $txt = Get-Content -LiteralPath $p -Raw -Encoding UTF8
    if ($txt -notmatch '@@') { return }
    $newTxt = Rewrite-CtasRefs $txt
    if ($newTxt -ne $txt) {
        Set-Content -LiteralPath $p -Value $newTxt -Encoding UTF8
        Write-Host "@@ rewrite: $($_.Name)"
    }
}

# ---------- ENERGY ----------
New-Item -ItemType Directory -Path $EnergyDir -Force | Out-Null
$energyManifestPath = Join-Path $Snap 'MANIFEST_ENERGY.txt'
$energyEntries = @(Parse-Manifest $energyManifestPath)
$energyNewLines = New-Object System.Collections.Generic.List[string]
$energyNewLines.Add("# Yenilendi: $Today") | Out-Null
$energySrcSet = @{}

foreach ($e in $energyEntries) {
    Copy-SnapFile $e.Src (Join-Path $EnergyDir $e.Dest) | Out-Null
    $energyNewLines.Add("$($e.Dest) <= $($e.Src)") | Out-Null
    $energySrcSet[$e.Src.Replace('\', '/').ToLowerInvariant()] = $true
}

# ENERGY eksikler — dokuman / FRK test / 91d / hotfix / 597 heal
$energyAdd = @(
    'prodEnergy/prodREADY_ENERGY3007/91d_debt_paid_sync_from_tah.sql',
    'prodEnergy/prodREADY_ENERGY/NOTES_CANLI_AKTARIM_REV_20260807.md',
    'prodEnergy/prodREADY_ENERGY/NOTES_597_V5_AFL_CANCEL_REV.md',
    'prodEnergy/prodREADY_ENERGY/NOTES_597_PERF_SAFE.md',
    'prodEnergy/prodREADY_ENERGY/NOTES_597_OPS_HEAL.md',
    'prodEnergy/prodREADY_ENERGY/NOTES_CUTOVER_DEV_PLAN_20260809.md',
    'prodEnergy/prodREADY_ENERGY/NOTES_REVIZYON_BACKLOG.md',
    'prodEnergy/prodREADY_ENERGY/20b_INVOICE_NCIX_DISABLE.sql',
    'prodEnergy/prodREADY_ENERGY/20d_597_LOADED_MAP_HEAL.sql',
    'prodEnergy/prodREADY_ENERGY/20e_597_PAY_PT_BAD_MAP_HEAL.sql',
    'prodEnergy/prodREADY_ENERGY/README.md',
    'prodEnergy/prodREADY_ENERGY/CHECKLIST.txt',
    'prodEnergy/prodREADY_ENERGY/MANUAL_CHECKLIST_ENERGY.txt',
    'prodEnergy/prodREADY_ENERGY3007/50e_613_RESUME_OPEN_DEBT_ONLY.sql',
    'prodEnergy/prodREADY_ENERGY3007/SSMS_POST_613_EXECS.sql',
    'prodEnergy/prodREADY_ENERGY3007/SSMS_TAHSILAT_EXECS.sql',
    'prodEnergy/prodREADY_ENERGY3007/README.md',
    'prodEnergy/prodREADY_ENERGY3007/RUN_ORDER.sql',
    'prodEnergy/prodREADY_ENERGY3007/MANUAL_CHECKLIST.txt',
    'prodEnergy/prodREADY_ENERGY3007/INDEX.md',
    'prodEnergy/90_afl_frk/00_README.txt',
    'prodEnergy/90_afl_frk/98_TEST_tam_iade_main_close.sql',
    'prodEnergy/90_afl_frk/98_TEST_asim_main_close.sql',
    'prodEnergy/prodREADY_ENERGY/00e_grow_izgazMGR_log.sql',
    'prodEnergy/HOTFIX_ANLIK_ENVANTER.md',
    'prodEnergy/hotfix/00_HOTFIX_ORDER.txt',
    'prodEnergy/hotfix/01_diag_kurus_src_en.sql',
    'prodEnergy/hotfix/02_patch_resync_amounts_from_ov.sql',
    'prodEnergy/hotfix/03_backfill_iade_invlines.sql',
    'prodEnergy/hotfix/04_patch_kismi_debt_pt.sql',
    'prodEnergy/hotfix/05_diag_linenr_gt_255.sql',
    'prodEnergy/prodREADY_ENERGY/MSSQL_RUN_PARALLEL.md'
)

$nnnE = Next-NNN $EnergyDir 76
foreach ($rel in $energyAdd) {
    $key = $rel.Replace('\', '/').ToLowerInvariant()
    if ($energySrcSet.ContainsKey($key)) { continue }
    try { $full = Resolve-SrcPath $rel } catch { Write-Warning "Atlandi (yok): $rel"; continue }
    $destName = ('{0:D3}_{1}' -f $nnnE, (To-SnapName $rel))
    Copy-SnapFile $rel (Join-Path $EnergyDir $destName) | Out-Null
    $energyNewLines.Add("$destName <= $rel  # ADD_$Today") | Out-Null
    $energySrcSet[$key] = $true
    $nnnE++
}

# Canli paket auto-scan: prodREADY_ENERGY* + 90_afl_frk (scratch/log haric)
# Boylece yeni heal/NOTES dosyalari manifest'e elle eklenmeden snapshot'a girer.
foreach ($packRel in @(
    'prodEnergy/prodREADY_ENERGY',
    'prodEnergy/prodREADY_ENERGY3007',
    'prodEnergy/90_afl_frk'
)) {
    try { $packDir = Resolve-SrcPath $packRel } catch { Write-Warning "Atlandi (yok): $packRel"; continue }
    $packFiles = Get-ChildItem -LiteralPath $packDir -File | Where-Object {
        $_.Extension -match '\.(sql|md|txt)$' -and
        $_.Name -notmatch '^_' -and
        $_.Name -notmatch '^logs_' -and
        $_.Name -notmatch '\.timing\.txt$'
    } | Sort-Object {
        if ($_.Name -match '^(\d+)') { [int]$Matches[1] } else { 999999 }
    }, Name

    foreach ($f in $packFiles) {
        $rel = "$packRel/$($f.Name)" -replace '\\', '/'
        $key = $rel.ToLowerInvariant()
        if ($energySrcSet.ContainsKey($key)) { continue }
        $destName = ('{0:D3}_{1}' -f $nnnE, (To-SnapName $f.Name))
        Copy-SnapFile $rel (Join-Path $EnergyDir $destName) | Out-Null
        $energyNewLines.Add("$destName <= $rel  # ADD_$Today AUTOSCAN") | Out-Null
        $energySrcSet[$key] = $true
        $nnnE++
    }
}

# ProdIzgazMgr2Energy/prodENERGY — TUM uretim SQL (master + financial + project)
# Haric: _tmp*, *.timing.txt, IzgazSchema, logs
$prodEnDir = Join-Path $Base 'ProdIzgazMgr2Energy\prodENERGY'
if (Test-Path $prodEnDir) {
    $prodFiles = Get-ChildItem -LiteralPath $prodEnDir -File | Where-Object {
        $_.Extension -match '\.(sql|md|txt)$' -and
        $_.Name -notmatch '^(_tmp|logs_)' -and
        $_.Name -notmatch '\.timing\.txt$' -and
        $_.Name -ne 'IzgazSchema.sql'
    } | Sort-Object {
        if ($_.Name -match '^(\d+)') { [int]$Matches[1] } else { 999999 }
    }, Name

    foreach ($f in $prodFiles) {
        $rel = "ProdIzgazMgr2Energy/prodENERGY/$($f.Name)"
        $key = $rel.ToLowerInvariant()
        if ($energySrcSet.ContainsKey($key)) { continue }
        $destName = ('{0:D3}_{1}' -f $nnnE, (To-SnapName $f.Name))
        Copy-SnapFile $rel (Join-Path $EnergyDir $destName) | Out-Null
        $energyNewLines.Add("$destName <= $rel  # ADD_$Today PRODENERGY") | Out-Null
        $energySrcSet[$key] = $true
        $nnnE++
    }
}

# ENERGY INDEX
$enIdx = New-Object System.Collections.Generic.List[string]
$enIdx.Add("# 20260708/ENERGY — INDEX ($Today)") | Out-Null
$enIdx.Add('') | Out-Null
$enIdx.Add('| NNN | Dosya | Kaynak |') | Out-Null
$enIdx.Add('|-----|-------|--------|') | Out-Null
foreach ($l in $energyNewLines) {
    if ($l -match '^(\d{3}_\S+)\s+<=\s+(\S+)') {
        $enIdx.Add("| $($Matches[1].Substring(0,3)) | $($Matches[1]) | $($Matches[2]) |") | Out-Null
    }
}
Set-Content -LiteralPath (Join-Path $EnergyDir '000_ENERGY_INDEX.MD') -Value $enIdx -Encoding UTF8

$energyNewLines | Set-Content -LiteralPath $energyManifestPath -Encoding UTF8

# ---------- REPORT/ — kontrol / FRK / checklist kopyalari ----------
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$reportManifest = New-Object System.Collections.Generic.List[string]
$reportManifest.Add("# REPORT — kontrol/rapor kopyalari · $Today") | Out-Null

$reportMap = @(
    @{ Src = 'prodEnergy/90_afl_frk/00_README.txt'; Dest = '000_README_AFL_FRK.TXT' },
    @{ Src = 'prodEnergy/90_afl_frk/91_afl_frk_compare_log.sql'; Dest = '091_AFL_FRK_COMPARE_LOG.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/92_stg_inv_pay_close_apply.sql'; Dest = '092_STG_INV_PAY_CLOSE_APPLY.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/93_scenario_dump_checklist.sql'; Dest = '093_SCENARIO_DUMP_CHECKLIST.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/93_tuketim_tutar_kontrol.sql'; Dest = '093_TUKETIM_TUTAR_KONTROL.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/93b_tuketim_tutar_ssms.sql'; Dest = '093B_TUKETIM_TUTAR_SSMS.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/94_tuketim_tutar_frk.sql'; Dest = '094_TUKETIM_TUTAR_FRK.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/95_ttk_inv_afl_fatura_rapor.sql'; Dest = '095_TTK_INV_AFL_FATURA_RAPOR.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/96_agr5727_ttk_vs_inv.sql'; Dest = '096_AGR5727_TTK_VS_INV.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/97_agr_frk_all.sql'; Dest = '097_AGR_FRK_ALL.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/98_tam_iade_main_pt_close_temp.sql'; Dest = '098_TAM_IADE_MAIN_PT_CLOSE_TEMP.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/98_TEST_tam_iade_main_close.sql'; Dest = '098_TEST_TAM_IADE_MAIN_CLOSE.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/98_TEST_asim_main_close.sql'; Dest = '098_TEST_ASIM_MAIN_CLOSE.SQL' },
    @{ Src = 'prodEnergy/90_afl_frk/99_afl_vs_en_kalan_frk.sql'; Dest = '099_AFL_VS_EN_KALAN_FRK.SQL' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/CHECK_QUERIES_ENERGY.sql'; Dest = '061_CHECK_QUERIES_ENERGY.SQL' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY3007/90_check_queries.sql'; Dest = '090_CHECK_QUERIES.SQL' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/NOTES_CANLI_AKTARIM_REV_20260807.md'; Dest = 'NOTES_CANLI_AKTARIM_REV_20260807.MD' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/NOTES_597_V5_AFL_CANCEL_REV.md'; Dest = 'NOTES_597_V5_AFL_CANCEL_REV.MD' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/NOTES_597_PERF_SAFE.md'; Dest = 'NOTES_597_PERF_SAFE.MD' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/NOTES_597_OPS_HEAL.md'; Dest = 'NOTES_597_OPS_HEAL.MD' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/NOTES_CUTOVER_DEV_PLAN_20260809.md'; Dest = 'NOTES_CUTOVER_DEV_PLAN_20260809.MD' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/NOTES_REVIZYON_BACKLOG.md'; Dest = 'NOTES_REVIZYON_BACKLOG.MD' },
    @{ Src = 'prodEnergy/HOTFIX_ANLIK_ENVANTER.md'; Dest = 'HOTFIX_ANLIK_ENVANTER.MD' },
    @{ Src = 'prodEnergy/PAKET_PATCH_HIZALAMA.md'; Dest = 'PAKET_PATCH_HIZALAMA.MD' },
    @{ Src = 'prodEnergy/patch/README.md'; Dest = 'PATCH_README.MD' },
    @{ Src = 'prodEnergy/hotfix/00_HOTFIX_ORDER.txt'; Dest = 'HOTFIX_00_ORDER.TXT' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/MANUAL_CHECKLIST_ENERGY.txt'; Dest = 'MANUAL_CHECKLIST_ENERGY.TXT' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY/CHECKLIST.txt'; Dest = 'CHECKLIST_ENERGY.TXT' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY3007/EXIT_MAP.md'; Dest = 'EXIT_MAP.MD' },
    @{ Src = 'prodEnergy/prodREADY_ENERGY3007/MANUAL_CHECKLIST.txt'; Dest = 'MANUAL_CHECKLIST_3007.TXT' },
    @{ Src = 'oracleCTAS/prodREADY/CHECK_QUERIES_ORACLE.sql'; Dest = '072_CHECK_QUERIES_ORACLE.SQL' },
    @{ Src = 'oracleCTAS3007/MANUAL_CHECKLIST_ORACLE.txt'; Dest = '074_MANUAL_CHECKLIST_ORACLE.TXT' },
    @{ Src = 'oracleCTAS/prodREADY/diag_o11_ctas_smoke.sql'; Dest = '078_DIAG_O11_CTAS_SMOKE.SQL' },
    @{ Src = 'oracleCTAS/prodREADY/diag_o11_precision.sql'; Dest = '079_DIAG_O11_PRECISION.SQL' },
    @{ Src = 'oracleCTAS/prodREADY/diag_linenr_gt_255.sql'; Dest = '077_DIAG_LINENR_GT_255.SQL' }
)

foreach ($r in $reportMap) {
    try { $full = Resolve-SrcPath $r.Src } catch { Write-Warning "REPORT atlandi: $($r.Src)"; continue }
    Copy-SnapFile $r.Src (Join-Path $ReportDir $r.Dest) | Out-Null
    $reportManifest.Add("$($r.Dest) <= $($r.Src)") | Out-Null
}

$reportReadme = @"
# 20260708/REPORT — kontrol / FRK / checklist

Kopya arsiv. Kaynak: ``90_afl_frk``, ``prodREADY_ENERGY*``, Oracle CHECK/diag.
Canli duzenleme kaynak klasorlerde; burasi aksam goc kontrol paketi.

Yenilendi: $Today

| Grup | Dosyalar |
|------|----------|
| AFL/FRK | 091–099 (+ 098_TEST_*) |
| Hotfix / anlık | HOTFIX_ANLIK_ENVANTER, HOTFIX_00_ORDER |
| Paket vs patch | PAKET_PATCH_HIZALAMA, PATCH_README |
| Energy check | CHECK_QUERIES*, EXIT_MAP, NOTES_* |
| Oracle check | CHECK_QUERIES_ORACLE, MANUAL_CHECKLIST, diag_* |

Manifest: ``MANIFEST_REPORT.txt``
"@
Set-Content -LiteralPath (Join-Path $ReportDir '000_README.MD') -Value $reportReadme -Encoding UTF8
$reportManifest | Set-Content -LiteralPath (Join-Path $Snap 'MANIFEST_REPORT.txt') -Encoding UTF8

# ---------- README ----------
$readme = @"
# MIGRATION_SCR_20260708 — CTAS + ENERGY + REPORT

Repo yolu = 195 yolu (ayni klasor yapisi):
- Repo: ``sql/IZGAZ2PCMS/IZGAZ2PCMS/MIGRATION_SCR_20260708/``
- 195:  ``C:\www\MIGRATION_SCR_20260708\``

Kaynaklar yerinde kaldi; bu klasor **kopya** paket yuzeyidir (cut degil).
Son yenileme: $Today.

## CTAS/
Omurga: ``oracleCTAS3007`` · ayni ad varsa daha yeni: ``oracleCTAS/prodREADY``  
Ad: ``NNN_ORIJINAL_AD.SQL`` (**BUYUK HARF**).

| NNN | Anlam |
|-----|--------|
| ``000_*`` | Dokuman — ``000_RUN_ORDER.MD`` sira kaynagi |
| ``001–027`` | Faz A — Master CTAS (+ LS_PROJECT / LS_PROJECTLINE) |
| ``030–060`` | Faz B — Full tahsilat / O60 GUVENCE |
| ``070+`` | prodREADY / 3007 extra (HOTFIX/diag/checklist) |
| ``090–091`` | Orkestrator |

## ENERGY/
| Kaynak | Icerik |
|--------|--------|
| ``prodREADY_ENERGY`` | 570 zinciri setup, 590/597 overlay, **610 GUVENCE_IADE**, RUN_ORDER, NOTES, hotfix |
| ``ProdIzgazMgr2Energy/prodENERGY`` | **tam master zincir** (04–920) + 57x + **590–596 PROJECT/PROJECTLINE** + SPEFEE/LEGAL/INSTALLMENT |
| ``prodREADY_ENERGY3007`` | financial chain, bankref, taksit, 91/91b/91c/**91d** |
| ``90_afl_frk`` | 91–99 FRK/TTK (+ 98_TEST_*) |

Index: ``ENERGY/000_ENERGY_INDEX.MD``

## REPORT/
Kontrol / FRK / checklist kopyalari (akis disi calistirma paketi).

Manifest: ``MANIFEST_CTAS.txt`` · ``MANIFEST_ENERGY.txt`` · ``MANIFEST_REPORT.txt``  
Yenile: ``_sync_snapshot.ps1``  
195 mirror: ``_deploy_195.ps1``  
**Yasak:** ``SRC_*`` / yan paket — tek yuzey bu uc klasor.
"@
Set-Content -LiteralPath (Join-Path $Snap 'README.md') -Value $readme -Encoding UTF8

Write-Host "OK CTAS=$($(Get-ChildItem $CtasDir -File).Count) ENERGY=$($(Get-ChildItem $EnergyDir -File).Count) REPORT=$($(Get-ChildItem $ReportDir -File).Count)"
Write-Host "Manifests: MANIFEST_CTAS / ENERGY / REPORT + README yenilendi ($Today)"
