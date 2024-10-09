#!/bin/bash
#
# top-proc.sh
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
DB_TOP_PROC="$DB_ROOT_DIR/top-proc.db"

function convert_date_timestamp() {
    local file_date="$1"

    local year=''
    local month=''
    local day=''
    local month_day_year=''
    local timestamp=0

    year="`echo "$file_date" | cut -f1 -d '.'`"
    month="`echo "$file_date" | cut -f2 -d '.'`"
    day="`echo "$file_date" | cut -f3 -d '.'`"

    month_day_year="$month/$day/$year"   

    timestamp=$(date -d "$month_day_year" +%s)

    echo $timestamp
}

function create_top_proc_db() {
    
    echo "[INFO] **TOP PROCESSES** Creating the DB file for Top Process: $DB_TOP_PROC"

    sqlite3 $DB_TOP_PROC <<EOF       
        CREATE TABLE IF NOT EXISTS proc (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER,
            pid TEXT,
            user TEXT,
            pri INTEGER,
            ni INTEGER,
            virt INTEGER,    
            res INTEGER,
            shr INTEGER,
            s TEXT,
            cpu REAL,
            mem REAL,
            time TEXT,
            command TEXT            
        );
EOF
}

function update_proc_db() {
    local timestamp="$1"
    local top_file="$2"

    local total_lines=0
    local line_num=1
    local pid_header_line=''

    local pid=''
    local user=''
    local pri=''
    local ni=''
    local virt=''
    local res=''
    local shr=''
    local s=''
    local cpu=''
    local mem=''
    local time=''
    local command=''

    total_lines=`wc -l "$top_file" | cut -f1 -d ' '`

    while [ $line_num -le $total_lines ]; do
        line="`cat "$top_file" | head -$line_num | tail -1`"
        line_num=`expr $line_num + 1`

        pid_header_line="`echo "$line" | grep -E '^ +PID\ USER'`"

        if [ ! -z "$pid_header_line" ]; then
            line_num=`expr $line_num + 1`

            for i in $(seq 1 $MAX_PROC_TO_EXTRACT); do
                pid="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $1}'`"
                user="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $2}'`"
                pri="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $3}'`"
                ni="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $4}'`"
                virt="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $5}'`"
                res="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $6}'`"
                shr="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $7}'`"
                s="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $8}'`"
                cpu="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $9}'`"
                mem="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $10}'`"
                time="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $11}'`"
                command="`cat "$top_file" | head -$line_num | tail -1 | awk '{print $12}'`"

                # PRAGMA busy_timeout = 5000; -- Set timeout to 5 seconds
                #    How long SQLite waits for a lock to be released. By setting a timeout,
                # you can reduce the frequency of these errors, as the process will wait 
                # for the lock to be released.
                sqlite3 $DB_TOP_PROC <<EOF 1>/dev/null
                    PRAGMA busy_timeout = 5000;

                    INSERT INTO proc (timestamp, pid, user, pri, ni, virt, res, shr, s, cpu, 
                                      mem, time, command) 
                    VALUES ("$timestamp", "$pid", "$user", "$pri", "$ni", "$virt", "$res", 
                            "$shr", "$s", "$cpu", "$mem", "$time", "$command");
EOF
                line_num=`expr $line_num + 1` 
            done
        fi
    done   
}

function top_proc_parallel_update() {
    local base_dir="$1"

    local file_date_array=()
    local file_queue=()
    local timestamp=0
    local total_files=0
    local file_num=0
    local top_file=''
    local count=1

    file_date_array=($(uniq_file_dates "$base_dir"))

    for date in "${file_date_array[@]}"; do      
        total_files=`ls -1 "$base_dir" | grep "$date" | wc -l`
        file_num=1

        while [ $file_num -le $total_files ]; do
            top_file="`echo -n "$base_dir"`/`ls -1 "$base_dir" | grep "$date" | head -$file_num | tail -1`"
            file_num=`expr $file_num + 1`

            if [ -f "$top_file" ]; then
                if [ $count -gt $MAX_PARALLEL_EXECUTION ]; then
                    timestamp="`convert_date_timestamp "$date"`"

                    for i in "${!file_queue[@]}"; do                                
                        update_proc_db "$timestamp" "${file_queue[$i]}" &
                    done

                    # Wait processes to finish.
                    wait

                    count=1
                    file_queue=() 
                fi

                file_queue+=("$top_file")
                count=`expr $count + 1`     
            fi
        done
    done

    # Check to see if has any iface not processed.
    if [ ${#file_queue[@]} -gt 0 ]; then               
        for i in "${!file_queue[@]}"; do                           
            update_proc_db "$timestamp" "${file_queue[$i]}" &
        done

        # Wait processes to finish.
        wait
    fi 
}

function main_top_proc() {
    local oswatcher_data_dir="$1"
    local base_dir="$oswatcher_data_dir/archive/oswtop"
    
    echo -e "\n[INFO] Starting to extract the TOP Processes..."

    local total_files=`count_files "$base_dir"`

    if [ $total_files -lt 1 ]; then
        echo "[WARN] **TOP PROCESSES** No files found on: $base_dir"
        echo "[WARN] **TOP PROCESSES** Skiping TOP Processes analysis..." 
        return
    else
        create_top_proc_db
        top_proc_parallel_update "$base_dir"
    fi
}