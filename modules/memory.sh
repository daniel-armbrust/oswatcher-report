#!/bin/bash
#
# memory.sh
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
RRD_MEMORY_FILE="$RRD_ROOT_DIR/memory.rrd"

function create_rrd_memory() {
    local base_dir="$1"  
         
    local timestamp_start=0  
    local file_date_array=()
    local total_data_points=0

    echo "[INFO] **MEMORY** Creating the RRD file for Memory: $RRD_MEMORY_FILE"   
    
    timestamp_start=`timestamp_start_end "$base_dir" | cut -f1 -d ':'`    
    timestamp_start=`expr $timestamp_start - 1`

    file_date_array=($(uniq_file_dates "$base_dir"))
    total_data_points=`expr ${#file_date_array[@]} \* 86400`

    rrdtool create $RRD_MEMORY_FILE \
        --start $timestamp_start \
        --step 30 \
        DS:used:GAUGE:120:0:U \
        DS:free:GAUGE:120:0:U \
        DS:total:GAUGE:120:0:U \
        DS:buffcache:GAUGE:120:0:U \
        RRA:AVERAGE:0.5:1:$total_data_points \
        RRA:AVERAGE:0.5:6:$total_data_points \
        RRA:AVERAGE:0.5:24:$total_data_points 
}

function update_rrd_memory() {
    local base_dir="$1"

    local tmp_file="`mktemp --suffix "_MEMORY"`"

    local line_count=0
    local total_lines=0
    local date_line=''    
    local timestamp=''

    local memory=''    
    local mem_used=0
    local mem_free=0
    local mem_total=0
    local mem_buffcache=0

    echo "[INFO] **MEMORY** Updating RRD file: $RRD_MEMORY_FILE"
    echo "[INFO] **MEMORY** Hold on, this can take a while ..."

    for top_file in "$base_dir"/* ; do
        egrep 'zzz|MiB Mem' "$top_file" > "$tmp_file"

        line_count=1
        total_lines=`wc -l "$tmp_file" | cut -f1 -d ' '`        

        while [ $line_count -le $total_lines ]; do
            date_line="`cat "$tmp_file" | head -$line_count | tail -1`"            
            line_count=`expr $line_count + 1`

            memory=''

            # Search for next 'MiB Mem' string 
            while [ $line_count -le $total_lines ]; do
                memory="`cat "$tmp_file" | head -$line_count | tail -1`"
                line_count=`expr $line_count + 1`

                if [ ! -z "`echo -n "$memory" | grep 'MiB Mem'`" ]; then
                    memory="`echo -n "$memory" | tr -s ' ' ' '`"
                    break                
                fi                  
            done                   

            mem_total="`echo "$memory" | cut -f4 -d ' '`"
            mem_free="`echo "$memory" | cut -f6 -d ' '`"
            mem_used="`echo "$memory" | cut -f8 -d ' '`"
            mem_buffcache="`echo "$memory" | cut -f10 -d ' '`"

            timestamp="`zzz_date_to_timestamp "$date_line"`"      

            rrdtool update $RRD_MEMORY_FILE $timestamp:$mem_used:$mem_free:$mem_total:$mem_buffcache
        done
    done

    rm -f "$tmp_file"
}

function graph_rrd_memory() {
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

        png_filename="$PNG_ROOT_DIR/memory_"`echo -n "$date" | tr '.' '-'`".png"

        echo "[INFO] **MEMORY** Creating the PNG of Memory: $png_filename"
      
        rrdtool graph $png_filename \
            --title "Memory Usage ($date)" \
            --vertical-label "Memory (MiB) (avg)" \
            --start $timestamp_start \
            --end $timestamp_end \
            DEF:total=$RRD_MEMORY_FILE:total:AVERAGE \
            DEF:used=$RRD_MEMORY_FILE:used:AVERAGE \
            DEF:free=$RRD_MEMORY_FILE:free:AVERAGE \
            DEF:buffcache=$RRD_MEMORY_FILE:buffcache:AVERAGE \
            AREA:buffcache#6E4F7C:"Buff/Cache" \
            AREA:used#FF0000:"Used Memory" \
            STACK:free#00FF00:"Free Memory" \
            LINE1:total#000000:"Total Memory" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:total:MIN:"(min) Total........\:   %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:used:MIN:"(min) Used.........\:     %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:free:MIN:"(min) Free.........\:    %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:buffcache:MIN:"(min) Buff/Cache...\:    %5.1lf MiB" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:total:MAX:"(max) Total........\:   %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:used:MAX:"(max) Used.........\:    %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:free:MAX:"(max) Free.........\:    %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:buffcache:MAX:"(max) Buff/Cache...\:    %5.1lf MiB" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:total:AVERAGE:"(avg) Total........\:   %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:used:AVERAGE:"(avg) Used.........\:    %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:free:AVERAGE:"(avg) Free.........\:    %5.1lf MiB" \
            COMMENT:"\n" \
            GPRINT:buffcache:AVERAGE:"(avg) Buff/Cache...\:    %5.1lf MiB" 1>/dev/null    
    done     
}

function main_memory() {
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswtop"

    local total_files=`count_files "$base_dir"`

    echo -e "\n[INFO] Starting Memory analysis..."

    if [ $total_files -lt 1 ]; then
        echo "[WARN] **MEMORY** No files found on: $base_dir"
        echo "[WARN] **MEMORY** Skiping Memory analysis..." 
        return
    else
        create_rrd_memory "$base_dir"
        update_rrd_memory "$base_dir"
        graph_rrd_memory "$base_dir"
    fi
}