-- Load https://github.com/bungle/lua-resty-template
local template = require 'resty.template'
-- Load redis
local redis = require "resty.redis"
local cjson = require "cjson"
local markdown = require "markdown"
-- Load our blog atom generator
local atom = require "atom"
-- We need os for date formatting
local os = require "os"

-- use nginx $root variable for template dir, needs trailing slash
local TEMPLATEDIR = ngx.var.root .. 'lua/';
-- The git repository storing the markdown files. Needs trailing slash
local BLAGDIR = TEMPLATEDIR .. 'md/'
local BLAGTITLE = 'hveem.no'
local BLAGURL = 'http://hveem.no/'
local BLAGAUTHOR = 'Tor Hveem'
-- URL base
local BASE = '/'


-- the redis db handle
local red = nil

local function filename2title(filename)
    title = filename:gsub('.md$', ''):gsub('-', ' '):gsub("^%l", string.upper)
    return title
end

local function slugify(title)
    slug = title:gsub(' ', '-')
    return slug
end

-- Swap key and values in a table
local function swap(t)
    local a = {}
    for k, v in pairs(t) do
        a[v] = k
    end
    return a
end

-- Helper to iterate a table by sorted keys
local function itersort (t, f)
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

-- Date formatter helper
local function blogdate(timestamp)
    return os.date('!%d %B %Y', timestamp)
end

-- Return a table with post date as key and title as val
local function posts_with_dates(limit)
    local posts, err = red:zrevrange('posts', 0, limit, 'withscores')
    if err then return {} end
    posts = red:array_to_hash(posts)
    return swap(posts)
end

-- 
-- Index view
--
local function index()

    -- increment index counter
    local counter, err = red:incr("index_visist_counter")
    if err then ngx.log(ngx.ERR, 'Error with visit counter: '..err) end
    -- Get 10 posts
    local posts = posts_with_dates(10)
    -- load template
    local context = {
        title = BLAGTITLE, 
        counter = tostring(counter),
        posts = posts,
    }
    -- render template with context
    template.render('index.html', context)
end

-- helper function to return blog content given a title
local function blogcontent(page)
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
    return mdhtml
end

-- 
-- Atom feed view
--
local function feed()

    -- increment feed counter
    local counter, err = red:incr("feed:visit")
    -- Get 10 posts
    local posts = posts_with_dates(10)
    -- Get the HTML content for the content
    local htmlposts = {}
    for date, ptitle in pairs(posts) do
        htmlposts[ptitle] = blogcontent(ptitle)
    end
    -- Set correct content type
    ngx.header.content_type = 'application/atom+xml'
    ngx.print( atom.generate_xml(BLAGTITLE, BLAGURL, BLAGAUTHOR .. "'s blog", BLAGAUTHOR, 'feed/', posts, htmlposts) )

end

--
-- the about view
--
local function about()
    -- increment about counter
    local counter, err = red:incr("about_visist_counter")

    local context = {title = 'My lua micro web framework', counter = tostring(counter) }
    template.render('about.html', context)
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
    local mdhtml = blogcontent(page)
    -- increment visist counter
    local counter, err = red:incr(page..":visit")

    -- Get more posts to be linked
    local posts = posts_with_dates(5) 

    local ctx = {
        created = blogdate(date),
        content = mdhtml,
        title = filename2title(page),
        filename2title = filename2title,
        posts = posts,
        counter = counter,
    }
    template.render('blog.html', ctx)
end

-- 
-- Initialise db
--
local function init_db()
    -- Start redis connection
    red = redis:new()
    local ok, err = red:connect("127.0.0.1", 6379)
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
    ['about$']    = about,
    ['feed/$']    = feed,
    ['(.*)$']     = blog,
}

-- Enable access to some functions in template
template.itersort = itersort
template.filename2title = filename2title
template.blogdate = blogdate
template.swap = swap

-- Set the content type
ngx.header.content_type = 'text/html';

-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "oj") -- regex mather in compile mode
    if match then
        init_db()
        exit = view(match) or ngx.HTTP_OK
        end_db()
        ngx.exit( exit )
    end
end
-- no match, return 404
--ngx.exit( ngx.HTTP_NOT_FOUND )
