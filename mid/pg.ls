export incoming = ->*
  @pg = yield olio.pg.connect-pool "postgres://postgres@localhost/#{olio.config.pg.db}"
  this <<< @pg.model
  this <<< @pg{exec, first, relate, related, save, wrap}
  yield @pg.exec 'BEGIN'

export outgoing = ->*
  if @pg.error!
    yield @pg.exec 'ROLLBACK'
  else
    yield @pg.exec 'COMMIT'
  @pg.release!
