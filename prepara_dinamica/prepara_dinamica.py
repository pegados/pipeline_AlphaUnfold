import subprocess
import os
import sys
import re
import shutil
import glob
import time

# =============================================================================
# CONFIGURAÇÕES
# =============================================================================
PH_PADRAO = 7.0

DESTINO_FINAL = "/home/alphafold/prontos_dinamica/phaseolin01"

TOPOLOGIA = "/programs/vmd-2.0.0a7/plugins/noarch/tcl/readcharmmtop1.2/top_all36_prot.rtf"

CONF_TEMPLATE = "/home/alphafold/pipeline/03-prepara_dinamica/arq.conf"

VMD_EXEC = "vmd"   # assume no PATH

# =============================================================================
# UTILIDADES
# =============================================================================
def instalar_dependencias():
    try:
        import Bio
        import pdb2pqr
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "biopython", "pdb2pqr"]
        )

def ordenacao_natural(texto):
    partes = re.split(r'(\d+)', texto)
    chave = []
    for p in partes:
        if p.isdigit():
            chave.append((0, int(p)))
        else:
            chave.append((1, p.lower()))
    return chave


def calcular_pbc(pdb_path):
    xs, ys, zs = [], [], []
    with open(pdb_path) as f:
        for l in f:
            if l.startswith(("ATOM", "HETATM")):
                xs.append(float(l[30:38]))
                ys.append(float(l[38:46]))
                zs.append(float(l[46:54]))

    if not xs:
        return (80, 80, 80), (0, 0, 0)

    dim = (
        max(xs) - min(xs) + 4.0,
        max(ys) - min(ys) + 4.0,
        max(zs) - min(zs) + 4.0
    )
    cen = (
        (max(xs) + min(xs)) / 2,
        (max(ys) + min(ys)) / 2,
        (max(zs) + min(zs)) / 2
    )
    return dim, cen

# =============================================================================
# ETAPA 1 – CIF → PDB
# =============================================================================
def converter_cif_para_pdb(cif_file):
    from Bio import PDB
    pdb_file = cif_file.replace(".cif", ".pdb")

    if os.path.exists(pdb_file):
        return pdb_file

    parser = PDB.MMCIFParser(QUIET=True)
    structure = parser.get_structure("protein", cif_file)
    io = PDB.PDBIO()
    io.set_structure(structure)
    io.save(pdb_file)
    return pdb_file

# =============================================================================
# ETAPA 2 – PROTONAÇÃO
# =============================================================================
def protonar_proteina(input_pdb, ph):
    base = os.path.splitext(input_pdb)[0]
    out_pqr = f"{base}_ph{ph}.pqr"
    out_pdb = f"{base}_ph{ph}.pdb"

    cmd = [
        sys.executable, "-m", "pdb2pqr",
        "--ff", "CHARMM",
        "--with-ph", str(ph),
        "--titration-state-method", "propka",
        "--pdb-output", out_pdb,
        input_pdb,
        out_pqr
    ]

    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)

    return out_pdb

# =============================================================================
# ETAPA 3 – VMD (PSF + SOLVATAÇÃO + ÍONS)
# =============================================================================
def gerar_sistema_vmd(job_dir, job_id, pdb_prot):
    tcl = f"""
package require psfgen
topology "{TOPOLOGIA}"

pdbalias residue HIS HSD
pdbalias atom ILE CD1 CD

segment U {{
    pdb "{os.path.basename(pdb_prot)}"
    first NTER
    last CTER
    auto angles dihedrals
}}

coordpdb "{os.path.basename(pdb_prot)}" U
guesscoord

writepsf {job_id}_base.psf
writepdb {job_id}_base.pdb

package require solvate
solvate {job_id}_base.psf {job_id}_base.pdb -t 12.0 -o {job_id}_solv

package require autoionize
autoionize -psf {job_id}_solv.psf -pdb {job_id}_solv.pdb -sc 0.15 -o {job_id}_final

exit
"""

    tcl_path = os.path.join(job_dir, "run_vmd.tcl")
    with open(tcl_path, "w") as f:
        f.write(tcl)

    subprocess.run(
        [VMD_EXEC, "-dispdev", "text", "-e", tcl_path],
        cwd=job_dir,
        capture_output=True
    )

# =============================================================================
# ETAPA 4 – GERAR .CONF
# =============================================================================
def gerar_conf(job_dir, job_id, pdb_final, psf_final):
    dim, cen = calcular_pbc(pdb_final)

    with open(CONF_TEMPLATE) as f:
        linhas = f.readlines()

    novas = []
    for l in linhas:
        if l.strip().startswith("structure"):
            novas.append(f"structure          {psf_final}\n")
        elif l.strip().startswith("coordinates"):
            novas.append(f"coordinates        {pdb_final}\n")
        elif "set outputname" in l:
            novas.append(f"set outputname     {job_dir}/output/{job_id}_min\n")
        elif "cellBasisVector1" in l:
            novas.append(f"cellBasisVector1 {dim[0]:.3f} 0 0\n")
        elif "cellBasisVector2" in l:
            novas.append(f"cellBasisVector2 0 {dim[1]:.3f} 0\n")
        elif "cellBasisVector3" in l:
            novas.append(f"cellBasisVector3 0 0 {dim[2]:.3f}\n")
        elif "cellOrigin" in l:
            novas.append(f"cellOrigin {cen[0]:.3f} {cen[1]:.3f} {cen[2]:.3f}\n")
        else:
            novas.append(l)

    conf_final = os.path.join(job_dir, f"{job_id}_min.conf")
    with open(conf_final, "w") as f:
        f.writelines(novas)

# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":

    if len(sys.argv) < 2:
        raiz = input("Diretório com outputs do AlphaFold: ").strip('"')
    else:
        raiz = sys.argv[1]

    instalar_dependencias()
    os.makedirs(DESTINO_FINAL, exist_ok=True)

    jobs = sorted(
        [d for d in os.listdir(raiz) if os.path.isdir(os.path.join(raiz, d))],
        key=ordenacao_natural
    )

    print(f"\nProcessando {len(jobs)} jobs\n")

    for job in jobs:
        job_dir = os.path.join(DESTINO_FINAL, job)
        os.makedirs(job_dir, exist_ok=True)
        os.makedirs(os.path.join(job_dir, "output"), exist_ok=True)

        cif = glob.glob(os.path.join(raiz, job, "**/*.cif"), recursive=True)
        if not cif:
            print(f"[-] {job}: CIF não encontrado")
            continue

        try:
            print(f"[+] {job}: pipeline iniciado")

            pdb = converter_cif_para_pdb(cif[0])
            pdb_prot = protonar_proteina(pdb, PH_PADRAO)

            shutil.copy2(pdb_prot, job_dir)

            pdb_job = os.path.join(job_dir, os.path.basename(pdb_prot))
            gerar_sistema_vmd(job_dir, job, pdb_job)

            pdb_final = os.path.join(job_dir, f"{job}_final.pdb")
            psf_final = os.path.join(job_dir, f"{job}_final.psf")

            gerar_conf(job_dir, job, pdb_final, psf_final)

            print(f"    ✓ {job} pronto")

        except Exception as e:
            print(f"    ✗ ERRO em {job}: {e}")

    print("\n--- PREPARAÇÃO PARA MODELAGEM FINALIZADA ---")
