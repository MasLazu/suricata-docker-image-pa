FROM ghcr.io/jasonish/suricata:master

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
COPY templates/ /templates/

# Reputation polling helper
COPY fetch-ipreputation.sh /usr/local/bin/fetch-ipreputation.sh
RUN chmod +x /usr/local/bin/fetch-ipreputation.sh

ENTRYPOINT ["/docker-entrypoint.sh"]