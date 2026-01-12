#!/bin/bash
set -euo pipefail

# ==============================================================================
# CONFIGURAÇÕES FIXAS
# ==============================================================================
AF_OUTPUT="/home/alphafold/outputs/pipelines_af/restante_pLDDT"
DIN_OUTPUT="/home/alphafold/prontos_dinamica/teste_pipeline/restante_pLDDT"

SCRIPT_FASTA="/home/alphafold/pipeline/trocas_blosum.py"
SCRIPT_AF="/home/alphafold/pipeline/alphafold3_array.sh"
SCRIPT_PREP="/home/alphafold/pipeline/prepara_dinamica.py"
SCRIPT_NAMD="/home/alphafold/pipeline/namd_array.sh"

PYTHON_BIN="/home/alphafold/bio_env/bin/python3"

BASE_FASTA_TMP="/home/alphafold/tmp_fastas"

# ==============================================================================
# FUNÇÕES
# ==============================================================================
erro() {
  echo "ERRO: $1"
  exit 1
}

contar_fastas() {
  ls "$1"/*.fasta 2>/dev/null | wc -l
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================
MODE="${1:-}"
[[ -z "$MODE" ]] && erro "Informe o modo: single | set | full"

CLEANUP_DIR=""

# ==============================================================================
# MODO SINGLE — 1 proteína
# ==============================================================================
if [[ "$MODE" == "single" ]]; then
  FASTA_BASE="${2:-}"
  [[ -f "$FASTA_BASE" ]] || erro "FASTA não encontrado"

  TS=$(date +%Y%m%d_%H%M%S)
  FASTAS_OUT="$BASE_FASTA_TMP/single_$TS"
  mkdir -p "$FASTAS_OUT"

  cp "$FASTA_BASE" "$FASTAS_OUT/00_single.fasta"

  CLEANUP_DIR="$FASTAS_OUT"

# ==============================================================================
# MODO SET — FASTAs já existentes
# ==============================================================================
elif [[ "$MODE" == "set" ]]; then
  FASTAS_OUT="${2:-}"
  [[ -d "$FASTAS_OUT" ]] || erro "Diretório de FASTAs não encontrado"

# ==============================================================================
# MODO FULL — mutantes + original
# ==============================================================================
elif [[ "$MODE" == "full" ]]; then
  FASTA_BASE="${2:-}"
  FASTAS_OUT="${3:-}"

  [[ -f "$FASTA_BASE" ]] || erro "FASTA base não encontrado"
  [[ -n "$FASTAS_OUT" ]] || erro "Informe diretório de saída"

  mkdir -p "$FASTAS_OUT"

  echo "==> [1/4] Gerando FASTAs (mutantes)"
  "$PYTHON_BIN" "$SCRIPT_FASTA" "$FASTA_BASE" "$FASTAS_OUT"

else
  erro "Modo inválido: $MODE"
fi

# ==============================================================================
# CONTAGEM
# ==============================================================================
N_FASTAS=$(contar_fastas "$FASTAS_OUT")
[[ "$N_FASTAS" -eq 0 ]] && erro "Nenhum FASTA encontrado"

ARRAY_RANGE="0-$((N_FASTAS - 1))"

echo "FASTAs detectados: $N_FASTAS"

# ==============================================================================
# ALPHAFOLD
# ==============================================================================
echo "==> [2/4] Submetendo AlphaFold"

AF_JOBID=$(sbatch --parsable \
  --array="$ARRAY_RANGE%1" \
  "$SCRIPT_AF" \
  "$FASTAS_OUT")

echo "AlphaFold JobID: $AF_JOBID"

# ==============================================================================
# PREPARAÇÃO
# ==============================================================================
echo "==> [3/4] Preparação para dinâmica"

PREP_JOBID=$(sbatch --parsable \
  --partition=filaA40 \
  --dependency=afterok:$AF_JOBID \
  --wrap="$PYTHON_BIN $SCRIPT_PREP $AF_OUTPUT")

echo "Preparação JobID: $PREP_JOBID"

# ==============================================================================
# NAMD
# ==============================================================================
echo "==> [4/4] Submetendo NAMD"

NAMD_JOBID=$(sbatch --parsable \
  --dependency=afterok:$PREP_JOBID \
  --array="$ARRAY_RANGE%2" \
  "$SCRIPT_NAMD" \
  "$DIN_OUTPUT")

echo "NAMD JobID: $NAMD_JOBID"

# ==============================================================================
# LIMPEZA AUTOMÁTICA (APENAS SINGLE)
# ==============================================================================
if [[ -n "$CLEANUP_DIR" ]]; then
  echo "==> Submetendo limpeza automática do workspace"

  sbatch \
    --dependency=afterok:$NAMD_JOBID \
    --wrap="rm -rf '$CLEANUP_DIR'"

  echo "Workspace temporário será removido após conclusão do NAMD"
fi

echo "==> PIPELINE SUBMETIDO COM SUCESSO"
