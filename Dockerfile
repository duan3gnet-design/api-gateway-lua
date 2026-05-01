FROM openresty/openresty:alpine-fat

RUN /usr/local/openresty/bin/opm get fffonion/lua-resty-openssl

WORKDIR /usr/local/openresty/nginx
