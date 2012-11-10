local redis = require "resty.redis"

-- load our template engine
local tirtemplate = require('tirtemplate')



-- Set the content type
ngx.header.content_type = 'text/html';

-- use nginx $root variable for template dir
TEMPLATEDIR = ngx.var.root .. 'lua/';

local function index()
    -- Index view
    
    -- Start redis connection
    local red = redis:new()
    local ok, err = red:connect("unix:/var/run/redis/redis.sock")
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end


    -- increment counter
    local counter, err = red:incr("index_visist_counter")

    -- put it into the connection pool of size 100,
    -- with 0 idle timeout
    local ok, err = red:set_keepalive(0, 100)
    if not ok then
        ngx.say("failed to set keepalive: ", err)
        return
    end

    -- load template
    local page = tirtemplate.tload('index.html')
    local context = {counter = tostring(counter) }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end

-- the about view
local function about()
    -- load template
    local page = tirtemplate.tload('about.html')
    local context = {counter = tostring(counter) }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end


-- mapping patterns to views
local routes = {
    ['^/$']      = index,
    ['^/about$'] = about,
}

-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    if ngx.re.match(pattern, ngx.var.uri) then
        view()
        -- return OK, since we called a view
        ngx.exit( ngx.HTTP_OK )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )
