require! \child_process
require! \prelude-ls
require! \colors
require! \bluebird
require! \fs
require! \path
require! \optimist
require! \chokidar
require! \glob
require! \co
require! \harmony-reflect

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

global.require-dir = ->
  return fold1 (<<<), (& |> map -> require-dir it) if &.length > 1
  it = "#{process.cwd!}/#it" if it.0 != '/'
  it = fs.realpath-sync it
  pairs-to-obj (glob.sync("#it/*.ls") |> map -> [ fs.path.basename(it, '.ls'), require it ])

global.exec = ->
  try
    process.exec-sync it
  catch
    false

global.exit = (message) ->
  error message.red
  process.exit 1

# Require a configuration file.  It also proves `cwd` is an olio project root.
if !fs.exists-sync './olio.ls'
  exit "You must provide a file named 'olio.ls' in your project root"

delete optimist.argv.$0

global.olio =
  pg:      require './pg'
  config:  require "#{process.cwd!}/olio.ls"
  command: delete optimist.argv._
  option:  pairs-to-obj(obj-to-pairs(optimist.argv) |> map -> [camelize(it[0]), it[1]])

# -----------------------------------------------------------------------------
# End global assignments.
# -----------------------------------------------------------------------------

# Load both built-in and project tasks.  Project tasks will mask built-ins of the same name.
tasks = require-dir "#__dirname/../task", "#{process.cwd!}/task"

# Print list of tasks if none given as command, or task does not exist.
if !task = tasks[first olio.command]
  info 'Tasks:'
  keys tasks |> each -> info "  #it"
  process.exit!

# Provide watch capability to all tasks.
if olio.option.watch
    process.argv.replace '--watch', '--supervised'
    process.argv.shift!
    while true
      process.spawn-sync (head process.argv), (tail process.argv), { stdio: 'inherit' }
else if olio.option.supervised
  # Always include the olio module in the watch list.
  chokidar.watch [ fs.realpath-sync "#__dirname/.." ] ++ (task.watch or []), persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    process.exit!
  (co task[first olio.command])!
else
  #task[first olio.command]!
  (co task[first olio.command])!
