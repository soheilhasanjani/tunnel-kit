{
	auto_https disable_redirects
}

(app) {
	@ws path {{WS_PATH}}*
	handle @ws {
		reverse_proxy 127.0.0.1:10086
	}

	@xhttp path {{XHTTP_PATH}}*
	handle @xhttp {
		reverse_proxy 127.0.0.1:10087 {
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

:80 {
	handle /.well-known/acme-challenge/* {
		root * /var/www/acme
		file_server
	}
	import app
}

:443 {
	tls {{CERT_FILE}} {{KEY_FILE}}
	import app
}
