# CTAS paket map — NNN_NAME_VER + RUNALL
# Sync tarafindan dot-source edilir. Canli kaynak adlari degismez.

function New-CtasItem {
    param(
        [int]$Seq,
        [string]$Name,
        [string]$Src,
        [bool]$InRunAll = $false,
        [string]$Ver = '01',
        [string]$StepId = '',
        [string]$StepLabel = '',
        [string]$Owner = 'MIGRATION',
        [string]$Tables = '',
        [string]$Amac = '',
        [string]$Gate = 'yok',
        [string]$Note = ''
    )
    $ext = if ($Src -match '\.(md|txt)$') { [IO.Path]::GetExtension($Src).ToUpperInvariant() } else { '.SQL' }
    $dest = ('{0:D3}_{1}_V{2}{3}' -f $Seq, $Name.ToUpperInvariant(), $Ver, $ext)
    [PSCustomObject]@{
        Seq       = $Seq
        Name      = $Name.ToUpperInvariant()
        Ver       = $Ver
        Src       = $Src
        Dest      = $dest
        InRunAll  = $InRunAll
        StepId    = $StepId
        StepLabel = if ($StepLabel) { $StepLabel } else { $Name.ToUpperInvariant() }
        Owner     = $Owner
        Tables    = $Tables
        Amac      = $Amac
        Gate      = $Gate
        Note      = $Note
    }
}

