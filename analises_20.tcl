# ==============================================================================
# Script TCL para VMD: RMSD, Raio de Giro e SASA
# Calcula média e desvio padrão dos últimos 20% da trajetória
# ==============================================================================

# 1. Carregar Arquivos
set psf_file [lindex $argv 0]
set dcd_file [lindex $argv 1]

mol new $psf_file type psf
mol addfile $dcd_file type dcd waitfor all

# 2. Definição de Seleções e Frames
set sel_total [atomselect top "protein"]
set sel_backbone [atomselect top "protein and backbone"]
# Resíduos hidrofóbicos padrão
set sel_hidro [atomselect top "protein and (resname ALA VAL LEU ILE MET PHE TRP PRO)"]

# Referência para RMSD (Frame 0)
set ref [atomselect top "protein and backbone" frame 0]

set num_frames [molinfo top get numframes]
set n_analise [expr int($num_frames / 5)]
set start_frame [expr $num_frames - $n_analise]

# Listas para armazenar valores
set val_rmsd {}
set val_rgyr {}
set val_sasa_glob {}
set val_sasa_hidro {}

# 3. Loop de Processamento (Apenas últimos 20%)
for {set i $start_frame} {$i < $num_frames} {incr i} {
    $sel_total frame $i
    $sel_backbone frame $i
    $sel_hidro frame $i
    
    $sel_total update
    $sel_backbone update

    # --- A. RMSD (Com alinhamento prévio) ---
    set trans_mat [measure fit $sel_backbone $ref]
    $sel_total move $trans_mat
    lappend val_rmsd [measure rmsd $sel_backbone $ref]

    # --- B. Raio de Giro ---
    lappend val_rgyr [measure rgyr $sel_total]

    # --- C. SASA Global ---
    lappend val_sasa_glob [measure sasa 1.4 $sel_total]

    # --- D. SASA Hidrofóbica ---
    # Superfície total, restrita aos átomos hidrofóbicos
    lappend val_sasa_hidro [measure sasa 1.4 $sel_total -restrict $sel_hidro]
}

# 4. Função Estatística
proc calc_stats {data_list} {
    set n [llength $data_list]
    if {$n == 0} { return "0.0 0.0" }
    
    set sum 0
    set sum_sq 0

    foreach val $data_list {
        set sum [expr $sum + $val]
        set sum_sq [expr $sum_sq + ($val * $val)]
    }

    set mean [expr $sum / $n]
    set variance [expr ($sum_sq / $n) - ($mean * $mean)]
    if {$variance < 0} { set variance 0 }
    set stdev [expr sqrt($variance)]

    return [list $mean $stdev]
}

# 5. Cálculos Finais
set stats_rmsd [calc_stats $val_rmsd]
set stats_rgyr [calc_stats $val_rgyr]
set stats_sasa_g [calc_stats $val_sasa_glob]
set stats_sasa_h [calc_stats $val_sasa_hidro]

# Extração (Média)
set mean_rmsd [lindex $stats_rmsd 0]
set mean_rgyr [lindex $stats_rgyr 0]
set mean_sasa_g [lindex $stats_sasa_g 0]
set mean_sasa_h [lindex $stats_sasa_h 0]

# Extração (Desvio Padrão do SASA Global)
set sd_sasa_g [lindex $stats_sasa_g 1]

# 6. Saída CSV Temporária
set outfile [open "metrics_temp.csv" w]
puts $outfile "Metric,Value"
puts $outfile "RMSD,$mean_rmsd"
puts $outfile "Raio_Giro,$mean_rgyr"
puts $outfile "SASA_Global,$mean_sasa_g"
puts $outfile "SASA_Hidro,$mean_sasa_h"
puts $outfile "Desvio_Padrao,$sd_sasa_g"
close $outfile

exit
