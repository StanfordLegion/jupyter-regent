c = get_config()
c.NotebookApp.ip = '*'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False

# Whether to trust or not X-Scheme/X-Forwarded-Proto and X-Real-Ip/X-Forwarded-
# For headerssent by the upstream reverse proxy. Necessary if the proxy handles
# SSL
c.NotebookApp.trust_xheaders = True
