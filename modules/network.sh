#!/bin/bash
#
# network.sh
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
RRD_NETWORK_FILE_PREFIX="$RRD_ROOT_DIR/network"

function create_rrd_network() {
    #
    # This function creates a temporary file that contains the network
    # interfaces found. From the network interfaces found, it will create
    # those RRD files (one per network interface).
    #
    local base_dir="$1"
    local iface_tmp_file="$2" 

    local tmp_file="`mktemp`"
    
    local file=''
    local iface_rrd_file=''
    local file_date_array=() 
    local timestamp_start=0    
    local total_data_points=0
    local total_lines=0
    local line_num=0

    file_date_array=($(uniq_file_dates "$base_dir"))
    total_data_points=`expr ${#file_date_array[@]} \* 86400`  

    # Get Network Interface names. Skip veth (virtual Ethernet) interface.
    ls -1 "$base_dir" | while read file; do
        cat "$base_dir/$file" | grep '^[0-9]\+:' | cut -f2 -d ' ' | cut -f1 -d ':' | grep -v 'veth' >> "$tmp_file"
    done
   
    cat "$tmp_file" | sort -n | uniq > "$iface_tmp_file"
    rm -f "$tmp_file"

    timestamp_start=`timestamp_start_end "$base_dir" | cut -f1 -d ':'`    
    timestamp_start=`expr $timestamp_start - 1`

    total_lines=`wc -l $iface_tmp_file | cut -f1 -d ' '`
    line_num=1

    while [ $line_num -le $total_lines ]; do        
        iface="`cat "$iface_tmp_file" | head -$line_num | tail -1 | tr -s '.' '-'`"
        line_num=`expr $line_num + 1`

        iface_rrd_file="$RRD_NETWORK_FILE_PREFIX"_"$iface.rrd"       

        echo "[INFO] **NETWORK** Creating the RRD file for Network: $iface_rrd_file"
        
        rrdtool create "$iface_rrd_file" \
            --start $timestamp_start \
            --step 30 \
            DS:in:COUNTER:120:0:U \
            DS:out:COUNTER:120:0:U \
            RRA:AVERAGE:0.5:1:$total_data_points \
            RRA:AVERAGE:0.5:6:$total_data_points \
            RRA:AVERAGE:0.5:24:$total_data_points                    
    done    
}

