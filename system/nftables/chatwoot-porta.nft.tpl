# Gerado por provision/70-chatwoot.sh; carregado pelo jarvis-chatwoot-porta.service.
# A porta local do Chatwoot (127.0.0.1:@CHATWOOT_PORT@) só aceita conexões do Caddy, do próprio chatwoot
# e do root. Sem isto, qualquer usuário da VPS — inclusive o hermes — falaria direto com o Rails,
# pulando o basic_auth do Caddy em /installation (criação do super admin) e /super_admin.
table inet jarvis_chatwoot
flush table inet jarvis_chatwoot
table inet jarvis_chatwoot {
	chain saida {
		type filter hook output priority 0; policy accept;
		ip daddr 127.0.0.1 tcp dport @CHATWOOT_PORT@ meta skuid != { 0, @CADDY_UID@, @CHATWOOT_UID@ } reject with tcp reset
		ip6 daddr ::1 tcp dport @CHATWOOT_PORT@ meta skuid != { 0, @CADDY_UID@, @CHATWOOT_UID@ } reject with tcp reset
	}
}
