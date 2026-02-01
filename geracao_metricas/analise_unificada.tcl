# ==========================================================================
# SCRIPT UNIFICADO DE ANÁLISE ESTRUTURAL (VMD)
# Integra: RMSD, RoG, SASA Total e RMSF
# ==========================================================================

set psf_file [lindex $argv 0]
set dcd_file [lindex $argv 1]
set pasta_origem [file dirname [file normalize $dcd_file]]

cd $pasta_origem

# Nomes simplificados para evitar nomes gigantescos
set out_stats "raw_stats.csv"
set out_rmsf  "raw_rmsf.csv"

# 1. Carregamento da Trajetória
mol new $psf_file type psf
mol addfile $dcd_file type dcd waitfor all

set total_frames [molinfo top get numframes]
set frames_esperados 250
set srad 1.4

# Filtro de integridade
if { $total_frames < $frames_esperados } {
    set outfile [open $out_stats w]
    puts $outfile "Arquivo;Metrica;Valor"
    puts $outfile "SISTEMA;STATUS;INCOMPLETO"
    close $outfile
    exit
}

# 2. Definições de Janela
set start_frame [expr int($total_frames * 0.8)]
set sel_ca [atomselect top "protein and name CA"]
set ref_ca [atomselect top "protein and name CA" frame 0]
set sel_prot [atomselect top "protein and noh"]

# 3. Processamento de Médias
set l_rmsd {}; set l_rog {}; set l_sasa_t {}

for {set i $start_frame} {$i < $total_frames} {incr i} {
    $sel_ca frame $i
    $sel_prot frame $i
    $sel_prot move [measure fit $sel_ca $ref_ca]
    
    lappend l_rmsd [measure rmsd $sel_ca $ref_ca]
    lappend l_rog [measure rgyr $sel_prot]
    lappend l_sasa_t [measure sasa $srad $sel_prot]
}

# 4. Função de Estatísticas
proc get_stats {data_list} {
    set sum 0
    foreach x $data_list { set sum [expr $sum + $x] }
    set avg [expr $sum / double([llength $data_list])]
    set sq_sum 0
    foreach x $data_list { set sq_sum [expr $sq_sum + pow($x - $avg, 2)] }
    set stdev [expr sqrt($sq_sum / double([llength $data_list]))]
    return [list $avg $stdev]
}

set outfile [open $out_stats w]
puts $outfile "Arquivo;Metrica;Valor"
foreach m {rmsd rog sasa_t} label {RMSD RoG SASA_Total} {
    set stats [get_stats [set l_$m]]
    puts $outfile "SISTEMA;$label;[lindex $stats 0]"
    puts $outfile "SISTEMA;${label}_SD;[lindex $stats 1]"
}
close $outfile

# 5. Cálculo de RMSF
set rmsf_values [measure rmsf $sel_ca first $start_frame last [expr $total_frames - 1] step 1]
set resids_rmsf [$sel_ca get resid]
set f_rmsf [open $out_rmsf w]
puts $f_rmsf "Residuo;RMSF"

foreach r $resids_rmsf v $rmsf_values { 
    # Converte o ponto decimal para vírgula antes de escrever no arquivo
    set v_virgula [string map {. ,} $v]
    puts $f_rmsf "$r;$v_virgula" 
}
close $f_rmsf

exit
