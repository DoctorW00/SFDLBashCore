#!/bin/bash

# SFDLBashCore - BASH Loader Core - No Bullshit Only Downloads (GrafSauger)

g_download_destination="$PWD"		# set download destination path
g_path_to_sfdl_files="$PWD"			# set your sfdl files path
g_aes_password="mlcboard.com" 		# set password to decrypt download infomation
g_maxDownloadThreads=3 				# set the maximum amount of simultaneously running downloads
g_totalBytes=0 						# total download size
g_download_name="myDownload"		# name the download; usually overwritten by sfdl Description if not empty
g_host="127.0.0.1" 					# ftp host
g_port=21 							# ftp port
g_user="anonymous" 					# ftp username
g_pass="anonymous@blashloader.core" # ftp password
g_base_paths="."					# set ftp path(s) array to download from

# exit codes:
#   1 - no more sfdl files in g_path_to_sfdl_files found (empty array)
# 666 - unable to decrypt sfdl using g_aes_password

g_loader_version="1.0.0"			# script version

function clean_path {
    local path="$1"
    cleaned_path=$(echo "$path" | sed 's#//*#/#g')
    echo "$cleaned_path"
}

function create_directory_if_not_exists {
    local directory="$1"
    if [ ! -d "$directory" ]; then
        mkdir -p "$directory"
    fi
}

function clean_download_file_name {
    local string="$1"
    local variable="$2"
    local result=""
    if [[ "$string" =~ ^(.*)$variable(.*)$ ]]; then
        result="${BASH_REMATCH[2]}"
    fi
    echo "$result"
}
function clean_download_dir_name {
    local string="$1"
    local pattern="$2"
    local result=""
    if [[ "$string" == *"$pattern"* ]]; then
        directory_path=$(dirname "${string%$pattern*}$pattern")
        result="${directory_path}/${pattern}"
    fi
    echo "$result"
}

