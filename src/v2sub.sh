#!/bin/bash
export LC_ALL=C
export LANG=C
export LANGUAGE=en_US.UTF-8

branch="master"
VERSION="$(curl -fsL https://api.github.com/repos/phlinhng/v2ray-tcp-tls-web/releases/latest | grep tag_name | sed -E 's/.*"v(.*)".*/\1/')"

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
  sudoCmd="sudo"
else
  sudoCmd=""
fi

# copied from v2ray official script
# colour code
RED="31m"      # Error message
GREEN="32m"    # Success message
YELLOW="33m"   # Warning message
BLUE="36m"     # Info message
# colour function
colorEcho(){
  echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}

#copied & modified from atrandys trojan scripts
#copy from 秋水逸冰 ss scripts
if [[ -f /etc/redhat-release ]]; then
  release="centos"
  systemPackage="yum"
  #colorEcho ${RED} "unsupported OS"
  #exit 0
elif cat /etc/issue | grep -Eqi "debian"; then
  release="debian"
  systemPackage="apt-get"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
  release="ubuntu"
  systemPackage="apt-get"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
  release="centos"
  systemPackage="yum"
  #colorEcho ${RED} "unsupported OS"
  #exit 0
elif cat /proc/version | grep -Eqi "debian"; then
  release="debian"
  systemPackage="apt-get"
elif cat /proc/version | grep -Eqi "ubuntu"; then
  release="ubuntu"
  systemPackage="apt-get"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
  release="centos"
  systemPackage="yum"
  #colorEcho ${RED} "unsupported OS"
  #exit 0
fi

read_json() {
  # jq [key] [path-to-file]
  ${sudoCmd} jq --raw-output $2 $1 2>/dev/null | tr -d '\n'
} ## read_json [path-to-file] [key]

write_json() {
  # jq [key = value] [path-to-file]
  jq -r "$2 = $3" $1 > tmp.$$.json && ${sudoCmd} mv tmp.$$.json $1 && sleep 1
} ## write_json [path-to-file] [key = value]

# https://stackoverflow.com/questions/37309551/how-to-urlencode-data-into-a-url-with-bash-or-curl
urlEncode() {
  printf %s "$1" | jq -s -R -r @uri
}

# a trick to redisplay menu option
show_menu() {
  echo ""
  echo "1) 生成订阅"
  echo "2) 更新订阅"
  echo "3) 显示订阅"
  echo "4) 回主菜单"
}

continue_prompt() {
  read -p "继续其他操作 (yes/no)? " choice
  case "${choice}" in
    y|Y|[yY][eE][sS] ) show_menu ;;
    * ) exit 0;;
  esac
}

get_docker() {
  if [ ! -x "$(command -v docker)" ]; then
    curl -sL https://get.docker.com/ | ${sudoCmd} bash
  fi
}

set_proxy() {
  ${sudoCmd} /bin/cp /etc/tls-shunt-proxy/config.yaml /etc/tls-shunt-proxy/config.yaml.bak 2>/dev/null
  wget -q https://raw.githubusercontent.com/phlinhng/v2ray-tcp-tls-web/${branch}/config/config.yaml -O /tmp/config_new.yaml

  if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.installed') == "true" ]]; then
    sed -i "s/FAKEV2DOMAIN/$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')/g" /tmp/config_new.yaml
    sed -i "s/##V2RAY@//g" /tmp/config_new.yaml
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.api.installed') == "true" ]]; then
    sed -i "s/FAKEAPIDOMAIN/$(read_json /usr/local/etc/v2script/config.json '.sub.api.tlsHeader')/g" /tmp/config_new.yaml
    sed -i "s/##SUBAPI@//g" /tmp/config_new.yaml
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.mtproto.installed') == "true" ]]; then
    sed -i "s/FAKEMTDOMAIN/$(read_json /usr/local/etc/v2script/config.json '.mtproto.fakeTlsHeader')/g" /tmp/config_new.yaml
    sed -i "s/##MTPROTO@//g" /tmp/config_new.yaml
  fi

  ${sudoCmd} /bin/cp -f /tmp/config_new.yaml /etc/tls-shunt-proxy/config.yaml
}

