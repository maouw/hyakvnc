#!/usr/bin/env bash
set -o pipefail
function m_slurm_list() {
	squeue "$@"
}
  
function m_slurm_stop() { 
	scancel "$@"
}
    
function m_slurm_start() {  
	sbatch "$@"
}

declare -Ax m_slurm_commands=(
	[list]=m_slurm_list
	[stop]=m_slurm_stop
	[start]=m_slurm_start
)
