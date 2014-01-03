# imap-pushover

Listens to an IMAP mailbox using IDLE, then sends a Pushover notification when new emails arrive.
This is useful to get new email notifications pushed within seconds to iOS or Android, but avoids needing to keep an open connection to the IMAP server on the phone/tablet. Avoiding the open connection saves battery on my phone and probably will on yours too.
The Pushover notification can contain a link to read the rest of the email using webmail or another app.

## Requirements

- Ruby 1.9.3+
- Rubygems: mail, pushover and loofah

A terminal multiplexer such as tmux or screen or a terminal detacher such as dtach, disown or nohup is useful to disconnect this program from the terminal after starting it.

## Configuration

Edit config.yaml with your own settings for the IMAP mail server and Pushover. You'll need to get your own API token and user key from Pushover.

notify_words sets the priority of different emails (for example, mailing list discussion vs things that should wake you up in the middle of the night).
In the configuration file, it's expressed as a mapping of strings to [Pushover API priorities](https://pushover.net/api#priority). The highest priority found in the email is used for the Pushover message. A single space will match any email.

## Thanks

- imap-idle-notify https://github.com/mlux/imap-idle-notify
- idlewatch https://otokar.looc2011.eu/idlewatch.html