generate_link() {
  if [ ! -d "/usr/bin/v2ray" ]; then
    colorEcho ${RED} "尚末安装v2Ray"
    return 1
  elif [ ! -f "/usr/local/etc/v2script/config.json" ]; then
    colorEcho ${RED} "配置文件不存在"
    return 1
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') != "true" ]]; then
    write_json /usr/local/etc/v2script/config.json '.sub.enabled' "true"
  fi

  if [[ "$(read_json /usr/local/etc/v2script/config.json '.sub.uri')" != "" ]]; then
    ${sudoCmd} rm -f /var/www/html/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')
    write_json /usr/local/etc/v2script/config.json '.sub.uri' \"\"
  fi

  #${sudoCmd} ${systemPackage} install uuid-runtime coreutils jq -y
  local uuid="$(read_json /etc/v2ray/config.json '.inbounds[0].settings.clients[0].id')"
  local V2_DOMAIN="$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')"

  read -p "输入节点名称[留空则使用默认值]: " remark

  if [ -z "${remark}" ]; then
    remark="${V2_DOMAIN}:443"
  fi

  local json="{\"add\":\"${V2_DOMAIN}\",\"aid\":\"0\",\"host\":\"\",\"id\":\"${uuid}\",\"net\":\"\",\"path\":\"\",\"port\":\"443\",\"ps\":\"${remark}\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}"

  local uri="$(printf "${json}" | base64)"
  local sub="$(printf "vmess://${uri}" | tr -d '\n' | base64)"

  local randomName="$(uuidgen | sed -e 's/-//g' | tr '[:upper:]' '[:lower:]' | head -c 16)" #random file name for subscription
  write_json /usr/local/etc/v2script/config.json '.sub.uri' "\"${randomName}\""

  printf "${sub}" | tr -d '\n' | ${sudoCmd} tee /var/www/html/$(read_json /usr/local/etc/v2script/config.json '.sub.uri') >/dev/null
  echo "https://${V2_DOMAIN}/${randomName}" | tr -d '\n' && printf "\n"
}

update_link() {
  if [ ! -d "/usr/bin/v2ray" ]; then
    colorEcho ${RED} "尚末安装v2Ray"
    return 1
  elif [ ! -f "/usr/local/etc/v2script/config.json" ]; then
    colorEcho ${RED} "配置文件不存在"
    return 1
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') == "true" ]]; then
    local uuid="$(read_json /etc/v2ray/config.json '.inbounds[0].settings.clients[0].id')"
    local V2_DOMAIN="$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')"
    local currentRemark="$(read_json /usr/local/etc/v2script/config.json '.sub.nodes[0]' | base64 -d | sed 's/^vmess:\/\///g' | base64 -d | jq --raw-output '.ps' | tr -d '\n')"
    read -p "输入节点名称[留空则使用默认值]: " remark

    if [ -z "${remark}" ]; then
      remark=currentRemark
    fi

    local json="{\"add\":\"${V2_DOMAIN}\",\"aid\":\"0\",\"host\":\"\",\"id\":\"${uuid}\",\"net\":\"\",\"path\":\"\",\"port\":\"443\",\"ps\":\"${remark}\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}"
    local uri="$(printf "${json}" | base64)"
    local sub="$(printf "vmess://${uri}" | tr -d '\n' | base64)"

    printf "${sub}" | tr -d '\n' | ${sudoCmd} tee /var/www/html/$(read_json /usr/local/etc/v2script/config.json '.sub.uri') >/dev/null
    echo "https://${V2_DOMAIN}/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')" | tr -d '\n' && printf "\n"

    colorEcho ${GREEN} "更新订阅完成"
  else
    generate_link
  fi
}

display_link_main() {
  local V2_DOMAIN="$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')"
  echo "https://${V2_DOMAIN}/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')" | tr -d '\n' && printf "\n"
}

