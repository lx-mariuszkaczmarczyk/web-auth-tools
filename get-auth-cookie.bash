#!/bin/bash

set -e -u #-x

declare\
 AUTH_COOKIE_NAME=''\
 AUTH_PASSWORD=''\
 AUTH_TYPE=''\
 AUTH_URL=''\
 AUTH_USER=''\
 BEARER_TOKEN=''\
 COOKIES_SAVE_FILE=''\
 HTTP_METHOD='GET'\
 REQUEST_BODY_FILE=''\
 TEMP_DIR="$(mktemp --directory --tmpdir -- "get-auth-cookie.${$}.XXXXXXXXXXXX_${RANDOM}${RANDOM}")"\
 WGET_CONFIG_FILE=''\
 WGET_EXEC="$(which -- 'wget' || true)"

declare -i\
 DELETE_TEMP_DIR=1\
 COOKIES_KEEP_SESSION=1\
 REDIRECTS_MAX=5

declare -a\
 HTTP_HEADERS=()

function _proc_cmdline() {
	local\
	 TEMP_SET_OPTION
	while [ ${#} -gt 0 ]; do
		if [[ "${1}" =~ ^--[A-Z][0-9A-Z_]{0,31}=\([^$=\;]*\)$ ]]; then
			TEMP_SET_OPTION="${1#--}"
			declare -a -g "${TEMP_SET_OPTION}"
		elif [[ "${1}" =~ ^--[A-Z][0-9A-Z_]{0,31}(\[[a-z0-9_]{1,32}\])=([^$]{0,255})$ ]]; then
			TEMP_SET_OPTION="${1#--}"
			declare -A -g "${TEMP_SET_OPTION}"
		elif [[ "${1}" =~ ^--[A-Z][0-9A-Z_]{0,31}=([^$]{0,255})$ ]]; then
			TEMP_SET_OPTION="${1#--}"
			declare -g "${TEMP_SET_OPTION}"
		else
			echo "ERROR: Invalid option: '${1}'" >&2
			exit 1
		fi
		shift 1
	done
}

_proc_cmdline "${@}"

if ! [ -n "${AUTH_COOKIE_NAME}" ]; then
	echo 'ERROR: AUTH_COOKIE_NAME needs to be set' >&2
	exit 1
fi

echo "INFO: temporary directory: '${TEMP_DIR}'" >&2

if ! [ -n "${TEMP_DIR}" ] || ! [ ${#TEMP_DIR} -gt 1 ]; then
	echo "ERROR: TEMP_DIR needs to be at least 2 characters long" >&2
	exit 1
fi

# if you find this too limiting, extend the protocol list below, it's here for security
if ! [[ "${AUTH_URL}" =~ ^http(s?)://([a-z0-9]+(\.[a-z0-9.-]*[a-z0-9])?)/(.*)$ ]]; then
	echo "ERROR: empty, invalid or unknown URL format: '${AUTH_URL}'" >&2
	exit 1
fi

COOKIES_TEMP_FILE="${TEMP_DIR}/cookies"
WGETRC_TEMP_FILE="${TEMP_DIR}/wgetrc"

_proc_cmdline "${@}"

echo -n '' >>"${COOKIES_TEMP_FILE}"
echo -n '' >"${WGETRC_TEMP_FILE}"

echo "INFO: temporary cookies file: '${COOKIES_TEMP_FILE}'" >&2
echo "INFO: temporary wgetrc file: '${WGETRC_TEMP_FILE}'" >&2

if [ -n "${WGET_CONFIG_FILE}" ]; then
	if ! cp --verbose --force -- "${WGET_CONFIG_FILE}" "${WGETRC_TEMP_FILE}" 1>&2; then
		echo "ERROR: failed to copy wget config file: '${WGET_CONFIG_FILE}' -> '${WGETRC_TEMP_FILE}'" >&2
		exit 2
	fi
fi

echo "INFO: authentication type: '${AUTH_TYPE}'" >&2
case "${AUTH_TYPE}" in
	'basic')
		if [ -n "${AUTH_USER}" ]; then
			echo $'\n'"user = ${AUTH_USER}" >>"${WGETRC_TEMP_FILE}"
		else
			echo 'INFO: AUTH_USER not set via command line' >&2
		fi
		if [ -n "${AUTH_PASSWORD}" ]; then
			echo $'\n'"password = ${AUTH_PASSWORD}" >>"${WGETRC_TEMP_FILE}"
		else
			echo 'INFO: AUTH_PASSWORD not set via command line' >&2
		fi
#		echo $'\n'"user = ${AUTH_USER}"$'\n'"password = ${AUTH_PASSWORD}" >>"${WGETRC_TEMP_FILE}"
#		echo "DEBUG: authentication username: '${AUTH_USER}'" >&2
	;;
	'bearer')
		if ! [ -n "${BEARER_TOKEN}" ]; then
			echo 'ERROR: empty BEARER_TOKEN' >&2
			exit 1
		fi
		echo $'\n'"header=Authorization: Bearer ${BEARER_TOKEN}" >>"${WGETRC_TEMP_FILE}"
	;;
esac

declare -i\
 WGET_EXIT_CODE=0

"${WGET_EXEC}"\
 --config="${WGETRC_TEMP_FILE}"\
 --method="${HTTP_METHOD}"\
 --load-cookies="${COOKIES_TEMP_FILE}"\
 --save-cookies="${COOKIES_TEMP_FILE}"\
 --server-response\
 $(if [ -n "${REQUEST_BODY_FILE}" ]; then
    echo "--body-file=${REQUEST_BODY_FILE}" >&1
 fi)\
 $(if [ ${COOKIES_KEEP_SESSION} -eq 1 ]; then
    echo '--keep-session-cookies' >&1
 fi)\
 --\
 "${AUTH_URL}"\
 1>&2 ||\
  WGET_EXIT_CODE=${?}

if ! [ ${WGET_EXIT_CODE} -eq 0 ]; then
	echo "ERROR: wget exited with error, code: #${WGET_EXIT_CODE}" >&2
	exit $((64 + ${WGET_EXIT_CODE}))
fi

# exit status 3 is "cookie not found"
declare -i\
 EXIT_CODE=3

{
	while read T_HOST T_SECURE_ONLY T_PATH T_HTTPX_ONLY T_LIFETIME T_COOKIE_NAME T_COOKIE_VALUE _T_SKIP_MISC; do
		if [ "${T_COOKIE_NAME}" = "${AUTH_COOKIE_NAME}" ]; then
			echo "NOTICE: found auth cookie: '${T_COOKIE_NAME}'" >&2
			echo "${T_COOKIE_VALUE}" >&1
			EXIT_CODE=0
		else
			echo "DEBUG: skipping cookie: '${T_COOKIE_NAME}'" >&2
		fi
	done
} <"${COOKIES_TEMP_FILE}"

if [ ${DELETE_TEMP_DIR} -eq 1 ]; then
	rm --verbose --force --recursive -- "${COOKIES_TEMP_FILE}" "${WGETRC_TEMP_FILE}" "${TEMP_DIR}" 1>&2
fi

exit ${EXIT_CODE}
