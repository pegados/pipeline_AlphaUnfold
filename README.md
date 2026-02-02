# **Pipeline AlphaUnfold**
### *Integração AlphaFold 3 + Dinâmica Molecular (NAMD3) + Análises Estruturais*

---

## **1. Visão Geral**

Este repositório contém um **pipeline computacional automatizado e reprodutível** para estudos estruturais e dinâmicos de proteínas, integrando as seguintes etapas:

1. Geração de mutantes a partir de uma sequência FASTA
2. Modelagem estrutural com **AlphaFold 3**
3. Preparação do sistema para dinâmica molecular:
   - protonação
   - geração de topologia
   - **geração da caixa de solvatação**
4. Execução de **dinâmica molecular com NAMD3**
5. Extração de métricas estruturais:
   - RMSD
   - RMSF
   - Raio de giro (RoG)
   - SASA
   - Poses finais (PDB)

O pipeline foi desenvolvido e validado em **ambiente HPC**, utilizando **SLURM**, **Apptainer** e nós com **GPU NVIDIA A40**.

---

## **2. Pré-requisitos**

### **2.1. Software necessário**

Antes de executar o pipeline, o ambiente deve possuir:

- **Linux**
- **SLURM**
- **Apptainer (ou Singularity)**
- **Python ≥ 3.9**
- **VMD**
- **NAMD3**
- **CUDA compatível com a GPU disponível**

---

### **2.2. Bases de dados do AlphaFold 3**

Os bancos de dados oficiais do AlphaFold 3 devem ser baixados previamente utilizando o script oficial da DeepMind:

```bash
wget https://raw.githubusercontent.com/google-deepmind/alphafold3/main/fetch_databases.sh
chmod +x fetch_databases.sh
./fetch_databases.sh /caminho/para/alphafold_databases
```

Referência oficial:
https://github.com/google-deepmind/alphafold3/blob/main/fetch_databases.sh

O diretório gerado deve ser configurado no script **alphafold3_array.sh**

### **2.3. Imagem Apptainer do AlphaFold 3**

É necessário possuir a imagem do AlphaFold 3 em formato Apptainer (.sif).

```bash
Link da imagem:
```

Exemplo de configuração:
```bash
CONTAINER="/home/alphafold/alphafold3.sif"
```

### **3. Observações Importantes sobre a Arquitetura**

Na arquitetura utilizada (Apptainer + nó único com GPU A40), foi observado que:

Executar mais de um job AlphaFold 3 simultaneamente no mesmo nó causou problemas nos outputs

Foram observados arquivos .cif ausentes ou incompletos

### **3.1. Configuração recomendada**

```bash
--array=0-14%1
```
Ou seja, apenas um job AlphaFold por vez por nó.

### **3.2. Execução paralela (experimental)**

Usuários avançados podem tentar:

```bash
export XLA_CLIENT_MEM_FRACTION=0.6
export XLA_PYTHON_CLIENT_PREALLOCATE=false
```

## **4. Ajustes Obrigatórios nos Arquivos**
### **4.1. pipeline.sh e pipeline-MODOS.sh**

Ajustar os caminhos principais:

```bash
FASTA_BASE="/home/alphafold/entrada/proteina.fasta"
FASTAS_OUT="/home/alphafold/inputs_array"
AF_OUTPUT="/home/alphafold/outputs/pipelines_af"
DIN_OUTPUT="/home/alphafold/prontos_dinamica"

```

### 4.2. `alphafold3_array.sh`

Ajustar os caminhos do AlphaFold:
```bash
INPUT_DIR="/home/alphafold/inputs"
OUTPUT_DIR="/home/alphafold/outputs/pipelines_af"
CONTAINER="/home/alphafold/alphafold3.sif"
MODEL_DIR="/home/alphafold/alphafold3/models"
DB_DIR="/home/alphafold/public_databases"
```

Dentro do container, o script principal está localizado em:
```bash
/app/alphafold/run_alphafold.py
```
Se necessário:
```bash
ALPHAFOLD_SCRIPT="/app/alphafold/run_alphafold.py"
```
### **4.3. `prepara_dinamica.py`**

Ajustar:

```bash
DESTINO_FINAL = "/home/alphafold/prontos_dinamica"
TOPOLOGIA = "/programs/vmd/plugins/top_all36_prot.rtf"
CONF_TEMPLATE = "/home/alphafold/pipeline/arq.conf"
VMD_EXEC = "/programs/vmd/bin/vmd"

```
### 4.4. `namd_array.sh`

Ajustar o binário do NAMD:
```bash
NAMD_BIN="namd3"
```
### **4.5. Arquivo `.conf` molde do NAMD3**

