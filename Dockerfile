FROM openresty/openresty:alpine-fat

# pgmoon: PostgreSQL client thuần Lua
# lua-resty-http: HTTP client cho reverse proxy
RUN opm get leafo/pgmoon \
 && opm get ledgetech/lua-resty-http
RUN /usr/local/openresty/bin/opm get fffonion/lua-resty-openssl

WORKDIR /usr/local/openresty/nginx
