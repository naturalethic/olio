# Pretty print objects

write = -> process.stdout.write it

ppval = (it, newline) ->
  if it is not undefined
    switch typeof! it
    | \Number    => write color(39, it.to-string!)
    | \String    => (it.length > 50 and it = it.substr(0, 100)); write color(220, it)
    | \Boolean   => write color(117, it.to-string!)
    | \Generator => write color(88, '<generator>')
    | \Null      => write color(245, 'null')
    | otherwise  => write color(94, String(it))
  write '\n' if newline

pparr = (it, indent = 0) ->
  if it.length is 0
    write '[]'
  prior-type = null
  for val in it
    write '\n' if prior-type is not \Object
    write ' ' * indent
    write '  * '
    pp val, 0, indent + 4
    prior-type = typeof! val
  write '\n' if !(is-object last it)

ppobj = (obj, indent = 0, second-indent, newline = false) ->
  second-indent ?= indent
  width = (keys obj) |> map (-> (dasherize it).length) |> fold1 Math.max
  width = 0
  k = sort keys obj
  if k.length is 0
    write '{}\n'
  else
    write '\n' if newline
  for i in [0 til k.length]
    it = k[i]
    indent = second-indent if i == 1
    write ' ' * indent
    write "#{color(246, dasherize it)}: #{' ' * (width - (dasherize it).length)}"
    switch typeof! obj[it]
    | \Object   => pp obj[it], indent + 2, null, true
    | \Array    => pp obj[it], indent
    | otherwise => pp obj[it], indent, null, true

pp = (it, indent = 0, second-indent, newline = false) ->
  switch typeof! it
  | \Object    => ppobj it, indent, second-indent, newline
  | \Array     => pparr it, indent, second-indent, newline
  | otherwise  => ppval it, newline

module.exports = pp