O pipeline utiliza um **arquivo de configuração do NAMD3 como molde**, que é automaticamente copiado e editado para cada sistema durante a etapa de preparação da dinâmica (`prepara_dinamica.py`).

Este arquivo define os **parâmetros físicos**, **topologias**, **potenciais** e **condições de contorno** da simulação.

#### **4.5.1. Topologias e parâmetros**

É obrigatório ajustar, no arquivo `.conf` molde, os caminhos para as topologias e parâmetros utilizados pelo NAMD3.  
Exemplo:

```tcl
# Topologias e parâmetros CHARMM
parameters          /home/alphafold/namd_parameters/par_all36_prot.prm
parameters          /home/alphafold/namd_parameters/par_all36_na.prm
parameters          /home/alphafold/namd_parameters/toppar_water_ions.str

```

#### 4.5.1. Requisitos de Arquivos
Esses arquivos devem existir no sistema e ser compatíveis com:
* A topologia utilizada no **VMD** (`top_all36_prot.rtf`)
* O modelo de água selecionado
* A ionização aplicada ($Na^+$ / $Cl^-$)

#### 4.5.2. Estrutura e Coordenadas
As linhas abaixo não precisam ser editadas manualmente, pois são substituídas automaticamente pelo pipeline para cada sistema:

```tcl
structure           CAMINHO/DO/ARQUIVO.psf
coordinates         CAMINHO/DO/ARQUIVO.pdb
Nota: Durante a preparação, o script prepara_dinamica.py ajusta esses campos para apontar para os arquivos finais de cada proteína.

```
#### 4.5.3. Condições Periódicas de Contorno (PBC)
As dimensões da caixa de solvatação e a origem da célula periódica também são calculadas automaticamente a partir do PDB final:

```Tcl

cellBasisVector1    X 0 0
cellBasisVector2    0 Y 0
cellBasisVector3    0 0 Z
cellOrigin          Xc Yc Zc

```
Esses valores são obtidos diretamente das coordenadas atômicas, garantindo consistência entre a solvatação e a dinâmica.

#### 4.5.4. Tempo de Simulação e Condições Termodinâmicas
O tempo total da simulação é controlado pelo número de passos (run) e pelo timestep.

Exemplo:

```Tcl

timestep            2.0
run                 2500000   ;# ~5 ns
Para simulações mais longas, esse valor pode ser ajustado conforme necessário.
```
A pressão e temperatura são controladas via:

```Tcl

langevin            on
langevinTemp        310

langevinPiston      on
langevinPistonTarget 1.01325   ;# 1 atm (ajustado conforme padrão NAMD)

```
#### 4.5.5. Importância do Arquivo .conf Molde
O arquivo .conf molde define o comportamento físico da simulação. Antes de executar o pipeline em produção, recomenda-se:

- Revisar cuidadosamente as topologias e parâmetros.

- Garantir compatibilidade com as versões do VMD e NAMD instaladas.

- Validar o arquivo com uma simulação curta de teste.

### 4.6. Configurações do SLURM

Todos os scripts .sh possuem diretivas #SBATCH.
É necessário ajustar:
```bash
#SBATCH --partition=filaA40
#SBATCH --cpus-per-task=16
#SBATCH --time=24:00:00
```
## 5. Execução do Pipeline
#### 5.1. Pipeline Padrão (pipeline.sh)

Executa:

- proteína selvagem
- 14 mutantes
- AlphaFold 3
- preparação
- dinâmica molecular

```bash
chmod +x pipeline.sh
./pipeline.sh
```

## 6. Pipeline com Modos (pipeline-MODOS.sh)
### 6.1. Modo `single`

Executa apenas uma proteína:
```bash
./pipeline-MODOS.sh single caminho/proteina.fasta
```

### 6.2 Modo `set`
Executa um conjunto de FASTAs já existentes:
```bash
./pipeline-MODOS.sh set caminho/diretorio_fastas
```
### 6.3 Modo `full`
Executa o pipeline completo (selvagem + mutantes):
```bash
./pipeline-MODOS.sh full caminho/proteina_base.fasta
```

## 7. Scripts de Análise de Métricas
### 7.1. Linux

Análises estatísticas consolidadas:
```bash
./analise_unificada.sh /diretorio_dinamicas

```

### 7.2. Windows

Versões equivalentes em PowerShell (`.ps1`) estão disponíveis para análise local.

## 8. Considerações Finais

- Pipeline projetado para robustez em HPC
- Execução totalmente automatizada
- Separação clara entre modelagem, dinâmica e análise
- Facilmente extensível para novos mutantes ou métricas

## 9. Recomendações

- Testar inicialmente com modo single
- Validar paths e permissões
- Confirmar versões do VMD e NAMD
- Monitorar uso de GPU com nvidia-smi