function human_readable_size {
    local bytes="$1"
    local -a units=('Bytes' 'KB' 'MB' 'GB' 'TB' 'PB' 'EB' 'ZB' 'YB')
    local unit_index=0
    while (( bytes > 1000 && unit_index < ${#units[@]}-1 )); do
        (( bytes /= 1000 ))
        (( unit_index++ ))
    done
    echo "$bytes ${units[unit_index]}"
}

function aes128cbc {
	aes_pass_md5="$(echo -n "$1" | md5sum | cut -d '-' -f1 | tr -d '[[:space:]]')"
	aes_iv="$(echo $2 | xxd -l 16 -ps)"
	echo $2 | openssl enc -d -a -A -aes-128-cbc -iv $aes_iv -K $aes_pass_md5 2> /dev/null| tail -c +17
}

function list_files_recursive {
    local server="$1"
    local port="$2"
    local path="$3"
    local file_list=()
    local file
    while IFS= read -r line; do
        filename=$(echo "$line" | awk '{print $NF}')
		file_size=$(echo "$line" | awk '{print $(NF-4)}')
        if [[ ! -z "$filename" && ! "$filename" =~ ^\.{1,2}$ ]]; then
            if [[ ! "$line" == "d"* ]]; then
                file_list+=("$(clean_path $path/$filename)|$file_size")
            fi
            if [[ "$line" == "d"* ]]; then
                subdir="${filename%/}"
                file_list+=($(list_files_recursive "$server" "$port" "$path/$subdir"))
            fi
        fi
    done < <(ftp -n << EOF
        open $server $port
        user $g_user $g_pass
        ls "$path"
        bye
EOF
)
    echo "${file_list[@]}"
}

function download_file {
    local file="$1"
    local target_dir="$2"
	filename="$(clean_download_file_name "$file" "$g_download_name")"
	dlFile="$(clean_path "$target_dir/$filename")"
	dlPath=$(dirname "$dlFile")
	create_directory_if_not_exists "$dlPath"
    ftp -n << EOF
        open $g_host $g_port
        user $g_user $g_pass
        binary
        get "$file" "$dlFile"
        bye
EOF
}

sfdl_files=()
while IFS= read -r -d '' file; do
    sfdl_files+=("$file")
done < <(find "$g_path_to_sfdl_files" -type f -name '*.sfdl' -print0)
sorted_files=($(for file in "${sfdl_files[@]}"; do
                    stat -c '%Y %n' "$file"
                done | sort -n | awk '{print $2}'))

if [ ${#sorted_files[@]} -eq 0 ]; then
    echo "Error: No SFDL files found!"
	exit 1
fi

sfdl="${sorted_files[0]}"
crypt="$(cat $sfdl | grep -m1 '<Encrypted' | cut -d '>' -f 2 | cut -d '<' -f 1)"
name="$(cat $sfdl | grep -m1 '<Description' | cut -d '>' -f 2 | cut -d '<' -f 1)"
host="$(cat $sfdl | grep -m1 '<Host' | cut -d '>' -f 2 | cut -d '<' -f 1)"
port="$(cat $sfdl | grep -m1 '<Port' | cut -d '>' -f 2 | cut -d '<' -f 1)"
user="$(cat $sfdl | grep -m1 '<Username' | cut -d '>' -f 2 | cut -d '<' -f 1)"
pass="$(cat $sfdl | grep -m1 '<Password' | cut -d '>' -f 2 | cut -d '<' -f 1)"
path=($(cat $sfdl | grep '<BulkFolderPath' | cut -d '>' -f 2 | cut -d '<' -f 1 | sed 's/ /\&#32;/g' | sort -u))

if [ "$crypt" = "true" ]; then
	# get host info and check if it is a real ip ...
	# ... to confirm a successful dectyption (won't work with dns names!)
	host="$(aes128cbc "$g_aes_password" "$host" | grep -E -o '([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})')"
	if [ -z "$host" ]; then
		echo "Error: Unable to decrypt $sfdl using password $g_aes_password!"
		exit 666
	else
		g_host="$host"
	fi
	name="$(aes128cbc "$g_aes_password" "$name")"
	user="$(aes128cbc "$g_aes_password" "$user")"
	pass="$(aes128cbc "$g_aes_password" "$pass")"
	for i in "${path[@]}"; do
		g_base_paths+="$(aes128cbc "$g_aes_password" "$i")"
	done
fi

if [[ -n "${name}" && ! "${name}" =~ ^[[:space:]]+$ ]]; then
	g_download_name="$name"
fi

if [[ -n "${user}" && ! "${user}" =~ ^[[:space:]]+$ ]]; then
	g_user="$user"
fi

if [[ -n "${pass}" && ! "${pass}" =~ ^[[:space:]]+$ ]]; then
	g_pass="$pass"
fi

if [[ -n "${port}" && ! "${port}" =~ ^[[:space:]]+$ ]]; then
	g_port="$port"
fi

# get ftp file index for all paths
file_list=()
for i in "${g_base_paths[@]}"; do
	echo "Indexing: $i"
	file_list+=($(list_files_recursive "$g_host" "$g_port" "$i"))
done

# list all files and get total download size
for file_info in "${file_list[@]}"; do
    file=$(echo "$file_info" | cut -d '|' -f 1)
    size=$(echo "$file_info" | cut -d '|' -f 2)
    (( g_totalBytes += size ))
    echo "$file - $(human_readable_size "$size")"
done

echo "Download size: $(human_readable_size "$g_totalBytes")"

# create download directory
g_download_destination="$g_download_destination/$g_download_name"
create_directory_if_not_exists "$g_download_destination"

# start download(s)
if hash lftp 2>/dev/null; then
	file_list_without_size=()
	for file_info in "${file_list[@]}"; do
		file=$(echo "$file_info" | cut -d '|' -f 1)
		file_list_without_size+=("$file")
	done
	
	root_directories=()
	for i in "${file_list_without_size[@]}"; do
		echo "file_list_without_size: $i"
		newFile=$(clean_download_dir_name "$i" "$g_download_name")
		root_directories+=("$newFile")
	done
	
	for i in "${root_directories[@]}"; do
		echo "root_directories: $i"
	done
	
	cleaned_array=()
	for element in "${root_directories[@]}"; do
		if [[ ! " ${cleaned_array[@]} " =~ " ${element} " ]]; then
			cleaned_array+=("$element")
		fi
	done
	
	for i in "${cleaned_array[@]}"; do
		echo "cleaned_array: $i"
	done
	
	lftp -p "$g_port" -u "$g_user","$g_pass" -e "set ftp:ssl-allow no; mirror --continue --parallel='$g_maxDownloadThreads' -vvv --log='$g_download_destination/sfdlbashcore.log' '${cleaned_array[@]}' '$g_download_destination'; exit" "$g_host"
else
	for file_info in "${file_list[@]}"; do
		file=$(echo "$file_info" | cut -d '|' -f 1)
		echo "Downloading: $file"
		download_file "$file" "$g_download_destination"
	done
fi

# move sfdl file to download
mv "$sfdl" "$g_download_destination"

# restart loader
exec "$0" "$@"
