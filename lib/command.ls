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
require! \deepmerge

# -----------------------------------------------------------------------------
# Global assignments.  Please keep all global assignments within this area.
# -----------------------------------------------------------------------------

process <<< child_process
global  <<< console
global  <<< prelude-ls

array-replace = (it, a, b) -> index = it.index-of(a); it.splice(index, 1, b) if index > -1; it

global <<< do
  fs:            fs <<< { path: path }
  Promise:       bluebird
  promise:       bluebird
  promisify:     bluebird.promisify
  promisify-all: bluebird.promisify-all
  livescript:    LiveScript
  glob:          glob
  re-uuid:       /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
  system-id:     -> "00000000-0000-0000-0000-00000000000#it"

global.require-dir = ->
  return fold1 (<<<), (& |> map -> require-dir it) if &.length > 1
  it = "#{process.cwd!}/#it" if it.0 != '/'
  return {} if not fs.exists-sync it
  it = fs.realpath-sync it
  pairs-to-obj (glob.sync("#it/*.ls") |> map -> [ fs.path.basename(it, '.ls'), require it ])

global.ex = (command) -> exec command, true
global.exec = (command, async) ->
  if async
    data = []
    return new Promise (resolve, reject) ->
      child = process.exec command
      child.stdout.on 'data', -> data.push it.to-string!; process.stdout.write it.green
      child.stderr.on 'data', -> data.push it.to-string!; process.stderr.write it.red
      child.on 'exit', -> resolve data.join('')
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
  error new String(message).red if message
  process.exit 1

# Require a configuration file.  It also proves `cwd` is an olio project root.
if !fs.exists-sync './olio.ls'
  exit "You must provide a file named 'olio.ls' in your project root"
if !fs.exists-sync './host.ls'
  exit "You must provide a file named 'host.ls' in your project root"


global.olio =
  pg:      require './pg'
  config:  deepmerge (require "#{process.cwd!}/olio.ls"), (require "#{process.cwd!}/host.ls")
  command: delete optimist.argv.$0
  task:    delete optimist.argv._
  option:  pairs-to-obj(obj-to-pairs(optimist.argv) |> map -> [camelize(it[0]), it[1]])

# Load libraries
olio <<< olio.lib = require-dir "#{process.cwd!}/lib"

if olio.config.log?identifier
  global <<< do
    log:   (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.log ...args
    info:  (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.info ...args
    warn:  (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.warn ...args
    error: (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.error ...args


# -----------------------------------------------------------------------------
# End global assignments.
# -----------------------------------------------------------------------------

# Load both built-in and project tasks.  Project tasks will mask built-ins of the same name.
task-modules = require-dir "#__dirname/../task", "#{process.cwd!}/task"

# Print list of tasks if none given, or task does not exist.
if !olio.task.0 or !(task-module = task-modules[camelize olio.task.0])
  exit 'No tasks defined' if !(keys task-modules).length
  info 'Tasks:'
  keys task-modules |> each -> info "  #it"
  process.exit!

# Print list of subtasks if one is acceptable and none given, or subtask does not exist.
if !(olio.task.1 and task = task-module[camelize olio.task.1]) and !(task = task-module[camelize olio.task.0])
  info 'Subtasks:'
  keys task-module
  |> filter -> it != camelize olio.task.0
  |> each -> info "  #{dasherize it}"
  process.exit!

# Provide watch capability to all tasks.
if olio.option.watch
    process.argv.shift!
    process.argv.shift!
    array-replace process.argv, '--watch', '--supervised'
    while true
      child = process.spawn-sync fs.path.resolve('node_modules/.bin/olio'), process.argv, { stdio: 'inherit' }
      if child.error
        info child.error
        process.exit!
else if olio.option.supervised
  # Always include the olio module in the watch list.
  chokidar.watch [ fs.realpath-sync "#__dirname/.." ] ++ (task-module.watch or []), persistent: true, ignore-initial: true, ignored: /(node_modules|\.git)/ .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    process.exit!
  co task
else
  co task
