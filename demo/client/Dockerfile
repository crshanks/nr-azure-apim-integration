FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

# Use envsubst to inject runtime env vars into nginx config
CMD ["/bin/sh", "-c", "envsubst '${APIM_ENDPOINT} ${NR_LICENSE_KEY}' < /etc/nginx/conf.d/default.conf > /tmp/default.conf && cp /tmp/default.conf /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
