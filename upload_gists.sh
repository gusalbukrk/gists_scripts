#!/bin/bash

# ===== STEP: FILL IN ========
username=your-username
token=your-token
# which directory you used as backup-dir in download_gists.sh?
# if default, don't change it below
backup_dir="${HOME}/gists_backup/"


# ===== STEP: SET VARIABLES, FUNCTIONS & DEFAULTS ========

base_url="https://api.github.com/"
gists_url="${base_url}gists"

request_header="curl -sH \"Authorization: token ${token}\""
request_type='"Content-Type: application/json"'
request="${request_header} $request_type"

descriptions_file="$backup_dir/descriptions.csv"

# set $msg written at uploadingMsg function as global
# this will make it accessible to the interrupt_uploading function
# that will be fired if user ctrl+c during the forking
msg=""


if_bad_credentials_quit() {
  req="${request_header} ${base_url}"
  res=$(eval "${req}")

  bad_credentials=$(grep '"message": "Bad credentials",' <<< "${res}")

  if [[ "${bad_credentials}" ]]; then
    echo "ERROR: Bad credentials"
    exit 0
  fi
}

# args: index, gists_quant
uploadingMsg() {
  # '$1 + 1' is needed because the array index starts at 0
  # first cur will be 1 and last will be equal to gists_quant
  cur=$(("${1}" + 1))

  # $msg is in the past because it'll be printed only after request completed
  msg="Uploading gist ${cur}/${2}..."
  echo -ne "${msg}"'\r'

  # only will add a newline at the last index
  if [[ "${cur}" -eq "${2}" ]]; then
    echo "${msg} ok"
  fi
}

endMsg() {
  echo "=========="
  # echo "${username}'s ${1} gists deleted!"
  echo "${1} gists uploaded to ${username}'s account!"
}

removeLeftover() {
  rm "new_gist.json"
}

interrupt_uploading() {
  echo "${msg} ok"
  echo "canceled by the user, won't continue"
  gists_forked_quant=$(echo "${msg}" | awk '{ print $3 }' | awk -F '/' '{ print $1 }')
  endMsg "${gists_forked_quant}"
  removeLeftover
  exit 0
}

# escape double quotes
# will be used to escape nested double quotes inside JSON
esc_quo() {
  backslash_esc=$(sed 's/\\/\\\\/g' <<< "${1}")
  dquotes_esc=$(sed 's/"/\\"/g' <<< "${backslash_esc}")
  newline_esc=$(sed ':a;N;$!ba;s/\n/\\n/g' <<< "${dquotes_esc}")

  echo $newline_esc
}

# remove enclosing quotes
# used to unqute descriptions, that in the file will be enclose in quotes for readability
rm_enc_quo() {
  str="${1}"
  
  # Substring expansion
  # ${parameter:offset:length}
  first_char="${str:0:1}"
  last_char=${str: -1:1}

  if [[ "${first_char}" == '"' && "${last_char}" == '"' ]]; then
    unquo=$(sed 's/.\(.*\)./\1/g' <<< "${str}")
    
    echo "${unquo}"
  else
    echo "${str}"
  fi
}

# args: id, desc, public
make_new_gist_json() {
  id="${1}"
  desc="${2}"
  public_raw="${3}"

  gist_folder="${backup_dir}${id}"

  files_raw=""

  # go to gist directory
  # this will make possible to iterate over files using just the dot (current directory)
  cd "${gist_folder}"

  files_list=$(find . -maxdepth 1 -type f | sed 's/.\/\(.*\)/\1/g')


  while read filename; do
    
    esc_filename=$(rm_enc_quo "${filename}")

    content=$(cat "${gist_folder}/${esc_filename}")
    esc_content=$(esc_quo "${content}")

    file='"'${esc_filename}'": { "content": "'${esc_content}'" }, '

    files_raw=${files_raw}' '${file}
  
  done <<< "${files_list}"

  # go to the previous directory
  # redirection is to silence the output
  cd - >/dev/null 2>&1

  # remove trailing comma from the last $file
  files_raw=$(sed 's/,\s$//g' <<< "${files_raw}")
  files='"files": { '${files_raw}' }'

  # in the descriptions.csv file, descriptions are quotes for readability
  # remove it the enclosing quotes
  unquo_desc=$(rm_enc_quo "${desc}")
  esc_desc=$(esc_quo "${unquo_desc}")
  description='"description": "'${esc_desc}'", '

  public='"public": '${public_raw}', '

  json='{ '${description}${public}${files}' }'

  echo $json > new_gist.json
}

# doesn't output '^C' after press ctrl+c
stty -echoctl


# ===== STEP: UPLOADING ========
if_bad_credentials_quit

# handle ctrl+c (if keys are pressed after the execution of this line of the code)
trap interrupt_uploading SIGINT

gists_quant=$(wc -l "${descriptions_file}" | sed 's/^\([0-9]*\).*/\1/g')

declare -i count
index=0

while read line; do

  id=$(sed 's/\(\w*\),.*/\1/g' <<< "${line}")
  desc=$(sed 's/\w*,\(.*\),\(true\|false\)/\1/g' <<< "${line}")
  public=$(sed 's/.*\(true\|false\)$/\1/g' <<< "${line}")

  # will make a json from the information above and save it to new_gist.json
  make_new_gist_json "${id}" "${desc}" "${public}"

  req=${request}" --data @new_gist.json "'"'${gists_url}'"'

  uploadingMsg "${index}" "${gists_quant}"

  res=$(eval ${req})

  index="${index}"+1
# make sure that gists are uploaded in the same order as they're originally created
done <<< $(tac "${descriptions_file}")


removeLeftover
endMsg "${gists_quant}"