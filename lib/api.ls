require! \koa

export start = (port = 9010) ->
  app = koa!
  app.use ->*
    @body = 'ok'
  app.listen port
