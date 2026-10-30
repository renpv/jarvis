# Gerado por provision/30-dns-caddy.sh. Cada site declara onde escuta (bind):
#   - VPN (@WG_SERVER_IP@), só HTTP: dashboard do Hermes e apps do Jarvis;
#   - IP público, com HTTPS automático: só o Chatwoot.
# Não use default_bind nem auto_https off globais: o primeiro vaza para os emissores de certificado
# e o segundo desliga o HTTPS do Chatwoot. O usuário e o hash da senha do dashboard vêm de
# /etc/caddy/secrets.env (fora do Git).
{
	# API de administração num socket que só o usuário caddy acessa (não em localhost,
	# onde qualquer usuário local — inclusive o hermes — poderia reconfigurar o Caddy).
	admin unix//run/caddy/admin.sock
}

http://hermes.@DOMAIN@ {
	bind @WG_SERVER_IP@
	basic_auth {
		{$DASHBOARD_USER} {$DASHBOARD_HASH}
	}
	# A aba Chat usa WebSocket, e o dashboard só aceita a Origin do endereço em que escuta
	# (127.0.0.1). Proteção contra "cross-site WebSocket hijacking", feita aqui: Origin de
	# outro site (ou de outro app *.jarvis.lan) leva 403; a certa é reescrita para o bind.
	@outra_origem {
		header Origin *
		not header Origin http://hermes.@DOMAIN@
	}
	respond @outra_origem "origem não permitida" 403
	reverse_proxy 127.0.0.1:@DASHBOARD_PORT@ {
		header_up Host 127.0.0.1:@DASHBOARD_PORT@
		header_up Origin http://127.0.0.1:@DASHBOARD_PORT@
	}
}

# Chatwoot: o único site público, com certificado do Let's Encrypt automático.
# O http:// precisa de site próprio com bind no IP público: com outro site já na porta 80 (o da VPN),
# o Caddy põe o redirect automático naquele servidor, e a 80 pública (desafio do Let's Encrypt e
# redirect para https) ficaria fechada.
http://@CHATWOOT_DOMAIN@ {
	bind @PUBLIC_IP@
	redir https://{host}{uri} 308
}

# Criação do primeiro administrador e o console super_admin pedem a mesma senha do dashboard:
# sem isso, quem abrisse o site primeiro criaria o super admin.
@CHATWOOT_DOMAIN@ {
	bind @PUBLIC_IP@
	@CHATWOOT_TLS@
	@restrito path /installation* /super_admin*
	basic_auth @restrito {
		{$DASHBOARD_USER} {$DASHBOARD_HASH}
	}
	reverse_proxy 127.0.0.1:@CHATWOOT_PORT@
}

# Apps publicados pelo Hermes (um arquivo por app, gerado por jarvis-expose, com bind na VPN).
import /etc/caddy/apps.d/*.caddy
