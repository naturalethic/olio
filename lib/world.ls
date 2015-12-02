require! \promise-mysql : mysql
require! './rivulet' : rivulet

olio.config.world          ?= {}
olio.config.world.host     ?= \127.0.0.1
olio.config.world.user     ?= \root
olio.config.world.database ?= \cfh

pool = mysql.create-pool olio.config.world

export transaction = ->*
  connection = yield pool.get-connection!
  yield connection.begin-transaction!
  tx =
    merge: (data) ->*
      for entity in difference (keys data), (yield connection.query "select json_keys(data) from world")
        yield connection.query "update world, (select json_merge(data, ?) as data from world) merged set world.data = merged.data", [ JSON.stringify({ (entity): [] }) ]
      yield connection.query "update world, (select json_merge(data, ?) as data from world) merged set world.data = merged.data", [ JSON.stringify(data) ]
    # search: (value, path, extract) ->*
    #   path = eval first values first yield connection.query "select json_search(data, 'one', ?, NULL, ?) from world", [ value, path ]
    #   extract = extract.replace /([\$\.])/g, "\\$1"
    #   yield tx.extract (//^(#extract\[\d+\])//.exec path).1
    contains: (value, path) ->*
      first values first yield connection.query "select json_contains(data, ?, ?) from world", [ JSON.stringify(value), path ]
    extract: (path) ->*
      JSON.parse(first values first yield connection.query "select json_extract(data, ?) from world", [ path ])
    commit: ->*
      yield connection.commit!
      connection.release!
    rollback: ->*
      yield connection.rollback!
      connection.release!
      path = eval first values first yield connection.query "select json_search(data, 'one', ?, NULL, ?) from world", [ value, path ]
      extract = extract.replace /([\$\.])/g, "\\$1"
      yield tx.extract (//^(#extract\[\d+\])//.exec path).1
    select: (extract, path, value) ->*
      path = eval first values first yield connection.query "select json_search(data, 'one', ?, NULL, ?) from world", [ value, path ]
      extract = extract.replace /([\$\.])/g, "\\$1"
      if path = (//^(#extract\[\d+\])//.exec path)?1
        cursor = rivulet yield tx.extract path
        # Should only save this shit on commit
        cursor.$observe '$', co.wrap ->*
          info "Saving #path"
          yield connection.query "update world, (select json_replace(data, ?, ?) as data from world) replaced set world.data = replaced.data", [ path, JSON.stringify(cursor.$get!) ]
        return cursor
      null
    select-copy: (extract, path, value) ->*
      if cursor = yield tx.select extract, path, value
        return cursor.$get!
      null
  tx

export end = ->*
  yield pool.end!

export reset = ->*
  connection = yield mysql.create-connection olio.config.world{host, user}
  if first((yield connection.query 'show databases') |> filter -> it.Database is olio.config.world.database)
    info "Dropping database '#{olio.config.world.database}'"
    yield connection.query "drop database if exists #{olio.config.world.database}"
  info "Creating database '#{olio.config.world.database}'"
  yield connection.query "create database #{olio.config.world.database}"
  connection.end!
  connection = yield mysql.create-connection olio.config.world{host, user, database}
  info "Creating table 'world'"
  yield connection.query "create table world (data json)"
  info "Inserting record"
  yield connection.query "insert world set data = '{}'"
  # info "Creating table 'document'"
  # yield connection.query """
  #   create table document (
  #     i       bigint not null auto_increment primary key,
  #     id      char(36),
  #     created datetime,
  #     updated datetime,
  #     kind    varchar(255),
  #     data    json,
  #     index   id (id),
  #     index   kind (kind)
  #   );
  # """
  # info "Creating insert trigger"
  # yield connection.query """
  #   create trigger before_insert_document before insert on document
  #   for each row begin
  #     set new.id = uuid(),
  #         new.created = now(),
  #         new.updated = now();
  #     if (new.data is null) then
  #       set new.data = '{}';
  #     end if;
  #   end;
  # """
  # info "Creating update trigger"
  # yield connection.query """
  #   create trigger before_update_document before update on document
  #   for each row begin
  #     set new.updated = now();
  #   end;
  # """
  connection.end!

#   tree = {}
#   for document in yield connection.query 'select * from document'
#     tree[document.kind] ?= []
#     tree[document.kind].push document{id, created, updated} <<< JSON.parse(document.data)
#   world = rivulet!
#   world tree
#   world.observe-deep '', co.wrap (world, diff) ->*
#     inserts = {}
#     updates = {}
#     for change in diff
#       continue if /^\w[\w\d\$]*\.\d+\.(id|created|update)$/.test change.path
#       if change.op is \add
#         if m = /^(\w[\w\d\$]*\.\d+)$/.exec change.path
#           inserts[m.1] = world.get m.1
#         else if m = /^(\w[\w\d\$]*\.\d+)/.exec change.path
#           updates[m.1] = world.get m.1 if not inserts[m.1]
#       else
#         if m = /^(\w[\w\d\$]*\.\d+)/.exec change.path
#           updates[m.1] = world.get m.1 if not inserts[m.1]
#     for path, data of inserts
#       info \INSERTING
#       { insert-id } = yield connection.query 'insert document set ?', kind: path.split('.').0, data: JSON.stringify(data)
#       document = first(yield connection.query 'select * from document where i = ?', insert-id){id, created, updated}
#       world.set "path/id", document.id
#       world.set "path/created", document.created
#       world.set "path/updated", document.updated
#     info world.state
#   world