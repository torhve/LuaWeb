A Simple nameless blog engine
======

My motivation was just having a simple no frills blog for publishing some of my latest writings. This project is not very serious and is meant for personal use.
The most unusual part about this project is it's usage of nginx as the "app server". This is possible using lua, since there is a nginx lua module that enables you to call lua from the nginx conf. Have a look at [openresty's site](http://openresty.org) for more about what it enables you to do.
One of the coolest things about Lua is its speed, check out <http://www.techempower.com/benchmarks/>

The full stack:

##### Components

-  [Lua(jit)](http://luajit.org/luajit.html) Superfast and lean scripting language.
-  [Nginx](http://nginx.org/) Superfast and lean web server.
-  [Openresty](http://openresty.org/) A bundle of plugins for nginx letting me run lua code directly in Nginx. 
-  [Redis](http://redis.io/) In-memory database with disk persist.
-  [Git](http://git-scm.com/) Disitributed version control system.
-  [Markdown](http://en.wikipedia.org/wiki/Markdown) Lightweight markup language.


Now we know the components in use, so now I can explain how they work togheter. Lua runs inside nginx and is being used as backend as it is being called in the web developer world. There is little to no javascript running in this setup. The backend loads a few templates (header, footer, etc) using Zed Shaw's tiny templating engine from another micro framework in Lua, check it out here: [Tir Microframework](http://sheddingbikes.com/posts/1289384533.html)

The index template looks in the predefined git repository for a list for markdown files, these will be the blog posts, then it runs git log to figure out the date the blog post was created and displays a list.

The blog post template extracts a filename from the URL and loads the corresponding Markdown file. The markdown gets compiled with Niklas Frykholm's Markdown parser written in lua.

Each view has a simple counter in redis, with the primary motivation of showcasing the speed of these pages. The Redis database is not really needed for any functionality.

Publishing a new article is then just the small matter of writing a Markdown file and pushing it to the blog repository and then it will display in the list and have its own permanent URL.

> nginx.conf, the Nginx web server configuration

    lua_package_path '/home/www/lua/?.lua;;';
    server {
      listen 80;
      server_name example.no www.example.no;
      set $root /home/www/;
      root $root;

      # Serve static if file exist, or send to lua
      location / { try_files $uri @lua; }
      # Lua app
      location @lua {
          content_by_lua_file $root/lua/index.lua;
      }
    }              

## Author

Tor Hveem <tor@hveem.no>

## License and Copyright

This code is licensed under the BSD license.

Copyright (C) 2013, by Tor Hveem <tor@hveem.no>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Neither the name of the <ORGANIZATION> nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

