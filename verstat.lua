#!/usr/bin/env pandoc-lua
local io       = require 'io'
local os       = require 'os'
local List     = require 'pandoc.List'
local json     = require 'pandoc.json'
local mediabag = require 'pandoc.mediabag'
local path     = require 'pandoc.path'
local zip      = require 'pandoc.zip'

--- Command line arguments
local arg = arg or {}

local appname = 'verstat'

local usage = table.concat {
  'Usage: %s COMMAND [OPTIONS] [PARAMETER]...\n',
  'Options:\n',
  '\t-v: increase verbosity; can be given multiple times\n',
}

function show_usage (progname)
  progname = progname or appname
  io.stderr:write(usage:format(progname))
end

function parse_args (args)
  -- default options
  local options = {
    verbosity = 0,
    command = false,
  }
  local positional_args = List{}

  do
    local i = 1
    while i <= #args do
      if args[i] == '-v' then
        options.verbosity = options.verbosity + 1
        i = i + 1
      elseif args[i]:match '^%-' then
        show_usage(args[0])
        os.exit(1)
      else
        positional_args:insert(args[i])
        i = i + 1
      end
    end
  end
  options.command = positional_args:remove(1)
  return options, positional_args
end

--- Returns the name of the verstat data directory.
local function get_data_directory ()
  if os.getenv(appname .. '_DATA_DIR') then
    return os.getenv(appname .. '_DATA_DIR')
  elseif os.getenv('XDG_DATA_HOME') then
    return path.join{os.getenv('XDG_DATA_HOME'), appname}
  elseif os.getenv('HOME') then
    return path.join{os.getenv('HOME'), '.' .. appname}
  else
    return '_' .. appname
  end
end

--- Returns `true` if there's a file with the given name and `false` otherwise.
local function file_exists (name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

--- Load the packages database
local function load_packages ()
  local db_filename = 'packages.json'
  local datadir = get_data_directory()
  local path_candidates = List {
    path.join{datadir, db_filename},
    db_filename
  }
  local db_path = path_candidates:find_if(file_exists)
  assert(db_path, 'Did not find a package database file.')

  local pkgs_json = io.open('packages.json'):read '*a'
  return json.decode(pkgs_json, false) or
    error 'JSON decoding the content of packages.json failed.'
end

--- Download a package from the web, returning a set of files to install.
-- Each file entry is a triple containing the filename, mime type, and contents.
local function download (pkgname, pkgdata)
  local zip_url = 'https://github.com/' .. pkgdata.repository ..
    '/archive/refs/tags/' .. pkgdata.version .. '.zip'
  local mt, zip_contents = mediabag.fetch(zip_url)

  local archive = zip.Archive(zip_contents)
  local filter_filename = pkgname .. '.lua'

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

  return List{
    {
      'filter/' .. filter_filename,
      'text/x-lua',
      extension.filter
    },
    {
      'filter/' .. pkgname .. '.license',
      'text/plain',
      extension.license
    }
  }
end


--- Packages database
local packages_db = load_packages()

--- Check if the package entry has all expected fields and set implied fields.
local function normalize_package (pkg)
  if not pkg.repository then
    error('Packages of type "github" must list a repository.')
  end
  return pkg
end

--- Get package data from the set of known extensions.
local function get_package_data (pkgname)
  local pkg = packages_db[pkgname] or
    error('Extension ' .. pkgname .. ' not found.')
  return normalize_package(pkg)
end

------------------------------------------------------------------------

local function add_packages (names)
  for _, pkgname in ipairs(names) do
    local pkg = get_package_data(pkgname)
    local files = download(pkgname, pkg)

    -- Write files
    mediabag.empty()
    for _, file in ipairs(files) do
      mediabag.insert(table.unpack(file))
    end
    mediabag.write('.')
    print("✓ " .. pkgname)
  end
end

local opts, positional_args = parse_args(arg)

if opts.command == 'add' then
  -- Each command line argument is taken to be the name of an extension.
  add_packages(positional_args)
else
  io.stderr:write('Unknown command: ' .. opts.command)
  os.exit(2)
end
