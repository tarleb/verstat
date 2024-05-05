local json = require 'pandoc.json'
local path = require 'pandoc.path'
local zip = require 'pandoc.zip'

local name = arg[1] or error 'no extension given'

local packages_json = io.open('packages.json'):read '*a'
local packages = json.decode(packages_json, false) or
  error 'JSON decoding the content of packages.json failed.'

local pkg = packages[name] or
  error('Extension ' .. name .. ' not found.')

if not pkg.repository then
  error('Packages of type "github" must list a repository.')
end

local zip_url = 'https://github.com/' .. pkg.repository ..
  '/archive/refs/tags/' .. pkg.version .. '.zip'
local mt, zip_contents = pandoc.mediabag.fetch(zip_url)

print(mt, 'length: ' .. tostring(#zip_contents))

local archive = zip.Archive(zip_contents)
local filter_filename = name .. '.lua'

local extension = {}
for _, entry in pairs(archive.entries) do
  if path.filename(entry.path) == filter_filename and
     entry:symlink() == nil then
    extension.filter = entry:contents()
  end
  if path.filename(entry.path) == 'LICENSE' then
    extension.license = entry:contents()
  end
end

if not extension.filter then
  error('Found no filter in the zip.')
end
if not extension.license then
  error('Found no license in the zip.')
end

local target_file = {
  filter = 'filter/' .. filter_filename,
  license = 'filter/' .. name .. '.license',
}

pandoc.mediabag.insert(target_file.filter, 'text/x-lua', extension.filter)
pandoc.mediabag.insert(target_file.license, 'text/plain', extension.license)
pandoc.mediabag.write('.')
