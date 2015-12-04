Module = (require \module).Module
require! \node-static
require! \http
require! 'socket.io': socket-io
require! \co
require! \rivulet
require! \world

export watch = [ __filename, \olio.ls, \session.ls, \react, "#__dirname/../lib" ]

export session = ->*
  file = new node-static.Server './public'
  server = http.create-server (request, response) ->
    if not fs.exists-sync "./public#{request.url}"
      request.url = '/'
    request.add-listener \end, ->
      file.serve request, response
    .resume!
  port = olio.option.port or olio.config.web?port or 8000
  schema = require "#{process.cwd!}/session"
  server.listen port, '0.0.0.0'
  server = socket-io server
  server.on \connection, (socket) ->
    $info = (...args) ->
      date = (new Date).toISOString!split \T
      if is-string(args.0)
        args.0 = args.0.magenta
      args.unshift "#{date.0.cyan}#{'T'.grey}#{date.1.cyan} #{socket.handshake.address.yellow} #{'INFO'.green}"
      if is-object(last args) or is-array(last args)
        obj = args.pop!
      info ...args
      pp obj if obj
    $info 'Connection established'
    session = rivulet {}, socket, \session
    session.$logger = $info
    session.$observe '$.end', ->
      $info 'Disconnecting'
      session.$socket.disconnect!
    glob.sync 'react/**/*' |> each ->
      module = new Module
      module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules" ]
      module._compile livescript.compile ([
        "export $local = {}"
        "$info = -> $local.info ...&"
        (fs.read-file-sync it .to-string!)
      ].join '\n'), { +bare }
      module.exports.$local.info = $info
      return if not module.exports.session
      keys module.exports.session |> each (key) ->
        reactor = module.exports.session[key]
        reactor.bind module.exports
        $info 'Observing', key
        session.$observe key, co.wrap ->*
          $info "Session reaction '#key'", it
          tx = yield world.transaction!
          tx.$info = $info
          try
            yield reactor tx, session, it
            yield tx.commit!
          catch e
            info e
            yield tx.rollback!
    session.$observe '$.id', co.wrap (id) ->*
      $info 'Session Id', id
      if id
        if not session.persistent
          record = yield world.select '$.session[*].id', id
          if record
            $info 'Loading session', record
            session.persistent = true
            for key, val of record
              session[key] = val
            # XXX: FIX THIS
              # session <<< record
          else
            delete session.id

    session.$observe '$.route', co.wrap (route) ->*
      if (not session.persistent) and session.route and session.route not in <[ login signup]>
        session.route = ''

      # if not id
      #   for key, val of session
      #     delete session[key] if key is not \route
      # else
      #   if id == \nobody
      #     session.route = ''
      #   else
      #     record = yield world.select '$.session[*].id', id
      #     if record
      #       $info 'Loading session', record
      #       session <<< record
      #     else if session.persistent
      #       $info 'Creating session', id
      #       yield world.save \session, session
      #     # else
      #     #   $info 'Deleting session id'
      #     #   delete session.id
    session.$observe '$', debounce 300, co.wrap ->*
      return if not session.persistent
      yield world.save \session, session
      # $info 'Session saved', session.$get!
