#!/bin/bash
#
# OSWatcher Report - A script that read and create a report with 
#                    some graphs from OSWatcher output files.
#
# Copyright (C) 2005-2022 by Daniel Armbrust <darmbrust@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

# Globals
# TODO: count the number of cpus to calculate parallel execution.
ROOT_DIR="`pwd`"
export RRD_ROOT_DIR="$ROOT_DIR/dbs"
export DB_ROOT_DIR="$RRD_ROOT_DIR"
export PNG_ROOT_DIR="$ROOT_DIR/report/graphs"

# Maximum number of Parallel Proccess to be executed.
export MAX_PARALLEL_EXECUTION=3    

# Maximum number of processes to be extracted and placed in the report.
export MAX_PROC_TO_EXTRACT=10      

# Delete old RRD and DB files.
export DELETE_OLD_FILES=false      

# HTML report file.
export HTML_REPORT_FILE="`pwd`/report/oswatcher-report-`date \+%Y-%m-%d`.html"

# Source external files.
source modules/functions.sh
source modules/load-average.sh
source modules/cpu.sh
source modules/memory.sh
source modules/network.sh
source modules/proc-states.sh
source modules/top-proc.sh
source modules/html-report.sh

function help() {
    echo ""
    echo "-d    OSWatcher data directory"
    echo "-h    Print this help"
    echo ""    
}

function check_intalled_tools() {   
    #
    # Check if the required tools are installed.
    #     RRDTOOL - https://rrdtool.org/
    #     SQLITE3 - https://www.sqlite.org/
    #

    if [ \( ! -f "`which rrdtool`" \) -o \( ! -f "`which sqlite3`" \) ]; then
        echo '[ERROR] This tool requires the RRDTOOL and SQLITE3 installed!'
        echo -e "\nRRDTOOL - https://rrdtool.org/"
        echo "SQLITE3 - https://www.sqlite.org/"
        echo -e "\nExiting..."

        exit 1        
    fi
}

function create_dirs() {
    test -d "$RRD_ROOT_DIR" || mkdir -p "$RRD_ROOT_DIR"
    test -d "$DB_ROOT_DIR" || mkdir -p "$DB_ROOT_DIR"
    test -d "$PNG_ROOT_DIR" || mkdir -p "$PNG_ROOT_DIR"
}

function check_previous_report_files() {
    #
    # Check if RRD files(s) or SQLite3 files exist.
    #

    local rrd_total_files=0
    local db_total_files=0

    rrd_total_files=`find "$RRD_ROOT_DIR" -type f -name "*.rrd" | wc -l`
    db_total_files=`find "$DB_ROOT_DIR" -type f -name "*.db" | wc -l`

    if [ \( $rrd_total_files -gt 0 \) -o \( $db_total_files -gt 0 \) ]; then        
        echo -e '\n[ERROR] RRD file(s) or SQLite3 file(s) cannot exist before run this script.'
        echo 'Exiting...'
        exit 1
    fi

    if [ -f $HTML_REPORT_FILE ]; then
        echo -e "\n[ERROR] Found previous HTML Report file: $HTML_REPORT_FILE"
        echo '[ERROR] Remove it first to continue.'
        echo 'Exiting...'
        exit 1
    fi
}

# Check execution parameters.
if [ $# -ne 2 ]; then
    help
    exit 1
fi

#  OSWatcher data directory
oswatcher_data_dir=''

while getopts "d:h" opt; do
  case $opt in
    d)
      oswatcher_data_dir="$OPTARG"
      ;;
    h)
      help
      exit 0
      ;;  
    *)
      help
      exit 1
      ;;
  esac
done 

if [ ! -d "$oswatcher_data_dir" ]; then
    echo '[ERROR] The OSWatcher data directory was not found!' >&2
    exit 1
fi

echo -e '[INFO] Starting OSWatcher Report'
echo '================================'

check_intalled_tools
check_previous_report_files
create_dirs

main_load_average "$oswatcher_data_dir"
main_cpu "$oswatcher_data_dir"
main_memory "$oswatcher_data_dir"
main_network "$oswatcher_data_dir"
main_proc_states "$oswatcher_data_dir"
main_top_proc "$oswatcher_data_dir"
main_html_report "$oswatcher_data_dir"

echo -e "\n[INFO] Done!"

exit 0