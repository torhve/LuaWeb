-- load our template engine
local tirtemplate = require('tirtemplate')
-- Load redis
local redis = require "resty.redis"
local cjson = require "cjson"
local markdown = require "markdown"

-- Set the content type
ngx.header.content_type = 'text/html';

-- use nginx $root variable for template dir, needs trailing slash
TEMPLATEDIR = ngx.var.root .. 'lua/';
-- The git repository storing the markdown files. Needs trailing slash
BLAGDIR = TEMPLATEDIR .. 'md/'
BLAGTITLE = 'hveem.no'

-- the db global
red = nil

-- Return a table with post date as key and title as val
local function posts_with_dates(limit)
    local posts, err = red:zrevrange('posts', 0, limit, 'withscores')
    if err then return {} end
    posts = red:array_to_hash(posts)
    return swap(posts)
end

function filename2title(filename)
    title = filename:gsub('.md$', ''):gsub('-', ' ')
    return title
end

function slugify(title)
    slug = title:gsub(' ', '-')
    return slug
end

-- Swap key and values in a table
function swap(t)
    local a = {}
    for k, v in pairs(t) do
        a[v] = k
    end
    return a
end

-- Helper to iterate a table by sorted keys
function itersort (t, f)
  local a = {}
  -- Sort on timestamp key reverse
  f = function(a,b) return tonumber(a)>tonumber(b) end
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end

-- 
-- Index view
--
local function index()
    
    -- increment index counter
    local counter, err = red:incr("index_visist_counter")
    -- Get 10 posts
    local posts = posts_with_dates(10)
    -- load template
    local page = tirtemplate.tload('index.html')
    local context = {
        title = BLAGTITLE, 
        counter = tostring(counter),
        posts = posts,
    }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end

--
-- the about view
--
local function about()
    -- increment about counter
    local counter, err = red:incr("about_visist_counter")

    -- load template
    local page = tirtemplate.tload('about.html')
    local context = {title = 'My lua micro web framework', counter = tostring(counter) }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end

local function saltvirt()
    -- increment saltvirt counter
    local counter, err = red:incr("saltvirt_visist_counter")
    -- load template
    local page = tirtemplate.tload('saltvirt.html')
    local context = {title = 'HTML5 virtualization UI on top of Salt Stack', counter = tostring(counter) }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end
local function icinga()
    -- increment icinga counter
    local counter, err = red:incr("icinga_visit_counter")
    -- load template
    local page = tirtemplate.tload('salt-icinga-nrpe-replacement.html')
    local context = {title = 'Salt as icinga NRPE replacement', counter = tostring(counter) }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end

--
-- blog view for a single post
--
local function blog(match)
    local page = match[1] 
    -- Checkf the requests page exists as a key in the sorted set
    local date, err = red:zscore('posts', page)
    -- No match, return 404
    if err or date == ngx.null then
        return ngx.HTTP_NOT_FOUND
    end
    -- Check if the page is in redis cache
    -- check if the page cache needs updating
    local post, err = red:get('post:'..page..':log')
    if err or post == ngx.null then
        ngx.say('Error fetching post from database')
        return 500
    end
    local postlog = cjson.decode(post)
    local lastupdate = 0
    for ref, attrs in pairs(postlog) do
        local logdate = attrs.timestamp
        if logdate > lastupdate then
            lastupdate = logdate
        end
    end
    local lastgenerated, err = red:get('post:'..page..':cached')
    local nocache = true
    if lastgenerated == ngx.null or err then 
        lastgenerated = 0 
        nocache = true 
    else
        lastgenerated = tonumber(lastgenerated)
    end
    if lastupdate <= lastgenerated then nocache = false end
    local mdhtml = '' 
    if nocache then
        local mdfile =  BLAGDIR .. page .. '.md'
        local mdfilefp = assert(io.open(mdfile, 'r'))
        local mdcontent = mdfilefp:read('*a')
        mdhtml = markdown(mdcontent) 
        mdfilefp:close()
        local ok, err = red:set('post:'..page..':cached', lastupdate)
        local ok, err = red:set('post:'..page..':md', mdhtml)
    else
        mdhtml = red:get('post:'..page..':md')
    end
    -- increment visist counter
    local counter, err = red:incr(page..":visit")

    -- Get more posts to be linked
    local posts = posts_with_dates(5)

    local ctx = {
        created = ngx.http_time(date),
        content = mdhtml,
        title = filename2title(page),
        posts = posts,
        counter = counter,
    } 
    local template = tirtemplate.tload('blog.html')
    ngx.print( template(ctx) )

end

-- 
-- Initialise db
--
local function init_db()
    -- Start redis connection
    red = redis:new()
    local ok, err = red:connect("unix:/var/run/redis/redis.sock")
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end
end

--
-- End db, we could close here, but park it in the pool instead
--
local function end_db()
    -- put it into the connection pool of size 100,
    -- with 0 idle timeout
    local ok, err = red:set_keepalive(0, 100)
    if not ok then
        ngx.say("failed to set keepalive: ", err)
        return
    end
end

-- mapping patterns to views
local routes = {
    ['$']         = index,
    ['saltvirt$'] = saltvirt,
    ['2013/01/05/salt-icinga-nrpe-replacement$'] = icinga,
    ['about$']    = about,
    ['(.*)$']     = blog,
}

local BASE = '/'
-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
        init_db()
        exit = view(match) or ngx.HTTP_OK
        end_db()
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )
