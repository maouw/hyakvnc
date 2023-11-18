#!/usr/bin/env bash

# Available Commands:
#  list        List all running and named Apptainer instances
#  run         Run a named instance of the given container image
#  start       Start a named instance of the given container image
#  stats       Get stats for a named instance
#  stop        Stop a named instance of a given container image



declare -A _module_methods=(
	[list]=_module_list
	 
)