#!/bin/bash

#### Description: 自动部署docker服务器
#### System requirement: Ubuntu 18.04
#### Written by: York Tang - ivanstang0415@gmail.com on 02-2019

# 自定义输出文本颜色
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

DDNS_CONF=/root/ss-config/ddns-config.json
SS_CONF=/root/ss-config/shadowsocksr-config.json
UDPSPEEDER_CONF=/root/ss-config/udpspeeder-config.json
UDPSPEEDER_BIN=/root/ss-config/speederv2_amd64
UDP2RAW_CONF=/root/ss-config/udp2raw.conf
UDP2RAW_BIN=/root/ss-config/udp2raw_amd64
SS_PASSWORD="1234567890"
SS_PORT=8333
SS_METHOD="chacha20-ietf-poly1305"
UDPSPEEDER_KEY="xxxx"
UDP2RAW_PASSWORD="yyyy"
UDPSPEEDER_SCRIPT=/root/ss-config/udpspeeder
UDP2RAW_SCRIPT=/root/ss-config/udp2raw


# 检查bbr设置
check_bbr(){
	check_bbr_status_on=`sysctl net.ipv4.tcp_congestion_control | awk '{print $3}'`
	if [[ "${check_bbr_status_on}" = "bbr" ]]; then
		check_bbr_status_off=`lsmod | grep bbr`
		if [[ "${check_bbr_status_off}" = "" ]]; then
			return 1
		else
			return 0			
		fi
	else
		return 2
	fi
}

# 应用bbr
enable_bbr(){
	check_bbr
	if [[ $? -eq 0 ]]; then
		echo -e "${Info} BBR 已在运行 !"
	else
		sed -i '/net\.core\.default_qdisc=fq/d' /etc/sysctl.conf
    	sed -i '/net\.ipv4\.tcp_congestion_control=bbr/d' /etc/sysctl.conf

    	echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    	echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    	sysctl -p >> /var/log/bbr.log

		sleep 1s
		
		check_running
		case "$?" in
		0)
		echo -e "${Info} BBR 已成功启用 !"
		;;
		1)
		echo -e "${Error} Linux 内核已经启用 BBR，但 BBR 并未运行 ！"
		;;
		2)
		echo -e "${Error} Linux 内核尚未配置启用 BBR ！"
		;;
		*)
		echo "${Error} BBR 状态未知，返回参数: $?}"
		;;
		esac
	fi
}

# 读取ddns配置
read_ddns_config(){
    if [ ! -f ${DDNS_CONF} ]; then
        cat > ${DDNS_CONF}<<-EOF
{
"host": "xxxx",
"key": "yyyy"
}
EOF
    fi
    HOST=`cat ${DDNS_CONF} | jq '.host' | sed 's/\"//g'`
    KEY=`cat ${DDNS_CONF} | jq '.key' | sed 's/\"//g'`
}

# 修改DDNS主机名
change_ddns_host(){
    read_ddns_config
    echo -e "请输入主机名"
    read -e -p "(当前: ${HOST}):" NEW_HOST
    if [ ! -z "${NEW_HOST}" ]; then
        sed -i "s/${HOST}/${NEW_HOST}/g" "$DDNS_CONF"
        read_ddns_config
        [[ "$HOST" != "$NEW_HOST" ]] && echo -e "${Error} 主机名修改失败 !" && exit 1
        echo -e "${Info} 主机名已修改为 ${NEW_HOST} !"
    fi
    echo -e "请输入DDNS更新的KEY"
    read -e -p "(当前: ${KEY}):" NEW_KEY
    if [ ! -z "${NEW_KEY}" ]; then
        sed -i "s/${KEY}/${NEW_KEY}/g" "$DDNS_CONF"
        read_ddns_config
        [[ "$KEY" != "$NEW_KEY" ]] && echo -e "${Error} DDNS更新KEY修改失败 !" && exit 1
        echo -e "${Info} DDNS更新KEY已修改为 ${NEW_KEY} !"
    fi
}
 
# 检验DDNS修改是否有效
verify_ddns(){
    read_ddns_config
    RESULT=`curl -4 "${HOST}:${KEY}@dyn.dns.he.net/nic/update?hostname=${HOST}"`
    if [[ $RESULT =~ "good" ]]; then
        echo -e "${Info} DDNS配置测试成功 !"
    elif [[ $RESULT =~ "nochg" ]]; then
        echo -e "${Info} DDNS配置测试成功 !"
    else
        echo -e "${Error} DDNS配置测试失败：$RESULT !"
    fi
}

