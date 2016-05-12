How to use Nginx for SSL termination from any domain
====================================================

(Or rather, any domain that you have the certs for!)

It's pretty common for cloud services to let customers use their own
domain names. For instance blog.mycompany.com might live on Medium's
infrastructure.

All that's required is for the blog entry of my DNS to point to the IP
Address of Medium. On Medium's side some logic will be required to
point visitiors with HTTP Host headers `blog.mycompany.com` to the
right content.

Things are great! But wait we're not done, I need my blog on
https. After all it's 2016 and free options for certs are abundant. So
there is no excuse, right ?

But it's not that simple. Serving SSL traffic for multiple hosts out
of the edge node has never been trivial. Server Name Indication (SNI),
is an extension of TLS acting like the Host header for HTTP that
enables us to do this. It was actually not part of the original SSL
spec, and was later added in 2003 [1], and for the rest of this we'll
disregard the fact that there are still web browsers out there that do
not support it [2].

Doing this with a stock Nginx we'd be required to modify the conf and
hot reload Nginx for any cert modification, which can become quite
heavy if you're the edge node for many customers.

In the following we'll look in details at using the Nginx Lua module
to solve this issue.

Prerquisites
============

    * Install OpenResty (Nginx + Lua prepackaged) :
    https://openresty.org/en/getting-started.html

    * Install Hashicorp's Vault that we'll use as mini-pki to generate certs.
    https://www.vaultproject.io/docs/install/index.html


DNS Entries
===========

Configure some DNS entries to point to your machine. Out in the real
world, customers would be pointing their authoritative DNS to point to
one of the IP of your edge node.

For this demonstration, let's just edit `/etc/hosts` and add a few entries :

```
127.0.0.1       blah.com
127.0.0.1       foo.com
127.0.0.1       example.foo.com
127.0.0.1       blog.foo.com
127.0.0.1       baz.com
127.0.0.1       bar.com
```


Generate some certs with Vault
==============================
https://www.vaultproject.io/docs/secrets/pki/

`$ vault server -dev`

`$ vault mount pki`
`$ vault mount-tune -max-lease-ttl=87600h pki`
`$ vault write pki/root/generate/internal common_name=star ttl=87600h > star_ca.pub.pki`
`$ vault write pki/roles/anything allow_any_name=true`
`$ vault write pki/issue/anything common_name=blah.com > blah.com.pki`

We're writing to `.pki` files, since vault outputs the certificate and
the key in one single file. We'll simply use an editor to separate
them into corresponding `.pem` and `.key` file for the certificate and
the secret key respectively.


Configure Nginx
===============

Static virtual hosts
--------------------

This is the configuration described at the beginning of the article.
We'll be able to add hosts, but any endpoint will require a hot
restart of Nginx.

Let's start with `blah.com`

```
    # blah.com virtual server
    server {
        listen *:8443;

        ssl on;

        server_name blah.com;
        ssl_certificate         certs/blah.com.pem;
        ssl_certificate_key     certs/blah.com.key;

        # teminate SSL and proxy to the actual internal web service.
        location / {
            proxy_pass http://127.0.0.1:8000;
        }
     }
```

`$ nginx -p `pwd` -c conf/nginx_static.conf`
`$ curl 'https://blah.com:8443' --cacert conf/certs/star_ca.pem
Hello world!
`

Let's now add another host in the configuration

```
    # foo.com virtual server
    server {
       listen *:8443;

       ssl on;

       server_name foo.com;
       ssl_certificate         certs/foo.com.pem;
       ssl_certificate_key     certs/foo.com.key;

       location / {
           proxy_pass http://127.0.0.1:8000;
       }
    }
```

`$ nginx -p `pwd` -c conf/nginx_static.conf -s reload`
`$ curl 'https://blah.com:8443' --cacert conf/certs/star_ca.pem
Hello world!`
`$ curl 'https://foo.com:8443' --cacert conf/certs/star_ca.pem
Hello world!
`

Hooray! We've added a domain name using SNI, terminated the SSL
connection for both and send it successfully to our 'Hello world'
backend app.

But hopefully we can do that without even reloading Nginx, or
modifying the configuration at all. Stay tuned.

Dynamic virtual hosts
---------------------

Here we're going to make a virtual server that can present the
certificate for any host that we have the certificate for. It's worth
noting that the paradigm above cannot be used. If we're making a
virtual host without a `server_name` directive all the traffic will
end up there. But if there is another server block with a specified
`server_name`, the traffic that doesn't match it Will Not end up in
our unnamed server block.

I'm using the `ssl_certificate_by_lua_file` directive in the Nginx
configuration to present the correct certificate. And the module
`ngx.ssl` that comes pre-packaged with OperResty. The module allows us
to lookup what SNI hostname the client sent, then load a suitable
certificate for that hostname.

In the code example that comes along we'll attempt to load
certificates from files, we'll first lookup the exact hostname, and if
not found a wildcard certificate. (eg. first blog.mycompany.com, then
'*.mycompany.com'). Certs are then cached in shared memory using
ngx.shcache [3], a module I wrote some time ago.

`$ nginx -p `pwd` -c conf/nginx_dynamic.conf`

Using the dedicated example.foo.com cert :
`$ curl 'https://example.foo.com:8443' --cacert $HOME/Dev/ngx_lua_ssl/conf/certs/star_ca.pem
Hello World!`

Using a generic *.foo.com cert :

`$ curl 'https://blog.foo.com:8443' --cacert $HOME/Dev/ngx_lua_ssl/conf/certs/star_ca.pem
Hello World!`

Voila! We've made a simple SSL termination at the edge which doesn't
need to hot-reload Nginx all the time.


Links
=====

[1] https://en.wikipedia.org/wiki/Server_Name_Indication
[2] https://cloudflare.github.io/sni-visualization/
[3] https://github.com/mtourne/ngx.shcache
