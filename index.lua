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

-- Get all the files in a dir
local function get_posts()
    local directory = shell_escape(BLAGDIR)
    local i, t, popen = 0, {}, io.popen
    local handle = popen('ls "'..directory..'"')
    if not handle then return {} end
    for filename in handle:lines() do
        i = i + 1
        t[i] = filename
    end
    handle:close()
    return t
end

-- Find the commit dates for  a file in a git dir was
local function file2gitci(dir, filename)
    local i, t, popen = 0, {}, io.popen
    local dir, filename = shell_escape(dir), shell_escape(filename)
    local cmd = 'git --git-dir "'..dir..'.git" log --pretty=format:"%ct" --date=local --reverse -- "'..filename..'"'
    local handle = popen(cmd)
    for gitdate in handle:lines() do
        i = i + 1
        t[i] = gitdate
    end
    handle:close()
    return t
end

local function filename2title(filename)
    title = filename:gsub('.md$', ''):gsub('-', ' ')
    return title
end

function slugify(title)
    slug = title:gsub(' ', '-')
    return slug
end

--- Better safe than sorry
function shell_escape(s)
    return (tostring(s) or ''):gsub('"', '\\"')
end

-- 
-- Index view
--
local function index()
    
    -- increment index counter
    local counter, err = red:incr("index_visist_counter")

    local postlist = get_posts()
    local posts = {}
    for i, post in pairs(postlist) do
        local gitdate = file2gitci(BLAGDIR, post)
        -- Skip unversioned files
        if #gitdate > 0 then 
            -- Use first date
            posts[gitdate[1]] = filename2title(post)
        end
    end
    -- Sort on timestamp key
    table.sort(posts, function(a,b) return tonumber(a)>tonumber(b) end)

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
    local mdfiles = get_posts()
    local mdcurrent = nil
    for i, mdfile in pairs(mdfiles) do
        if page..'.md' == mdfile then
            mdcurrent = mdfile
            break
        end
    end
    -- No match, return 404
    if not mdcurrent then
        return ngx.HTTP_NOT_FOUND
    end
    
    local mdfile =  BLAGDIR .. mdcurrent
    local mdfilefp = assert(io.open(mdfile, 'r'))
    local mdcontent = mdfilefp:read('*a')
    mdfilefp:close()
    local mdhtml = markdown(mdcontent) 
    local gitdate = file2gitci(BLAGDIR, mdcurrent)
    -- increment visist counter
    local counter, err = red:incr(page..":visit")

    local ctx = {
        created = ngx.http_time(gitdate[1]),
        content = mdhtml,
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
