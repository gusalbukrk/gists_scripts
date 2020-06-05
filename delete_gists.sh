#!/bin/bash

# ===== STEP: FILL IN ========
username=your-username
token=your-token


# ===== STEP: SET VARIABLES, FUNCTIONS & DEFAULTS ========
base_url="https://api.github.com/"

request_header="curl -sH \"Authorization: token ${token}\""
user_url="${base_url}users/${username}/"
user_gists_url="${user_url}gists"
gists_url="${base_url}gists/"

# set $msg written at deletingMsg function as global
# this will make it accessible to the interrupt_deleting function
# that will be fired if user ctrl+c during the forking
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

# args: index, gists_quant
deletingMsg() {
  # '$1 + 1' is needed because the array index starts at 0
  # first cur will be 1 and last will be equal to gists_quant
  cur=$(("${1}" + 1))

  # $msg is in the past because it'll be printed only after request completed
  msg="Deleting gist ${cur}/${2}..."
  echo -ne "${msg}"'\r'

  # only will add a newline at the last index
  if [[ "${cur}" -eq "${2}" ]]; then
    echo "${msg} ok"
  fi
}

endMsg() {
  echo "=========="
  echo "${username}'s ${1} gists deleted!"
}

interrupt_deleting() {
  echo "${msg} ok"
  echo "canceled by the user, won't continue"
  gists_forked_quant=$(echo "${msg}" | awk '{ print $3 }' | awk -F '/' '{ print $1 }')
  endMsg "${gists_forked_quant}"
  exit 0
}

# doesn't output '^C' after press ctrl+c
stty -echoctl


# ===== STEP: GET GISTS INFO ========
echo -n "Getting gists info from source..."

declare -i page
page=1
# colon is the no-op (do-nothing) command; while will keep running until break
while [[ : ]]; do
  request="${request_header} \"${user_gists_url}?page=${page}&per_page=100\""
  partial_response=$(eval "${request}")

  if_bad_credentials_quit "${partial_response}"

  # if current response is empty, get out of the loop
  if_empty_response_complete "${partial_response}" && break

  # append responses
  response="${response}${partial_response}"

  page="${page}"+1
done

echo " ok"


# ===== STEP: SAVE INFO IN ARRAYS ========
# each property will be saved in a separate array
# info about a specific gist will be stored at the same index in every array
declare -a gists_urls_arr
mapfile -t gists_urls_arr < <(grep -o '"git_push_url": "https://gist.github.com/[a-z0-9]*.git"' <<< "${response}" | sed 's/.*com\/\(.*\)\.git\"/\1/g')

gists_quant="${#gists_urls_arr[@]}"


# ===== STEP: FORKING ========
# handle ctrl+c (if keys are pressed after the execution of this line of the code)
trap interrupt_deleting SIGINT

declare -i index
index=0
while [[ "${index}" -lt "${gists_quant}" ]]; do
  gist_id="${gists_urls_arr[${index}]}"
  
  request="${request_header} -X 'DELETE' ${gists_url}${gist_id}"

  deletingMsg "${index}" "${gists_quant}"

  response=$(eval "${request}")

  index=$index+1
done

endMsg "${gists_quant}"