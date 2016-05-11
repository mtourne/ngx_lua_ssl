Nginx as SSL Edge-node
======================

It's pretty common for cloud services to let customers use their own
domain names. For instance blog.mycompany.com might live on Medium's
infrastructure.

All that's required is for the blog DNS entry to point to the IP
Address of Medium. On Medium's side some logic will be required to
point visitiors with HTTP Host headers `blog.mycompany.com` to the
right content.

Things are great, until we introduce SSL and certificates into the
mix. After all it's 2016 and free options for certs are abundant. So I
should be expecting https for my blog, right ?

But it's not that simple. Serving SSL traffic for multiple hosts out
of the edge node has never been trivial. SNI, acting like the Host
header in the HTTP spec is was let us do this. It was actually not
part of the original SSL spec, and was later added in 2003 [1], and
for the rest of this article we'll disregard the fact that there are
still web browsers out there that do not support it.

Doing this with a stock Nginx we'd be required to modify the conf and
hot reload Nginx for any cert modification, which can become quite
heavy if you're the edge node for many customers.

In the following we'll look in details at using the Nginx Lua module
to solve this issue.

Prerquisites
============

    * Install OpenResty (Nginx + Lua prepackaged) :
    https://openresty.org/en/getting-started.html

    * Install Hashicorp's Vault for our mini-pki
    https://www.vaultproject.io/docs/install/index.html


DNS Entries
===========

Configure some DNS entries to point to your machine, out in the real
this world it's easy to imagine how multiple DNS entries would point
to the IP of your edge node.

For this demonstration, let's just edit `/etc/hosts` and add a few entries :

```
127.0.0.1       blah.com
127.0.0.1       foo.com
127.0.0.1       example.foo.com
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



Links
=====

[1] https://en.wikipedia.org/wiki/Server_Name_Indication
