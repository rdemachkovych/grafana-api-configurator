#!/bin/bash

# Taken from https://github.com/grafana/grafana-docker/issues/74

GRAFANA_URL= ${GRAFANA_URL:-https://$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD@localhost:3000}
DATASOURCES_PATH=${DATASOURCES_PATH:-/etc/grafana/datasources}
DASHBOARDS_PATH=${DASHBOARDS_PATH:-/etc/grafana/dashboards}
FOLDERS_PATH=${FOLDERS_PATH:-/etc/grafana/folders}

# Generic function to call the Vault API
grafana_api() {
  local verb=$1
  local url=$2
  local params=$3
  local bodyfile=$4
  local response
  local cmd

  cmd="curl -L --fail -s -H \"Accept: application/json\" -H \"Content-Type: application/json\" -X ${verb} -k ${GRAFANA_URL}${url}"
  [[ -n "${params}" ]] && cmd="${cmd} -d \"${params}\""
  [[ -n "${bodyfile}" ]] && cmd="${cmd} --data @${bodyfile}"
  #echo "Running ${cmd}"
  eval ${cmd} || return 1
  return 0
}

wait_for_api() {
  while ! grafana_api GET /api/user/preferences
  do
    sleep 5
  done
}

install_folders() {
  local folder
  local folder_name

  for folder in ${FOLDERS_PATH}/*.json
  do
    if [[ -f "${folder}" ]]; then
      folder_name=$(jq '.title' $folder)
      echo -e "\n* Installing folder ${folder_name}"
      if grafana_api POST /api/folders "" "${folder}"; then
        echo -e "\n* installed ok"
        change_dashboard_folderid "$folder_name"
      else
        echo -e "\n* install failed"
      fi
    fi
  done
}

install_datasources() {
  local datasource

  for datasource in ${DATASOURCES_PATH}/*.json
  do
    if [[ -f "${datasource}" ]]; then
      echo -e "\n* Installing datasource ${datasource}"
      if grafana_api POST /api/datasources "" "${datasource}"; then
        echo -e "\n* installed ok"
      else
        echo -e "\n* install failed"
      fi
    fi
  done
}

install_dashboards() {
  local dashboard

  for dashboard in ${DASHBOARDS_PATH}/*.json
  do
    if [[ -f "${dashboard}" ]]; then
      echo -e "\n* Installing dashboard ${dashboard}"
      if grafana_api POST /api/dashboards/import "" "${dashboard}"; then
        echo -e "\n* installed ok"
      else
        echo -e "\n* install failed"
      fi

    fi
  done
}

change_dashboard_folderid() {
  local folder_name=$1
  local json_data=$(grafana_api GET /api/folders "" "" "" "")
  local dashboard
  local tmp=$(mktemp)
  local folderId=$(echo $json_data | jq ".[] | select(.title == $folder_name)" | jq '.id')

  if [[ -z "$folderId" ]]; then
    echo -e "\n folderId empty"
  fi

  for dashboard in ${DASHBOARDS_PATH}/*.json
  do
    if [[ -f "${dashboard}" ]]; then
      jq ".folderId = $folderId" ${dashboard} > "$tmp" && mv "$tmp" ${dashboard}
      echo -e "\n* Change folderId ${dashboard}"
    fi
  done
}

configure_grafana() {
  wait_for_api
  install_datasources
  install_folders
  install_dashboards
}

echo -e "\n* Running configure_grafana in the background..."

configure_grafana &
