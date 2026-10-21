{
  "log": {
    "loglevel": "debug",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": 10086,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "{{UUID}}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "{{WS_PATH}}"
        }
      }
    },
    {
      "port": 10087,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "{{UUID}}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "{{XHTTP_PATH}}",
          "mode": "auto"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
