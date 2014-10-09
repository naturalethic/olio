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
require! \LiveScript

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
  livescript:    LiveScript
  glob:          glob
  re-uuid:       /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

global.require-dir = ->
  return fold1 (<<<), (& |> map -> require-dir it) if &.length > 1
  it = "#{process.cwd!}/#it" if it.0 != '/'
  return {} if not fs.exists-sync it
  it = fs.realpath-sync it
  pairs-to-obj (glob.sync("#it/*.ls") |> map -> [ fs.path.basename(it, '.ls'), require it ])

global.exec = (command, async) ->
  if async
    child = process.exec command
    child.stdout.on 'data', -> process.stdout.write it
    child.stderr.on 'data', -> process.stderr.write it
  else
    try
      process.exec-sync command
    catch
      false

global.spawn = ->
  words = it.match(/[^"'\s]+|"[^"]+"|'[^'']+'/g)
  child = process.spawn (head words), (tail words)
  child.stdout.on 'data', -> process.stdout.write it
  child.stderr.on 'data', -> process.stderr.write it

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
task-modules = require-dir "#__dirname/../task", "#{process.cwd!}/task"

# Print list of tasks if none given as command, or task does not exist.
if !(task-module = task-modules[olio.command.0])
  info 'Tasks:'
  keys task-modules |> each -> info "  #it"
  process.exit!

# Print list of subtasks if one is acceptable and none given as command, or subtask does not exist.
if !(task = task-module[olio.command.1]) and !(task = task-module[olio.command.0])
  info 'Subtasks:'
  keys task-module
  |> filter -> it != olio.command.0
  |> each -> info "  #it"
  process.exit!

# Provide watch capability to all tasks.
if olio.option.watch
    process.argv.replace '--watch', '--supervised'
    process.argv.shift!
    while true
      process.spawn-sync (head process.argv), (tail process.argv), { stdio: 'inherit' }
else if olio.option.supervised
  # Always include the olio module in the watch list.
  chokidar.watch [ fs.realpath-sync "#__dirname/.." ] ++ (task-module.watch or []), persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    process.exit!
  (co task)!
else
  (co task)!
