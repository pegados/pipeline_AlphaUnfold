# ======================================================================
# ORQUESTRADOR DE ANÁLISES DE DINÂMICA MOLECULAR
# FUNÇÃO: Automação VMD -> Organização de Dados -> Tabela Final
# ======================================================================

$scriptTcl = "analise_unificada.tcl"
$vmdPath = "& 'C:\Program Files (x86)\University of Illinois\VMD\vmd.exe'"

# 1. Criar pasta centralizada para os arquivos de RMSF
$diretorioRMSF = Join-Path $PSScriptRoot "RMSF_MEDIO"
if (!(Test-Path $diretorioRMSF)) { 
    New-Item -ItemType Directory -Path $diretorioRMSF | Out-Null 
}

$pastasModelos = Get-ChildItem -Directory

foreach ($pastaObj in $pastasModelos) {
    $pasta = $pastaObj.FullName
    $nome = $pastaObj.Name 
    
    if ($nome -eq "RMSF_MEDIO") { continue }

    $psf = Get-ChildItem -Path $pasta -Filter "*final.psf" | Select-Object -First 1
    $arquivosDcd = Get-ChildItem -Path $pasta -Recurse -Filter *.dcd
    
    if ($psf -and $arquivosDcd) {
        foreach ($dcd in $arquivosDcd) {
            Write-Host "Analisando ID: $nome" -ForegroundColor Cyan
            # O TCL gera "raw_stats.csv" e "raw_rmsf.csv"
            Invoke-Expression "$vmdPath -dispdev text -e $scriptTcl -args `"$($psf.FullName)`" `"$($dcd.FullName)`""
        }
    }

    # 2. Consolidação do Resumo (Ajustado para procurar "raw_stats.csv")
    $csvsEstatistica = Get-ChildItem -Path $pasta -Recurse -Filter "raw_stats.csv"
    if ($csvsEstatistica) {
        $acumulador = @()
        foreach ($c in $csvsEstatistica) {
            $linhas = Import-Csv -Path $c.FullName -Delimiter ";"
            foreach ($l in $linhas) {
                $valNum = $l.Valor -replace ',', '.'
                if ([double]::TryParse($valNum, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]0)) { 
                    $acumulador += [PSCustomObject]@{ Metrica = $l.Metrica; Valor = [double]$valNum } 
                }
            }
        }
        
        $resumoPath = Join-Path $pasta "RESUMO.csv"
        if ($acumulador.Count -gt 0) {
            $acumulador | Group-Object Metrica | ForEach-Object {
                $media = ($_.Group.Valor | Measure-Object -Average).Average
                [PSCustomObject]@{ 
                    Modelo = $nome; 
                    Metrica = $_.Name; 
                    Valor_Final = ([math]::Round($media, 4)).ToString().Replace('.', ',')
                }
            } | Export-Csv -Path $resumoPath -NoTypeInformation -Delimiter ";" -Encoding UTF8
        }
    }

    # 3. Organização do RMSF (Ajustado para procurar "raw_rmsf.csv")
    $arquivosRMSF = Get-ChildItem -Path $pasta -Recurse -Filter "raw_rmsf.csv"
    foreach ($file in $arquivosRMSF) {
        $novoNome = "$nome.csv"
        Move-Item -Path $file.FullName -Destination (Join-Path $diretorioRMSF $novoNome) -Force
    }

    # Limpeza de temporários
    Get-ChildItem -Path $pasta -Recurse -Include "raw_stats.csv" | Remove-Item -Force
}

# 4. Gerar Tabela Final Consolidada
$todosResumos = Get-ChildItem -Recurse -Filter "RESUMO.csv"
if ($todosResumos) {
    $dadosFinais = foreach ($r in $todosResumos) { Import-Csv -Path $r.FullName -Delimiter ";" }
    $modelosBrutos = $dadosFinais.Modelo | Select-Object -Unique
    $metricas = @("RMSD", "RMSD_SD", "RoG", "RoG_SD", "SASA_Total", "SASA_Total_SD")

    $tabelaFinal = foreach ($m in $metricas) {
        $row = [ordered]@{ "Metrica" = $m }
        foreach ($mod in $modelosBrutos) {
            $item = $dadosFinais | Where-Object { $_.Modelo -eq $mod -and $_.Metrica -eq $m }
            $valor = if ($item) { $item.Valor_Final } else { "N/A" }
            $row.Add($mod.ToUpper(), $valor)
        }
        [PSCustomObject]$row
    }
    $tabelaFinal | Export-Csv -Path "RESULTADOS_RMSD_RoG_SASA.csv" -NoTypeInformation -Delimiter ";" -Encoding UTF8
}

Write-Host "Processo concluído! RMSFs em: RMSF_MEDIO" -ForegroundColor Green