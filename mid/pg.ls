export incoming = ->*
  @pg = yield olio.pg.connect 'postgres://postgres@localhost/cfh'
  yield @pg.exec 'BEGIN'

export outgoing = ->*
  if @pg.error!
    error "pg: [#{@pg.error!name}] #{@pg.error!message}".red
    yield @pg.exec 'ROLLBACK'
  else
    yield @pg.exec 'COMMIT'
  @pg.release!
