#!/usr/bin/env ruby

require 'yaml'
require 'net/imap'
require 'fileutils'
require 'rubygems'
require 'mail'
require 'pushover'
require 'loofah'

def puts_log str
  puts "[#{Time.now.to_s}] #{str}"
  STDOUT.flush
end

def openNewConnection
  puts_log "Opening new IMAP connection"
  imap = Net::IMAP.new($config['server'], $config['port'], :ssl => $config['ssl'])
  imap.login($config['username'], $config['password'])
  caps = imap.capability
  raise 'Server must support IMAP IDLE' if !caps.include? 'IDLE'
  imap.examine($config['folder'])
  return imap
end

def checkForUnread imap
  puts_log "Checking for unread messages"
  status = imap.status($config['folder'], ['MESSAGES','UNSEEN','RECENT'])
  imap.uid_search(['UNSEEN']).each do |msg_id|
    if $uids_seen.include? msg_id
      puts_log "Already seen message #{msg_id}"
      next
    end
    #who sent it and the subject are in the envelope part
    puts_log "New message #{msg_id}"
    envelope = imap.uid_fetch(msg_id, 'ENVELOPE')[0].attr['ENVELOPE']
    addr = envelope.from[0].mailbox + '@' + envelope.from[0].host
    puts_log "Found new mail from #{addr}"
    #download the rest of the message to extract the body text
    rfc = imap.uid_fetch(msg_id, 'RFC822')
    bodytext = ''
    mail = Mail.read_from_string(rfc[0].attr['RFC822'])
    name = mail[:from].display_names.first
    subj = mail.subject
    if mail.multipart?
      text_parts = mail.parts.select { |p| p.content_type.include? 'text/plain' }
      html_parts = mail.parts.select { |p| p.content_type.include? 'text/html' }
      # try to find a plaintext mime part
      if text_parts.size > 0
        text_parts.each { |p| bodytext << p.body.to_s }
      # no plaintext, fallback to html
      elsif html_parts.size > 0
        html_parts.each { |p| bodytext << p.body.to_s }
      end
    else
      # not multipart, just grab whatever's there
      bodytext = mail.body.to_s
    end
    bodytext = Loofah::fragment(bodytext).to_text
    #replace whitespace with a single space
    bodytext.gsub!(/\s+/, ' ')
    #remove leading/trailing whitespace
    bodytext.strip!
    filterSend(name, addr, subj, bodytext)
    $uids_seen << msg_id
  end
end

def filterSend(name, addr, subj, body)
  combined = "#{name}\n#{addr}\n#{subj}\n#{body}"
  combined.downcase!
  no_priority = -1000
  best_priority = no_priority
  $config['notify_words'].each do |word, priority|
    if combined.include? word
      puts_log "Matched '#{word}' with priority #{priority}"
      best_priority = priority if priority > best_priority
    end
  end
  puts_log "Pushover priority #{best_priority}"
  sendPushover(name, addr, subj, body, best_priority) if best_priority > no_priority
end

def sendPushover(name, addr, subj, body, priority_num)
  short_body = body.slice(0..$config['body_length'])
  short_body = "no mail body" if short_body.length == 0
  combined_title = name.to_s.length > 0 ? "#{name} - #{subj}" : "#{addr} - #{subj}"
  status_request = Pushover.notification(user: $config['pushover_user'], 
    token: $config['pushover_token'],
    device: $config['pushover_device'],
    title: combined_title,
    message: short_body,
    priority: priority_num,
    sound: $config['pushover_sound'],
    url: $config['pushover_url'],
    url_title: $config['pushover_url_title'],
    retry: $config['pushover_retry'],
    expire: $config['pushover_expire'])
  puts_log "Notification sent to Pushover, response #{status_request.to_s}"
end

#globals for config and message UIDs seen
currentDir = File.expand_path(File.dirname(__FILE__))
$config = YAML.load_file(currentDir + '/config.yaml')
$uids_seen = []

imap = openNewConnection
checkForUnread imap
loop do
  imap = openNewConnection if imap.disconnected?
  Thread.new do
    sleep $config['sleep_time']
    puts_log "Ending IDLE"
    imap.idle_done
    puts_log "IDLE ended"
  end
  begin
    puts_log "Starting IDLE"
    imap.idle do |resp|
      if resp.kind_of?(Net::IMAP::ContinuationRequest) and resp.data.text == 'idling'
        puts_log "IMAP IDLE continuation request received"
      end
      if resp.kind_of?(Net::IMAP::UntaggedResponse) and resp.name == 'EXISTS'
        puts_log "New message exists, opening another connection to retrieve it"
        imap2 = openNewConnection
        checkForUnread imap2
        imap2.logout
      end
    end
  rescue Errno::ECONNRESET
    puts_log "Connection reset by peer"
  rescue Net::IMAP::Error => error
    puts_log "IMAP error : #{error.inspect}"
    imap.disconnect
  end
end
