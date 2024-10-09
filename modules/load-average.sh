#!/bin/bash
#
# load-average.sh
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
RRD_LOAD_AVERAGE_FILE="$RRD_ROOT_DIR/load-average.rrd"

function create_rrd_load_average() {
    local base_dir="$1"  
         
    local timestamp_start=0  
    local file_date_array=()
    local total_data_points=0

    echo "[INFO] **LOAD AVERAGE** Creating the RRD file for Load Average: $RRD_LOAD_AVERAGE_FILE"   
    
    timestamp_start=`timestamp_start_end "$base_dir" | cut -f1 -d ':'`    
    timestamp_start=`expr $timestamp_start - 1`

    file_date_array=($(uniq_file_dates "$base_dir"))
    total_data_points=`expr ${#file_date_array[@]} \* 86400`

    rrdtool create $RRD_LOAD_AVERAGE_FILE \
        --start $timestamp_start \
        --step 30 \
        DS:load1:GAUGE:120:0:U \
        DS:load5:GAUGE:120:0:U \
        DS:load15:GAUGE:120:0:U \
        RRA:AVERAGE:0.5:1:$total_data_points \
        RRA:AVERAGE:0.5:6:$total_data_points \
        RRA:AVERAGE:0.5:24:$total_data_points 
}

function update_rrd_load_average() {
    local base_dir="$1"

    local tmp_file="`mktemp --suffix "_LOAD-AVERAGE"`"

    local line_count=0
    local total_lines=0
    local date_line=''
    local load_average=''
    local timestamp=''
    local colon_count=0

    echo "[INFO] **LOAD AVERAGE** Updating RRD file: $RRD_LOAD_AVERAGE_FILE"
    echo "[INFO] **LOAD AVERAGE** Hold on, this can take a while ..."

    for top_file in "$base_dir"/* ; do        
        egrep 'zzz|load average:' "$top_file" > "$tmp_file"        

        line_count=1
        total_lines=`wc -l "$tmp_file" | cut -f1 -d ' '`

        while [ $line_count -le $total_lines ]; do
            date_line="`cat "$tmp_file" | head -$line_count | tail -1`"            
            line_count=`expr $line_count + 1`

            load_average=''            

            # Search for next 'load average:' string 
            while [ $line_count -le $total_lines ]; do
                load_average="`cat "$tmp_file" | head -$line_count | tail -1`"
                line_count=`expr $line_count + 1`

                if [ ! -z "`echo -n "$load_average" | grep 'load average:'`" ]; then
                    load_average="`echo -n "$load_average" | cut -f3- -d ',' | cut -f2 -d ':' | tr -d ' ' | tr -s ',' ':'`"
                    break                
                fi                  
            done 
     
            timestamp="`zzz_date_to_timestamp "$date_line"`"      

            colon_count=`echo -n "$timestamp:$load_average" | tr -cd ':' | wc -m`

            # TODO: show errors when we don't get the timestamp and load average.
            if [ $colon_count -eq 3 ]; then                  
                rrdtool update $RRD_LOAD_AVERAGE_FILE $timestamp:$load_average                                
            fi 
        done
    done

    rm -f "$tmp_file"
}

function graph_rrd_load_average() {
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

        png_filename="$PNG_ROOT_DIR/load_average_"`echo -n "$date" | tr '.' '-'`".png"

        echo "[INFO] **LOAD AVERAGE** Creating the PNG of Load Average: $png_filename"
      
        rrdtool graph $png_filename \
            --title "Load Average ($date)" \
            --vertical-label "Load Average (avg)" \
            --start $timestamp_start \
            --end $timestamp_end \
            DEF:load1=$RRD_LOAD_AVERAGE_FILE:load1:AVERAGE \
            DEF:load5=$RRD_LOAD_AVERAGE_FILE:load5:AVERAGE \
            DEF:load15=$RRD_LOAD_AVERAGE_FILE:load15:AVERAGE \
            AREA:load1#6E4F7C:"1  Minute Load" \
            AREA:load5#FF0000:"5  Minutes Load" \
            AREA:load15#6E4F7C:"15 Minutes Load" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:load1:MIN:"(min) 1  Minute  Load\:  %5.2lf" \
            COMMENT:"\n" \
            GPRINT:load5:MIN:"(min) 5  Minutes Load\:  %5.2lf" \
            COMMENT:"\n" \
            GPRINT:load15:MIN:"(min) 15 Minutes Load\:  %5.2lf" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:load1:MAX:"(max) 1  Minute  Load\:  %5.2lf" \
            COMMENT:"\n" \
            GPRINT:load5:MAX:"(max) 5  Minutes Load\:  %5.2lf" \
            COMMENT:"\n" \
            GPRINT:load15:MAX:"(max) 15 Minutes Load\:  %5.2lf" \
            COMMENT:"\n" \
            COMMENT:" " \
            COMMENT:"\n" \
            GPRINT:load1:AVERAGE:"(avg) 1  Minute  Load\:  %5.2lf" \
            COMMENT:"\n" \
            GPRINT:load5:AVERAGE:"(avg) 5  Minutes Load\:  %5.2lf" \
            COMMENT:"\n" \
            GPRINT:load15:AVERAGE:"(avg) 15 Minutes Load\:  %5.2lf" 1>/dev/null
    done     
}

function main_load_average() {
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswtop"

    local total_files=`count_files "$base_dir"`

    echo -e "\n[INFO] Starting Load Average analysis..."

    if [ $total_files -lt 1 ]; then
        echo "[WARN] **LOAD AVERAGE** No files found on: $base_dir"
        echo "[WARN] **LOAD AVERAGE** Skiping Load Average analysis..." 
        return
    else       
        create_rrd_load_average "$base_dir"
        update_rrd_load_average "$base_dir"
        graph_rrd_load_average "$base_dir"
    fi
}