# 读取json配置文件中的password的值
read_json_password(CONF_FILE){
    if [ ! -f ${CONF_FILE} ]; then
        echo "找不到配置文件 ${CONF_FILE}, 退出！"
        exit 1
    fi
    PASSWORD=`cat ${CONF_FILE} | jq '.password' | sed 's/\"//g'`
}

# 读取json配置文件中的password的值
read_ss_password(CONF_FILE){
    if [ ! -f ${CONF_FILE} ]; then
        echo "找不到SS配置文件 ${CONF_FILE}, 退出！"
        exit 1
    fi
    PASSWORD=`cat ${CONF_FILE} | jq '.password' | sed 's/\"//g'`
}

# 读取json配置文件中的key的值
read_udpspeeder_key(){
    if [ ! -f ${UDPSPEEDER_CONF} ]; then
        echo "找不到配置文件 ${UDPSPEEDER_CONF}, 退出！"
        exit 1
    fi
    UDPSPEEDER_KEY=`cat ${UDPSPEEDER_CONF} | jq '.key' | sed 's/\"//g'`
}

# 读取conf配置文件中的密码
read_udp2raw_password(){
    if [ ! -f ${UDP2RAW_CONF} ]; then
        echo "找不到配置文件 ${UDP2RAW_CONF}, 退出！"
        exit 1
    fi
    UDP2RAW_PASSWORD=`cat ${UDP2RAW_CONF} | grep '\-k' | awk '{print $2}'`
}

# 配置SS连接密码
config_ss_password(){
    echo -e "请输入SS的连接密码"
    read -e -p "(当前的密码是: ${SS_PASSWORD}):" NEW_PASSWORD
    if [ ! -z "${NEW_PASSWORD}" ]; then
        SS_PASSWORD = NEW_PASSWORD
        echo -e "${Info} SS连接密码已修改为 ${SS_PASSWORD} !"
    fi

    CONF_FILE="/root/ssr-config/udpspeeder-config.json"
    

    CONF_FILE="/root/ssr-config/udp2raw.conf"
    read_conf_password
    echo -e "请输入UDP2Raw的连接密码"
    read -e -p "(当前的密码是: ${PASSWORD}):" NEW_PASSWORD
    if [ ! -z "${NEW_PASSWORD}" ]; then
        sed -i "s/${PASSWORD}/${NEW_PASSWORD}/g" "${CONF_FILE}"
        read_conf_password
        [[ "${PASSWORD}" != "${NEW_PASSWORD}" ]] && echo -e "${Error} UDP2Raw连接密码修改失败 !" && exit 1
        echo -e "${Info} UDP2Raw连接密码已修改为 ${NEW_PASSWORD} !"
    fi
}

# 配置SS连接端口号
config_ss_password(){
    echo -e "请输入SS的服务端口号"
    read -e -p "(当前的端口号是: ${SS_PORT}):" NEW_PORT
    if [ ! -z "${NEW_PORT}" ]; then
        SS_PORT = NEW_PORT
        echo -e "${Info} SS连接端口已修改为 ${SS_PORT} !"
    fi
}

# 配置SS加密方式
config_ss_encryption(){
    echo -e "请输入SS的加密方式"
    echo -e "可以使用的加密方式有：rc4-md5,aes-128-gcm, aes-192-gcm, aes-256-gcm,aes-128-cfb, aes-192-cfb, aes-256-cfb,aes-128-ctr, aes-192-ctr, aes-256-ctr,camellia-128-cfb, camellia-192-cfb,camellia-256-cfb, bf-cfb,chacha20-ietf-poly1305,xchacha20-ietf-poly1305,
                              salsa20, chacha20 and chacha20-ietf.The default cipher is chacha20-ietf-poly1305."
    read -e -p "(当前的加密方式是: ${SS_METHOD}):" NEW_METHOD
    if [ ! -z "${NEW_PORT}" ]; then
        SS_METHOD = NEW_METHOD
        echo -e "${Info} SS加密方式已修改为 ${SS_METHOD} !"
    fi
}

