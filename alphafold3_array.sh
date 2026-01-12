#!/bin/bash
#SBATCH --job-name=alphafold3_array
#SBATCH --partition=filaA40
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=24:00:00
#SBATCH --output=/home/alphafold/logs/af_%A_%a.out
#SBATCH --error=/home/alphafold/logs/af_%A_%a.err

set -euo pipefail

# ==============================================================================
# CONFIGURAÇÃO GERAL
# ==============================================================================
FASTA_DIR="$1"

INPUT_DIR="/home/alphafold/inputs"
OUTPUT_DIR="/home/alphafold/outputs/pipelines_af/restante_pLDDT"

CONTAINER="/home/alphafold/alphafold3.sif"
MODEL_DIR="/home/alphafold/alphafold3/models"
DB_DIR="/home/alphafold/public_databases"
ALPHAFOLD_SCRIPT="/home/alphafold/alphafold3/run_alphafold.py"

[[ -z "$FASTA_DIR" ]] && { echo "Uso: sbatch --array=0-N%1 $0 /dir_fastas"; exit 1; }
[[ ! -d "$FASTA_DIR" ]] && { echo "Diretório FASTA inválido"; exit 2; }

mkdir -p "$INPUT_DIR"

# ==============================================================================
# SELEÇÃO DO FASTA PELO ARRAY (ORDEM ESTÁVEL)
# ==============================================================================
mapfile -t FASTAS < <(ls "$FASTA_DIR"/*.fasta | sort)
FASTA="${FASTAS[$SLURM_ARRAY_TASK_ID]}"

[[ -z "${FASTA:-}" ]] && { echo "FASTA não encontrado"; exit 3; }

FASTA_BASENAME=$(basename "$FASTA")
FASTA_NAME="${FASTA_BASENAME%.*}"

echo "[$SLURM_JOB_ID/$SLURM_ARRAY_TASK_ID] Processando: $FASTA_BASENAME"

# ==============================================================================
# BOAS PRÁTICAS JAX
# ==============================================================================
export XLA_CLIENT_MEM_FRACTION=0.75
export XLA_PYTHON_CLIENT_PREALLOCATE=false

# ==============================================================================
# PREPARAÇÃO DE DIRETÓRIOS
# ==============================================================================
JOB_ID="${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
JOB_OUTPUT_DIR="$OUTPUT_DIR/${JOB_ID}_${FASTA_NAME}"
mkdir -p "$JOB_OUTPUT_DIR"

# ==============================================================================
# FASTA → JSON (AlphaFold 3)
# ==============================================================================
SEQ=$(grep -v "^>" "$FASTA" \
  | tr -d '\n\r ' \
  | tr '[:lower:]' '[:upper:]' \
  | sed 's/[^ACDEFGHIKLMNPQRSTVWY]//g')

[[ -z "$SEQ" ]] && { echo "FASTA inválido"; exit 4; }

INPUT_JSON="${JOB_ID}_${FASTA_NAME}.json"
JSON_PATH="$INPUT_DIR/$INPUT_JSON"

cat <<EOF > "$JSON_PATH"
{
  "name": "$FASTA_NAME",
  "sequences": [
    {
      "protein": {
        "id": "A",
        "sequence": "$SEQ"
      }
    }
  ],
  "modelSeeds": [1],
  "dialect": "alphafold3",
  "version": 1
}
EOF

# ==============================================================================
# DETECÇÃO DE GPU
# ==============================================================================
APPTAINER_GPU_FLAG=""
EXECUTION_MODE="CPU"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  APPTAINER_GPU_FLAG="--nv"
  EXECUTION_MODE="GPU"
fi

echo "Modo de execução: $EXECUTION_MODE"

# ==============================================================================
# EXECUÇÃO DO ALPHAFOLD 3
# ==============================================================================
START_TIME=$(date +%s)

apptainer exec \
  $APPTAINER_GPU_FLAG \
  --bind "$INPUT_DIR:/data/input" \
  --bind "$JOB_OUTPUT_DIR:/data/output" \
  --env OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK" \
  "$CONTAINER" \
  python "$ALPHAFOLD_SCRIPT" \
    --json_path="/data/input/$INPUT_JSON" \
    --output_dir="/data/output" \
    --model_dir="$MODEL_DIR" \
    --db_dir="$DB_DIR"

EXIT_CODE=$?

# ==============================================================================
# LOG FINAL
# ==============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Job ID: $JOB_ID"
echo "FASTA: $FASTA_NAME"
echo "Sequência (aa): ${#SEQ}"
echo "Tempo total: ${DURATION}s"
echo "Status: $([ $EXIT_CODE -eq 0 ] && echo SUCCESS || echo FAILED)"

exit $EXIT_CODE