# Sirali map — tek kaynak gercek
$script:CtasMap = @(
    # DOC 000-009
    (New-CtasItem 1 'DUMP_MANIFEST' 'oracleCTAS3007/DUMP_MANIFEST.txt' -Amac 'Dump tablo listesi' -Note 'DOC')
    (New-CtasItem 2 'INDEX' 'oracleCTAS3007/INDEX.md' -Amac 'CTAS index' -Note 'DOC')
    (New-CtasItem 3 'SCHEMA_CTAS_ORDER' 'oracleCTAS3007/SCHEMA_CTAS_ORDER.md' -Amac 'Sema / sira aciklamasi' -Note 'DOC')
    (New-CtasItem 4 'TABLE_CATALOG' 'oracleCTAS3007/TABLE_CATALOG.md' -Amac 'Tablo katalogu' -Note 'DOC')

    # SETUP 010-019
    (New-CtasItem 10 'MIG_CTAS_LOG' 'oracleCTAS3007/00_mig_ctas_log.sql' -InRunAll $true `
        -StepId 'O0L' -StepLabel 'mig_ctas_log' -Tables 'MIG_CTAS_LOG' `
        -Amac 'Adim log altyapisi')
    (New-CtasItem 11 'SESSION_PARALLEL' 'oracleCTAS3007/00_session_parallel.sql' -InRunAll $true `
        -StepId 'O0' -StepLabel 'session_parallel' `
        -Amac 'Session DOP 56 (TEMP → 48)')
    (New-CtasItem 12 'MIG_PARAM_FULL' 'oracleCTAS3007/00_mig_param_full.sql' -InRunAll $true `
        -StepId 'O0b' -StepLabel 'mig_param_full' -Tables 'MIG_PARAM' `
        -Amac 'FULL mod — AGR filtre kapali')

    # MASTER 020-049
    (New-CtasItem 20 'LS_FLAT' 'oracleCTAS3007/LS_FLAT.sql' -InRunAll $true `
        -StepId 'A01' -Tables 'LS_FLAT' -Amac 'Bina/daire FLAT staging')
    (New-CtasItem 21 'LS_ITEMS' 'oracleCTAS3007/LS_ITEMS.sql' -InRunAll $true `
        -StepId 'A02' -Tables 'LS_ITEMS' -Amac 'Sayac envanteri')
    (New-CtasItem 22 'LS_REGISTER' 'oracleCTAS3007/LS_REGISTER.sql' -InRunAll $true `
        -StepId 'A03' -Tables 'LS_REGISTER' -Amac 'Abone/firma sicil')
    (New-CtasItem 23 'LS_IT_USER' 'oracleCTAS3007/LS_IT_USER.sql' -InRunAll $true `
        -StepId 'A04' -Tables 'LS_IT_USER' -Amac 'Kullanici staging')
    (New-CtasItem 24 'LS_AGREEMENT' 'oracleCTAS3007/LS_AGREEMENT.sql' -InRunAll $true `
        -StepId 'A05' -Tables 'LS_AGREEMENT' -Amac 'Sozlesme staging')
    (New-CtasItem 25 'LS_AGR_CLOSE' 'oracleCTAS3007/LS_AGR_CLOSE.sql' -InRunAll $true `
        -StepId 'A06' -Tables 'LS_AGR_CLOSE' -Amac 'Sozlesme kapatma')
    (New-CtasItem 26 'LS_AGR_GUARANTY' 'oracleCTAS3007/LS_AGR_GUARANTY.sql' -InRunAll $true `
        -StepId 'A07' -Tables 'LS_AGR_GUARANTY' `
        -Amac 'Teminat/garanti (GTYPE39 TOTAL damgasiz)')
    (New-CtasItem 27 'LS_AGR_DEVICE' 'oracleCTAS3007/LS_AGR_DEVICE.sql' -InRunAll $true `
        -StepId 'A08' -Tables 'LS_AGR_DEVICE' -Amac 'Sozlesme cihaz')
    (New-CtasItem 28 'LS_AGR_SERVQ' 'oracleCTAS3007/LS_AGR_SERVQ.sql' -InRunAll $true `
        -StepId 'A09' -Tables 'LS_AGR_SERVQ' -Amac 'Servis ekipmani')
    (New-CtasItem 29 'LS_FITMENT_FEE' 'oracleCTAS3007/LS_FITMENTFEE.sql' -InRunAll $true `
        -StepId 'A10' -StepLabel 'LS_FITMENT_FEE' -Tables 'LS_FITMENT_FEE' -Amac 'Baglanti ucreti')
    (New-CtasItem 30 'LS_AGR_AUTO_PAYMENT_LOG' 'oracleCTAS3007/LS_AGREEMENT_AUTO_PAYMENT_LOG.sql' -InRunAll $true `
        -StepId 'A11' -StepLabel 'LS_AGREEMENT_AUTO_PAYMENT_LOG' -Tables 'LS_AGREEMENT_AUTO_PAYMENT_LOG' `
        -Amac 'Banka talimat log')
    (New-CtasItem 31 'LS_BANK_CONFIRM' 'oracleCTAS3007/LS_BANK_CONFIRM.sql' -InRunAll $true `
        -StepId 'A12' -Tables 'LS_BANK_CONFIRM' -Amac 'Banka mutabakat')
    (New-CtasItem 32 'LS_BANK_ACC' 'oracleCTAS3007/LS_BANK_ACC.sql' -InRunAll $true `
        -StepId 'A12b' -Tables 'LS_BANK_ACC' -Amac 'Banka hesap')
    (New-CtasItem 33 'LS_INSTALLMENT' 'oracleCTAS3007/LS_INSTALLMENT.sql' -InRunAll $true `
        -StepId 'A13' -Tables 'LS_INSTALLMENT' -Amac 'Taksit baslik')
    (New-CtasItem 34 'LS_INSTALLMENT_PLAN' 'oracleCTAS3007/LS_INSTALLMENT_PLAN.sql' -InRunAll $true `
        -StepId 'A14' -Tables 'LS_INSTALLMENT_PLAN' -Amac 'Taksit satirlari')
    (New-CtasItem 35 'LS_WORK' 'oracleCTAS3007/LS_WORK.sql' -InRunAll $true `
        -StepId 'A15' -Tables 'LS_WORK' -Amac 'Is emri / randevu')
    (New-CtasItem 36 'LS_WORK_RESULT' 'oracleCTAS3007/LS_WORK_RESULT.sql' -InRunAll $true `
        -StepId 'A16' -Tables 'LS_WORK_RESULT' -Amac 'Is emri sonuc')
    (New-CtasItem 37 'LS_SPEFEE_ADD' 'oracleCTAS3007/LS_SPEFEE_ADD.sql' -InRunAll $true `
        -StepId 'A17' -Tables 'LS_SPEFEE_ADD' -Amac 'SPEFEE devir')
    (New-CtasItem 38 'LS_PROJECT' 'oracleCTAS/LS_PROJECT.sql' -InRunAll $true `
        -StepId 'A18' -Owner 'MIGRATION' -Tables 'LS_PROJECT' -Amac 'Proje baslik (MIGRATION)')
    (New-CtasItem 39 'LS_PROJECTLINE' 'oracleCTAS/LS_PROJECTLINE.sql' -InRunAll $true `
        -StepId 'A19' -Owner 'MIGRATION' -Tables 'LS_PROJECTLINE' -Amac 'Proje satirlari (MIGRATION)')

    # OKUMA 100-129
    (New-CtasItem 100 'MIG_ACCRUE_TYPE_MAP' 'oracleCTAS3007/09_mig_accrue_type_map.sql' -InRunAll $true `
        -StepId 'O09' -Tables 'MIG_ACCRUE_TYPE_MAP' -Amac 'ACCRUE→TYPE map')
    (New-CtasItem 101 'LS_READING' 'oracleCTAS3007/LS_READING.sql' -InRunAll $true `
        -StepId 'RD' -Tables 'LS_READING' -Amac 'Sayac okuma')
    (New-CtasItem 102 'LS_READING_SYNTH' 'oracleCTAS3007/LS_READING_SYNTH.sql' -InRunAll $true `
        -StepId 'RDs' -Tables 'LS_READING' -Amac 'Sentetik okuma gap')
    (New-CtasItem 103 'LS_HHD_MSTR' 'oracleCTAS3007/LS_HHD_MSTR.sql' -InRunAll $true `
        -StepId 'HHD' -Tables 'LS_OV_HHD_MSTR,LS_OV_HHD_TRAN_MAP,LS_OV_HHD_MSTR_SKIP' `
        -Amac 'HHD master + MAP')
    (New-CtasItem 104 'GATE_HHD_MSTR' 'oracleCTAS3007/LS_HHD_MSTR_GATE.sql' -InRunAll $true `
        -StepId 'HHDg' -StepLabel 'LS_HHD_MSTR_GATE' -Gate 'PASS zorunlu' -Amac 'HHD gate')
    (New-CtasItem 105 'LS_KFACTOR_VALUE' 'oracleCTAS3007/LS_KFACTOR_VALUE.sql' -InRunAll $true `
        -StepId 'KF' -Tables 'LS_KFACTOR_VALUE' -Amac 'Isil deger / kromatograf')
    (New-CtasItem 106 'LS_ADJUSTMENT_COEFFICIENT' 'oracleCTAS3007/LS_ADJUSTMENT_COEFFICIENT.sql' -InRunAll $true `
        -StepId 'AC' -Tables 'LS_ADJUSTMENT_COEFFICIENT' -Amac 'Duzeltme katsayisi')
    (New-CtasItem 107 'LS_SPEFEE' 'oracleCTAS3007/LS_SPEFEE.sql' -InRunAll $true `
        -StepId 'SF' -Tables 'LS_SPEFEE' -Amac 'Ozel ucret')

    # FATURA / OVERLAY 130-199
    (New-CtasItem 130 'STG_INV_ACC_INC' 'oracleCTAS3007/10_stg_inv_acc_inc.sql' -InRunAll $true `
        -StepId 'O10' -Tables 'STG_INV_ACC_INC' `
        -Amac 'Fatura fee pivot (+TOTAL_DV; ACCRUE 5/6/21/341)')
    (New-CtasItem 131 'LS_INVOICE' 'oracleCTAS3007/11_ls_invoice.sql' -InRunAll $true `
        -StepId 'O11' -Tables 'LS_INVOICE' -Amac 'Ana fatura (DV=TOTAL_DV)')
    (New-CtasItem 132 'LS_INVLINES' 'oracleCTAS3007/12_ls_invlines.sql' -InRunAll $true `
        -StepId 'O12' -Tables 'LS_INVLINES' `
        -Amac 'Fatura kalemleri (109/111 damga TL=0/DV)')
    (New-CtasItem 133 'LS_MIG_AGR_LIST' 'oracleCTAS3007/13_ls_mig_agr_list.sql' -InRunAll $true `
        -StepId 'O13' -Tables 'LS_MIG_AGR_LIST' -Amac 'Migrate AGR listesi')
    (New-CtasItem 134 'LS_DEBT_PAYTRANS' 'oracleCTAS3007/14_ls_debt_paytrans.sql' -InRunAll $true `
        -StepId 'O14' -Tables 'LS_DEBT_PAYTRANS' -Amac 'Borc PT prefab')
    (New-CtasItem 135 'LS_EKSILTEN_OVERLAY' 'oracleCTAS3007/20_ls_eksilten_overlay.sql' -InRunAll $true `
        -StepId 'O20' -Tables 'LS_OV_EKS_CLASS,LS_OV_IADE_*,LS_OV_KISMI_*,LS_OV_MAIN_UPD' `
        -Amac 'Eksilten / iade overlay')
    (New-CtasItem 136 'GATE_EKSILTEN' 'oracleCTAS3007/27_gate_eksilten.sql' -InRunAll $true `
        -StepId 'O27' -Gate 'PASS zorunlu' -Amac 'Eksilten hard gate')
    (New-CtasItem 137 'LS_TAHSILAT_OVERLAY' 'oracleCTAS3007/30_ls_tahsilat_overlay.sql' -InRunAll $true `
        -StepId 'O30' -Tables 'LS_OV_PAY_*,LS_OV_TAH_*,LS_OV_MAHSUP_*,LS_OV_CANCEL_*' `
        -Amac 'Tahsilat overlay' -Note 'PIN_3007')
    (New-CtasItem 138 'LS_OV_DEBT_PAID_LASTPAID' 'oracleCTAS3007/32_ls_ov_debt_paid_lastpaid.sql' -InRunAll $true `
        -StepId 'O32' -Tables 'LS_OV_DEBT_PAID_UPD,LS_OV_INV_PAY_GAP' `
        -Amac 'DEBT_PAID / LPD set')
    (New-CtasItem 139 'LS_OV_PAY_PT_BANK_ENRICH' 'oracleCTAS3007/34_ls_ov_pay_pt_bank_enrich.sql' -InRunAll $true `
        -StepId 'O34' -Tables 'LS_OV_PAY_PT,LS_OV_TAH_INVOICE' `
        -Amac 'PAY_PT bank / PAID enrich')
    (New-CtasItem 140 'LS_INVOICE_CLOSE_BANK' 'oracleCTAS3007/33_ls_invoice_close_bank_patch.sql' -InRunAll $true `
        -StepId 'O33' -Tables 'LS_INVOICE' -Amac 'INV CLOSED/LPD/BANK patch')
    (New-CtasItem 141 'LS_DEBT_PAYTRANS_REBUILD' 'oracleCTAS3007/14b_ls_debt_paytrans_rebuild.sql' -InRunAll $true `
        -StepId 'O14b' -Tables 'LS_DEBT_PAYTRANS' -Amac 'Borc PT final rebuild')
    (New-CtasItem 142 'LS_OV_ID_MAP' 'oracleCTAS3007/35_ls_ov_id_map.sql' -InRunAll $true `
        -StepId 'O35' -Tables 'LS_OV_ID_MAP' -Amac 'Overlay SRC_KEY map')
    (New-CtasItem 143 'GATE_TAHSILAT' 'oracleCTAS3007/41_gate_tahsilat.sql' -InRunAll $true `
        -StepId 'O41' -Gate 'PASS zorunlu' -Amac 'Tahsilat hard gate' -Note 'PIN_3007')

    # POST 200-249
    (New-CtasItem 200 'LS_AFL_OPEN_DEBT' 'oracleCTAS3007/50_ls_afl_open_debt.sql' -InRunAll $true `
        -StepId 'O50' -Tables 'LS_AFL_OPEN_DEBT' -Amac 'AFL acik borc snapshot')
    (New-CtasItem 201 'LS_STG_INV_PAY_CLOSE' 'oracleCTAS3007/51_ls_stg_inv_pay_close.sql' -InRunAll $true `
        -StepId 'O51' -Tables 'LS_STG_INV_PAY_CLOSE' -Amac 'STG kapama aday')
    (New-CtasItem 202 'LS_PAYMENT' 'oracleCTAS3007/52_ls_payment.sql' -InRunAll $true `
        -StepId 'O52' -Tables 'LS_PAYMENT' -Amac 'Makbuz grain tahsilat')
    (New-CtasItem 203 'LS_EKSILTEN_FAMILY' 'oracleCTAS3007/53_ls_eksilten_family.sql' -InRunAll $true `
        -StepId 'O53' -Tables 'LS_EKSILTEN,LS_PARTIAL_EKSILTEN' -Amac 'Eksilten family tablolar')
    (New-CtasItem 204 'LS_ARTIRAN_EMANET' 'oracleCTAS3007/54_ls_artiran_emanet.sql' -InRunAll $true `
        -StepId 'O54' -Tables 'LS_ARTIRAN,LS_EMANET' -Amac 'Artiran + emanet')
    (New-CtasItem 205 'LS_MAHSUP' 'oracleCTAS3007/55_ls_mahsup.sql' -InRunAll $true `
        -StepId 'O55' -Tables 'LS_MAHSUP' -Amac 'Mahsup staging')
    (New-CtasItem 206 'LS_TAKSIT' 'oracleCTAS3007/56_ls_taksit.sql' -InRunAll $true `
        -StepId 'O56' -Tables 'LS_TAKSIT' -Amac 'Taksit durum tablosu')
    (New-CtasItem 207 'LS_INSTALLMENT_PLAN_PAY' 'oracleCTAS3007/57_ls_installment_plan_pay.sql' -InRunAll $true `
        -StepId 'O57' -Tables 'LS_INSTALLMENT_PLAN_PAY' -Amac 'Taksit plan odeme')
    (New-CtasItem 208 'GATE_PILOT_PARITY' 'oracleCTAS3007/58_gate_pilot_parity.sql' -InRunAll $true `
        -StepId 'O58' -Gate 'PASS zorunlu' -Amac 'Parity / dump kapisi')
    (New-CtasItem 209 'TUKETIM_TUTAR_KONTROL' 'oracleCTAS3007/59_tuketim_tutar_kontrol.sql' -InRunAll $true `
        -StepId 'O59' -Tables 'TUKETIM_TUTAR_KONTROL' -Amac 'TTK master (O59)')
    (New-CtasItem 210 'LS_OV_GUVENCE_IADE' 'oracleCTAS3007/60_ls_ov_guvence_iade.sql' -InRunAll $true `
        -StepId 'O60' -Tables 'LS_OV_GUVENCE_IADE_*' -Amac 'TYPE110 guvence iade overlay')
    (New-CtasItem 211 'LS_CUSTODY' 'oracleCTAS3007/61_ls_custody.sql' -InRunAll $true `
        -StepId 'O61' -Tables 'LS_CUSTODY' -Amac 'Custody staging')

    # CLOSE 250-259
    (New-CtasItem 250 'TRANSFER_INDEXES' 'oracleCTAS3007/98_transfer_indexes.sql' -InRunAll $true `
        -StepId 'O98' -Amac 'Dump oncesi join IX')
    (New-CtasItem 251 'LOG_STATUS' 'oracleCTAS3007/99_log_status.sql' -InRunAll $true `
        -Amac 'MIG_CTAS_LOG ozet')

    # EXTRA 900+ — RUNALL disi
    (New-CtasItem 900 'MIG_PARAM_PILOT' 'oracleCTAS3007/00_mig_param_pilot.sql' `
        -Amac 'Pilot AGR listesi' -Note 'PILOT')
    (New-CtasItem 901 'RUN_PILOT_OVERLAY' 'oracleCTAS3007/00_run_pilot_overlay.sql' `
        -Amac 'Pilot overlay orch' -Note 'PILOT')
    (New-CtasItem 902 'STG_CLEANUP' 'oracleCTAS3007/99_stg_cleanup.sql' `
        -Amac 'STG/TMP drop (opsiyonel)' -Note 'OPSIYONEL')
    (New-CtasItem 910 'HOTFIX_LS_OV_TAH_LOG' 'oracleCTAS/prodREADY/30_HOTFIX_ls_ov_tah_log_pay_before.sql' `
        -Amac 'TAH log hotfix' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 911 'LS_TAHSILAT_LOG' 'oracleCTAS/prodREADY/40_ls_tahsilat_log.sql' `
        -Amac 'Tahsilat log' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 912 'CHECK_QUERIES_ORACLE' 'oracleCTAS/prodREADY/CHECK_QUERIES_ORACLE.sql' `
        -Amac 'Oracle check sorgulari' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 913 'DESIGN_MAP' 'oracleCTAS/prodREADY/DESIGN_MAP.txt' `
        -Amac 'Tasarim map' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 914 'MANUAL_CHECKLIST_ORACLE' 'oracleCTAS3007/MANUAL_CHECKLIST_ORACLE.txt' `
        -Amac 'Oracle checklist' -Note 'DOC')
    (New-CtasItem 915 'README_PRODREADY' 'oracleCTAS/prodREADY/README.md' `
        -Amac 'prodREADY README' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 916 'SCENARIO_MAP' 'oracleCTAS/prodREADY/SCENARIO_MAP.md' `
        -Amac 'Senaryo map' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 917 'DIAG_LINENR_GT_255' 'oracleCTAS/prodREADY/diag_linenr_gt_255.sql' `
        -Amac 'LINENR>255 diag' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 918 'DIAG_O11_CTAS_SMOKE' 'oracleCTAS/prodREADY/diag_o11_ctas_smoke.sql' `
        -Amac 'O11 smoke diag' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 919 'DIAG_O11_PRECISION' 'oracleCTAS/prodREADY/diag_o11_precision.sql' `
        -Amac 'O11 precision diag' -Note 'EXTRA_PRODREADY')
    (New-CtasItem 920 'LS_HHD_MSTR_DIAG' 'oracleCTAS3007/LS_HHD_MSTR_DIAG.sql' `
        -Amac 'HHD diag' -Note 'EXTRA_3007')
    (New-CtasItem 921 'VERIFY_SYNTH_GAP' 'oracleCTAS3007/VERIFY_SYNTH_GAP.sql' `
        -Amac 'Synth gap verify' -Note 'EXTRA_3007')
    (New-CtasItem 922 'PILOT_FINDINGS' 'oracleCTAS3007/PILOT_FINDINGS.md' `
        -Amac 'Pilot bulgulari' -Note 'EXTRA_3007')
    (New-CtasItem 923 'README_3007' 'oracleCTAS3007/README.md' `
        -Amac '3007 README' -Note 'EXTRA_3007')
    (New-CtasItem 924 'NOTES_CTAS_NO_RESTART' 'oracleCTAS3007/NOTES_CTAS_NO_RESTART.md' `
        -Amac 'FAIL→resume; RUNALL bashtan YASAK' -Note 'DOC')
    (New-CtasItem 925 'DIAG_DV_TYPE109' 'oracleCTAS3007/diag_dv_type109.sql' `
        -Amac 'Soft assert TYPE109/111 DV + damga satiri' -Note 'EXTRA_3007')
)