# 配置UDPSpeeder
config_udpspeeder(){
    read_udpspeeder_key

    echo -e "请输入UDPSpeeder的连接密码"
    read -e -p "(当前的密码是: ${UDPSPEEDER_KEY}):" NEW_UDPSPEEDER_KEY
    if [ ! -z "${NEW_UDPSPEEDER_KEY}" ]; then
        sed -i "s/${UDPSPEEDER_KEY}/${NEW_UDPSPEEDER_KEY}/g" "${UDPSPEEDER_CONF}"
        read_udpspeeder_key
        [[ "${UDPSPEEDER_KEY}" != "${NEW_UDPSPEEDER_KEY}" ]] && echo -e "${Error} UDPSpeeder连接密码修改失败 !" && exit 1
        echo -e "${Info} UDPSpeeder连接密码已修改为 ${UDPSPEEDER_KEY} !"
    fi

    if [ ! -f ${UDPSPEEDER_CONF} ]; then
        echo "找不到配置文件 ${UDPSPEEDER_CONF}, 退出！"
        exit 1
    fi
    UDPSPEEDER_TARGET=`cat ${UDPSPEEDER_CONF} | jq '.target' | sed 's/\"//g'`
    TARGET="127.0.0.1:${SS_PORT}"
    sed -i "s/${UDPSPEEDER_TARGET}/${TARGET}/g" "${UDPSPEEDER_CONF}"
}

# 配置UDP2RAW
config_udp2raw(){
    read_udp2raw_password

    echo -e "请输入UDP2Raw的连接密码"
    read -e -p "(当前的密码是: ${UDP2RAW_PASSWORD}):" NEW_UDP2RAW_PASSWORD
    if [ ! -z "${NEW_UDP2RAW_PASSWORD}" ]; then
        sed -i "s/${UDP2RAW_PASSWORD}/${NEW_UDP2RAW_PASSWORD}/g" "${UDP2RAW_CONF}"
        read_udp2raw_password
        [[ "${UDP2RAW_PASSWORD}" != "${NEW_UDP2RAW_PASSWORD}" ]] && echo -e "${Error} UDP2Raw连接密码修改失败 !" && exit 1
        echo -e "${Info} UDP2Raw连接密码已修改为 ${UDP2RAW_PASSWORD} !"
    fi
}


curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt update && apt install -y docker-ce jq
enable_bbr
mkdir /root/ss-config
if [ ! -f ${DDNS_CONF} ]; then
	wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/ddns-config.json
fi
if [ ! -f ${SS_CONF} ]; then
	wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/shadowsocks-config.json
fi
if [ ! -f ${UDP2RAW_CONF} ]; then
	wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/udp2raw.conf
fi
if [ ! -f ${UDP2RAW_BIN} ]; then
    wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/udp2raw_amd64
    chmod 755 ${UDP2RAW_BIN}
fi
if [ ! -f ${UDPSPEEDER_CONF} ]; then
	wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/udpspeeder-config.json
fi
if [ ! -f ${UDPSPEEDER_BIN} ]; then
    wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/speederv2_amd64
    chmod 755 ${UDPSPEEDER_BIN}
fi
if [ ! -f ${UDPSPEEDER_SCRIPT} ]; then
    wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/udpspeeder
    chmod 755 ${UDPSPEEDER_SCRIPT}
fi
if [ ! -f ${UDP2RAW_SCRIPT} ]; then
    wget -N --directory-prefix=/root/ss-config https://raw.githubusercontent.com/ivanstang/ss-config/master/udp2raw
    chmod 755 ${UDP2RAW_SCRIPT}
fi

change_ddns_host
verify_ddns
config_ss_password
config_ss_port
config_ss_encryption
docker pull shadowsocks/shadowsocks-libev
docker rm -f ss
docker run -e PASSWORD=${SS_PASSWORD} -e METHOD=${SS_METHOD} -p ${SS_PORT}:8388 -p ${SS_PORT}:8388/udp --name ss -d shadowsocks/shadowsocks-libev

config_udpspeeder
/root/ss-config/udpspeeder restart

config_udp2raw
/root/ss-config/udp2raw restart

if [ -f "/etc/rc.local" ]; then
    mv /etc/rc.local /etc/rc.local.old
fi
wget -N --directory-prefix=/etc https://raw.githubusercontent.com/ivanstang/ss-config/master/rc.local
chmod 755 /etc/rc.local
