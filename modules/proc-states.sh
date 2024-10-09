#!/bin/bash
#
# proc-states.sh
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
RRD_PROCESS_STATES_FILE="$RRD_ROOT_DIR/process-states.rrd"

function create_rrd_proc_states() {
    local base_dir="$1"       
    local timestamp_start=0  
    local file_date_array=()
    local total_data_points=0

    echo "[INFO] **PROCESS STATES** Creating the RRD file for Process States: $RRD_PROCESS_STATES_FILE"   
    
    timestamp_start=`timestamp_start_end "$base_dir" | cut -f1 -d ':'`    
    timestamp_start=`expr $timestamp_start - 1`

    file_date_array=($(uniq_file_dates "$base_dir"))
    total_data_points=`expr ${#file_date_array[@]} \* 86400`

    rrdtool create $RRD_PROCESS_STATES_FILE \
        --start $timestamp_start \
        --step 30 \
        DS:total:GAUGE:60:0:U \
        DS:running:GAUGE:60:0:U \
        DS:sleeping:GAUGE:60:0:U \
        DS:stopped:GAUGE:60:0:U \
        DS:zombie:GAUGE:60:0:U \
        RRA:AVERAGE:0.5:1:$total_data_points \
        RRA:AVERAGE:0.5:6:$total_data_points \
        RRA:AVERAGE:0.5:24:$total_data_points
}

function update_rrd_proc_states() {
    local base_dir="$1"

    local tmp_file="`mktemp --suffix "_PROC-STATES"`"

    local line_count=0
    local total_lines=0
    local date_line=''    
    local timestamp=''

    local proc=''    
    local total=0
    local running=0
    local sleeping=0
    local stopped=0
    local zombie=0

    echo "[INFO] **PROCESS STATES** Updating RRD file: $RRD_PROCESS_STATES_FILE"
    echo "[INFO] **PROCESS STATES** Hold on, this can take a while ..."

    for top_file in "$base_dir"/* ; do
        egrep 'zzz|Tasks:' "$top_file" > "$tmp_file"

        line_count=1
        total_lines=`wc -l "$tmp_file" | cut -f1 -d ' '`        

        while [ $line_count -le $total_lines ]; do
            date_line="`cat "$tmp_file" | head -$line_count | tail -1`"            
            line_count=`expr $line_count + 1`

            proc=''

            # Search for next 'MiB Mem' string 
            while [ $line_count -le $total_lines ]; do
                proc="`cat "$tmp_file" | head -$line_count | tail -1`"
                line_count=`expr $line_count + 1`

                if [ ! -z "`echo -n "$proc" | grep 'Tasks:'`" ]; then
                    proc="`echo -n "$proc" | tr -s ' ' ' '`"
                    break                
                fi                  
            done                   

            total="`echo "$proc" | cut -f2 -d ' '`"
            running="`echo "$proc" | cut -f4 -d ' '`"
            sleeping="`echo "$proc" | cut -f6 -d ' '`"
            stopped="`echo "$proc" | cut -f8 -d ' '`"
            zombie="`echo "$proc" | cut -f10 -d ' '`"

            timestamp="`zzz_date_to_timestamp "$date_line"`"      

            rrdtool update $RRD_PROCESS_STATES_FILE $timestamp:$total:$running:$sleeping:$stopped:$zombie
        done
    done

    rm -f "$tmp_file"
}

function graph_rrd_proc_states() {
    local base_dir="$1"

    local file_date_array=()
    local file_date=''
    local zzz_start_date=''
    local timestamp_start=''    
    local zzz_end_date=''
    local timestamp_end=''
    local png_filename=''
        
    file_date_array=($(uniq_file_dates "$base_dir"))

    for date in "${file_date_array[@]}"; do
        first_file_date="$base_dir/`ls -1 $base_dir | grep "$date" | head -1`"
        zzz_start_date="`grep 'zzz' "$first_file_date" | head -1`"
        timestamp_start="`zzz_date_to_timestamp "$zzz_start_date"`"

        last_file_date="$base_dir/`ls -1 $base_dir | grep "$date" | tail -1`"
        zzz_end_date="`grep 'zzz' "$last_file_date" | tail -1`"
        timestamp_end="`zzz_date_to_timestamp "$zzz_end_date"`"        

        png_filename="$PNG_ROOT_DIR/process_states_"`echo -n "$date" | tr '.' '-'`".png"

        echo "[INFO] **PROCESS STATES** Creating the PNG of Process States: $png_filename"
      
        rrdtool graph $png_filename \
            --title "Process States Overview ($date)" \
            --vertical-label "Processes (avg)" \
            --start $timestamp_start \
            --end $timestamp_end \
            DEF:total=$RRD_PROCESS_STATES_FILE:total:AVERAGE \
            DEF:running=$RRD_PROCESS_STATES_FILE:running:AVERAGE \
            DEF:sleeping=$RRD_PROCESS_STATES_FILE:sleeping:AVERAGE \
            DEF:stopped=$RRD_PROCESS_STATES_FILE:stopped:AVERAGE \
            DEF:zombie=$RRD_PROCESS_STATES_FILE:zombie:AVERAGE \
            AREA:running#00FF00:"Running Processes" \
            AREA:total#6E4F7C:"Total Processes" \
            STACK:sleeping#0000FF:"Sleeping Processes" \
            STACK:stopped#FFFF00:"Stopped Processes" \
            STACK:zombie#FF0000:"Zombie Processes" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:total:MIN:"(min) Total......\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:running:MIN:"(min) Running....\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:sleeping:MIN:"(min) Sleeping...\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:stopped:MIN:"(min) Stopped....\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:zombie:MIN:"(min) Zombie.....\:   %.0lf" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:total:MAX:"(max) Total......\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:running:MAX:"(max) Running....\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:sleeping:MAX:"(max) Sleeping...\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:stopped:MAX:"(max) Stopped....\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:zombie:MAX:"(max) Zombie.....\:   %.0lf" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:total:AVERAGE:"(avg) Total......\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:running:AVERAGE:"(avg) Running....\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:sleeping:AVERAGE:"(avg) Sleeping...\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:stopped:AVERAGE:"(avg) Stopped....\:   %.0lf" \
            COMMENT:"\n" \
            GPRINT:zombie:AVERAGE:"(avg) Zombie.....\:   %.0lf" 1>/dev/null           
    done     
}

function main_proc_states() {
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswtop"

    local total_files=`count_files "$base_dir"`

    echo -e "\n[INFO] Starting Process States analysis..."

    if [ $total_files -lt 1 ]; then
        echo "[WARN] **PROCESS STATES** No files found on: $base_dir"
        echo "[WARN] **PROCESS STATES** Skiping Process States analysis..." 
        return
    else
        create_rrd_proc_states "$base_dir"
        update_rrd_proc_states "$base_dir"
        graph_rrd_proc_states "$base_dir"
    fi
}