display_link_more() {
  local mainSub="https://$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')"
  local mainSubEncoded="$(urlEncode ${mainSub})"
  local apiPrefix="https://$(read_json /usr/local/etc/v2script/config.json '.sub.api.tlsHeader')/sub?url=${mainSubEncoded}&target="

  colorEcho ${YELLOW} "v2RayNG / Shadowrocket / Pharos Pro"
  printf %s "${mainSub}" | tr -d '\n' && printf "\n\n"

  colorEcho ${YELLOW} "Clash"
  printf %s "${apiPrefix}clash" | tr -d '\n' && printf "\n\n"

  colorEcho ${YELLOW} "ClashR"
  printf %s "${apiPrefix}clashr" | tr -d '\n' && printf "\n\n"

  colorEcho ${YELLOW} "Quantumult"
  printf %s "${apiPrefix}quan" | tr -d '\n' && printf "\n\n"

  colorEcho ${YELLOW} "QuantumultX"
  printf %s "${apiPrefix}quanx" | tr -d '\n' && printf "\n\n"

  colorEcho ${YELLOW} "Loon"
  printf  %s "${apiPrefix}loon" | tr -d '\n' && printf "\n"
}

install_api() {
  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') == "true" ]]; then
    read -p "用于API的域名 (出于安全考虑，请使用和v2Ray不同的子域名): " api_domain
    if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.installed') == "true" ]]; then
      if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader') == "${api_domain}" ]]; then
        colorEcho ${RED} "域名 ${api_domain} 与现有v2Ray域名相同"
        show_menu
        return 1
      fi
    fi
    ${sudoCmd} ${systemPackage} install curl -y -qq
    get_docker

    # set up api
    wget -q https://raw.githubusercontent.com/phlinhng/v2ray-tcp-tls-web/${branch}/config/pref.ini -O /tmp/pref.ini
    sed -i "s/FAKECONFIGPREFIX/https:\/\/${api_domain}/g" /tmp/pref.ini
    mv /tmp/pref.ini /usr/local/etc/v2script/pref.ini

    ${sudoCmd} docker rm $(${sudoCmd} docker stop $(${sudoCmd} docker ps -q --filter ancestor=tindy2013/subconverter) 2>/dev/null) 2>/dev/null
    ${sudoCmd} docker run -d --restart=always -p 127.0.0.1:25500:25500 -v /usr/local/etc/v2script/pref.ini:/base/pref.ini tindy2013/subconverter:latest
    write_json /usr/local/etc/v2script/config.json ".sub.api.installed" "true"
    write_json /usr/local/etc/v2script/config.json ".sub.api.tlsHeader" "\"${api_domain}\""

    set_proxy
    ${sudoCmd} systemctl start tls-shunt-proxy
    ${sudoCmd} systemctl daemon-reload

    colorEcho ${GREEN} "subscription manager api has been set up."
    display_link_more
  else
    colorEcho ${YELLOW} "你还没有生成订阅连接"
  fi
}

display_link() {
  if [ ! -d "/usr/bin/v2ray" ]; then
    colorEcho ${RED} "尚末安装v2Ray"
    return 1
  elif [ ! -f "/usr/local/etc/v2script/config.json" ]; then
    colorEcho ${RED} "配置文件不存在"
    return 1
  fi

  if [[ "$(read_json /usr/local/etc/v2script/config.json '.sub.api.installed')" == "true" ]]; then
    display_link_more
  elif [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') == "true" ]]; then
    colorEcho ${YELLOW} "若您使用v2RayNG/Shdowrocket/Pharos Pro以外的客戶端, 需要安装订阅管理API"
    read -p "是否安装 (yes/no)? " choice
    case "${choice}" in
      y|Y|[yY][eE][sS] ) install_api;;
      * ) display_link_main;;
    esac
  else
    colorEcho ${YELLOW} "你还没有生成订阅连接, 请先运行\"1) 生成订阅\""
  fi
}

menu() {
  colorEcho ${YELLOW} "v2Ray TCP+TLS+WEB subscription manager v${VERSION}"
  colorEcho ${YELLOW} "author: phlinhng"
  echo ""

  PS3="选择操作[输入任意值或按Ctrl+C退出]: "
  COLUMNS=39
  options=("生成订阅" "更新订阅" "显示订阅" "回主菜单")
  select opt in "${options[@]}"
  do
    case "${opt}" in
      "生成订阅") generate_link && continue_prompt ;;
      "更新订阅") update_link && continue_prompt ;;
      "显示订阅") display_link && continue_prompt ;;
      "回主菜单") v2script && exit 0 ;;
      *) break;;
    esac
  done

}

menu