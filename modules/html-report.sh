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

mapfile -t GRAPHS_ARRAY <<EOA
cpu_:CPU Usage
load_average_:Load Average
memory_:Memory Usage
network_:Network
process_states_:Process States
EOA

function write_html_header() {
    cat <<EOF >$HTML_REPORT_FILE
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OSWatcher Report</title>
    <style>
        table {
            border-collapse: collapse;
            margin: auto;
            width: 40%;
        }
        th, td {
            border: 1px solid #ccc;
            padding: 15px;
            text-align: center;
        }
        th {
            background-color: #f2f2f2;
        }        
        tr:hover {
            background-color: #e0e0e0;
        }
    </style> 
</head>
<body>
    <div style="text-align: center;">
        <h1> OSWatcher Report </h1>
        <h3> <a href="mailto:darmbrust@gmail.com">by Daniel Armbrust</a> </h3>
        <br>
EOF
}

function write_html_table() {
    local tmp_file="$1"
    local title="$2"

    echo "<h2> $title </h2>" >>$HTML_REPORT_FILE
    echo '<br>' >>$HTML_REPORT_FILE
    echo '<table border="1" align="center" cellspacing="10"><thead><tr>' >>$HTML_REPORT_FILE
    echo '<th>PID</th><th>USER</th><th>PR</th><th>NI</th><th>VIRT</th>' >>$HTML_REPORT_FILE
    echo '<th>RES</th><th>SHR</th><th>S</th><th>%CPU</th><th>%MEM</th>' >>$HTML_REPORT_FILE
    echo '<th>TIME+</th><th>COMMAND</th></tr></thead><tbody>' >>$HTML_REPORT_FILE

    cat "$tmp_file" | while read line; do
        total_column=`echo "$line" | grep -o '|' | wc -l`
        total_column=`expr $total_column + 1`
    
        echo '<tr>' >>$HTML_REPORT_FILE

        for i in $(seq 1 $total_column); do
            echo -n "<td>`echo -n "$line" | cut -f$i -d '|'`</td>" >>$HTML_REPORT_FILE
        done

        echo '</tr>' >>$HTML_REPORT_FILE
    done

    echo '</tbody></table><br>' >>$HTML_REPORT_FILE
}

function write_html_graphs() {
    local graph_file_prefix=''
    local graph_title=''

    for i in "${!GRAPHS_ARRAY[@]}"; do
        graph_file_prefix="`echo "${GRAPHS_ARRAY[$i]}" | cut -f1 -d ':'`"
        graph_title="`echo "${GRAPHS_ARRAY[$i]}" | cut -f2 -d ':'`"
       
        echo "<h2> $graph_title </h2><br>" >>$HTML_REPORT_FILE
        
        ls -1 report/graphs/ | grep "$graph_file_prefix" | while read graph_file; do
            echo "<img src=\"graphs/$graph_file\"><br><br>" >>$HTML_REPORT_FILE            
        done
    done
}

function write_html_top_cpu_usage() {
    local file_date_array="$1"    
    
    local top_cpu_tmp_file="`mktemp --suffix "_TOP-CPU"`"   
    
    local date=''
    local timetamp_start=''

    file_date_array=($(uniq_file_dates "$base_dir"))

    for i in "${!file_date_array[@]}"; do                           
        date="`echo "${file_date_array[$i]}" | tr -s '.' '-'`"
        timetamp_start="`date -d "$date" +%s`"
    
        sqlite3 $DB_TOP_PROC "
            SELECT pid, user, pri, ni, virt, res, shr, s, cpu, mem, time, command 
                FROM proc WHERE timestamp = "$timetamp_start"
            ORDER BY timestamp DESC, cpu DESC limit $MAX_PROC_TO_EXTRACT;" >$top_cpu_tmp_file
    done

    write_html_table "$top_cpu_tmp_file" 'Process - TOP CPU Usage'

    rm -f "$top_cpu_tmp_file"
}

function write_html_top_mem_usage() {
    local array_name="$1"
    local -n date_array="$array_name"

    local top_mem_tmp_file="`mktemp --suffix "_TOP-MEMORY"`"  
   
    local date=''
    local timetamp_start=''       

    for i in "${!date_array[@]}"; do            
        date="`echo "${date_array[$i]}" | tr -s '.' '-'`"
        timetamp_start="`date -d "$date" +%s`"
     
        sqlite3 $DB_TOP_PROC "
            SELECT pid, user, pri, ni, virt, res, shr, s, cpu, mem, time, command 
                FROM proc WHERE timestamp = "$timetamp_start"
            ORDER BY timestamp DESC, mem DESC limit $MAX_PROC_TO_EXTRACT;" >$top_mem_tmp_file
    done

    write_html_table "$top_mem_tmp_file" 'Process - TOP Memory Usage'

    rm -f "$top_mem_tmp_file"
}

function main_html_report() {    
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswtop"   

    local file_date_array=()
    
    file_date_array=($(uniq_file_dates "$base_dir"))

    write_html_header
    write_html_graphs
    write_html_top_cpu_usage file_date_array
    write_html_top_mem_usage file_date_array

    echo '</div></body></html>' >>$HTML_REPORT_FILE
}