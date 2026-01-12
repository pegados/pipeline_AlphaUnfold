#!/bin/bash

# ==============================================================================
# VARREDURA DE ANÁLISES NAMD CONSOLIDADA
# ==============================================================================

if [ $# -ne 1 ]; then
    echo "Uso: $0 <diretorio_raiz_namd>"
    exit 1
fi

ROOT_DIR=$(realpath "$1")
SCRIPT_TCL="$(dirname "$0")/analises_20.tcl"
CSV_FINAL="$(pwd)/analises_consolidadas_formatado.csv"

# Cabeçalho limpo (5 métricas + nome)
echo "Proteina;RMSD;Raio_Giro;SASA_Global;SASA_Hidro;Desvio_Padrao_SASA" > "$CSV_FINAL"

echo "==========================================================="
echo " DIRETÓRIO : $ROOT_DIR"
echo " SAÍDA     : $CSV_FINAL"
echo "==========================================================="

find "$ROOT_DIR" -name "*.psf" | while read psf_path; do

    PASTA_MAE=$(dirname "$psf_path")
    PROTEINA=$(basename "$PASTA_MAE")

    # Pega o primeiro DCD encontrado na pasta
    find "$PASTA_MAE" -name "*.dcd" | head -n 1 | while read dcd_path; do
        
        echo ">>> PROCESSANDO: $PROTEINA"
        rm -f metrics_temp.csv

        # Roda o VMD (Silencioso no terminal, escreve metrics_temp.csv)
        vmd -dispdev text -e "$SCRIPT_TCL" -args "$psf_path" "$dcd_path" > /dev/null

        if [ -f "metrics_temp.csv" ]; then
            # Extração dos valores e troca de ponto por vírgula
            RMSD=$(grep "RMSD" metrics_temp.csv | cut -d',' -f2 | tr '.' ',')
            RGYR=$(grep "Raio_Giro" metrics_temp.csv | cut -d',' -f2 | tr '.' ',')
            SASA_G=$(grep "SASA_Global" metrics_temp.csv | cut -d',' -f2 | tr '.' ',')
            SASA_H=$(grep "SASA_Hidro" metrics_temp.csv | cut -d',' -f2 | tr '.' ',')
            SD_SASA=$(grep "Desvio_Padrao" metrics_temp.csv | cut -d',' -f2 | tr '.' ',')

            # Escreve a linha final
            echo "${PROTEINA};${RMSD};${RGYR};${SASA_G};${SASA_H};${SD_SASA}" >> "$CSV_FINAL"
            
            rm metrics_temp.csv
            echo "    [OK] Dados extraídos."
        else
            echo "    [ERRO] VMD não gerou saída para $PROTEINA"
        fi
    done
done

echo ""
echo "==========================================================="
echo " CONCLUÍDO."
