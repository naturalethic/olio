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
require! \deep-extend
require! \livescript
Module = (require \module).Module

# -----------------------------------------------------------------------------
# Global assignments.  Please keep all global assignments within this area.
# -----------------------------------------------------------------------------

process <<< child_process
global  <<< console
global  <<< prelude-ls

array-replace = (it, a, b) -> index = it.index-of(a); it.splice(index, 1, b) if index > -1; it

global <<< do
  pp:            require './pp'
  co:            co
  fs:            fs <<< { path: path }
  glob:          glob
  livescript:    livescript
  extend:        deep-extend
  watcher:       chokidar
  Promise:       bluebird
  promise:       bluebird
  promisify:     bluebird.promisify
  promisify-all: bluebird.promisify-all
  is-array:      -> typeof! it is \Array
  is-function:   -> typeof! it is \Function
  is-number:     -> typeof! it is \Number
  is-object:     -> typeof! it is \Object
  is-string:     -> typeof! it is \String
  is-undefined:  -> typeof! it is \Undefined

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

global.debounce = (func, wait = 300) ->
  timeout = null
  ->
    args = arguments
    clear-timeout timeout
    timeout := set-timeout (~>
      timeout := null
      func.apply this, args
    ), wait

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

global.olio =
  config:  require "#{process.cwd!}/olio.ls"
  task:    [last((delete optimist.argv.$0).split ' ')] ++ delete optimist.argv._
  option:  pairs-to-obj(obj-to-pairs(optimist.argv) |> map -> [camelize(it[0]), it[1]])

if fs.exists-sync './host.ls'
  extend olio.config, require "#{process.cwd!}/host.ls"

if olio.config.log?identifier
  global <<< do
    log:   (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.log ...args
    info:  (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.info ...args
    warn:  (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.warn ...args
    error: (...args) -> args.unshift "[#{olio.config.log.identifier}]"; console.error ...args

# -----------------------------------------------------------------------------
# End global assignments.
# -----------------------------------------------------------------------------

# Load plugin and project tasks.  Project tasks will mask plugins of the same name.
task-modules = pairs-to-obj (((glob.sync "#{process.cwd!}/node_modules/olio*/task/*") ++ glob.sync("#{process.cwd!}/task/*")) |> map ->
  [ (camelize fs.path.basename(it).replace //#{fs.path.extname it}$//, ''), it ]
)

# Print list of tasks if none given, or task does not exist.
if !olio.task.0 or !task-modules[camelize olio.task.0]
  exit 'No tasks defined' if !(keys task-modules).length
  info 'Tasks:'
  keys task-modules |> each -> info "  #it"
  process.exit!

task-module = new Module
# task-module.paths = [ "#{process.cwd!}/node_modules/olio/node_modules", "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
task-module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib", "#{__dirname}/../lib" ]
task-module._compile (livescript.compile ([
  (fs.read-file-sync task-modules[camelize olio.task.0] .to-string!)
].join '\n'), { +bare }), task-modules[camelize olio.task.0]
task-module = task-module.exports

# Print list of subtasks if one is acceptable and none given, or subtask does not exist.
if !(olio.task.1 and task = task-module[camelize olio.task.1.to-string!]) and !(task = task-module[camelize olio.task.0])
  info 'Subtasks:'
  keys task-module
  |> filter -> it != camelize olio.task.0
  |> each -> info "  #{dasherize it}"
  process.exit!

# Provide watch capability to all tasks.
if olio.option.watch and task-module.watch
    process.argv.shift!
    process.argv.shift!
    argv = olio.task ++ process.argv
    array-replace argv, '--watch', '--supervised'
    while true
      child = process.spawn-sync fs.path.resolve('node_modules/.bin/olio'), argv, { stdio: 'inherit' }
      if child.error
        info child.error
        process.exit!
else if olio.option.supervised
  watcher.watch (task-module.watch or []), persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    process.exit!
  co task
else
  co task
