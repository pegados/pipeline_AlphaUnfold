#!/bin/bash
set -euo pipefail

# ==============================================================================
# CONFIGURAÇÃO GERAL DO PIPELINE
# ==============================================================================
FASTA_BASE="$1"
FASTAS_OUT="$2"
AF_OUTPUT="/home/alphafold/outputs/pipelines_af"
DIN_OUTPUT="/home/alphafold/prontos_dinamica/teste_pipeline"

SCRIPT_FASTA="/home/alphafold/pipeline/trocas_blosum.py"
SCRIPT_AF="/home/alphafold/pipeline/alphafold3_array.sh"
SCRIPT_PREP="/home/alphafold/pipeline/prepara_dinamica.py"
SCRIPT_NAMD="/home/alphafold/pipeline/namd_array.sh"

# ==============================================================================
# 1. GERA FASTAs (14 proteínas)
# ==============================================================================
echo "==> [1/4] Gerando FASTAs"
python3 "$SCRIPT_FASTA" \
  "$FASTA_BASE" \
  "$FASTAS_OUT" \

# ==============================================================================
# 2. ALPHAFOLD (array serializado)
# ==============================================================================
echo "==> [2/4] Submetendo AlphaFold"

AF_JOBID=$(sbatch --parsable \
  --array=0-1%1 \
  "$SCRIPT_AF" \
  "$FASTAS_OUT")

echo "AlphaFold JobID: $AF_JOBID"

# ==============================================================================
# 3. PREPARAÇÃO PARA DINÂMICA (afterok)
# ==============================================================================
echo "==> [3/4] Preparação para dinâmica"

PREP_JOBID=$(sbatch --parsable \
  --partition=filaA40 \
  --dependency=afterok:$AF_JOBID \
  --wrap="/home/alphafold/bio_env/bin/python3 $SCRIPT_PREP $AF_OUTPUT")

echo "Preparação JobID: $PREP_JOBID"

# ==============================================================================
# 4. NAMD (array paralelo)
# ==============================================================================
echo "==> [4/4] Submetendo NAMD"

sbatch \
  --dependency=afterok:$PREP_JOBID \
  --array=0-1%2 \
  "$SCRIPT_NAMD" \
  "$DIN_OUTPUT"

echo "==> PIPELINE COMPLETO SUBMETIDO COM SUCESSO"
