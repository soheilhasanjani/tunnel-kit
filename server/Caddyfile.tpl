{
	https_port {{CADDY_HTTPS_PORT}}
	auto_https disable_redirects
}

https://{{DOMAIN}}:{{CADDY_HTTPS_PORT}} {
	bind 127.0.0.1
	tls {{CERT_FILE}} {{KEY_FILE}}

	@xhttp path {{XHTTP_PATH}}*

	handle @xhttp {
		reverse_proxy 127.0.0.1:{{XHTTP_PORT}} {
			flush_interval -1
			transport http {
				versions h2c
			}
		}
	}

	handle /api/* {
		reverse_proxy 127.0.0.1:8787
	}

	handle {
		root * /var/www/tunnel-kit
		encode gzip
		try_files {path} /index.html
		file_server
	}
}
