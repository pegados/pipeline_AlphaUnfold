#!/bin/bash
# ==============================================================================
# ORQUESTRADOR DE ANÁLISES DE DINÂMICA MOLECULAR (LINUX)
# VMD + Consolidação Estatística + RMSF
# ==============================================================================

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Uso: $0 <diretorio_raiz_namd>"
    exit 1
fi

ROOT_DIR=$(realpath "$1")
SCRIPT_TCL="$(dirname "$0")/analise_unificada.tcl"
VMD_BIN="vmd"

RMSF_DIR="$(pwd)/RMSF_MEDIO"
FINAL_TABLE="$(pwd)/RESULTADOS_RMSD_RoG_SASA.csv"

mkdir -p "$RMSF_DIR"

echo "==========================================================="
echo " ROOT      : $ROOT_DIR"
echo " TCL       : $SCRIPT_TCL"
echo " RMSF DIR  : $RMSF_DIR"
echo "==========================================================="

# Limpa arquivos antigos
find "$ROOT_DIR" -name "raw_stats.csv" -delete
find "$ROOT_DIR" -name "raw_rmsf.csv" -delete
find "$ROOT_DIR" -name "RESUMO.csv" -delete

# ============================================================
# 1. RODAR VMD PARA CADA SISTEMA
# ============================================================
find "$ROOT_DIR" -type d | while read pasta; do

    psf=$(find "$pasta" -name "*final.psf" | head -n 1)
    dcd=$(find "$pasta" -name "*.dcd" | head -n 1)
    nome=$(basename "$pasta")

    [[ -z "$psf" || -z "$dcd" ]] && continue

    echo ">>> Analisando: $nome"

    ( cd "$pasta" && \
      $VMD_BIN -dispdev text -e "$SCRIPT_TCL" -args "$psf" "$dcd" > /dev/null )

done

# ============================================================
# 2. CONSOLIDAÇÃO ESTATÍSTICA POR SISTEMA
# ============================================================
find "$ROOT_DIR" -name "raw_stats.csv" | while read csv; do
    pasta=$(dirname "$csv")
    modelo=$(basename "$pasta")

    awk -F';' '
    NR>1 && $3 ~ /^[0-9]/ {
        gsub(",", ".", $3)
        print $2 ";" $3
    }' "$csv" | awk -F';' '
    {
        soma[$1]+=$2
        soma2[$1]+=$2*$2
        n[$1]++
    }
    END {
        print "Modelo;Metrica;Valor_Final"
        for (m in soma) {
            avg=soma[m]/n[m]
            printf "%s;%s;%.4f\n","'"$modelo"'",m,avg
            printf "%s;%s_SD;%.4f\n","'"$modelo"'",m,sqrt((soma2[m]/n[m])-(avg*avg))
        }
    }' > "$pasta/RESUMO.csv"
done

# ============================================================
# 3. ORGANIZAÇÃO DOS RMSFs
# ============================================================
find "$ROOT_DIR" -name "raw_rmsf.csv" | while read rmsf; do
    pasta=$(dirname "$rmsf")
    modelo=$(basename "$pasta")
    mv "$rmsf" "$RMSF_DIR/${modelo}.csv"
done

# ============================================================
# 4. TABELA FINAL CONSOLIDADA
# ============================================================
echo "Metrica;$(find "$ROOT_DIR" -name RESUMO.csv | sed 's|.*/||;s|/RESUMO.csv||' | tr '\n' ';')" > "$FINAL_TABLE"

for met in RMSD RMSD_SD RoG RoG_SD SASA_Total SASA_Total_SD; do
    linha="$met"
    for r in $(find "$ROOT_DIR" -name RESUMO.csv); do
        val=$(grep ";$met;" "$r" | cut -d';' -f3)
        linha+=";${val:-N/A}"
    done
    echo "$linha" >> "$FINAL_TABLE"
done

echo "==========================================================="
echo " ANÁLISE CONCLUÍDA"
echo " RMSF     : $RMSF_DIR"
echo " TABELA   : $FINAL_TABLE"
echo "==========================================================="