function Get-CtasDestName([object]$item) { return $item.Dest }

function Get-CtasHeader([object]$item, [object]$nextItem) {
    $next = if ($nextItem) { $nextItem.Dest } else { '(son)' }
    $lines = @(
        "-- $($item.Dest)"
        "-- Amac: $($item.Amac)"
    )
    if ($item.Tables) { $lines += "-- Uretir: $($item.Tables)" }
    $lines += "-- Gate: $($item.Gate)"
    $lines += "-- Sonraki: $next"
    return ($lines -join "`r`n") + "`r`n"
}

function Add-CtasHeaderStamp([string]$body, [object]$item, [object]$nextItem) {
    $stamp = Get-CtasHeader $item $nextItem
    # Eski paket stamp'ini kaldir
    if ($body -match '(?s)\A-- \d{3}_[A-Z0-9_]+_V\d{2}\.[A-Z]+\r?\n(?:-- .+\r?\n){1,6}') {
        $body = [regex]::Replace($body, '(?s)\A-- \d{3}_[A-Z0-9_]+_V\d{2}\.[A-Z]+\r?\n(?:-- .+\r?\n){1,6}', '')
    }
    return $stamp + $body
}

function Build-CtasRunAll([object[]]$map) {
    $runItems = @($map | Where-Object { $_.InRunAll })
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('-- CTAS FULL — tek orchestrator')
    [void]$sb.AppendLine('-- FAIL = DUR (WHENEVER SQLERROR EXIT)')
    [void]$sb.AppendLine('-- Resume: MIG_CTAS_LOG son OK → o NNN dosyadan devam')
    [void]$sb.AppendLine('-- TEMP baskisi → SESSION DOP 48')
    [void]$sb.AppendLine('-- Ad: NNN_NAME_Vnn.SQL | Map: _ctas_nnn_map.ps1')
    [void]$sb.AppendLine('WHENEVER SQLERROR EXIT FAILURE')
    [void]$sb.AppendLine('SET ECHO ON')
    [void]$sb.AppendLine('SET SERVEROUTPUT ON SIZE UNLIMITED')
    [void]$sb.AppendLine('SET TIMING ON')
    [void]$sb.AppendLine('SET DEFINE OFF')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('PROMPT ========== CTAS FULL RUN START ==========')

    $i = 0
    while ($i -lt $runItems.Count) {
        $it = $runItems[$i]
        # LOG + SESSION: STEP_BEGIN yok (kaynakla ayni)
        if ($it.Seq -eq 10 -or $it.Seq -eq 11) {
            [void]$sb.AppendLine("@@$($it.Dest)")
            $i++
            continue
        }
        if ($it.Seq -eq 12) {
            [void]$sb.AppendLine("EXEC MIGRATION.P_MIG_CTAS_RUN_INIT('FULL');")
        }
        if ($it.StepId) {
            $label = $it.StepLabel.Replace("'", "''")
            [void]$sb.AppendLine("EXEC MIGRATION.P_MIG_CTAS_STEP_BEGIN('$($it.StepId)','$label');")
        }
        [void]$sb.AppendLine("@@$($it.Dest)")
        if ($it.StepId) {
            $label = $it.StepLabel.Replace("'", "''")
            if ($it.Tables) {
                $tabs = $it.Tables.Replace("'", "''")
                [void]$sb.AppendLine("EXEC MIGRATION.P_MIG_CTAS_STEP_END('$($it.StepId)','$label','$($it.Owner)','$tabs');")
            } else {
                [void]$sb.AppendLine("EXEC MIGRATION.P_MIG_CTAS_STEP_END('$($it.StepId)','$label');")
            }
        }
        [void]$sb.AppendLine('')
        $i++
    }

    [void]$sb.AppendLine('PROMPT ========== CTAS FULL RUN DONE ==========')
    [void]$sb.AppendLine('PROMPT Dump: 001_DUMP_MANIFEST_V01.TXT')
    [void]$sb.AppendLine('/')
    return $sb.ToString()
}

function Build-CtasRunOrderMd([object[]]$map, [string]$today) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# CTAS — CALISTIRMA SIRASI ($today)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Tek giris: `00_RUN_ALL.SQL`')
    [void]$sb.AppendLine('Ad: `NNN_NAME_Vnn.SQL` (BUYUK HARF)')
    [void]$sb.AppendLine('FAIL → o NNN''den devam — bashtan RUNALL YASAK')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| NNN | AD | V | RUN | Amac |')
    [void]$sb.AppendLine('|-----|----|---|-----|------|')
    foreach ($it in $map) {
        $run = if ($it.InRunAll) { 'Y' } else { '-' }
        [void]$sb.AppendLine("| $($it.Seq.ToString('000')) | $($it.Name) | V$($it.Ver) | $run | $($it.Amac) |")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('```text')
    [void]$sb.AppendLine('cd ...\MIGRATION_SCR_20260708\CTAS')
    [void]$sb.AppendLine('sqlplus user/pass@db @00_RUN_ALL.SQL')
    [void]$sb.AppendLine('```')
    return $sb.ToString()
}
