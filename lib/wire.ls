require! \object-path

module.exports = (options = {}) ->
  throw 'Socket required' if not options.socket
  socket    = options.socket
  channel   = options?channel or \session
  validator = options?validator
  logger    = options?logger
  observers = {}
  observers-all = []
  validation-observers-all = []
  socket.on channel, ([path, value]) ->
    logger 'Session received', path, value if logger
    validation = {}
    if validator
      validation = {}
      if not validator.validate path, value
        for error in validator.errors
          prop = path + error.data-path
          if error.keyword is \required
            prop = "#prop.#{error.params.missing-property}"
          if error.keyword is \additionalProperties
            prop = "#prop.#{error.params.additional-property}"
          if not $get validation, prop
            $set validation, prop, error{keyword, message}
    if Obj.empty validation
      for fn in observers-all
        fn path, value
      for fn in (observers[camelize path] or [])
        fn value, path
    else
      logger 'Validation fault', path, value, validation if logger
      socket.emit "#{channel}-validation", [ path, validation ]
  socket.on "#{channel}-validation", ([path, value]) ->
    logger 'Validation received', path, value if logger
    for fn in validation-observers-all
      fn path, value
  wire =
    cache: {}
    send: (path, value) ->
      if value?$get
        value = value.$get!
      object-path.set wire.cache, path, value
      logger 'Session sending', path, value if logger
      socket.emit channel, [ path, value ]
    observe: (paths, fn) ->
      if not is-array paths
        paths = [ paths ]
      for path in paths
        path = camelize path
        observers[path] ?= []
        observers[path].push fn
    observe-all: (fn) ->
      observers-all.push fn
    observe-all-validation: (fn) ->
      validation-observers-all.push fn
    forget: (path, fn) ->
      path = camelize path
      observers[path] = reject (-> it is fn), observers[path]
    invalidate: (path, validation) ->
      obj = {}
      object-path.set(obj, path, validation)
      logger 'Validation fault', path, obj if logger
      socket.emit "#{channel}-validation", [ path, obj ]

