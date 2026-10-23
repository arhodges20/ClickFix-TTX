FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx ca-certificates curl procps \
 && rm -rf /var/lib/apt/lists/*

ADD https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 /usr/bin/cloudflared
RUN chmod +x /usr/bin/cloudflared

RUN unlink /etc/nginx/sites-enabled/default
COPY nginx.conf /etc/nginx/nginx.conf

COPY ttx /var/www/html/ttx
RUN chmod +x /var/www/html/ttx/set-url.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
