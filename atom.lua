-- Copyright (C) 2013 Tor Hveem (thveem)

-- Simple atom generator in lua 

local tirtemplate = require('tirtemplate')
local setmetatable = setmetatable
local ipairs = ipairs
local pairs = pairs
local table = table
local tonumber = tonumber
local ngx = ngx
local os = os

module(...)

_VERSION = '0.01'

local mt = { __index = _M }

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

local function rfc3339(date)
    return os.date('!%Y-%m-%dT%H:%M:%SZ', date)
end


function generate_xml(title, link, description, author, feedurl, entries)
    local entriesxml = ''
    local updated 

    for date, ptitle in itersort(entries) do
        if updated == nil then
            updated = rfc3339(date)
        end
        local etitle = ptitle:gsub('-', ' ')
        local entryxml = [[
  <entry>
    <title>]]..etitle..[[</title>
    <id>]]..link..ptitle..[[</id>
    <link rel="alternate" href="]]..link..ptitle..[[" />
    <updated>]]..rfc3339(date)..[[</updated>
  </entry>
]]
        entriesxml = entriesxml .. entryxml
    end

    local xml = [[
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">

  <title>]] .. title .. [[</title>
  <link href="]]..link..[["/>
  <updated>]]..updated..[[</updated>
  <author>
    <name>]]..author..[[</name>
  </author>
  <link rel="self" href="]]..link..feedurl..[[" />
  <id>]]..link..[[</id>
]]..entriesxml..[[
</feed>
]]
    return xml
end

local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        error('attempt to write to undeclared variable "' .. key .. '"')
    end
}

setmetatable(_M, class_mt)
