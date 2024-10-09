#!/bin/bash
#
# cpu.sh
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
RRD_CPU_FILE="$RRD_ROOT_DIR/cpu.rrd"

function create_rrd_cpu() {
    local base_dir="$1"       
    local timestamp_start=0  
    local file_date_array=()
    local total_data_points=0

    echo "[INFO] **CPU** Creating the RRD file for CPU: $RRD_CPU_FILE"   
    
    timestamp_start=`timestamp_start_end "$base_dir" | cut -f1 -d ':'`    
    timestamp_start=`expr $timestamp_start - 1`

    file_date_array=($(uniq_file_dates "$base_dir"))
    total_data_points=`expr ${#file_date_array[@]} \* 86400`

    rrdtool create $RRD_CPU_FILE \
        --start $timestamp_start \
        --step 30 \
        DS:cpu_user:GAUGE:120:0:U \
        DS:cpu_system:GAUGE:120:0:U \
        DS:cpu_idle:GAUGE:120:0:U \
        RRA:AVERAGE:0.5:1:$total_data_points \
        RRA:AVERAGE:0.5:6:$total_data_points \
        RRA:AVERAGE:0.5:24:$total_data_points         
}

function update_rrd_cpu() {
    local base_dir="$1"

    local tmp_file="`mktemp`"

    local line_count=0
    local total_lines=0
    local date_line=''    
    local timestamp=''    

    local cpu=''
    local cpu_user=''
    local cpu_system=''
    local cpu_idle=''

    echo "[INFO] **CPU** Updating RRD file: $RRD_CPU_FILE"
    echo "[INFO] **CPU** Hold on, this can take a while ..."

    for top_file in "$base_dir"/* ; do
        egrep 'zzz|Cpu' "$top_file" > "$tmp_file"

        line_count=1
        total_lines=`wc -l "$tmp_file" | cut -f1 -d ' '`        

        while [ $line_count -le $total_lines ]; do
            date_line="`cat "$tmp_file" | head -$line_count | tail -1`"            
            line_count=`expr $line_count + 1`

            cpu=''

            # Search for next 'Cpu' string 
            while [ $line_count -le $total_lines ]; do
                cpu="`cat "$tmp_file" | head -$line_count | tail -1`"
                line_count=`expr $line_count + 1`

                if [ ! -z "`echo -n "$cpu" | grep 'Cpu'`" ]; then
                    cpu="`echo -n "$cpu" | tr -s ' ' ' '`"
                    break                
                fi                  
            done            

            cpu_user="`echo "$cpu" | cut -f2 -d ' '`"
            cpu_system="`echo "$cpu" | cut -f4 -d ' '`"
            cpu_idle="`echo "$cpu" | cut -f8 -d ' '`"

            timestamp="`zzz_date_to_timestamp "$date_line"`"      

            rrdtool update $RRD_CPU_FILE $timestamp:$cpu_user:$cpu_system:$cpu_idle
        done
    done

    rm -f "$tmp_file"
}

function graph_rrd_cpu() {
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

        png_filename="$PNG_ROOT_DIR/cpu_"`echo -n "$date" | tr '.' '-'`".png"

        echo "[INFO] **CPU** Creating the PNG of CPU: $png_filename"
      
        rrdtool graph $png_filename \
            --title "CPU Usage ($date)" \
            --start $timestamp_start \
            --end $timestamp_end \
            --vertical-label "CPU Usage (avg)" \
            DEF:cpu_user=$RRD_CPU_FILE:cpu_user:AVERAGE \
            DEF:cpu_system=$RRD_CPU_FILE:cpu_system:AVERAGE \
            DEF:cpu_idle=$RRD_CPU_FILE:cpu_idle:AVERAGE \
            AREA:cpu_idle#8C9DFF:"Idle CPU" \
            AREA:cpu_user#7C3172:"User CPU" \
            AREA:cpu_system#9E8300:"System CPU" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:cpu_user:MIN:"(min) User CPU...\:   %3.1lf%%" \
            COMMENT:"\n" \
            GPRINT:cpu_system:MIN:"(min) System CPU.\:   %3.1lf%%" \
            COMMENT:"\n" \
            GPRINT:cpu_idle:MIN:"(min) Idle CPU...\:  %3.1lf%%" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:cpu_user:MAX:"(max) User CPU...\:   %3.1lf%%" \
            COMMENT:"\n" \
            GPRINT:cpu_system:MAX:"(max) System CPU.\:   %3.1lf%%" \
            COMMENT:"\n" \
            GPRINT:cpu_idle:MAX:"(max) Idle CPU...\:  %3.1lf%%" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:cpu_user:AVERAGE:"(avg) User CPU...\:   %3.1lf%%" \
            COMMENT:"\n" \
            GPRINT:cpu_system:AVERAGE:"(avg) System CPU.\:   %3.1lf%%" \
            COMMENT:"\n" \
            GPRINT:cpu_idle:AVERAGE:"(avg) Idle CPU...\:  %3.1lf%%" 1>/dev/null
    done     
}

function main_cpu() {
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswtop"

    local total_files=`count_files "$base_dir"`

    echo -e "\n[INFO] Starting CPU analysis..."

    if [ $total_files -lt 1 ]; then
        echo "[WARN] **CPU** No files found on: $base_dir"
        echo "[WARN] **CPU** Skiping CPU analysis..." 
        return
    else
        create_rrd_cpu "$base_dir"
        update_rrd_cpu "$base_dir"
        graph_rrd_cpu "$base_dir"
    fi
}