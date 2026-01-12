#!/bin/bash
#SBATCH --job-name=namd_array
#SBATCH --partition=filaA40
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=24:00:00
#SBATCH --output=/home/alphafold/logs/namd_%A_%a.out
#SBATCH --error=/home/alphafold/logs/namd_%A_%a.err

set -euo pipefail

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
BASE_DIR="$1"   # diretório com as pastas geradas pelo pipeline Python
NAMD_BIN="namd3"  # ou caminho absoluto se necessário

[[ -z "$BASE_DIR" ]] && { echo "Uso: sbatch --array=0-N namd_array.sh /dir_namd"; exit 1; }
[[ ! -d "$BASE_DIR" ]] && { echo "Erro: diretório inválido"; exit 2; }

# ==============================================================================
# SELEÇÃO DO JOB PELO ARRAY
# ==============================================================================
JOBS=($(ls -d "$BASE_DIR"/*/))
JOB_DIR="${JOBS[$SLURM_ARRAY_TASK_ID]}"

[[ -z "$JOB_DIR" ]] && { echo "Job não encontrado"; exit 3; }

JOB_NAME=$(basename "$JOB_DIR")

CONF_FILE=$(ls "$JOB_DIR"/*_min.conf 2>/dev/null | head -n 1)

[[ ! -f "$CONF_FILE" ]] && { echo "Arquivo .conf não encontrado em $JOB_DIR"; exit 4; }

echo "[$SLURM_JOB_ID/$SLURM_ARRAY_TASK_ID] Rodando NAMD em: $JOB_NAME"
echo "Config: $CONF_FILE"

# ==============================================================================
# EXECUÇÃO DO NAMD
# ==============================================================================
cd "$JOB_DIR"

srun "$NAMD_BIN" +p"$SLURM_CPUS_PER_TASK" "$CONF_FILE"
