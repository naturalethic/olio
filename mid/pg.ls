module.exports = (next) ->*
  if @ses
    @pg = yield olio.pg.connect-pool "postgres://postgres@#{olio.config.pg.host or 'localhost'}/#{olio.config.pg.db}"
    this <<< @pg.model
    this <<< @pg{exec, first, relate, related, save, wrap}
    yield @pg.exec 'BEGIN'
  try
    yield next
    if @ses
      yield @pg.exec 'COMMIT'
  catch e
    if @ses
      yield @pg.exec 'ROLLBACK'
    throw e
  finally
    if @ses
      @pg.release!
