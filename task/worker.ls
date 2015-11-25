require! \browserify
require! \livescript
require! \watchify
require! \node-notifier

export watch = [ __filename ]
setup-bundlers = ->
  bundlers = []
  glob.sync 'worker/*.ls' |> each (path) ->
    name = "#{path.substring 7, path.length - 3}"
    bundler = watchify browserify [ "tmp/#name.js" ], {
      paths:
        fs.realpath-sync "#__dirname/../node_modules"
    }
    build = ->
      script = []
      script.push """
        self <<< require 'prelude-ls'
        if console.log.apply
          <[ log info warn error ]> |> each (key) ~> self[key] = -> console[key] ...&
        else
          <[ log info warn error ]> |> each (key) ~> self[key] = console[key]
      """
      script.push fs.read-file-sync(path).to-string!
      fs.write-file-sync "tmp/#name.js", livescript.compile(script.join('\n'), { -header, +bare })
    bundle = ->
      info "Browserify -> public/#name.js"
      bundler.bundle (err, buf) ->
        return info err if err
        fs.write-file-sync "public/#name.js", buf
        info "--- Done ---"
    bundler.on \update, bundle
    bundlers.push [ bundler, bundle, build ]
  bundlers.build = ->
    bundlers |> each ([bundler, bundle, build]) ->
      build!
      bundle! if not bundler._bundled
    node-notifier.notify title: 'Olio', message: "Workers Built"
  bundlers

export worker = ->*
  exec "mkdir -p tmp"
  exec "mkdir -p public"
  bundlers = setup-bundlers!
  watcher.watch <[ worker olio.ls host.ls ]>, persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    bundlers.build!
  bundlers.build!
