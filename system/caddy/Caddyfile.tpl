# Gerado por provision/30-dns-caddy.sh. O Caddy escuta APENAS no IP da VPN.
# O usuário e o hash da senha do dashboard vêm de /etc/caddy/secrets.env (fora do Git).
{
	default_bind @WG_SERVER_IP@
	auto_https off
	admin localhost:2019
}

http://hermes.@DOMAIN@ {
	basic_auth {
		{$DASHBOARD_USER} {$DASHBOARD_HASH}
	}
	reverse_proxy 127.0.0.1:@DASHBOARD_PORT@ {
		header_up Host 127.0.0.1:@DASHBOARD_PORT@
	}
}

# Apps publicados pelo Hermes (um arquivo por app, gerado por jarvis-expose).
import /etc/caddy/apps.d/*.caddy
