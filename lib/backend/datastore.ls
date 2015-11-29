require! \marklogic

state = {}

export init = ->
  state.db = marklogic.create-database-client host: \localhost, port: 8000, user: \admin, password: \9rXA1bR7efra

export read = ->*

export patch = (diffs) ->

