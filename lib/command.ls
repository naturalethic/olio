require! \child_process
require! \prelude-ls
require! \colors
require! \bluebird
require! \fs
require! \path
require! \optimist
require! \chokidar
require! \glob

# -----------------------------------------------------------------------------
# Global assignments.  Please keep all global assignments within this area.
# -----------------------------------------------------------------------------

process <<< child_process
global  <<< console
global  <<< prelude-ls

Array::remove  = -> index = @index-of(it); @splice(index, 1) if index > -1; this
Array::replace = (a, b) -> index = @index-of(a); @splice(index, 1, b) if index > -1; this

global <<< do
  fs:            fs <<< { path: path }
  Promise:       bluebird
  promise:       bluebird
  promisify:     bluebird.promisify
  promisify-all: bluebird.promisify-all

# Require this configuration file.  It also proves `cwd` is an olio project root.
if !fs.exists-sync './olio.ls'
  error "You must provide a file named 'olio.ls' in your project root"
  process.exit!

global.olio =
  pg:      require './pg'
  api:     require './api'
  config:  require "#{process.cwd!}/olio.ls"
  task:    {}
  command: head optimist.argv._
  args:    tail optimist.argv._
  option:  optimist.argv

delete olio.option._
delete olio.option.$0

# -----------------------------------------------------------------------------
# End global assignments.
# -----------------------------------------------------------------------------

# Load both built-in and project tasks.  Project tasks will mask built-ins of the same name.
[ "#__dirname/../task/*.ls", "#{process.cwd!}/task/*.ls" ]
|> each ->
  glob.sync it
  |> each ->
    olio.task[fs.path.basename(it, '.ls')] = require it

# Print list of tasks if none given as command, or task does not exist.
if !olio.command or !olio.task[olio.command]
  info 'Tasks:'
  keys olio.task |> each -> info "  #it"
  process.exit!

task = olio.task[olio.command]

# Provide watch capability to all tasks.
if olio.option.watch
    process.argv.replace '--watch', '--supervised'
    process.argv.shift!
    while true
      process.spawn-sync (head process.argv), (tail process.argv), { stdio: 'inherit' }
else if olio.option.supervised
  task[olio.command]!
  # Always include the olio module in the watch list.
  chokidar.watch [ fs.realpath-sync "#__dirname/.." ] ++ (task.watch or []), persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    process.exit!
else
  task[olio.command]!
