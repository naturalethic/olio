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
    session.logger = $info
    session.observe \end, ->
      $info 'Disconnecting'
      session.socket.disconnect!
    glob.sync 'react/**/*' |> each ->
      module = new Module
      module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
      module._compile livescript.compile ([
        "export $local = {}"
        "$info = -> $local.info ...&"
        (fs.read-file-sync it .to-string!)
      ].join '\n'), { +bare }
      module.exports.$local.info = $info
      return if not module.exports.session
      keys module.exports.session |> each (key) ->
        # reactor = co.wrap(module.exports.session[key])
        reactor = module.exports.session[key]
        reactor.bind module.exports
        $info 'Observing', key
        session.observe key, co.wrap ->*
          $info "Session reaction '#key'", it
          tx = yield world.transaction!
          try
            yield reactor tx, session, it
            yield tx.commit!
          catch e
            info e
            yield tx.rollback!
        # session.observe ((dasherize key).replace /-/g, '.'), co.wrap ->*
        #   $info "Session reaction '#{dasherize key}'", it
        #   tx = yield world.transaction!
        #   try
        #     module.exports[key] tx, session
        #     yield tx.commit!
        #   catch
        #     yield tx.rollback!
        # module.exports[key] = co.wrap(module.exports[key])
        # module.exports[key].bind module.exports
        # $info 'Observing', (dasherize key).replace(/-/g, '.')
        # session.observe ((dasherize key).replace /-/g, '.'), co.wrap ->*
        #   $info "Reaction: #{dasherize key}", it
        #   tx = yield world.transaction!
        #   try
        #     module.exports[key] tx, session
        #     yield tx.commit!
        #   catch
        #     yield tx.rollback!


    # session.observe \id, co.wrap ->*
    #   if not id = session.get \id
    #     session session!{route}
    #   else
    #     if id == \nobody
    #       session.set \route, ''
    #     record = first (yield r.table(\session).filter(id: id))
    #     if record
    #       $info 'Loading session', record
    #       session record
    #     else if session.get \persistent
    #       $info 'Creating session', it
    #       yield r.table(\session).insert it
    #     else
    #       $info 'Deleting session id'
    #       session.del \id
    # session.observe-deep '', co.wrap ->*
    #   return if not session.get \persistent
    #   return if not session.get \id
    #   return if session.get(\id) is \nobody
    #   yield r.table(\session).get(session.get \id).update session!
    #   $info 'Session saved', session!