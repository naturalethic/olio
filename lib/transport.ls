require! \nodemailer
require! \sendgrid
require! \twilio
require! \jade

state = {}

if transport = olio.config.transport?mail
  if transport.vendor is \sendgrid
    transport.instance = sendgrid transport.identifier, transport.secret
    promisify-all transport.instance
if transport = olio.config.transport?sms
  if transport.vendor is \twilio
    transport.instance = twilio transport.identifier, transport.secret
if transport = olio.config.transport?dump
  if transport.vendor is \gmail
    transport.instance = nodemailer.create-transport service: \Gmail, auth: { user: transport.identifier, pass: transport.secret }

export dispatch = (world, notification) ->*
  failed = []
  for t in olio.config.notification.transport?[camelize notification.name] or []
    continue if notification["dispatched#{capitalize t}"]
    try
      continue if not transport[t]
      yield transport[t] world, notification
      notification["dispatched#{capitalize t}"] = true
    catch e
      info e
      failed.push t
  notification.dispatched = true if empty failed

transport =
  mail: (world, notification) ->*
    return if not transport = olio.config.transport.mail
    return if not transport.instance
    person = yield world.get notification.recipient
    return if transport.whitelist and person.emails.0.email.replace(/\+[^\@]+/, '') not in transport.whitelist
    return if not fs.exists-sync (path = "notification/#{notification.name}.mail")
    html = jade.render-file path, notification.data.$get!
    subject = (fs.read-file-sync path).to-string!split(/\n/).0.substr(4)
    yield transport.instance.send-async do
      from:     transport.sender-email
      fromname: transport.sender-name
      to:       person.emails.0.email
      toname:   "#{person.name} #{person.surname}"
      subject:  subject
      html:     html
    if dump = olio.config.transport.dump
      if dump.instance
        yield dump.instance.send-mail do
          from:    dump.identifier
          to:      dump.identifier.replace('@', "+#{notification.id}@")
          subject: "#{subject} | #{person.name} #{person.surname} <#{person.emails.0.email}>"
          html:    html

# export process-text = (job, person) ->*
#   if olio.config.twilio.whitelist and person.phone not in olio.config.twilio.whitelist
#     throw "Non-whitelisted recipient: #{person.phone}"
#   yield state.twilio.sms.messages.post do
#     to: "+1#{person.phone}"
#     from: olio.config.twilio.phone
#     body: job.data.summary
#   if state.dump
#     state.dump.send-mail do
#       from:    "Alacrity <#{olio.config.alacrity.user}>"
#       to:      olio.config.alacrity.user.replace('@', "+#{job.id}@")
#       subject: "#{job.data.summary} | #{person.name} | #{person.phone}"
#       html:    "#{job.data.summary} | #{person.name} | #{person.phone}"
#     job.log 'Sent copy to alacrity dump'
