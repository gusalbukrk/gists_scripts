# !/bin/bash

# ===== EDIT HERE ========
username=your-username
token=your-token
backup_dir="${HOME}/gists_backup/"
# ========================


# ====== STEP: SET VARIABLES, FUNCTIONS & DEFAULTS ========
request_header="curl -sH \"Authorization: token ${token}\""
base_url="https://api.github.com/"
user_url="${base_url}users/${username}/"
gists_url="${user_url}gists"

msg=""

# args: partial_response
if_bad_credentials_quit() {
  bad_credentials=$(grep 'Bad credentials' <<< "${partial_response}")
  if [[ "${bad_credentials}" ]]; then
    echo " failed"
    echo "Bad credentials"
    exit 0
  fi
}

#args: partial_response
if_empty_response_complete() {
  # if no more results, api will return '[]' filled with two whitespaces
  # I couldn't identify which ones; thats why I used posix character classes
  if [[ "${partial_response}" =~ "["[[:space:]]{2}"]" ]]; then
    return 0
  fi

  return 1
}

strip_enclose_quotes() {
  striped=$(sed 's/^"\(.*\)"$/\1/g' <<< "${1}")
  echo "${striped}"
}

downloadingMsg() {
  cur="$(( ${2} + 1 ))"
  msg="${1} gist ${cur}/${3}..."
  echo -ne "${msg}"'\r'

  # only will add a newline at the last index
  # '$2 + 1' is needed because the array index starts at 0
  if [[ $(("${2}" + 1)) -eq "${3}" ]]; then
    echo "${msg} ok"
  fi
}

endMsg() {
  echo "=========="
  echo "${username}'s ${1} gists backed up to ${backup_dir} !"
}

interrupt_script() {
  echo "${msg} ok"
  echo "canceled by the user, won't continue"
  gists_forked_quant=$(echo "${msg}" | awk '{ print $3 }' | awk -F '/' '{ print $1 }')
  endMsg "${gists_forked_quant}"
  exit 0
}

writeDescriptions() {
  # will save gists' description to the file 'description' in key-value pairs format
  gist_id="${1}"
  desc="${2}"
  public="${3}"
  # columns:
  log="${gist_id},${desc},${public}"

  # if line with the specific gist info already exists
  # will remove it and write again
  already_exists=$(grep "${gist_id}" "descriptions.csv")
  
  if [[ "${already_exists}" ]]; then
    # echo "exists"
    # if $already_exists contains slashes,
    # they'll be confused with sed delimiter, resulting in error
    # that's why use $gist_id instead
    sed -i  "/${gist_id}/d" descriptions.csv
  fi

  echo "${log}" >> descriptions.csv
}

# doesn't output '^C' after press ctrl+c
stty -echoctl


# ====== STEP: GET GISTS INFO ========
echo -n "Getting gists info..."

declare -i page
page=1
while [[ ! "${completed}" ]]; do
  request="${request_header} \"${gists_url}?page=${page}&per_page=100\""
  partial_response=$(eval "${request}")

  if_bad_credentials_quit "${partial_response}"

  # if current response is empty, get out of the loop
  if_empty_response_complete "${partial_response}" && break

  # append responses
  response="${response}${partial_response}"

  page="${page}"+1
done

echo " ok"


# ====== STEP: SAVE INFO IN ARRAYS ========
# save each property in a separate array
# info about a specific gist will be stored at the same index in every array
declare -a gists_desc_arr
# the character set before the last closing quote in the grep pattern is to make sure that only quotes not preceeded by backlashed are marked as closing quotes
# otherwise nested quotes would be interpreted as a closing quote
mapfile -t gists_desc_arr < <(grep -P -o '"description": ".*?[^\\]"' <<< "${response}" | awk -F ':[[:blank:]]' '{ print $2 }')
declare -a gists_urls_arr
mapfile -t gists_urls_arr < <(grep -o '"git_push_url": "https://gist.github.com/[a-z0-9]*.git"' <<< "${response}" | awk '{ print $2 }')
declare -a gists_visibility
mapfile -t gists_visibility < <(grep -E -o '"public": ((true)|(false))' <<< "${response}" | awk -F ': ' '{ print $2 }')


# ====== STEP: CREATE & CDING INTO BACKUP DIRECTORY ========
if [[ ! -d "${backup_dir}" ]]; then
  mkdir "${backup_dir}"
fi
cd "${backup_dir}" || { echo "Can't access the backup directory"; exit 1; }

# will create if file already doesn't exist
# if omited grep will throw a error at the first script run
touch "descriptions.csv"


# ====== STEP: DOWNLOAD (CLONE/PULL) ========
# handle ctrl+c (if keys are pressed after the execution of this line of the code)
trap interrupt_script SIGINT

gists_quant="${#gists_desc_arr[@]}"

declare -i index
index=0
# because array starts at 0, less than (lt) will include all elements
while [[ "${index}" -lt "${gists_quant}" ]]; do
  url="${gists_urls_arr[${index}]}"
  striped_url="$(strip_enclose_quotes ${url})"

  gist_id="$(sed 's/.*com\/\(.*\)\.git/\1/g' <<< "${striped_url}")"

  # because the `cd "${backup_dir}"` executed before this while block
  # the program will already be in the backup directory
  # therefore there isn't the need to write full paths
  # just the gist id will suffice to navigate the insides of the backup directory
  if [[ -d "${gist_id}" ]]; then
    cd "${gist_id}"

    # pulling before print $msg
    # otherwise, if the user cancel during the pulling, download won't finish and partial files will be erased
    # making the index in the $msg wrong
    git pull -q
    downloadingMsg "Pulling" "${index}" "${gists_quant}"
    
    cd ..
  else
    # clone before print $msg
    # otherwise, if the user cancel during the cloning, download won't finish and partial files will be erased
    # making the index in the $msg wrong
    git clone -q "${striped_url}"
    downloadingMsg "Cloning" "${index}" "${gists_quant}"
  fi

  desc="${gists_desc_arr[$index]}"
  public="${gists_visibility[$index]}"
  # log to descriptions.csv
  writeDescriptions "${gist_id}" "${desc}" "${public}"

  index="${index}"+1

done

endMsg "${gists_quant}"