function update_rrd_network() {    
    local iface="$1"    

    local iface_file=''
    local network_file=''
    local iface_rrd_file=''
    local date_line=''
    local iface_line=''
    local timestamp=''
    local iface_file=''
    local rx=0
    local tx=0

    local total_lines=0
    local line_num=0
    local rx_line_num=0
    local tx_line_num=0

    local JUMP_LINE_NUM_RX=6
    local JUMP_LINE_NUM_TX=10       

    for network_file in "$base_dir"/* ; do
        total_lines=`wc -l $network_file | cut -f1 -d ' '`
        line_num=1

        while [ $line_num -le $total_lines ]; do
            date_line=`cat "$network_file" | head -$line_num | tail -1 | grep '^zzz ***'`
            line_num=`expr $line_num + 1`

            if [ ! -z "$date_line" ]; then
                while [ $line_num -le $total_lines ]; do
                    iface_line="`cat "$network_file" | head -$line_num | tail -1 | grep "^[0-9]:\ $iface"`"                    
                    line_num=`expr $line_num + 1`
                    
                    if [ ! -z "$iface_line" ]; then
                        rx_line_num=`expr $line_num + $JUMP_LINE_NUM_RX`
                        rx=`cat "$network_file" | head -$rx_line_num | tail -1 | awk '{print $1}'`                        

                        tx_line_num=`expr $line_num + $JUMP_LINE_NUM_TX`
                        tx=`cat "$network_file" | head -$tx_line_num | tail -1 | awk '{print $1}'`

                        line_num=`expr $line_num + $JUMP_LINE_NUM_TX`

                        timestamp="`zzz_date_to_timestamp "$date_line"`"                    

                        iface_file="`echo "$iface" | tr -s '.' '-'`"
                        iface_rrd_file="$RRD_NETWORK_FILE_PREFIX"_"$iface_file.rrd"

                        # TODO: Handle RRDLOCK                                                
                        rrdtool update $iface_rrd_file $timestamp:$rx:$tx                 

                        break
                    fi
                done                
            fi            
        done
    done    
}

function network_parallel_update() {       
    local base_dir="$1"
    local iface_tmp_file="$2"    
        
    local total_lines=0
    local line_num=0
    local count=1
    local iface_queue=()

    total_lines=`wc -l $iface_tmp_file | cut -f1 -d ' '`
    line_num=1

    echo "[INFO] **NETWORK** Updating RRD files ..."
    echo "[INFO] **NETWORK** Hold on, this can take a while ..."       

    while [ $line_num -le $total_lines ]; do
        iface="`cat "$iface_tmp_file" | head -$line_num | tail -1`"
        line_num=`expr $line_num + 1`        

        if [ $count -gt $MAX_PARALLEL_EXECUTION ]; then            
            for i in "${!iface_queue[@]}"; do                                
                update_rrd_network "${iface_queue[$i]}" &
            done

            # Wait processes to finish.
            wait

            count=1
            iface_queue=()              
        fi

        iface_queue+=("$iface")
        count=`expr $count + 1`        
    done    

    # Check to see if has any iface not processed.
    if [ ${#iface_queue[@]} -gt 0 ]; then               
        for i in "${!iface_queue[@]}"; do                           
            update_rrd_network "${iface_queue[$i]}" &
        done

        # Wait processes to finish.
        wait
    fi    
}

function graph_rrd_network() {
    local base_dir="$1"
    local iface_tmp_file="$2"

    local iface_filename=''
    local file_date_array=()
    local file_date=''
    local zzz_start_date=''
    local timestamp_start=''    
    local zzz_end_date=''
    local timestamp_end=''
    local iface_rrd_file=''
    local png_filename=''

    file_date_array=($(uniq_file_dates "$base_dir")) 

    for date in "${file_date_array[@]}"; do
        first_file_date="$base_dir/`ls -1 $base_dir | grep "$date" | head -1`"
        zzz_start_date="`grep 'zzz' "$first_file_date" | head -1`"
        timestamp_start="`zzz_date_to_timestamp "$zzz_start_date"`"
        
        last_file_date="$base_dir/`ls -1 $base_dir | grep "$date" | tail -1`"
        zzz_end_date="`grep 'zzz' "$last_file_date" | tail -1`"
        timestamp_end="`zzz_date_to_timestamp "$zzz_end_date"`"
        
        cat $iface_tmp_file | while read iface; do   
            iface_filename="`echo "$iface" | tr -s '.' '-'`"         
            iface_rrd_file="$RRD_NETWORK_FILE_PREFIX"_"$iface_filename.rrd"           
            png_filename="$PNG_ROOT_DIR/network_"$iface_filename"-"`echo -n "$date" | tr '.' '-'`".png"
            
            echo "[INFO] **NETWORK** Creating the PNG of Network: $png_filename"

            rrdtool graph $png_filename \
                --title "Network Traffic - $iface ($date)" \
                --vertical-label "Bytes (avg)" \
                --start $timestamp_start \
                --end $timestamp_end \
                DEF:in=$iface_rrd_file:in:AVERAGE \
                DEF:out=$iface_rrd_file:out:AVERAGE \
                AREA:in#00FF00:"Incoming Traffic" \
                STACK:out#0000FF:"Outgoing Traffic" \
                COMMENT:"\n" \
                COMMENT:" " \
                COMMENT:"\n" \
                GPRINT:in:MIN:"(min) Incoming Traffic........\:   %.2lf Bytes" \
                COMMENT:"\n" \
                GPRINT:out:MIN:"(min) Outgoing Traffic........\:   %.2lf Bytes" \
                COMMENT:"\n" \
                COMMENT:" " \
                COMMENT:"\n" \
                GPRINT:in:MAX:"(max) Incoming Traffic........\:   %.2lf Bytes" \
                COMMENT:"\n" \
                GPRINT:out:MAX:"(max) Outgoing Traffic........\:   %.2lf Bytes" \
                COMMENT:"\n" \
                COMMENT:" " \
                COMMENT:"\n" \
                GPRINT:in:AVERAGE:"(avg) Incoming Traffic........\:   %.2lf Bytes" \
                COMMENT:"\n" \
                GPRINT:out:AVERAGE:"(avg) Outgoing Traffic........\:   %.2lf Bytes" 1>/dev/null                
        done
    done
}

function main_network() {
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswifconfig"
    
    local iface_tmp_file="`mktemp --suffix "_IFACE"`"    
        
    local total_files=`count_files "$base_dir"`
    local file_queue=()

    echo -e "\n[INFO] Starting Network analysis..."

    if [ $total_files -lt 1 ]; then
        echo "[WARN] **NETWORK** No files found on: $base_dir"
        echo "[WARN] **NETWORK** Skiping CPU analysis..." 
        return        
    else    
        create_rrd_network "$base_dir" "$iface_tmp_file"
        network_parallel_update "$base_dir" "$iface_tmp_file"
        graph_rrd_network "$base_dir" "$iface_tmp_file"

        rm -f "$iface_tmp_file"
    fi
}