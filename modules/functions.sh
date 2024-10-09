#!/bin/bash
#
# functions.sh
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

function month_to_number() {
    local month_name="$1"

    local months=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

     for i in "${!months[@]}"; do
        if [[ "${months[i]}" == "$month_name" ]]; then
            local month=$((i + 1))

            if [ ${#month} -eq 1 ]; then
                echo "0$month"
            else
                echo "$month"
            fi

            return      
        fi
    done
}

function uniq_file_dates() {
    local base_dir="$1"
    local file_array=()

    # Get all dates from files
    for file in "$base_dir"/* ; do
        file_date="`echo "$file" | cut -f4- -d '_' | cut -f1-3 -d '.' `"
        file_array+=("$file_date")
    done

    file_array=($(printf "%s\n" "${file_array[@]}" | sort -u))

    echo "${file_array[@]}"
}

function zzz_date_to_timestamp() {
    local zzz_date="$1"

    local month_name="`echo -n "$zzz_date" | cut -f3 -d ' '`"
    local month="`month_to_number "$month_name"`"     

    local day="`echo -n "$zzz_date" | cut -f4 -d ' '`"
    local hour="`echo -n "$zzz_date" | cut -f5 -d ' '`"
    local year="`echo -n "$zzz_date" | cut -f7 -d ' '`"

    local date_hour="$year-$month-$day $hour"
    local timestamp=$(date -d "$date_hour" +%s)

    echo "$timestamp"
}

function timestamp_start_end() {
    local dir="$1"

    local first_file="`ls -1 "$dir" | head -1`"
    local last_file="`ls -1 "$dir" | tail -1`"
    
    local first_date="`grep 'zzz' "$dir/$first_file" | head -1`"
    local last_date="`grep 'zzz' "$dir/$last_file" | tail -1`"

    local first_timestamp=`zzz_date_to_timestamp "$first_date"`
    local last_timestamp=`zzz_date_to_timestamp "$last_date"` 

    echo "$first_timestamp:$last_timestamp"    
}

function count_files() {
    local dir="$1"
    local total_files=`ls -1 "$dir" 2>/dev/null | wc -l`

    echo "$total_files"     
}