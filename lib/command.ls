require! \child_process
require! \prelude-ls
require! \bluebird
require! \fs
require! \path
require! \optimist
require! \chokidar
require! \glob
require! \co
require! \deep-extend
require! \clone
require! \livescript
require! \node-uuid
require! \harmony-reflect
require! \object-path
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
  uuid:          node-uuid.v4
  shy:           (obj, props) -> (props |> filter -> obj[camelize it]).length < props.length
  livescript:    livescript
  extend:        deep-extend
  clone:         clone
  watcher:       chokidar
  Promise:       bluebird
  promise:       bluebird
  promisify:     bluebird.promisify
  promisify-all: bluebird.promisify-all
  is-array:      -> typeof! it is \Array
  is-function:   -> typeof! it in <[ Function GeneratorFunction ]>
  is-number:     -> typeof! it is \Number
  is-object:     -> typeof! it is \Object
  is-string:     -> typeof! it is \String
  is-undefined:  -> typeof! it is \Undefined
  is-null:       -> typeof! it is \Null
  $set:          (o, k, v) -> object-path.set o, k, v
  $get:          (o, k)    -> object-path.get o, k

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
      (process.exec-sync command).to-string!
    catch
      false

global.debounce = ->
  return if &.length < 1
  wait = 1
  if is-function &0
    func = &0
  else
    wait = &0
  if &.length > 1
    if is-function &1
      func = &1
    else
      wait = &1
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
  process.spawn-sync (head words), (tail words), stdio: \inherit

global.exit = (message) ->
  error new String(message).red if message
  process.exit 1

if !fs.exists-sync './olio.ls'
  exit "You must provide a file named 'olio.ls' in your project root"

global.olio =
  config:  require "#{process.cwd!}/olio.ls"
  task:    [last((delete optimist.argv.$0).split ' ')] ++ delete optimist.argv._
  option:  pairs-to-obj(obj-to-pairs(optimist.argv) |> map -> [camelize(it[0]), it[1]])

if fs.exists-sync './host.ls'
  extend olio.config, require "#{process.cwd!}/host.ls"

olio.config.log ?= {}
olio.config.log.color ?= true

global.color = (c, v) -> (olio.config.log.color and "\x1b[38;5;#{c}m#{v}\x1b[0m") or v


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
task-module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib", "#__dirname/../lib" ]
task-module.paths.push "#__dirname/../node_modules" if fs.exists-sync "#__dirname/../node_modules"
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
